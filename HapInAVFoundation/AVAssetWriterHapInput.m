#import "AVAssetWriterHapInput.h"
#include "HapPlatform.h"
#import "HapCodecSubTypes.h"
#import "PixelFormats.h"
#import "hap.h"
#import "Utility.h"

#include "DXTEncoder.h"
#include "ImageMath.h"
/*
On Apple we support GL encoding using the GPU.
The GPU is very fast but produces low quality results
Squish produces nicer results but takes longer.
We select the GPU when the quality setting is above "High"
YCoCg encodes YCoCg in DXT and requires a shader to draw, and produces very high quality results
*/
#include "GLDXTEncoder.h"
#include "SquishEncoder.h"
#include "YCoCg.h"
#include "YCoCgDXTEncoder.h"

#import "AVPlayerItemHapDXTOutput.h"




#define kHapCodecCVPixelBufferLockFlags kCVPixelBufferLock_ReadOnly

NSString *const			AVVideoCodecHap = @"Hap1";
NSString *const			AVVideoCodecHapAlpha = @"Hap5";
NSString *const			AVVideoCodecHapQ = @"HapY";

#define FourCCLog(n,f) NSLog(@"%@, %c%c%c%c",n,(int)((f>>24)&0xFF),(int)((f>>16)&0xFF),(int)((f>>8)&0xFF),(int)((f>>0)&0xFF))




//	these aren't in the header file because the user-facing API doesn't need to call them
@interface AVAssetWriterHapInput ()
@property (assign,readwrite) CMTime lastEncodedDuration;
- (void) appendEncodedFrames;
@end




@implementation AVAssetWriterHapInput


+ (void) initialize	{
	@synchronized ([AVPlayerItemHapDXTOutput class])	{
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
- (id) initWithOutputSettings:(NSDictionary *)n	{
	self = [super initWithMediaType:AVMediaTypeVideo outputSettings:nil];
	if (self!=nil)	{
		encodeQueue = NULL;
		exportCodecType = kHapCodecSubType;
		exportPixelFormat = kHapCVPixelFormat_RGB_DXT1;
		exportTextureType = HapTextureFormat_RGB_DXT1;
		exportImgSize = NSMakeSize(1,1);
		exportDXTImgSize = NSMakeSize(4,4);
		formatConvertPoolLength = 0;
		dxtBufferPoolLength = 0;
		hapBufferPoolLength = 0;
		encoderLock = OS_SPINLOCK_INIT;
		dxtEncoder = NULL;
		encoderProgressLock = OS_SPINLOCK_INIT;
		encoderProgressFrames = [[NSMutableArray arrayWithCapacity:0] retain];
		encoderWaitingToRunOut = NO;
		lastEncodedDuration = kCMTimeZero;
		if (n==nil)
			goto BAIL;
		//	get the video size- if i can't, bail
		NSNumber		*tmpNum = nil;
		tmpNum = [n objectForKey:AVVideoWidthKey];
		if (tmpNum==nil)
			goto BAIL;
		exportImgSize.width = [tmpNum doubleValue];
		tmpNum = [n objectForKey:AVVideoHeightKey];
		if (tmpNum==nil)
			goto BAIL;
		exportImgSize.height = [tmpNum doubleValue];
		//NSLog(@"\t\texportImgSize is %d x %d",(NSUInteger)exportImgSize.width,(NSUInteger)exportImgSize.height);
		//	if the size isn't a multiple of 4, account for it by adding padding to the right/bottom of the image
		exportDXTImgSize = NSMakeSize(roundUpToMultipleOf4(((uint32_t)(exportImgSize.width))), roundUpToMultipleOf4(((uint32_t)(exportImgSize.height))));
		//NSLog(@"\t\texportDXTImgSize is %d x %d",(NSUInteger)exportDXTImgSize.width,(NSUInteger)exportDXTImgSize.height);
		//	get the requested codec type- if it's not hap, bail
		NSString		*codecString = [n objectForKey:AVVideoCodecKey];
		BOOL			hapExport = NO;
		BOOL			highQualityExport = NO;
		if (codecString==nil)
			goto BAIL;
		else if ([codecString isEqualToString:AVVideoCodecHap])	{
			hapExport = YES;
			exportCodecType = kHapCodecSubType;
			exportPixelFormat = kHapCVPixelFormat_RGB_DXT1;
			exportTextureType = HapTextureFormat_RGB_DXT1;
		}
		else if ([codecString isEqualToString:AVVideoCodecHapAlpha])	{
			hapExport = YES;
			exportCodecType = kHapAlphaCodecSubType;
			exportPixelFormat = kHapCVPixelFormat_RGBA_DXT5;
			exportTextureType = HapTextureFormat_RGBA_DXT5;
		}
		else if ([codecString isEqualToString:AVVideoCodecHapQ])	{
			hapExport = YES;
			exportCodecType = kHapYCoCgCodecSubType;
			exportPixelFormat = kHapCVPixelFormat_YCoCg_DXT5;
			exportTextureType = HapTextureFormat_YCoCg_DXT5;
		}
		if (!hapExport)
			goto BAIL;
		//	if there's a quality key and it's > 0.75, we'll use squish to compress the frames (higher quality, but much slower)
		NSDictionary	*propertiesDict = [n objectForKey:AVVideoCompressionPropertiesKey];
		NSNumber		*qualityNum = (propertiesDict==nil) ? nil : [propertiesDict objectForKey:AVVideoQualityKey];
		if (qualityNum!=nil && [qualityNum floatValue]>=0.80)
			highQualityExport = YES;
		//	figure out the max dxt frame size in bytes, make the dxt buffer pool
		NSUInteger		dxtFrameSizeInBytes = dxtBytesForDimensions(exportDXTImgSize.width, exportDXTImgSize.height, exportCodecType);
		//NSLog(@"\t\tdxtFrameSizeInBytes is %d",dxtFrameSizeInBytes);
		dxtBufferPoolLength = dxtFrameSizeInBytes;
		//	figure out the max hap frame size in bytes, make the hap buffer pool
		hapBufferPoolLength = HapMaxEncodedLength(dxtFrameSizeInBytes);
		//NSLog(@"\t\thapBufferPoolLength is %d",hapBufferPoolLength);
		
		//	make the dxt encoder
		switch (exportCodecType)	{
		case kHapCodecSubType:
		case kHapAlphaCodecSubType:
		{
			if (highQualityExport)
				dxtEncoder = HapCodecSquishEncoderCreate(HapCodecSquishEncoderMediumQuality, exportPixelFormat);
			else
				dxtEncoder = HapCodecGLEncoderCreate((unsigned int)exportImgSize.width, (unsigned int)exportImgSize.height, exportPixelFormat);
			break;
		}
		case kHapYCoCgCodecSubType:
			dxtEncoder = HapCodecYCoCgDXTEncoderCreate();
			break;
		}
		if (dxtEncoder==NULL)	{
			NSLog(@"\t\terr: couldn't make dxtEncoder, %s",__func__);
			FourCCLog(@"\t\texport codec type was",exportCodecType);
			goto BAIL;
		}
		
		//FourCCLog(@"\t\texportCodecType is",exportCodecType);
		//FourCCLog(@"\t\texportPixelFormat is",exportPixelFormat);
		//	make a buffer pool for format conversion buffers (i know what the desired pixel format is for the dxt encoder, so i know how big the format conversion buffers have to be)
		encoderInputPxlFmt = ((HapCodecDXTEncoderRef)dxtEncoder)->pixelformat_function(dxtEncoder, exportPixelFormat);
		//FourCCLog(@"\t\tencoderInputPxlFmt is",encoderInputPxlFmt);
		encoderInputPxlFmtBytesPerRow = roundUpToMultipleOf16(((uint32_t)exportImgSize.width * 4));
		formatConvertPoolLength = encoderInputPxlFmtBytesPerRow*(NSUInteger)(exportImgSize.height);
		
		//encodeQueue = dispatch_queue_create("HapEncode", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT, QOS_CLASS_USER_INITIATED, -1));
		encodeQueue = dispatch_queue_create("HapEncode", DISPATCH_QUEUE_CONCURRENT);
	}
	return self;
	BAIL:
	NSLog(@"ERR: bailed in %s",__func__);
	[self release];
	return nil;
}
- (void) dealloc	{
	if (encodeQueue!=NULL)	{
		dispatch_release(encodeQueue);
		encodeQueue = NULL;
	}
	OSSpinLockLock(&encoderLock);
	if (dxtEncoder!=NULL)	{
		HapCodecDXTEncoderDestroy((HapCodecDXTEncoderRef)dxtEncoder);
		dxtEncoder = NULL;
	}
	OSSpinLockUnlock(&encoderLock);
	OSSpinLockLock(&encoderProgressLock);
	if (encoderProgressFrames!=nil)	{
		[encoderProgressFrames release];
		encoderProgressFrames = nil;
	}
	OSSpinLockUnlock(&encoderProgressLock);
	[super dealloc];
}
- (BOOL) appendPixelBuffer:(CVPixelBufferRef)pb withPresentationTime:(CMTime)t	{
	return [self appendPixelBuffer:pb withPresentationTime:t asynchronously:YES];
}
- (BOOL) appendPixelBuffer:(CVPixelBufferRef)pb withPresentationTime:(CMTime)t asynchronously:(BOOL)a	{
	//NSLog(@"%s at time %@",__func__,[(id)CMTimeCopyDescription(kCFAllocatorDefault,t) autorelease]);
	BOOL			returnMe = YES;
	//	get the pixel format of the passed buffer- if it's not BGRA or RGBA, log the problem (only log the problem if there's a non-null pixel buffer)
	OSType			sourceFormat = CVPixelBufferGetPixelFormatType(pb);
	if (pb!=NULL)	{
		switch (sourceFormat)	{
		case k32BGRAPixelFormat:
		case k32RGBAPixelFormat:
			break;
		default:
			FourCCLog(@"\t\tERR: can't append pixel buffer- required RGBA or BGRA pixel format, but supplied",sourceFormat);
			returnMe = NO;
			break;
		}
	}
	
	//	if i'm done accepting samples (because something marked me as finished), i won't be encoding a frame- but i'll still want to execute the block
	HapEncoderFrame		*encoderFrame = nil;
	OSSpinLockLock(&encoderProgressLock);
	if (encoderWaitingToRunOut)	{
		if (pb!=NULL)	{
			NSLog(@"\t\tERR: can't append pixel buffer, marked as finished and waiting for in-flight tasks to complete");
			returnMe = NO;
		}
	}
	//	else i'm not done accepting samples...
	else	{
		//	make a HapEncoderFrame (we'll finish populating it later, during the encode), and add it to the encoderProgressFrames array
		encoderFrame = (pb==NULL) ? nil : [[HapEncoderFrame alloc] initWithPresentationTime:t];
		if (encoderFrame!=nil)	{
			[encoderProgressFrames addObject:encoderFrame];
			[encoderFrame release];
		}
	}
	OSSpinLockUnlock(&encoderProgressLock);
	
	//	retain the pixel buffer i was passed- i'll release it in the block (on the GCD-controlled thread)
	if (pb!=NULL)
		CVPixelBufferRetain(pb);
	
	
	//	assemble a block that will encode the passed pixel buffer- i'll either be dispatching this block (via GCD) or executing it immediately...
	void			(^encodeBlock)() = ^(){
		//NSLog(@"%s",__func__);
		//	if there's a pixel buffer to encode, let's take care of that first
		if (pb!=NULL)	{
			//	lock the base address of the pixel buffer, get a ptr to the raw pixel data- i'll either be converting it or encoding it
			CVPixelBufferLockBaseAddress(pb,kHapCodecCVPixelBufferLockFlags);
			void			*sourceBuffer = CVPixelBufferGetBaseAddress(pb);
			void			*formatConvertBuffer = nil;
			
			//	if the passed buffer's pixel format doesn't match 'encoderInputPxlFmt', convert the pixels
			if (sourceFormat!=encoderInputPxlFmt)	{
				//FourCCLog(@"\t\tsource doesn't match encoder input, which is",encoderInputPxlFmt);
				formatConvertBuffer = CFAllocatorAllocate(_HIAVFMemPoolAllocator, formatConvertPoolLength, 0);
				switch (encoderInputPxlFmt)	{
				case kHapCVPixelFormat_CoCgXY:
					if (sourceFormat==k32BGRAPixelFormat)	{
						ConvertBGR_ToCoCg_Y8888((uint8_t *)sourceBuffer,
							(uint8_t *)formatConvertBuffer,
							(NSUInteger)exportImgSize.width,
							(NSUInteger)exportImgSize.height,
							CVPixelBufferGetBytesPerRow(pb),
							encoderInputPxlFmtBytesPerRow,
							0);
					}
					else	{
						ConvertRGB_ToCoCg_Y8888((uint8_t *)sourceBuffer,
							(uint8_t *)formatConvertBuffer,
							(NSUInteger)exportImgSize.width,
							(NSUInteger)exportImgSize.height,
							CVPixelBufferGetBytesPerRow(pb),
							encoderInputPxlFmtBytesPerRow,
							0);
					}
					break;
				case k32RGBAPixelFormat:
					if (sourceFormat==k32BGRAPixelFormat)	{
						uint8_t			permuteMap[] = {2, 1, 0, 3};
						ImageMath_Permute8888(sourceBuffer,
							CVPixelBufferGetBytesPerRow(pb),
							formatConvertBuffer,
							encoderInputPxlFmtBytesPerRow,
							(NSUInteger)exportImgSize.width,
							(NSUInteger)exportImgSize.height,
							permuteMap,
							0);
					}
					else	{
						NSLog(@"\t\terr: unhandled, %s",__func__);
						FourCCLog(@"\t\tsourceFormat is",sourceFormat);
						FourCCLog(@"\t\tencoderInputPxlFmt is",encoderInputPxlFmt);
					}
					break;
				default:
					NSLog(@"\t\terr: default case, %s",__func__);
					FourCCLog(@"\t\tsourceFormat is",sourceFormat);
					FourCCLog(@"\t\tencoderInputPxlFmt is",encoderInputPxlFmt);
					break;
				}
			}
			
			//	encode the DXT frame...
			
			void			*dxtBuffer = CFAllocatorAllocate(_HIAVFMemPoolAllocator, dxtBufferPoolLength, 0);
			int				intErr = 0;
			//	slightly different path depending on whether i'm converting the passed pixel buffer...
			OSSpinLockLock(&encoderLock);
			if (dxtEncoder==nil)	{
				NSLog(@"\t\terr: encoder nil in %s",__func__);
				intErr = -1;
			}
			else	{
				if (formatConvertBuffer==nil)	{
					intErr = ((HapCodecDXTEncoderRef)dxtEncoder)->encode_function(dxtEncoder,
						sourceBuffer,
						(unsigned int)CVPixelBufferGetBytesPerRow(pb),
						encoderInputPxlFmt,
						dxtBuffer,
						(unsigned int)exportImgSize.width,
						(unsigned int)exportImgSize.height);
				}
				//	...or if i'm converting the format conversion buffer 
				else	{
					intErr = ((HapCodecDXTEncoderRef)dxtEncoder)->encode_function(dxtEncoder,
						formatConvertBuffer,
						(unsigned int)(formatConvertPoolLength/(NSUInteger)exportImgSize.height),
						encoderInputPxlFmt,
						dxtBuffer,
						(unsigned int)exportImgSize.width,
						(unsigned int)exportImgSize.height);
				}
			}
			OSSpinLockUnlock(&encoderLock);
			//	unlock the pixel buffer immediately
			CVPixelBufferUnlockBaseAddress(pb,kHapCodecCVPixelBufferLockFlags);
			//	if there was an error with the DXT encode, don't proceed
			if (intErr!=0)	{
				NSLog(@"\t\terr %d encoding dxt data in %s, not appending buffer",intErr,__func__);
			}
			else	{
				//	make a buffer to encode into (needs enough memory for a max-size hap frame), then do the dxt->hap encode into this buffer
				OSStatus				osErr = noErr;
				CMBlockBufferRef		maxSizeHapBlockBuffer = NULL;
				osErr = CMBlockBufferCreateWithMemoryBlock(NULL, NULL, hapBufferPoolLength, _HIAVFMemPoolAllocator, NULL, 0, hapBufferPoolLength, kCMBlockBufferAssureMemoryNowFlag, &maxSizeHapBlockBuffer);
				if (osErr!=noErr)
					NSLog(@"\t\terr %d at CMBlockBufferCreateWithMemoryBlock() in %s, not appending buffer",(int)osErr,__func__);
				else	{
					void					*hapBuffer = nil;
					size_t					hapBufferLength = 0;
					unsigned long			bytesWrittenToHapBuffer = 0;
					osErr = CMBlockBufferGetDataPointer(maxSizeHapBlockBuffer, 0, NULL, &hapBufferLength, (char **)&hapBuffer);
					if (osErr!=noErr)
						NSLog(@"\t\terr %d at CMBlockBufferGetDataPointer() in %s, not appending buffer",(int)osErr,__func__);
					else	{
						enum HapResult		hapErr = HapResult_No_Error;
						hapErr = HapEncode(dxtBuffer,
							dxtBufferPoolLength,
							exportTextureType,
							HapCompressorSnappy,
							hapBuffer,
							hapBufferLength,
							&bytesWrittenToHapBuffer);
						if (hapErr!=HapResult_No_Error)
							NSLog(@"\t\terr %d at HapEncode() in %s, not appending buffer",hapErr,__func__);
						else	{
							//	make a new block buffer that refers to a subset of the previous block- only the subset that was populated with data.  this is necessary- if the sample buffer's length doesn't match the block buffer's length, the frame can't be added.
							CMBlockBufferRef			hapBlockBuffer = NULL;
							osErr = CMBlockBufferCreateWithBufferReference(NULL,
								maxSizeHapBlockBuffer,
								0,
								bytesWrittenToHapBuffer,
								0,
								&hapBlockBuffer);
							if (osErr!=noErr || hapBlockBuffer==NULL)
								NSLog(@"\t\terr %d creating block buffer from reference in %s, not appending buffer",(int)osErr,__func__);
							else	{
								//	make a CMFormatDescriptionRef that will describe the frame i'm supplying
								CMFormatDescriptionRef		desc = NULL;
								NSDictionary				*bufferExtensions = [NSDictionary dictionaryWithObjectsAndKeys:
									[NSNumber numberWithDouble:2.199996948242188], kCMFormatDescriptionExtension_GammaLevel,
									[NSNumber numberWithInt:((exportCodecType==kHapAlphaCodecSubType)?32:24)],kCMFormatDescriptionExtension_Depth,
									@"Hap",kCMFormatDescriptionExtension_FormatName,
									[NSNumber numberWithInt:2], kCMFormatDescriptionExtension_RevisionLevel,
									[NSNumber numberWithInt:512], kCMFormatDescriptionExtension_SpatialQuality,
									[NSNumber numberWithInt:0], kCMFormatDescriptionExtension_TemporalQuality,
									@"VDVX", kCMFormatDescriptionExtension_Vendor,
									[NSNumber numberWithInt:2], kCMFormatDescriptionExtension_Version,
									nil];
								osErr = CMVideoFormatDescriptionCreate(NULL,
									exportCodecType,
									(uint32_t)exportImgSize.width,
									(uint32_t)exportImgSize.height,
									(CFDictionaryRef)bufferExtensions,
									&desc);
								if (osErr!=noErr)
									NSLog(@"\t\terr %d at CMVideoFormatDescriptionCreate() in %s, not appending buffer",(int)osErr,__func__);
								else	{
									//	finish populating the 'encoderFrame' i created when i dispatched this block (which also updates its encoded var)
									[encoderFrame
										addEncodedBlockBuffer:hapBlockBuffer
										withLength:bytesWrittenToHapBuffer
										formatDescription:desc];
									//	release the format description i allocated
									CFRelease(desc);
									desc = NULL;
								}
								//	release the block buffer i allocated
								CFRelease(hapBlockBuffer);
								hapBlockBuffer = NULL;
							}
						}
					}
					
					//	release the block buffer i allocated
					if (maxSizeHapBlockBuffer!=NULL)	{
						CFRelease(maxSizeHapBlockBuffer);
						maxSizeHapBlockBuffer = NULL;
					}
				}
			}
			
			//	release the dxt and format conversion buffers, if they exist
			if (dxtBuffer!=nil)	{
				CFAllocatorDeallocate(_HIAVFMemPoolAllocator, dxtBuffer);
				dxtBuffer = nil;
			}
			if (formatConvertBuffer!=nil)	{
				CFAllocatorDeallocate(_HIAVFMemPoolAllocator, formatConvertBuffer);
				formatConvertBuffer = nil;
			}
			
			//	release the pixel buffer i retained before i dispatched this block!
			CVPixelBufferRelease(pb);
		}
		
		
		
		
		/*	...at this point, i would like to figure out which HapEncoderFrame instances in 
		"encoderProgressFrames" have had their "encoded" flags set to YES, create CMSampleBufferRefs 
		from them, and then append those CMSampleBufferRefs to me.  note that i do this even if i 
		didn't just create/encode/append a hap buffer...		*/
		
		[self appendEncodedFrames];
		
	};
	
	
	//	if i'm to be executing asynchronously, dispatch the encode block on the queue- else just execute the encode block
	if (a)
		dispatch_async(encodeQueue, encodeBlock);
	else
		encodeBlock();
	
	return returnMe;
}
- (BOOL) appendSampleBuffer:(CMSampleBufferRef)n	{
	BOOL						returnMe = NO;
	CMFormatDescriptionRef		sampleFmt = CMSampleBufferGetFormatDescription(n);
	//	try to get the format description of the sample
	if (sampleFmt!=NULL)	{
		//FourCCLog(@"\t\tmedia subtype of sample buffer is",CMFormatDescriptionGetMediaSubType(sampleFmt));
		OSType			sampleFourCC = CMFormatDescriptionGetMediaSubType(sampleFmt);
		//	if the format description is a match for the export type, just append it immediately
		if (sampleFourCC==exportCodecType)	{
			returnMe = [super appendSampleBuffer:n];
		}
		//	else the format description isn't a match for the export type- try to get the image buffer and then append it
		else	{
			CVImageBufferRef		sampleImageRef = CMSampleBufferGetImageBuffer(n);
			if (sampleImageRef!=NULL)
				returnMe = [self appendPixelBuffer:sampleImageRef withPresentationTime:CMSampleBufferGetPresentationTimeStamp(n) asynchronously:NO];
			else
				NSLog(@"\t\terr: sample missing image buffer in %s",__func__);
		}
	}
	//	else i couldn't get the sample's format description
	else	{
		NSLog(@"\t\terr: sample didn't have format description in %s",__func__);
		//	try to get the image buffer from the sample, then try appending it
		CVImageBufferRef		sampleImageRef = CMSampleBufferGetImageBuffer(n);
		if (sampleImageRef!=NULL)
			returnMe = [self appendPixelBuffer:sampleImageRef withPresentationTime:CMSampleBufferGetPresentationTimeStamp(n) asynchronously:NO];
		else
			NSLog(@"\t\terr: sample missing a format description didn't have an image buffer either in %s",__func__);
	}
	return returnMe;
}
- (BOOL) finishedEncoding	{
	BOOL		returnMe = NO;
	OSSpinLockLock(&encoderProgressLock);
	if ([encoderProgressFrames count]==0)
		returnMe = YES;
	OSSpinLockUnlock(&encoderProgressLock);
	return returnMe;
}
- (void) finishEncoding	{
	OSSpinLockLock(&encoderProgressLock);
	BOOL			needsToEncodeMore = NO;
	if (encoderWaitingToRunOut || [encoderProgressFrames count]>0)
		needsToEncodeMore = YES;
	OSSpinLockUnlock(&encoderProgressLock);
	
	if (needsToEncodeMore)
		[self appendEncodedFrames];
}
- (void)markAsFinished	{
	//NSLog(@"%s",__func__);
	OSSpinLockLock(&encoderProgressLock);
	encoderWaitingToRunOut = YES;
	OSSpinLockUnlock(&encoderProgressLock);
	//	append any encoded frames- if there are frames left over that aren't done encoding yet, this does nothing.  if there aren't any frames left over, it marks the input as finished.
	[self appendEncodedFrames];
}
- (BOOL) isReadyForMoreMediaData	{
	BOOL		returnMe = [super isReadyForMoreMediaData];
	if (returnMe)	{
		OSSpinLockLock(&encoderProgressLock);
		if (encoderWaitingToRunOut)	{
			//NSLog(@"\t\tpretending i'm not ready for more data, waiting to run out- %s",__func__);
			returnMe = NO;
		}
		else if ([encoderProgressFrames count]>8)	{
			//NSLog(@"\t\ttoo many frames waiting to be appended, not ready- %s",__func__);
			returnMe = NO;
		}
		OSSpinLockUnlock(&encoderProgressLock);
	}
	return returnMe;
}
//	synthesized so we get automatic atomicity
@synthesize lastEncodedDuration;

//	runs through the encoder progress frames, getting as many sample buffers as possible and appending them (in order)
- (void) appendEncodedFrames	{
	//NSLog(@"%s",__func__);
	/*
	//	this bit just appends every encoded frame with a duration of 1- i don't know if it produces an accurate file or not.
	OSSpinLockLock(&encoderProgressLock);
	//	run through all the frames that are encoded, stop as soon as i hit a frame that isn't encoded
	NSUInteger			countOfFramesToRemove = 0;
	for (HapEncoderFrame *framePtr in encoderProgressFrames)	{
		if (![framePtr encoded])
			break;
		CMSampleBufferRef		hapSampleBuffer = [framePtr allocCMSampleBufferWithDurationTimeValue:1];
		if (hapSampleBuffer==NULL)
			NSLog(@"\t\terr: couldn't make hap sample buffer, %s",__func__);
		else	{
			[super appendSampleBuffer:hapSampleBuffer];
			CFRelease(hapSampleBuffer);
			hapSampleBuffer = NULL;
		}
		++countOfFramesToRemove;
	}
	for (int i=0; i<countOfFramesToRemove; ++i)
		[encoderProgressFrames removeObjectAtIndex:0];
	if (encoderWaitingToRunOut && [encoderProgressFrames count]==0)	{
		NSLog(@"\t\twaiting to run out & no more frames, marking super as finished");
		[super markAsFinished];
	}
	OSSpinLockUnlock(&encoderProgressLock);
	*/
	
	
	
	
	OSSpinLockLock(&encoderProgressLock);
	if (![super isReadyForMoreMediaData])	{
		NSLog(@"\t\terr: not ready for more media data, %s",__func__);
		[encoderProgressFrames removeAllObjects];
		[super markAsFinished];
	}
	//	first of all, if there's only one sample and i'm waiting to finish- append the last sample and then i'm done (yay!)
	else if (encoderWaitingToRunOut && [encoderProgressFrames count]<=1)	{
		HapEncoderFrame			*lastFrame = ([encoderProgressFrames count]<1) ? nil : [encoderProgressFrames objectAtIndex:0];
		if (lastFrame!=nil && [lastFrame encoded])	{
			//NSLog(@"\t\tone frame left and it's encoded, making a sample buffer and then appending it");
			//	make a hap sample buffer, append it
			CMSampleBufferRef	hapSampleBuffer = [lastFrame allocCMSampleBufferWithDurationTimeValue:[self lastEncodedDuration].value];
			if (hapSampleBuffer==NULL)
				NSLog(@"\t\terr: couldn't make sample buffer from frame duration, %s",__func__);
			else	{
				[super appendSampleBuffer:hapSampleBuffer];
				CFRelease(hapSampleBuffer);
			}
			[encoderProgressFrames removeObjectAtIndex:0];
			//	mark myself as finished either way
			//NSLog(@"\t\tmarking super as finished in %s",__func__);
			[super markAsFinished];
		}
		else if (lastFrame==nil)	{
			//NSLog(@"\t\tno last frame, marking super as finished in %s",__func__);
			[super markAsFinished];
		}
	}
	//	else i'm either not waiting to run out, or there's more than one frame in the array...
	else	{
		//	i'm going to run through all the encoderProgressFrames, trying to append as many encoded frames as i can
		HapEncoderFrame		*lastFramePtr = nil;
		int					numberOfSamplesAppended = 0;
		for (HapEncoderFrame *framePtr in encoderProgressFrames)	{
			//	if there's at least one other encoded frame...
			if (lastFramePtr!=nil)	{
				//	if the last frame isn't encoded or i'm not ready for more media data, bail- i can't do anything
				if (![lastFramePtr encoded] || ![super isReadyForMoreMediaData])
					break;
				
				//	tell the last frame to create a sample buffer derived from this frame's presentation time
				CMSampleBufferRef	hapSampleBuffer = [lastFramePtr allocCMSampleBufferWithNextFramePresentationTime:[framePtr presentationTime]];
				if (hapSampleBuffer==NULL)
					NSLog(@"\t\terr: couldn't make sample buffer from frame, %s, not appending buffer",__func__);
				else	{
					//	save the duration- i need to save the duration because i have to apply a duration to the final frame
					CMSampleTimingInfo		sampleTimingInfo;
					CMSampleBufferGetSampleTimingInfo(hapSampleBuffer, 0, &sampleTimingInfo);
					//NSLog(@"\t\tappending sample at time %@",[(id)CMTimeCopyDescription(kCFAllocatorDefault, sampleTimingInfo.presentationTimeStamp) autorelease]);
					[self setLastEncodedDuration:sampleTimingInfo.duration];
					
					[super appendSampleBuffer:hapSampleBuffer];
					CFRelease(hapSampleBuffer);
				}
				//	increment the # of samples appended regardless- if i couldn't make a sample buffer i want to free the frame
				++numberOfSamplesAppended;
			}
			lastFramePtr = framePtr;
		}
		//	if i appended samples, i can free those frames now...
		if (numberOfSamplesAppended>0)	{
			for (int i=0; i<numberOfSamplesAppended; ++i)
				[encoderProgressFrames removeObjectAtIndex:0];
		}
	}
	OSSpinLockUnlock(&encoderProgressLock);
	
}


- (BOOL) canPerformMultiplePasses	{
	return NO;
}
- (void) setPerformsMultiPassEncodingIfSupported:(BOOL)n	{
	[super setPerformsMultiPassEncodingIfSupported:NO];
}


@end
