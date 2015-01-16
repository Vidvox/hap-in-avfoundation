#import "AVPlayerItemHapDXTOutput.h"
#import "AVPlayerItemAdditions.h"
#import "PixelFormats.h"
#import "HapPlatform.h"
#import "HapCodecGL.h"
#include "YCoCg.h"
#include "YCoCgDXT.h"




BOOL				_AVFinHapCVInit = NO;
/*			Callback for multithreaded Hap decoding			*/
void HapMTDecode(HapDecodeWorkFunction function, void *p, unsigned int count, void *info HAP_ATTR_UNUSED)	{
	dispatch_apply(count, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t index) {
		function(p, (unsigned int)index);
	});
}
#define FourCCLog(n,f) NSLog(@"%@, %c%c%c%c",n,(int)((f>>24)&0xFF),(int)((f>>16)&0xFF),(int)((f>>8)&0xFF),(int)((f>>0)&0xFF))




@implementation AVPlayerItemHapDXTOutput


+ (void) initialize	{
	@synchronized (self)	{
		if (!_AVFinHapCVInit)	{
			HapCodecRegisterPixelFormats();
			_AVFinHapCVInit = YES;
		}
	}
	//	make sure the CMMemoryPool used by this framework exists
	OSSpinLockLock(&_HIAVFMemPoolLock);
	if (_HIAVFMemPool==NULL)
		_HIAVFMemPool = CMMemoryPoolCreate(NULL);
	if (_HIAVFMemPoolAllocator==NULL)
		_HIAVFMemPoolAllocator = CMMemoryPoolGetAllocator(_HIAVFMemPool);
	OSSpinLockUnlock(&_HIAVFMemPoolLock);
}
- (id) initWithHapAssetTrack:(AVAssetTrack *)n	{
	self = [self init];
	if (self!=nil)	{
		if (n!=nil)	{
			OSSpinLockLock(&propertyLock);
			
			if (decodeQueue!=nil)
				dispatch_release(decodeQueue);
			//decodeQueue = dispatch_queue_create("HapDecode", DISPATCH_QUEUE_CONCURRENT);
			decodeQueue = dispatch_queue_create("HapDecode", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, DISPATCH_QUEUE_PRIORITY_HIGH, -1));
			if (track != nil)
				[track release];
			track = [n retain];
			if (gen != nil)
				[gen release];
			//	can't make a sample buffer generator 'cause i don't have a timebase- AVPlayerItem seems to be the only thing that uses this?
			gen = [[AVSampleBufferGenerator alloc] initWithAsset:[n asset] timebase:NULL];
			//gen = [[AVSampleBufferGenerator alloc] init];
			lastGeneratedSampleTime = kCMTimeInvalid;
			if (decompressedFrames != nil)
				[decompressedFrames removeAllObjects];
			
			OSSpinLockUnlock(&propertyLock);
		}
	}
	return self;
}
- (id) init	{
	self = [super init];
	if (self!=nil)	{
		propertyLock = OS_SPINLOCK_INIT;
		decodeQueue = NULL;
		track = nil;
		gen = nil;
		lastGeneratedSampleTime = kCMTimeInvalid;
		decompressedFrames = [[NSMutableArray arrayWithCapacity:0] retain];
		outputAsRGB = NO;
		destRGBPixelFormat = kCVPixelFormatType_32RGBA;
		dxtPoolLength = 0;
		convPoolLength = 0;
		rgbPoolLength = 0;
		glDecoder = NULL;
		allocFrameBlock = NULL;
		postDecodeBlock = NULL;
		[self setSuppressesPlayerRendering:YES];
	}
	return self;
}
- (void) dealloc	{
	OSSpinLockLock(&propertyLock);
	if (decodeQueue!=NULL)	{
		dispatch_release(decodeQueue);
		decodeQueue=NULL;
	}
	if (gen != nil)	{
		[gen release];
		gen = nil;
	}
	if (track != nil)	{
		[track release];
		track = nil;
	}
	if (decompressedFrames != nil)	{
		[decompressedFrames release];
		decompressedFrames = nil;
	}
	if (glDecoder != NULL)	{
		HapCodecGLDestroy(glDecoder);
		glDecoder = NULL;
	}
	if (allocFrameBlock != nil)	{
		Block_release(allocFrameBlock);
		allocFrameBlock = nil;
	}
	if (postDecodeBlock!=nil)	{
		Block_release(postDecodeBlock);
		postDecodeBlock = nil;
	}
	OSSpinLockUnlock(&propertyLock);
	[super dealloc];
}
- (HapDecoderFrame *) allocFrameClosestToTime:(CMTime)n	{
	HapDecoderFrame			*returnMe = nil;
	
	OSSpinLockLock(&propertyLock);
	if (track!=nil && gen!=nil)	{
		//	check and see if any of my frames have finished decoding
		NSMutableArray			*decodedFrames = nil;
		for (HapDecoderFrame *framePtr in decompressedFrames)	{
			//	if this frame has been decoded, i'll either be returning it or adding it to an array and returning something from the array
			if ([framePtr decoded])	{
				//	if there's an array of completed frames, add this (decoded) frame to it
				if (decodedFrames!=nil)
					[decodedFrames addObject:framePtr];
				//	else there's no array of completed frames...
				else	{
					//	if i haven't found a frame to return yet, i'll be returning this one
					if (returnMe==nil)
						returnMe = framePtr;
					//	else i already found a frame to return- i need to start using the decodedFrames array!
					else	{
						decodedFrames = [NSMutableArray arrayWithCapacity:0];
						[decodedFrames addObject:returnMe];
						returnMe = nil;
						[decodedFrames addObject:framePtr];
					}
				}
			}
		}
		//	if i have an array of decoded frames, sort it by the frame's time, find the frame i'll be returning, remove all of them from the array
		if (decodedFrames!=nil)	{
			[decodedFrames sortUsingComparator:^(id obj1, id obj2)	{
				return (NSComparisonResult)CMTimeCompare(CMSampleBufferGetPresentationTimeStamp([obj1 hapSampleBuffer]), CMSampleBufferGetPresentationTimeStamp([obj2 hapSampleBuffer]));
			}];
			returnMe = [decodedFrames objectAtIndex:0];
			[returnMe retain];
			for (id anObj in decodedFrames)
				[decompressedFrames removeObjectIdenticalTo:anObj];
		}
		//	else if i found a single frame to return, remove it from the array
		else if (returnMe!=nil)	{
			[returnMe retain];
			[decompressedFrames removeObjectIdenticalTo:returnMe];
		}
		
		
		//	use GCD to start decompressing a frame for the passed time
		dispatch_async(decodeQueue, ^{
			[self _decodeFrameForTime:n];
		});
		
	}
	OSSpinLockUnlock(&propertyLock);
	
	return returnMe;
}
- (HapDecoderFrame *) allocFrameForTime:(CMTime)n	{
	//NSLog(@"%s ... %@",__func__,[(id)CMTimeCopyDescription(kCFAllocatorDefault,n) autorelease]);
	//	decode a frame synchronusly
	[self _decodeFrameForTime:n];
	//	run through the decompressed frames, find the frame for this time
	HapDecoderFrame			*returnMe = nil;
	OSSpinLockLock(&propertyLock);
	//	check and see if any of my frames have finished decoding
	for (HapDecoderFrame *framePtr in decompressedFrames)	{
		//	if this frame has been decoded, i'll either be returning it or adding it to an array and returning something from the array
		if ([framePtr decoded] && CMTIME_COMPARE_INLINE(n,==,CMSampleBufferGetPresentationTimeStamp([framePtr hapSampleBuffer])))	{
			returnMe = framePtr;
			break;
		}
	}
	if (returnMe!=nil)	{
		[returnMe retain];
		[decompressedFrames removeObjectIdenticalTo:returnMe];
	}
	OSSpinLockUnlock(&propertyLock);
	return returnMe;
}
- (HapDecoderFrame *) allocFrameForHapSampleBuffer:(CMSampleBufferRef)n	{
	if (n==NULL)
		return nil;
	//	decode the sample buffer synchronously
	[self _decodeSampleBuffer:n];
	//	run through the decompressed frames, find the frame for this time
	CMTime					sampleTime = CMSampleBufferGetPresentationTimeStamp(n);
	HapDecoderFrame			*returnMe = nil;
	OSSpinLockLock(&propertyLock);
	//	check and see if any of my frames have finished decoding
	for (HapDecoderFrame *framePtr in decompressedFrames)	{
		//	if this frame has been decoded, i'll either be returning it or adding it to an array and returning something from the array
		if ([framePtr decoded] && CMTIME_COMPARE_INLINE(sampleTime,==,CMSampleBufferGetPresentationTimeStamp([framePtr hapSampleBuffer])))	{
			returnMe = framePtr;
			break;
		}
	}
	if (returnMe!=nil)	{
		[returnMe retain];
		[decompressedFrames removeObjectIdenticalTo:returnMe];
	}
	OSSpinLockUnlock(&propertyLock);
	return returnMe;
}
- (void) _decodeSampleBuffer:(CMSampleBufferRef)newSample	{
	//NSLog(@"%s ... %p",__func__,newSample);
	HapDecoderFrameAllocBlock		localAllocFrameBlock = nil;
	AVFHapDXTPostDecodeBlock		localPostDecodeBlock = nil;
	CMTime							cursorTime = CMSampleBufferGetPresentationTimeStamp(newSample);
	
	OSSpinLockLock(&propertyLock);
	lastGeneratedSampleTime = cursorTime;
	localAllocFrameBlock = (allocFrameBlock==nil) ? nil : [allocFrameBlock retain];
	localPostDecodeBlock = (postDecodeBlock==nil) ? nil : [postDecodeBlock retain];
	BOOL				localOutputAsRGB = outputAsRGB;
	OSType				localDestRGBPixelFormat = destRGBPixelFormat;
	OSSpinLockUnlock(&propertyLock);
	
	
	//	make a sample decoder frame from the sample buffer- this calculates various minimum buffer sizes
	HapDecoderFrame		*sampleDecoderFrame = [[HapDecoderFrame alloc] initEmptyWithHapSampleBuffer:newSample];
	size_t				dxtMinDataSize = [sampleDecoderFrame dxtMinDataSize];
	size_t				rgbMinDataSize = [sampleDecoderFrame rgbMinDataSize];
	//	make sure that the buffer pools are sized appropriately.  don't know if i'll be using them or not, but make sure they're sized properly regardless.
	if (dxtPoolLength!=dxtMinDataSize)
		dxtPoolLength = dxtMinDataSize;
	if (localOutputAsRGB)	{
		if (rgbPoolLength!=rgbMinDataSize)
			rgbPoolLength = rgbMinDataSize;
	}
	//	allocate a decoder frame- this data structure holds all the values needed to decode the hap frame into a blob of memory (actually a DXT frame).  if there's a custom frame allocator block, use that- otherwise, just make a CFData and decode into that.
	HapDecoderFrame			*newDecoderFrame = nil;
	if (localAllocFrameBlock!=nil)	{
		//NSLog(@"\t\tthere's a local frame allocator block, using that...");
		newDecoderFrame = localAllocFrameBlock(newSample);
	}
	if (newDecoderFrame==nil)	{
		//	make an empty frame (i can just retain & use the sample frame i made earlier to size the pools)
		newDecoderFrame = (sampleDecoderFrame==nil) ? nil : [sampleDecoderFrame retain];
		
		//	allocate mem objects for dxt and rgb data
		void			*dxtMem = CFAllocatorAllocate(_HIAVFMemPoolAllocator, dxtPoolLength, 0);
		void			*rgbMem = (localOutputAsRGB) ? CFAllocatorAllocate(_HIAVFMemPoolAllocator, rgbPoolLength, 0) : nil;
		
		//	populate the empty frame with the dxt/rgb mem objects i just created
		[newDecoderFrame setDXTData:dxtMem];
		[newDecoderFrame setDXTDataSize:dxtPoolLength];
		if (localOutputAsRGB)	{
			[newDecoderFrame setRGBData:rgbMem];
			[newDecoderFrame setRGBDataSize:rgbPoolLength];
			//	make sure that the frame i'll be decoding knows what pixel format it should be decoding to
			[newDecoderFrame setRGBPixelFormat:localDestRGBPixelFormat];
		}
		//	store the MemObject instances- which are pooled- in the frame
		if (localOutputAsRGB)	{
			CFDataRef		dxtDataRef = CFDataCreateWithBytesNoCopy(NULL, dxtMem, dxtPoolLength, _HIAVFMemPoolAllocator);
			CFDataRef		rgbDataRef = CFDataCreateWithBytesNoCopy(NULL, rgbMem, rgbPoolLength, _HIAVFMemPoolAllocator);
			[newDecoderFrame setUserInfo:[NSArray arrayWithObjects:(NSData *)dxtDataRef, (NSData *)rgbDataRef, nil]];
			CFRelease(dxtDataRef);
			CFRelease(rgbDataRef);
		}
		else	{
			CFDataRef		dxtDataRef = CFDataCreateWithBytesNoCopy(NULL, dxtMem, dxtPoolLength, _HIAVFMemPoolAllocator);
			[newDecoderFrame setUserInfo:(NSData *)dxtDataRef];
			CFRelease(dxtDataRef);
		}
	}
	//	free the sample decoder frame i used to calculate and configure the size of the buffer pools
	if (sampleDecoderFrame!=nil)	{
		[sampleDecoderFrame release];
		sampleDecoderFrame = nil;
	}
	
	if (newDecoderFrame==nil)
		NSLog(@"\t\terr: decoder frame nil, %s",__func__);
	else	{
		//	decode the frame (into DXT data)
		NSSize				imgSize = [newDecoderFrame imgSize];
		NSSize				dxtImgSize = [newDecoderFrame dxtImgSize];
		void				*dxtData = [newDecoderFrame dxtData];
		size_t				dxtDataSize = [newDecoderFrame dxtDataSize];
		CMSampleBufferRef	hapSampleBuffer = [newDecoderFrame hapSampleBuffer];
		CMBlockBufferRef	dataBlockBuffer = (hapSampleBuffer==nil) ? nil : CMSampleBufferGetDataBuffer(hapSampleBuffer);
		if (dxtData==NULL || dataBlockBuffer==NULL)
			NSLog(@"\t\terr:dxtData or dataBlockBuffer null in %s",__func__);
		else	{
			OSStatus				cmErr = kCMBlockBufferNoErr;
			size_t					dataBlockBufferAvailableData = 0;
			size_t					dataBlockBufferTotalDataSize = 0;
			//OSType					dxtPixelFormat = [newDecoderFrame dxtPixelFormat];
			enum HapTextureFormat	dxtTextureFormat = 0;
			char					*dataBuffer = nil;
			cmErr = CMBlockBufferGetDataPointer(dataBlockBuffer,
				0,
				&dataBlockBufferAvailableData,
				&dataBlockBufferTotalDataSize,
				&dataBuffer);
			if (cmErr != kCMBlockBufferNoErr)
				NSLog(@"\t\terr %d at CMBlockBufferGetDataPointer() in %s",(int)cmErr,__func__);
			else	{
				if (dataBlockBufferAvailableData > dxtDataSize)
					NSLog(@"\t\terr: block buffer larger than allocated dxt data, %ld vs. %ld, %s",dataBlockBufferAvailableData,dxtDataSize,__func__);
				else	{
					//unsigned long			outputBufferBytesUsed = 0;
					unsigned int			hapErr = HapResult_No_Error;
					hapErr = HapDecode(dataBuffer,
						dataBlockBufferAvailableData,
						(HapDecodeCallback)HapMTDecode,
						NULL,
						dxtData,
						dxtDataSize,
						NULL,
						&dxtTextureFormat);
					if (hapErr != HapResult_No_Error)
						NSLog(@"\t\terr %d at HapDecode() in %s",hapErr,__func__);
					else	{
						//NSLog(@"\t\thap decode successful, output texture format is %d",dxtTextureFormat);
						[newDecoderFrame setDXTTextureFormat:dxtTextureFormat];
						
						//	if the decoder frame has a buffer for rgb data, convert the DXT data into rgb data of some sort
						void			*rgbData = [newDecoderFrame rgbData];
						size_t			rgbDataSize = [newDecoderFrame rgbDataSize];
						OSType			rgbPixelFormat = [newDecoderFrame rgbPixelFormat];
						if (rgbData!=nil)	{
							//	if the DXT data is a YCoCg texture format
							if (dxtTextureFormat == HapTextureFormat_YCoCg_DXT5)	{
								//	convert the YCoCg/DXT5 data to just plain ol' DXT5 data in a conversion buffer
								size_t			convMinDataSize = (NSUInteger)dxtImgSize.width * (NSUInteger)dxtImgSize.height * 32 / 8;
								if (convMinDataSize!=convPoolLength)
									convPoolLength = convMinDataSize;
								void			*convMem = CFAllocatorAllocate(_HIAVFMemPoolAllocator, convPoolLength, 0);
								DeCompressYCoCgDXT5((const byte *)dxtData, (byte *)convMem, imgSize.width, imgSize.height, dxtImgSize.width*4);
								//	convert the DXT5 data in the conversion buffer to either RGBA or BGRA data in the rgb buffer
								if (rgbPixelFormat == k32RGBAPixelFormat)	{
									ConvertCoCg_Y8888ToRGB_((uint8_t *)convMem, (uint8_t *)rgbData, imgSize.width, imgSize.height, dxtImgSize.width * 4, rgbDataSize/(NSUInteger)dxtImgSize.height, 1);
								}
								else	{
									ConvertCoCg_Y8888ToBGR_((uint8_t *)convMem, (uint8_t *)rgbData, imgSize.width, imgSize.height, dxtImgSize.width * 4, rgbDataSize/(NSUInteger)dxtImgSize.height, 1);
								}
								
								if (convMem!=nil)	{
									CFAllocatorDeallocate(_HIAVFMemPoolAllocator, convMem);
									convMem = nil;
								}
							}
							//	else it's a "normal" (non-YCoCg) DXT texture format, use the GL decoder
							else if (dxtTextureFormat==HapTextureFormat_RGB_DXT1 || dxtTextureFormat==HapTextureFormat_RGBA_DXT5)	{
								OSSpinLockLock(&propertyLock);
								//	if the decoder exists and its format or dimensions have changed, trash it
								if (glDecoder!=nil && (dxtTextureFormat!=HapCodecGLGetCompressedFormat(glDecoder) || HapCodecGLGetWidth(glDecoder)!=(NSUInteger)dxtImgSize.width || HapCodecGLGetHeight(glDecoder)!=(NSUInteger)dxtImgSize.height))	{
									HapCodecGLDestroy(glDecoder);
									glDecoder = NULL;
								}
								//	if necessary, make a decoder
								if (glDecoder==NULL)	{
									glDecoder = HapCodecGLCreateDecoder(imgSize.width, imgSize.height, dxtTextureFormat);
									if (glDecoder==NULL)
										NSLog(@"\t\terr: couldn't create gl decoder in %s",__func__);
								}
								
								//	decode the DXT data into the rgb buffer
								//NSLog(@"\t\tcalling %ld with userInfo %@",rgbDataSize/(NSUInteger)dxtImgSize.height,[newDecoderFrame userInfo]);
								hapErr = HapCodecGLDecode(glDecoder,
									(unsigned int)(rgbDataSize/(NSUInteger)dxtImgSize.height),
									(rgbPixelFormat==kCVPixelFormatType_32BGRA) ? HapCodecGLPixelFormat_BGRA8 : HapCodecGLPixelFormat_RGBA8,
									dxtData,
									rgbData);
								if (hapErr!=HapResult_No_Error)
									NSLog(@"\t\terr %d at HapCodecGLDecoder() in %s",hapErr,__func__);
								else	{
									//NSLog(@"\t\tsuccessfully decoded to RGB data!");
								}
								OSSpinLockUnlock(&propertyLock);
							}
							else	{
								NSLog(@"\t\terr: unrecognized text format %X in %s",dxtTextureFormat,__func__);
							}
						}
						
						//	mark the frame as decoded so it can be displayed
						[newDecoderFrame setDecoded:YES];
					}
				}
			}
		}
		
		//	run the post-decode block (if there is one).  note that this is run even if the decode is unsuccessful...
		if (localPostDecodeBlock!=nil)
			localPostDecodeBlock(newDecoderFrame);
	}
	
	
	OSSpinLockLock(&propertyLock);
	//	add the frame i just decoded into the 'decompressedFrames' array
	if (newDecoderFrame!=nil)	{
		[decompressedFrames addObject:newDecoderFrame];
		[newDecoderFrame release];
		newDecoderFrame = nil;
	}
	OSSpinLockUnlock(&propertyLock);
	
	
	if (localAllocFrameBlock!=nil)
		[localAllocFrameBlock release];
	if (localPostDecodeBlock!=nil)
		[localPostDecodeBlock release];
}
//	this method could be called from any thread- if you're using "allocFrameForTime:" then this method will be called from the thread upon which it will be returning, if you're using allocFrameClosestToTime: then this method will be called by GCD on an arbitrary thread.
- (void) _decodeFrameForTime:(CMTime)decodeTime	{
	//NSLog(@"%s ... %f",__func__,CMTimeGetSeconds(decodeTime));
	OSSpinLockLock(&propertyLock);
	if (track!=nil)	{
		AVSampleCursor			*cursor = [track makeSampleCursorWithPresentationTimeStamp:decodeTime];
		//CMTime					cursorTime = [cursor presentationTimeStamp];
		//	if the requested decode time is different from the last time i generated a sample for...
		//if (!CMTIME_COMPARE_INLINE(lastGeneratedSampleTime,==,cursorTime))	{
			//	generate a sample buffer for the requested time.  this sample buffer contains a hap frame (compressed).
			AVSampleBufferRequest	*request = [[AVSampleBufferRequest alloc] initWithStartCursor:cursor];
			CMSampleBufferRef		newSample = (gen==nil) ? nil : [gen createSampleBufferForRequest:request];
			OSSpinLockUnlock(&propertyLock);
			
			if (newSample==NULL)	{
				NSLog(@"\t\terr: sample null, %s",__func__);
			}
			else	{
				[self _decodeSampleBuffer:newSample];
				CFRelease(newSample);
			}
			
			if (request != nil)	{
				[request release];
				request = nil;
			}
		//}
		//else
		//	OSSpinLockUnlock(&propertyLock);
	}
	else	{
		NSLog(@"\t\terr: track nil in %s",__func__);
		OSSpinLockUnlock(&propertyLock);
	}
	
}
- (void) setAllocFrameBlock:(HapDecoderFrameAllocBlock)n	{
	OSSpinLockLock(&propertyLock);
	if (allocFrameBlock != nil)
		Block_release(allocFrameBlock);
	allocFrameBlock = (n==nil) ? nil : Block_copy(n);
	OSSpinLockUnlock(&propertyLock);
}
- (void) setPostDecodeBlock:(AVFHapDXTPostDecodeBlock)n	{
	OSSpinLockLock(&propertyLock);
	if (postDecodeBlock!=nil)
		Block_release(postDecodeBlock);
	postDecodeBlock = (n==nil) ? nil : Block_copy(n);
	OSSpinLockUnlock(&propertyLock);
}


/*		these methods aren't in the documentation or header files, but they're there and they do what they sound like.		*/
- (void)_detachFromPlayerItem	{
	//NSLog(@"%s",__func__);
	OSSpinLockLock(&propertyLock);
	
	if (decodeQueue!=NULL)	{
		dispatch_release(decodeQueue);
		decodeQueue = NULL;
	}
	if (track != nil)	{
		[track release];
		track = nil;
	}
	if (gen != nil)	{
		[gen release];
		gen = nil;
	}
	[decompressedFrames removeAllObjects];
	
	OSSpinLockUnlock(&propertyLock);
}
- (BOOL)_attachToPlayerItem:(id)arg1	{
	//NSLog(@"%s",__func__);
	BOOL		returnMe = YES;
	if (arg1!=nil)	{
		//	from the player item's asset, find the hap video track
		AVAsset				*itemAsset = [arg1 asset];
		AVAssetTrack		*hapTrack = [arg1 hapTrack];
		//	i only want to attach if there's a hap track...
		if (hapTrack!=nil)	{
			OSSpinLockLock(&propertyLock);
			
			if (decodeQueue!=nil)
				dispatch_release(decodeQueue);
			//decodeQueue = dispatch_queue_create("HapDecode", DISPATCH_QUEUE_CONCURRENT);
			decodeQueue = dispatch_queue_create("HapDecode", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, DISPATCH_QUEUE_PRIORITY_HIGH, -1));
			if (track != nil)
				[track release];
			track = [hapTrack retain];
			if (gen != nil)
				[gen release];
			gen = [[AVSampleBufferGenerator alloc] initWithAsset:itemAsset timebase:[arg1 timebase]];
			lastGeneratedSampleTime = kCMTimeInvalid;
			if (decompressedFrames != nil)
				[decompressedFrames removeAllObjects];
			
			OSSpinLockUnlock(&propertyLock);
			//returnMe = YES;
		}
	}
	return returnMe;
}
- (void) setOutputAsRGB:(BOOL)n	{
	OSSpinLockLock(&propertyLock);
	outputAsRGB = n;
	OSSpinLockUnlock(&propertyLock);
}
- (BOOL) outputAsRGB	{
	OSSpinLockLock(&propertyLock);
	BOOL		returnMe = outputAsRGB;
	OSSpinLockUnlock(&propertyLock);
	return returnMe;
}
- (void) setDestRGBPixelFormat:(OSType)n	{
	if (n!=kCVPixelFormatType_32BGRA && n!=kCVPixelFormatType_32RGBA)	{
		NSString		*errFmtString = [NSString stringWithFormat:@"\t\tERR in %s, can't use new format:",__func__];
		FourCCLog(errFmtString,n);
		return;
	}
	OSSpinLockLock(&propertyLock);
	destRGBPixelFormat = n;
	OSSpinLockUnlock(&propertyLock);
}
- (OSType) destRGBPixelFormat	{
	OSSpinLockLock(&propertyLock);
	OSType		returnMe = destRGBPixelFormat;
	OSSpinLockUnlock(&propertyLock);
	return returnMe;
}


@end

