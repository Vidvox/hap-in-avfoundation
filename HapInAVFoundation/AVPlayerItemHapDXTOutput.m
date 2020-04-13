#import "AVPlayerItemHapDXTOutput.h"
#import "AVPlayerItemAdditions.h"
#import "AVAssetAdditions.h"
#import "PixelFormats.h"
#import "HapPlatform.h"
#import "HapCodecGL.h"
#include "YCoCg.h"
#include "YCoCgDXT.h"
#include "SquishRGTC1Decoder.h"




BOOL				_AVFinHapCVInit = NO;
/*			Callback for multithreaded Hap decoding			*/
void HapMTDecode(HapDecodeWorkFunction function, void *p, unsigned int count, void *info HAP_ATTR_UNUSED)	{
	dispatch_apply(count, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t index) {
		function(p, (unsigned int)index);
	});
}
#define FourCCLog(n,f) NSLog(@"%@, %c%c%c%c",n,(int)((f>>24)&0xFF),(int)((f>>16)&0xFF),(int)((f>>8)&0xFF),(int)((f>>0)&0xFF))
#define LOCK os_unfair_lock_lock
#define UNLOCK os_unfair_lock_unlock
#define MAXDECODETIMES 6
#define MAXDECODEFRAMES 3
#define MAXDECODINGFRAMES 3
#define MAXDECODEDFRAMES 3
#define MAXPLAYEDOUTFRAMES 3




@implementation AVPlayerItemHapDXTOutput


+ (void) initialize	{
	@synchronized (self)	{
		if (!_AVFinHapCVInit)	{
			HapCodecRegisterPixelFormats();
			_AVFinHapCVInit = YES;
		}
	}
	//	make sure the CMMemoryPool used by this framework exists
	LOCK(&_HIAVFMemPoolLock);
	if (_HIAVFMemPool==NULL)
		_HIAVFMemPool = CMMemoryPoolCreate(NULL);
	if (_HIAVFMemPoolAllocator==NULL)
		_HIAVFMemPoolAllocator = CMMemoryPoolGetAllocator(_HIAVFMemPool);
	UNLOCK(&_HIAVFMemPoolLock);
}
- (id) initWithHapAssetTrack:(AVAssetTrack *)n	{
	self = [self init];
	if (self!=nil)	{
		if (n!=nil)	{
			LOCK(&propertyLock);
			
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
			if (decodeTimes != nil)
				[decodeTimes removeAllObjects];
			if (decodeFrames != nil)
				[decodeFrames removeAllObjects];
			if (decodingFrames != nil)
				[decodingFrames removeAllObjects];
			if (decodedFrames != nil)
				[decodedFrames removeAllObjects];
			if (playedOutFrames != nil )
				[playedOutFrames removeAllObjects];
			
			UNLOCK(&propertyLock);
		}
	}
	return self;
}
- (id) init	{
	self = [super init];
	if (self!=nil)	{
		propertyLock = OS_UNFAIR_LOCK_INIT;
		decodeQueue = NULL;
		track = nil;
		gen = nil;
		lastGeneratedSampleTime = kCMTimeInvalid;
		decodeTimes = [[NSMutableArray arrayWithCapacity:0] retain];
		decodeFrames = [[NSMutableArray arrayWithCapacity:0] retain];
		decodingFrames = [[NSMutableArray arrayWithCapacity:0] retain];
		decodedFrames = [[NSMutableArray arrayWithCapacity:0] retain];
		playedOutFrames = [[NSMutableArray arrayWithCapacity:0] retain];
		outputAsRGB = NO;
		destRGBPixelFormat = kCVPixelFormatType_32RGBA;
		dxtPoolLengths[0] = 0;
		dxtPoolLengths[1] = 0;
		convPoolLength = 0;
		rgbPoolLength = 0;
		allocFrameBlock = NULL;
		postDecodeBlock = NULL;
		[self setSuppressesPlayerRendering:YES];
	}
	return self;
}
- (void) dealloc	{
	LOCK(&propertyLock);
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
	if (decodeTimes != nil)	{
		[decodeTimes release];
		decodeTimes = nil;
	}
	if (decodeFrames != nil)	{
		[decodeFrames release];
		decodeFrames = nil;
	}
	if (decodingFrames != nil)	{
		[decodingFrames release];
		decodingFrames = nil;
	}
	if (decodedFrames != nil)	{
		[decodedFrames release];
		decodedFrames = nil;
	}
	if (playedOutFrames != nil)	{
		[playedOutFrames release];
		playedOutFrames = nil;
	}
	if (allocFrameBlock != nil)	{
		Block_release(allocFrameBlock);
		allocFrameBlock = nil;
	}
	if (postDecodeBlock!=nil)	{
		Block_release(postDecodeBlock);
		postDecodeBlock = nil;
	}
	UNLOCK(&propertyLock);
	[super dealloc];
}

#pragma mark -

//	you must lock before calling this method- checks all cached frames looking for a frame with the passed time
- (BOOL) _containsPendingFrameForTime:(CMTime)n	{
	for (HapDecoderFrame *framePtr in decodeFrames)	{
		if ([framePtr containsTime:n])	{
			return YES;
		}
	}
	for (HapDecoderFrame *framePtr in decodingFrames)	{
		if ([framePtr containsTime:n])	{
			return YES;
		}
	}
	return NO;
}
- (BOOL) _containsAvailableFrameForTime:(CMTime)n	{
	for (HapDecoderFrame *framePtr in decodedFrames)	{
		if ([framePtr containsTime:n])	{
			return YES;
		}
	}
	for (HapDecoderFrame *framePtr in playedOutFrames)	{
		if ([framePtr containsTime:n])	{
			return YES;
		}
	}
	return NO;
}
//	you should only call this method from the 'decodeQueue'!  doesn't decode anything- just creates a HapDecoderFrame instance with all the appropriate fields/blocks of memory, and places it in 'decodeFrames'
- (void) _prepareDecodeFrameForTime:(CMTime)n	{
	//NSLog(@"%s ... %f",__func__,CMTimeGetSeconds(n));
	LOCK(&propertyLock);
	//	check to see if we already have a decode frame pending or available for that time
	if ([self _containsPendingFrameForTime:n] || [self _containsAvailableFrameForTime:n])	{
		//	do nothing, we've already got a frame in decodeFrames or decodingFrames that contains the passed time
		UNLOCK(&propertyLock);
	}
	//	else we don't have a frame for the corresponding time- set one up by pulling a sample from the track
	else	{
		//	get a CMSampleBufferRef for the passed time, use the buffer to set up a decode
		if (track!=nil)	{
			AVSampleCursor			*cursor = [track makeSampleCursorWithPresentationTimeStamp:n];
			//	generate a sample buffer for the requested time.  this sample buffer contains a hap frame (compressed).
			AVSampleBufferRequest	*request = [[AVSampleBufferRequest alloc] initWithStartCursor:cursor];
			[request setMode:AVSampleBufferRequestModeImmediate];
			CMSampleBufferRef		newSample = (gen==nil) ? nil : [gen createSampleBufferForRequest:request];
			UNLOCK(&propertyLock);
		
			if (newSample==NULL)	{
				NSLog(@"\t\terr: sample null, %s",__func__);
			}
			else	{
				[self _prepareDecodeFrameForCMSampleBuffer:newSample];
				CFRelease(newSample);
				newSample = NULL;
			}
		
			if (request != nil)	{
				[request release];
				request = nil;
			}
		}
		else	{
			NSLog(@"\t\terr: track nil in %s",__func__);
			UNLOCK(&propertyLock);
		}
	}
}
//	you should only call this method from the 'decodeQueue'!  doesn't decode anything- just creates a HapDecoderFrame instance with all the appropriate fields/blocks of memory, and places it in 'decodeFrames'
- (void) _prepareDecodeFrameForCMSampleBuffer:(CMSampleBufferRef)n	{
	//NSLog(@"%s ... %f",__func__,CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(n)));
	//NSLog(@"%s ... %@",__func__,[(id)CMTimeCopyDescription(kCFAllocatorDefault, CMSampleBufferGetPresentationTimeStamp(n)) autorelease]);
	OSStatus				cmErr = noErr;
	if (CMSampleBufferHasDataFailed(n, &cmErr))	{
		NSLog(@"\t\terr: CMSampleBufferHasDataFailed in %s returns %d",__func__,cmErr);
	}
	else if (!CMSampleBufferIsValid(n))	{
		NSLog(@"\t\terr: CMSampleBufferIsValid failed in %s",__func__);
	}
	
	
	
	
	/*	as of 10.13, the sample buffer we were passed may not be contiguous.  this is a problem 
	because we expect to read directly from the block buffer during decompression, so if this is the 
	case we have to create a contiguous sample buffer and go from there.			*/
	CMBlockBufferRef		origBlockBuffer = CMSampleBufferGetDataBuffer(n);
	if (origBlockBuffer == NULL)
		return;
	
	//	make sure that the sample buffer's data is ready, because that's a problem too now in 10.13
	while (!CMSampleBufferDataIsReady(n))	{
		//NSLog(@"\t\tsleeping, sample buffer isn't ready yet in %s",__func__);
		usleep(1000);
	}
	
	//	if the orig block buffer is contiguous, then we already have a contiguous sample buffer- we can proceed
	CMSampleBufferRef		contigSampleBuffer = NULL;
	if (CMBlockBufferIsRangeContiguous(origBlockBuffer,0,0))	{
		contigSampleBuffer = n;
		CFRetain(contigSampleBuffer);
	}
	//	else the orig block buffer is *not* contiguous- we have to make a new block buffer, and then make a new sample buffer from that
	else	{
		//NSLog(@"\t\tblock buffer isn't contiguous, correcting...");
		//	make a new contiguous block buffer
		CMBlockBufferRef		contigBlockBuffer = NULL;
		cmErr = CMBlockBufferCreateContiguous(
			_HIAVFMemPoolAllocator,	//	structure allocator
			origBlockBuffer,	//	source buffer
			_HIAVFMemPoolAllocator,	//	block allocator
			NULL,	//	custom block source
			0,	//	offset to data
			0, 	//	data length
			kCMBlockBufferAssureMemoryNowFlag | kCMBlockBufferAlwaysCopyDataFlag,	//	flags
			&contigBlockBuffer);
		if (cmErr!=noErr || contigBlockBuffer==NULL)	{
			NSLog(@"\t\terr: %d creating contiguous block buffer in %s",(int)cmErr,__func__);
		}
		else	{
			//	get the sample timing info array
			CMItemCount				timingInfoCount = 0;
			cmErr = CMSampleBufferGetSampleTimingInfoArray(n, 0, NULL, &timingInfoCount);
			CMSampleTimingInfo		*timingInfoArray = NULL;
			if (timingInfoCount > 0)	{
				timingInfoArray = malloc(sizeof(CMSampleTimingInfo)*timingInfoCount);
				cmErr = CMSampleBufferGetSampleTimingInfoArray(n, timingInfoCount, timingInfoArray, &timingInfoCount);
			}
			//	get the sample size array
			CMItemCount				sampleSizeCount = 0;
			cmErr = CMSampleBufferGetSampleSizeArray(n, 0, NULL, &sampleSizeCount);
			size_t					*sampleSizeArray = NULL;
			if (sampleSizeCount > 0)	{
				sampleSizeArray = malloc(sizeof(size_t)*sampleSizeCount);
				cmErr = CMSampleBufferGetSampleSizeArray(n, sampleSizeCount, sampleSizeArray, &sampleSizeCount);
			}
			
			
			//	make a new sample buffer
			cmErr = CMSampleBufferCreateReady(
				_HIAVFMemPoolAllocator,	//	allocator
				contigBlockBuffer,	//	data buffer- must not be NULL
				CMSampleBufferGetFormatDescription(n),	//	format description
				CMSampleBufferGetNumSamples(n),	//	number of samples
				timingInfoCount,	//	number of sample timing entries
				timingInfoArray,	//	array of CMSampleTimingInfo structs
				sampleSizeCount,	//	number of sample sizes
				sampleSizeArray,	//	array of sample size entries, one per sample
				&contigSampleBuffer);
			if (cmErr!=noErr || contigBlockBuffer==NULL)	{
				NSLog(@"\t\terr: %d creating sample buffer in %s",(int)cmErr,__func__);
			}
			else	{
				//NSLog(@"\t\tlooks like we successfully created a contiguous buffer?");
			}
			
			
			//	release the sample size array we allocated locally
			if (sampleSizeArray != NULL)	{
				free(sampleSizeArray);
				sampleSizeArray = NULL;
			}
			//	release the timing info array we allocated locally
			if (timingInfoArray != NULL)	{
				free(timingInfoArray);
				timingInfoArray = NULL;
			}
			//	release the block buffer
			CFRelease(contigBlockBuffer);
			contigBlockBuffer = NULL;
		}
		
	}
	
	
	if (contigSampleBuffer == NULL)	{
		NSLog(@"\t\terr: couldn't create a contiguous sample buffer in %s for %@",__func__,n);
		return;
	}
	//	...at this point we've established a contiguous sample buffer with the data that we need to decompress.
	
	
	HapDecoderFrameAllocBlock		localAllocFrameBlock = nil;
	
	LOCK(&propertyLock);
	localAllocFrameBlock = (allocFrameBlock==nil) ? nil : [allocFrameBlock retain];
	BOOL				localOutputAsRGB = outputAsRGB;
	OSType				localDestRGBPixelFormat = destRGBPixelFormat;
	UNLOCK(&propertyLock);
	
	
	//	make a sample decoder frame from the sample buffer- this calculates various minimum buffer sizes
	HapDecoderFrame		*sampleDecoderFrame = [[HapDecoderFrame alloc] initEmptyWithHapSampleBuffer:contigSampleBuffer];
	size_t				*dxtMinDataSizes = [sampleDecoderFrame dxtMinDataSizes];
	size_t				rgbMinDataSize = [sampleDecoderFrame rgbMinDataSize];
	//	make sure that the buffer pools are sized appropriately.  don't know if i'll be using them or not, but make sure they're sized properly regardless.
	dxtPoolLengths[0] = dxtMinDataSizes[0];
	dxtPoolLengths[1] = dxtMinDataSizes[1];
	if (localOutputAsRGB)	{
		if (rgbPoolLength!=rgbMinDataSize)
			rgbPoolLength = rgbMinDataSize;
	}
	//	allocate a decoder frame- this data structure holds all the values needed to decode the hap frame into a blob of memory (actually a DXT frame).  if there's a custom frame allocator block, use that- otherwise, just make a CFData and decode into that.
	HapDecoderFrame			*newDecoderFrame = nil;
	if (localAllocFrameBlock!=nil)	{
		newDecoderFrame = localAllocFrameBlock(contigSampleBuffer);
	}
	if (newDecoderFrame==nil)	{
		//	make an empty frame (i can just retain & use the sample frame i made earlier to size the pools)
		newDecoderFrame = (sampleDecoderFrame==nil) ? nil : [sampleDecoderFrame retain];
		
		//	allocate mem objects for dxt and rgb data
		void			**dxtMem = [newDecoderFrame dxtDatas];
		dxtMem[0] = CFAllocatorAllocate(_HIAVFMemPoolAllocator, dxtPoolLengths[0], 0);
		dxtMem[1] = (dxtPoolLengths[1]<1) ? nil : CFAllocatorAllocate(_HIAVFMemPoolAllocator, dxtPoolLengths[1], 0);
		//	update the data sizes in the frame
		size_t			*dxtDataSizes = [newDecoderFrame dxtDataSizes];
		dxtDataSizes[0] = dxtPoolLengths[0];
		dxtDataSizes[1] = (dxtPoolLengths[1]<1) ? 0 : dxtPoolLengths[1];
		void			*rgbMem = (localOutputAsRGB) ? CFAllocatorAllocate(_HIAVFMemPoolAllocator, rgbPoolLength, 0) : nil;
		
		
		if (localOutputAsRGB)	{
			[newDecoderFrame setRGBData:rgbMem];
			[newDecoderFrame setRGBDataSize:rgbPoolLength];
			//	make sure that the frame i'll be decoding knows what pixel format it should be decoding to
			[newDecoderFrame setRGBPixelFormat:localDestRGBPixelFormat];
		}
		//	store the CFData instances- which are pooled- in the frame
		CFDataRef		dxtAlphaDataRef = (dxtPoolLengths[1]<1 || dxtMem[1]==NULL)
			?	NULL
			:	CFDataCreateWithBytesNoCopy(NULL, dxtMem[1], dxtPoolLengths[1], _HIAVFMemPoolAllocator);
		if (localOutputAsRGB)	{
			CFDataRef		dxtDataRef = CFDataCreateWithBytesNoCopy(NULL, dxtMem[0], dxtPoolLengths[0], _HIAVFMemPoolAllocator);
			CFDataRef		rgbDataRef = (rgbPoolLength<1 || rgbMem==NULL)
				?	NULL
				:	CFDataCreateWithBytesNoCopy(NULL, rgbMem, rgbPoolLength, _HIAVFMemPoolAllocator);
			[newDecoderFrame setUserInfo:[NSArray arrayWithObjects:(NSData *)dxtDataRef, (dxtAlphaDataRef==NULL)?(id)[NSNull null]:(NSData *)dxtAlphaDataRef, (rgbDataRef==NULL)?[NSNull null]:(NSData *)rgbDataRef, nil]];
			if (dxtDataRef != NULL)	{
				CFRelease(dxtDataRef);
				dxtDataRef = NULL;
			}
			if (rgbDataRef != NULL)	{
				CFRelease(rgbDataRef);
				rgbDataRef = NULL;
			}
		}
		else	{
			CFDataRef		dxtDataRef = CFDataCreateWithBytesNoCopy(NULL, dxtMem[0], dxtPoolLengths[0], _HIAVFMemPoolAllocator);
			[newDecoderFrame setUserInfo:[NSArray arrayWithObjects:(NSData *)dxtDataRef, (NSData *)dxtAlphaDataRef, nil]];
			CFRelease(dxtDataRef);
		}
		if (dxtAlphaDataRef != NULL)	{
			CFRelease(dxtAlphaDataRef);
			dxtAlphaDataRef = NULL;
		}
	}
	//	free the sample decoder frame i used to calculate and configure the size of the buffer pools
	if (sampleDecoderFrame!=nil)	{
		[sampleDecoderFrame release];
		sampleDecoderFrame = nil;
	}
	
	//	if i've created a new decoder frame, add it to the array of frames to be decoded
	if (newDecoderFrame==nil)
		NSLog(@"\t\terr: decoder frame nil, %s",__func__);
	else	{
        LOCK(&propertyLock);
		[decodeFrames addObject:newDecoderFrame];
		while ([decodeFrames count] > MAXDECODEFRAMES)
			[decodeFrames removeObjectAtIndex:0];
        UNLOCK(&propertyLock);
		
		[newDecoderFrame release];
		newDecoderFrame = nil;
	}
	
	
	if (localAllocFrameBlock!=nil)
		[localAllocFrameBlock release];
	
	if (contigSampleBuffer != NULL)	{
		CFRelease(contigSampleBuffer);
		contigSampleBuffer = NULL;
	}
}
//	you should only call this method from the 'decodeQueue'!  does nothing if you haven't already prepared a decode frame!  pulls the appropriate frame from 'decodeFrames', moves it to 'decodingFrames', starts decoding it, moves it to 'decodedFrames' when complete
- (void) _beginDecodingFrameForTime:(CMTime)n	{
	//NSLog(@"%s ... %f",__func__,CMTimeGetSeconds(n));
	//	find a frame to decode
	HapDecoderFrame		*frameToDecode = nil;
	NSInteger			tmpIndex = 0;
	NSInteger			matchingIndex = NSNotFound;
	LOCK(&propertyLock);
	tmpIndex = 0;
	matchingIndex = NSNotFound;
	for (HapDecoderFrame *frame in decodeFrames)	{
		if ([frame containsTime:n])	{
			frameToDecode = [frame retain];
			matchingIndex = tmpIndex;
			break;
		}
		++tmpIndex;
	}
	if (frameToDecode == nil)	{
		NSLog(@"\t\terr: frameToDecode nil in %s",__func__);
	}
	else	{
		[decodingFrames addObject:frameToDecode];
		while ([decodingFrames count]>MAXDECODINGFRAMES)
			[decodingFrames removeObjectAtIndex:0];
		if (matchingIndex != NSNotFound)
			[decodeFrames removeObjectAtIndex:matchingIndex];
	}
	UNLOCK(&propertyLock);
	
	//	if i found something to decode...
	if (frameToDecode != nil)	{
		//	decode the frame
		[self _decodeHapDecoderFrame:frameToDecode];
		
		//	now that i'm done decoding it, move it into the array of decoded frames
		LOCK(&propertyLock);
		tmpIndex = 0;
		matchingIndex = NSNotFound;
		for (HapDecoderFrame *frame in decodingFrames)	{
			if (frame == frameToDecode)	{
				matchingIndex = tmpIndex;
				break;
			}
			++tmpIndex;
		}
		[decodedFrames addObject:frameToDecode];
		while ([decodedFrames count]>MAXDECODEDFRAMES)
			[decodedFrames removeObjectAtIndex:0];
		if (matchingIndex != NSNotFound)
			[decodingFrames removeObjectAtIndex:matchingIndex];
		UNLOCK(&propertyLock);
		
		[frameToDecode release];
		frameToDecode = nil;
	}
}
//	you should only call this method from the 'decodeQueue'!  does nothing if 'decodeFrames' is empty!  pulls a frame from 'decodeFrames', moves it to 'decodingFrames', starts decoding it, moves it to 'decodedFrames' when complete
- (void) _beginDecodingNextFrame	{
	//NSLog(@"%s",__func__);
	//	copy the 'decodeTimes' and clear the array
	LOCK(&propertyLock);
	NSArray			*copiedDecodeTimes = (decodeTimes==nil || [decodeTimes count]<1) ? nil : [[decodeTimes copy] autorelease];
	[decodeTimes removeAllObjects];
	UNLOCK(&propertyLock);
	//	run through the copy of decode times, prepping frames for each time
	for (NSValue *timeVal in copiedDecodeTimes)	{
		CMTime		time = [timeVal CMTimeValue];
		[self _prepareDecodeFrameForTime:time];
	}
	
	//	find a frame to decode
    LOCK(&propertyLock);
	HapDecoderFrame		*frameToDecode = nil;
	frameToDecode = (decodeFrames==nil || [decodeFrames count]<1) ? nil : [[decodeFrames objectAtIndex:0] retain];
	if (frameToDecode == nil)	{
		//NSLog(@"\t\terr: frameToDecode nil in %s",__func__);
	}
	else	{
		[decodingFrames addObject:frameToDecode];
		while ([decodingFrames count]>MAXDECODINGFRAMES)
			[decodingFrames removeObjectAtIndex:0];
		[decodeFrames removeObjectAtIndex:0];
	}
	UNLOCK(&propertyLock);
	
	//	if i found something to decode...
	if (frameToDecode != nil)	{
		//	decode the frame
		[self _decodeHapDecoderFrame:frameToDecode];
		
		//	now that i'm done decoding it, move it into the array of decoded frames
		LOCK(&propertyLock);
		NSInteger			tmpIndex = 0;
		NSInteger			matchingIndex = NSNotFound;
		for (HapDecoderFrame *frame in decodingFrames)	{
			if (frame == frameToDecode)	{
				matchingIndex = tmpIndex;
				break;
			}
			++tmpIndex;
		}
		[decodedFrames addObject:frameToDecode];
		while ([decodedFrames count]>MAXDECODEDFRAMES)
			[decodedFrames removeObjectAtIndex:0];
		if (matchingIndex != NSNotFound)
			[decodingFrames removeObjectAtIndex:matchingIndex];
		
		
		//	we're adding a decoded frame- increment the age of any other decoded frames, then remove any frames that are "too old"
		NSMutableIndexSet		*indicesToDelete = nil;
		tmpIndex = 0;
		//NSLog(@"\t\tdecoded frame %@, bumping age of decoded frames",frameToDecode);
		for (HapDecoderFrame *frame in decodedFrames)	{
			[frame incrementAge];
			if ([frame age] >= MAXDECODEFRAMES)	{
				//NSLog(@"\t\tframe %@ is too old and should be tossed",frame);
				if (indicesToDelete == nil)
					indicesToDelete = [[[NSMutableIndexSet alloc] init] autorelease];
				[indicesToDelete addIndex:tmpIndex];
			}
			++tmpIndex;
		}
		if (indicesToDelete != nil)
			[decodedFrames removeObjectsAtIndexes:indicesToDelete];
		
		
		UNLOCK(&propertyLock);
		
		[frameToDecode release];
		frameToDecode = nil;
	}
	
	//	if there are any decodeFrames, we'll need to call this method again...
	LOCK(&propertyLock);
	BOOL			shouldBeginDecodingNextFrame = ([decodeFrames count]<1) ? NO : YES;
	if (shouldBeginDecodingNextFrame && decodeQueue!=nil)	{
		dispatch_async(decodeQueue, ^{
			@autoreleasepool	{
				[self _beginDecodingNextFrame];
			}
		});
	}
	UNLOCK(&propertyLock);
	
}
- (void) _beginDecodingFrameForCMSampleBuffer:(CMSampleBufferRef)n	{
	//NSLog(@"%s",__func__);
	if (n == NULL)
		return;
	CMTime			sampleTime = CMSampleBufferGetPresentationTimeStamp(n);
	[self _beginDecodingFrameForTime:sampleTime];
}
- (void) _decodeHapDecoderFrame:(HapDecoderFrame *)n	{
	//NSLog(@"%s ... %@",__func__,n);
	if (n==nil)	{
		NSLog(@"\t\terr: decoder frame nil, %s",__func__);
		return;
	}
	
	[n retain];
	
	LOCK(&propertyLock);
	AVFHapDXTPostDecodeBlock		localPostDecodeBlock = (postDecodeBlock==nil) ? nil : [postDecodeBlock retain];
	//BOOL				localOutputAsRGB = outputAsRGB;
	//OSType				localDestRGBPixelFormat = destRGBPixelFormat;
	UNLOCK(&propertyLock);
	
	//	decode the frame (into DXT data)
	NSSize				imgSize = [n imgSize];
	NSSize				dxtImgSize = [n dxtImgSize];
	void				**dxtDatas = [n dxtDatas];
	size_t				*dxtDataSizes = [n dxtDataSizes];
	CMSampleBufferRef	hapSampleBuffer = [n hapSampleBuffer];
	OSStatus			cmErr = noErr;
	
	CMBlockBufferRef	dataBlockBuffer = (hapSampleBuffer==nil) ? nil : CMSampleBufferGetDataBuffer(hapSampleBuffer);
	if (dxtDatas[0]==NULL || dataBlockBuffer==NULL)	{
		NSLog(@"\t\terr:dxtData or dataBlockBuffer null in %s",__func__);
	}
	else	{
		size_t					dataBlockBufferAvailableData = 0;
		//size_t					dataBlockBufferTotalDataSize = 0;
		dataBlockBufferAvailableData = CMBlockBufferGetDataLength(dataBlockBuffer);
		//NSLog(@"\t\tdataBlockBufferTotalDataSize is %ld",dataBlockBufferAvailableData);
		enum HapTextureFormat	*dxtTextureFormats = [n dxtTextureFormats];
		dxtTextureFormats[0] = 0;
		dxtTextureFormats[1] = 0;
		char					*dataBuffer = nil;
		cmErr = CMBlockBufferGetDataPointer(dataBlockBuffer,
			0,
			NULL,
			NULL,
			&dataBuffer);
		if (cmErr != kCMBlockBufferNoErr)
			NSLog(@"\t\terr %d at CMBlockBufferGetDataPointer() in %s",(int)cmErr,__func__);
		else	{
			unsigned int			hapErr = HapResult_No_Error;
			unsigned int			hapTexCount = 0;
			hapErr = HapGetFrameTextureCount(dataBuffer, dataBlockBufferAvailableData, &hapTexCount);
			if (hapErr != HapResult_No_Error)
				NSLog(@"\t\terr: %d at HapGetFrameTextureCount() in %s",hapErr,__func__);
			else	{
				
				hapErr = HapDecode(dataBuffer, dataBlockBufferAvailableData,
					0,
					(HapDecodeCallback)HapMTDecode,
					NULL,
					dxtDatas[0],
					dxtDataSizes[0],
					NULL,
					&(dxtTextureFormats[0]));
				if (hapErr != HapResult_No_Error)	{
					NSLog(@"\t\terr: %d at HapDecode() with index 0 in %s",hapErr,__func__);
				}
				
				if (hapTexCount>1)	{
					hapErr = HapDecode(dataBuffer, dataBlockBufferAvailableData,
						1,
						(HapDecodeCallback)HapMTDecode,
						NULL,
						dxtDatas[1],
						dxtDataSizes[1],
						NULL,
						&(dxtTextureFormats[1]));
					if (hapErr != HapResult_No_Error)	{
						NSLog(@"\t\terr: %d at HapDecode() with index 1 in %s",hapErr,__func__);
					}
				}
			}
		
			if (hapErr == HapResult_No_Error)	{
				//	if the decoder frame has a buffer for rgb data, convert the DXT data into rgb data of some sort
				void			*rgbData = [n rgbData];
				size_t			rgbDataSize = [n rgbDataSize];
				OSType			rgbPixelFormat = [n rgbPixelFormat];
				if (rgbData!=nil)	{
					//	if the DXT data is a YCoCg texture format
					if (dxtTextureFormats[0] == HapTextureFormat_YCoCg_DXT5)	{
						//	convert the YCoCg/DXT5 data to just plain ol' DXT5 data in a conversion buffer
						size_t			convMinDataSize = (NSUInteger)dxtImgSize.width * (NSUInteger)dxtImgSize.height * 32 / 8;
						if (convMinDataSize!=convPoolLength)
							convPoolLength = convMinDataSize;
						void			*convMem = CFAllocatorAllocate(_HIAVFMemPoolAllocator, convPoolLength, 0);
						DeCompressYCoCgDXT5((const byte *)dxtDatas[0], (byte *)convMem, imgSize.width, imgSize.height, dxtImgSize.width*4);
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
					else if (dxtTextureFormats[0]==HapTextureFormat_RGB_DXT1 || dxtTextureFormats[0]==HapTextureFormat_RGBA_DXT5)	{
						//	make a GL decoder
						void			*glDecoder = HapCodecGLCreateDecoder(dxtImgSize.width, dxtImgSize.height, dxtTextureFormats[0]);
						if (glDecoder != NULL)	{
							//	decode the DXT data into the rgb buffer
							//NSLog(@"\t\tcalling %ld with userInfo %@",rgbDataSize/(NSUInteger)dxtImgSize.height,[n userInfo]);
							hapErr = HapCodecGLDecode(glDecoder,
								(unsigned int)(rgbDataSize/(NSUInteger)dxtImgSize.height),
								(rgbPixelFormat==kCVPixelFormatType_32BGRA) ? HapCodecGLPixelFormat_BGRA8 : HapCodecGLPixelFormat_RGBA8,
								dxtDatas[0],
								rgbData);
							if (hapErr!=HapResult_No_Error)
								NSLog(@"\t\terr %d at HapCodecGLDecoder() in %s",hapErr,__func__);
							else	{
								//NSLog(@"\t\tsuccessfully decoded to RGB data!");
							}
						
							//	free the GL decoder
							HapCodecGLDestroy(glDecoder);
							glDecoder = NULL;
						}
					
					}
                    else if (dxtTextureFormats[0] == HapTextureFormat_A_RGTC1)    {
                        unsigned int        bytesPerRow = (unsigned int)(rgbDataSize/(NSUInteger)dxtImgSize.height);
                        HapCodecSquishRGTC1DecodeAsAlphaOnly(dxtDatas[0], rgbData, bytesPerRow, dxtImgSize.width, dxtImgSize.height);
                    }
					else	{
						NSLog(@"\t\terr: unrecognized text formats %X/%x in %s",dxtTextureFormats[0],dxtTextureFormats[1],__func__);
					}
				
					//	if there's an alpha plane, decode it and apply it to the rgbData
					if (dxtTextureFormats[1] == HapTextureFormat_A_RGTC1)	{
						unsigned int		bytesPerRow = (unsigned int)(rgbDataSize/(NSUInteger)dxtImgSize.height);
						HapCodecSquishRGTC1Decode(dxtDatas[1], rgbData, bytesPerRow, dxtImgSize.width, dxtImgSize.height);
					}
				}
			
				//	mark the frame as decoded so it can be displayed
				[n setDecoded:YES];
			}
		
		}
	}
	
	//	run the post-decode block (if there is one).  note that this is run even if the decode is unsuccessful...
	if (localPostDecodeBlock!=nil)
		localPostDecodeBlock(n);
	
	[n release];
}

#pragma mark -

- (HapDecoderFrame *) allocFrameClosestToTime:(CMTime)n	{
	//NSLog(@"%s ... %f",__func__,CMTimeGetSeconds(n));
	HapDecoderFrame			*returnMe = nil;
	NSInteger				tmpIndex = 0;
	NSInteger				matchingIndex = NSNotFound;
	LOCK(&propertyLock);
	if (track==nil || gen==nil)	{
		UNLOCK(&propertyLock);
		return returnMe;
	}
	//NSLog(@"\t\tdecodedFrames are %@",decodedFrames);
	//NSLog(@"\t\tplayedOutFrames are %@",playedOutFrames);
	
	//	check 'playedOutFrames' to see if a frame that contains the passed time is available.  if it is, return it.
	tmpIndex = 0;
	matchingIndex = NSNotFound;
	for (HapDecoderFrame *frame in playedOutFrames)	{
		if ([frame containsTime:n])	{
			returnMe = [frame retain];
			matchingIndex = tmpIndex;
			break;
		}
		++tmpIndex;
	}
	if (returnMe != nil)	{
		//	rearrange the array of frames
		if (matchingIndex != NSNotFound)
			[playedOutFrames removeObjectAtIndex:matchingIndex];
		[playedOutFrames addObject:returnMe];
		while ([playedOutFrames count]>MAXPLAYEDOUTFRAMES)
			[playedOutFrames removeObjectAtIndex:0];
		//	we don't want to return the same frame twice
		CMTime				frameTime = [returnMe presentationTime];
		if (CMTIME_COMPARE_INLINE(frameTime,==,lastGeneratedSampleTime))	{
			[returnMe release];
			returnMe = nil;
		}
		else
			lastGeneratedSampleTime = frameTime;
		UNLOCK(&propertyLock);
		//NSLog(@"\t\treturning playedOutFrame %@",returnMe);
		return returnMe;
	}
	
	//	check 'decodedFrames' to see if a frame that contains the passed time is available.  if it is, move it to 'playedOutFrames' and then return it
	tmpIndex = 0;
	matchingIndex = NSNotFound;
	for (HapDecoderFrame *frame in decodedFrames)	{
		if ([frame containsTime:n])	{
			returnMe = [frame retain];
			matchingIndex = tmpIndex;
			break;
		}
		++tmpIndex;
	}
	if (returnMe != nil)	{
		//	move the frame to the array of played out frames
		if (matchingIndex != NSNotFound)
			[decodedFrames removeObjectAtIndex:matchingIndex];
		[playedOutFrames addObject:returnMe];
		while ([playedOutFrames count]>MAXPLAYEDOUTFRAMES)
			[playedOutFrames removeObjectAtIndex:0];
		//	we don't want to return the same frame twice
		CMTime				frameTime = [returnMe presentationTime];
		if (CMTIME_COMPARE_INLINE(frameTime,==,lastGeneratedSampleTime))	{
			[returnMe release];
			returnMe = nil;
		}
		else
			lastGeneratedSampleTime = frameTime;
		UNLOCK(&propertyLock);
		//NSLog(@"\t\treturning decodedFrame %@",returnMe);
		return returnMe;
	}
	
	
	//	...if i'm here, i don't have a frame available for the passed time...
	
	
	//	i don't have the exact time, so i'm going to have to decode it- add the time to the array of times
	NSValue				*tmpVal = [NSValue valueWithCMTime:n];
	if (![decodeTimes containsObject:tmpVal])	{
		[decodeTimes addObject:tmpVal];
		while ([decodeTimes count] > MAXDECODETIMES)
			[decodeTimes removeObjectAtIndex:0];
	}
	
	//	run through all the decoded frames, looking for the frame closest to the passed time
	CMTimeRange				trackRange = [track timeRange];
	double					trackDuration = CMTimeGetSeconds(trackRange.duration);
	double					trackCenter = trackDuration/2.0;
	double					targetFrameTime = CMTimeGetSeconds(n);
	double					runningDelta = 999999.0;
	for (HapDecoderFrame *frame in decodedFrames)	{
		double			frameTime = CMTimeGetSeconds([frame presentationTime]);
		double			frameDelta = targetFrameTime - frameTime;
		if (fabs(frameDelta) < fabs(runningDelta))	{
			runningDelta = frameDelta;
			if (returnMe != nil)
				[returnMe release];
			returnMe = [frame retain];
		}
		double			frameWrapDelta = 999999.0;
		if (frameTime < trackCenter)
			frameWrapDelta = (trackDuration - frameTime) + targetFrameTime;
		else
			frameWrapDelta = frameTime + (trackDuration - targetFrameTime);
		if (fabs(frameWrapDelta) < fabs(runningDelta))	{
			runningDelta = frameWrapDelta;
			if (returnMe != nil)
				[returnMe release];
			returnMe = [frame retain];
		}
	}
	
	//	we're not going to return a frame from 'playedOutFrames' if it's not an exact match but we want to run through them anyway so we can prevent a close match from 'decodedFrames' from being returned...
	for (HapDecoderFrame *frame in playedOutFrames)	{
		double			frameTime = CMTimeGetSeconds([frame presentationTime]);
		double			frameDelta = targetFrameTime - frameTime;
		if (fabs(frameDelta) < fabs(runningDelta))	{
			runningDelta = frameDelta;
			if (returnMe != nil)	{
				[returnMe release];
				returnMe = nil;
			}
			//returnMe = [frame retain];
		}
		double			frameWrapDelta = 999999.0;
		if (frameTime < trackCenter)
			frameWrapDelta = (trackDuration - frameTime) + targetFrameTime;
		else
			frameWrapDelta = frameTime + (trackDuration - targetFrameTime);
		if (fabs(frameWrapDelta) < fabs(runningDelta))	{
			runningDelta = frameWrapDelta;
			if (returnMe != nil)	{
				[returnMe release];
				returnMe = nil;
			}
			//returnMe = [frame retain];
		}
	}
	
	//if ([decodedFrames containsObject:returnMe])
		//NSLog(@"\t\treturning close decodedFrame %@",returnMe);
	//else if ([playedOutFrames containsObject:returnMe])
		//NSLog(@"\t\treturning close playedOutFrame %@",returnMe);
	
	
	//	we don't want to return the same frame twice
	CMTime				frameTime = [returnMe presentationTime];
	if (CMTIME_COMPARE_INLINE(frameTime,==,lastGeneratedSampleTime))	{
		[returnMe release];
		returnMe = nil;
	}
	else
		lastGeneratedSampleTime = frameTime;
	//	when i finish decoding a frame asynchornously, i automatically start decoding a new frame- so i only need to start decoding here if i'm not currently decoding anything...
	BOOL				needsToStartDecoding = NO;
	if ([decodeFrames count]<1)	{
		needsToStartDecoding = YES;
	}
	//	start decoding the frame for the passed time on the decode queue
	if (needsToStartDecoding)	{
		dispatch_async(decodeQueue, ^{
			@autoreleasepool	{
				[self _beginDecodingNextFrame];
			}
		});
	}
	UNLOCK(&propertyLock);
	//NSLog(@"\t\treturning %@",returnMe);
	return returnMe;
}
- (HapDecoderFrame *) allocFrameForTime:(CMTime)n	{
	//NSLog(@"%s ... %f",__func__,CMTimeGetSeconds(n));
	
	HapDecoderFrame			*returnMe = nil;
	NSInteger				tmpIndex = 0;
	NSInteger				matchingIndex = NSNotFound;
	LOCK(&propertyLock);
	if (track==nil || gen==nil)	{
		UNLOCK(&propertyLock);
		return returnMe;
	}
	//	check 'decodedFrames' to see if a frame that contains the passed time is available.  if it is, move it to 'playedOutFrames' and then return it
	tmpIndex = 0;
	matchingIndex = NSNotFound;
	for (HapDecoderFrame *frame in decodedFrames)	{
		if ([frame containsTime:n])	{
			returnMe = [frame retain];
			matchingIndex = tmpIndex;
			break;
		}
		++tmpIndex;
	}
	if (returnMe != nil)	{
		if (matchingIndex != NSNotFound)
			[decodedFrames removeObjectAtIndex:matchingIndex];
		[playedOutFrames addObject:returnMe];
		while ([playedOutFrames count]>MAXPLAYEDOUTFRAMES)
			[playedOutFrames removeObjectAtIndex:0];
		UNLOCK(&propertyLock);
		return returnMe;
	}
	
	//	check 'playedOutFrames' to see if a frame that contains the passed time is available.  if it is, return it.
	tmpIndex = 0;
	matchingIndex = NSNotFound;
	for (HapDecoderFrame *frame in playedOutFrames)	{
		if ([frame containsTime:n])	{
			returnMe = [frame retain];
			matchingIndex = tmpIndex;
			break;
		}
		++tmpIndex;
	}
	if (returnMe != nil)	{
		if (matchingIndex != NSNotFound)
			[playedOutFrames removeObjectAtIndex:matchingIndex];
		[playedOutFrames addObject:returnMe];
		while ([playedOutFrames count]>MAXPLAYEDOUTFRAMES)
			[playedOutFrames removeObjectAtIndex:0];
		UNLOCK(&propertyLock);
		return returnMe;
	}
	
	//	if i'm here then i don't have any already-decoded frames for the passed time, so i have to decode one, and then pull it out of the decoded array
	UNLOCK(&propertyLock);
	[self _prepareDecodeFrameForTime:n];
	[self _beginDecodingFrameForTime:n];
	LOCK(&propertyLock);
	
	tmpIndex = 0;
	matchingIndex = NSNotFound;
	for (HapDecoderFrame *frame in decodedFrames)	{
		if ([frame containsTime:n])	{
			returnMe = [frame retain];
			matchingIndex = tmpIndex;
			break;
		}
		++tmpIndex;
	}
	if (returnMe != nil)	{
		if (matchingIndex != NSNotFound)
			[decodedFrames removeObjectAtIndex:matchingIndex];
		[playedOutFrames addObject:returnMe];
		while ([playedOutFrames count]>MAXPLAYEDOUTFRAMES)
			[playedOutFrames removeObjectAtIndex:0];
	}
	UNLOCK(&propertyLock);
	return returnMe;
}
- (HapDecoderFrame *) allocFrameForHapSampleBuffer:(CMSampleBufferRef)n	{
	//NSLog(@"%s",__func__);
	if (n == NULL)
		return nil;
	return [self allocFrameForTime:CMSampleBufferGetPresentationTimeStamp(n)];
}

- (HapDecoderFrame *) findFrameClosestToTime:(CMTime)n    {
    HapDecoderFrame            *returnMe = nil;
    LOCK(&propertyLock);
    if (track==nil || gen==nil)    {
        UNLOCK(&propertyLock);
        return returnMe;
    }
    for (HapDecoderFrame *frame in playedOutFrames)    {
        if ([frame containsTime:n])    {
            returnMe = [frame retain];
            returnMe = [frame autorelease];
            UNLOCK(&propertyLock);
            return returnMe;
        }
    }
    for (HapDecoderFrame *frame in decodedFrames)    {
        if ([frame containsTime:n])    {
            returnMe = [frame retain];
            returnMe = [frame autorelease];
            UNLOCK(&propertyLock);
            return returnMe;
        }
    }
    UNLOCK(&propertyLock);
    return returnMe;
}

#pragma mark -

- (void) setAllocFrameBlock:(HapDecoderFrameAllocBlock)n	{
	LOCK(&propertyLock);
	if (allocFrameBlock != nil)
		Block_release(allocFrameBlock);
	allocFrameBlock = (n==nil) ? nil : Block_copy(n);
	UNLOCK(&propertyLock);
}
- (void) setPostDecodeBlock:(AVFHapDXTPostDecodeBlock)n	{
	LOCK(&propertyLock);
	if (postDecodeBlock!=nil)
		Block_release(postDecodeBlock);
	postDecodeBlock = (n==nil) ? nil : Block_copy(n);
	UNLOCK(&propertyLock);
}


/*		these methods aren't in the documentation or header files, but they're there and they do what they sound like.		*/
- (void)_detachFromPlayerItem	{
	//NSLog(@"%s",__func__);
	LOCK(&propertyLock);
	
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
	lastGeneratedSampleTime = kCMTimeInvalid;
	[decodeTimes removeAllObjects];
	[decodeFrames removeAllObjects];
	[decodingFrames removeAllObjects];
	[decodedFrames removeAllObjects];
	[playedOutFrames removeAllObjects];
	
	UNLOCK(&propertyLock);
}
- (BOOL)_attachToPlayerItem:(id)arg1	{
	//NSLog(@"%s",__func__);
	BOOL		returnMe = YES;
	if (arg1!=nil)	{
		
		AVAsset				*itemAsset = nil;
		AVAssetTrack		*hapTrack = nil;
		/*	AVMutableComposition is a subclass of AVAsset- but AVSampleBufferGenerator can't work with 
		it, so if the player we're attaching to loaded a composition we have to programmatically 
		determine the source URL, creat our own asset, pull its hap track, and create the sample 
		buffer generator from *that*.			*/
		if ([[arg1 asset] isKindOfClass:[AVComposition class]])	{
			NSArray				*segments = [[arg1 hapTrack] segments];
			AVCompositionTrackSegment	*segment = (segments==nil || [segments count]<1) ? nil : [segments objectAtIndex:0];
			NSURL				*assetURL = (segment==nil) ? nil : [segment sourceURL];
			itemAsset = [AVAsset assetWithURL:assetURL];
			NSArray				*hapTracks = [itemAsset hapVideoTracks];
			hapTrack = (hapTracks==nil || [hapTracks count]<1) ? nil : [hapTracks objectAtIndex:0];
		}
		//	else the passed player item's asset is presumably a plain, old-fashioned AVAsset
		else	{
			itemAsset = [arg1 asset];
			hapTrack = [arg1 hapTrack];
		}
		
		//	i only want to attach if there's a hap track...
		if (hapTrack!=nil)	{
			LOCK(&propertyLock);
			
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
			[decodeTimes removeAllObjects];
			[decodeFrames removeAllObjects];
			[decodingFrames removeAllObjects];
			[decodedFrames removeAllObjects];
			[playedOutFrames removeAllObjects];
			
			UNLOCK(&propertyLock);
			//returnMe = YES;
		}
	}
	return returnMe;
}
- (void) setOutputAsRGB:(BOOL)n	{
	LOCK(&propertyLock);
	outputAsRGB = n;
	UNLOCK(&propertyLock);
}
- (BOOL) outputAsRGB	{
	LOCK(&propertyLock);
	BOOL		returnMe = outputAsRGB;
	UNLOCK(&propertyLock);
	return returnMe;
}
- (void) setDestRGBPixelFormat:(OSType)n	{
	if (n!=kCVPixelFormatType_32BGRA && n!=kCVPixelFormatType_32RGBA)	{
		NSString		*errFmtString = [NSString stringWithFormat:@"\t\tERR in %s, can't use new format:",__func__];
		FourCCLog(errFmtString,n);
		return;
	}
	LOCK(&propertyLock);
	destRGBPixelFormat = n;
	UNLOCK(&propertyLock);
}
- (OSType) destRGBPixelFormat	{
	LOCK(&propertyLock);
	OSType		returnMe = destRGBPixelFormat;
	UNLOCK(&propertyLock);
	return returnMe;
}


@end

