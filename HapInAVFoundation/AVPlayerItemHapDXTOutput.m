#import "AVPlayerItemHapDXTOutput.h"
#import "AVPlayerItemAdditions.h"
#import "PixelFormats.h"




BOOL				_AVFinHapCVInit = NO;




@implementation AVPlayerItemHapDXTOutput


+ (void) initialize	{
	@synchronized (self)	{
		if (!_AVFinHapCVInit)	{
			HapCodecRegisterPixelFormats();
			_AVFinHapCVInit = YES;
		}
	}
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
		allocFrameBlock = nil;
		postDecodeBlock = nil;
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
//	this method should always be called from a GCD-controlled thread!
- (void) _decodeFrameForTime:(CMTime)decodeTime	{
	HapDecoderFrameAllocBlock		localAllocFrameBlock = nil;
	AVFHapDXTPostDecodeBlock		localPostDecodeBlock = nil;
	OSSpinLockLock(&propertyLock);
	if (track!=nil)	{
		AVSampleCursor			*cursor = [track makeSampleCursorWithPresentationTimeStamp:decodeTime];
		CMTime					cursorTime = [cursor presentationTimeStamp];
		//	if the requested decode time is different from the last time i generated a sample for...
		if (!CMTIME_COMPARE_INLINE(lastGeneratedSampleTime,==,cursorTime))	{
			//	generate a sample buffer for the requested time.  this sample buffer contains a hap frame (compressed).
			AVSampleBufferRequest	*request = [[AVSampleBufferRequest alloc] initWithStartCursor:cursor];
			CMSampleBufferRef		newSample = (gen==nil) ? nil : [gen createSampleBufferForRequest:request];
			if (newSample==NULL)
				NSLog(@"\t\terr: sample null, %s",__func__);
			else	{
				/*
				NSUInteger		sampleCount = CMSampleBufferGetNumSamples(newSample);
				NSLog(@"\t\tthere are %ld sample",(unsigned long)sampleCount);
				CMSampleTimingInfo		*timingInfoStruct = malloc(sizeof(CMSampleTimingInfo));
				for (int i=0; i<sampleCount; ++i)	{
					CMSampleBufferGetSampleTimingInfo(newSample, i, timingInfoStruct);
					NSLog(@"\t\t\tsample %d is %@/%@",i,[(NSString *)CMTimeCopyDescription(kCFAllocatorDefault, timingInfoStruct->presentationTimeStamp) autorelease],[(NSString *)CMTimeCopyDescription(kCFAllocatorDefault, timingInfoStruct->duration) autorelease]);
				}
				free(timingInfoStruct);
				*/
				
				
				lastGeneratedSampleTime = cursorTime;
				localAllocFrameBlock = (allocFrameBlock==nil) ? nil : [allocFrameBlock retain];
				localPostDecodeBlock = (postDecodeBlock==nil) ? nil : [postDecodeBlock retain];
				OSSpinLockUnlock(&propertyLock);
				
				
				//	allocate a decoder frame- this data structure holds all the values needed to decode the hap frame into a blob of memory (actually a DXT frame).  if there's a custom frame allocator block, use that- otherwise, just make a CFData and decode into that.
				HapDecoderFrame			*newDecoderFrame = nil;
				if (localAllocFrameBlock!=nil)
					newDecoderFrame = localAllocFrameBlock(newSample);
				if (newDecoderFrame==nil)
					newDecoderFrame = [[HapDecoderFrame alloc] initWithHapSampleBuffer:newSample];
				
				if (newDecoderFrame==nil)
					NSLog(@"\t\terr: decoder frame nil, %s",__func__);
				else	{
					//	tell the frame to decode- then run the post-decode block (if there is one)
					[newDecoderFrame _decode];
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
				
				CFRelease(newSample);
			}
			
			if (request != nil)	{
				[request release];
				request = nil;
			}
		}
	}
	OSSpinLockUnlock(&propertyLock);
	
	if (localAllocFrameBlock!=nil)
		[localAllocFrameBlock release];
	if (localPostDecodeBlock!=nil)
		[localPostDecodeBlock release];
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


@end

