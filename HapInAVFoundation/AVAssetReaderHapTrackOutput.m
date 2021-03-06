#import "AVAssetReaderHapTrackOutput.h"
#import "AVAssetAdditions.h"




@implementation AVAssetReaderHapTrackOutput


- (id) initWithTrack:(AVAssetTrack *)trackPtr outputSettings:(NSDictionary *)settings	{
	//NSLog(@"%s ... %p",__func__,self);
	self = [super initWithTrack:trackPtr outputSettings:nil];
	if (self!=nil)	{
		hapLock = HAP_LOCK_INIT;
		hapDXTOutput = nil;
		lastCopiedBufferTime = kCMTimeInvalid;
		if (![trackPtr isHapTrack])	{
			return nil;
		}
		
		hapDXTOutput = [[AVPlayerItemHapDXTOutput alloc] initWithHapAssetTrack:trackPtr];
		[hapDXTOutput setOutputAsRGB:YES];
		[hapDXTOutput setDestRGBPixelFormat:kCVPixelFormatType_32BGRA];
	}
	return self;
}
- (void) dealloc	{
	//NSLog(@"%s ... %p",__func__,self);
	HapLockLock(&hapLock);
	if (hapDXTOutput!=nil)	{
		hapDXTOutput = nil;
	}
	HapLockUnlock(&hapLock);
}
- (CMSampleBufferRef) copyNextSampleBuffer	{
	//NSLog(@"%s",__func__);
	CMSampleBufferRef		returnMe = NULL;
	//	call the super, which gets the raw sample buffer (contains encoded hap data)
	CMSampleBufferRef		hapBuffer = [super copyNextSampleBuffer];
	if (hapBuffer==NULL)	{
		//NSLog(@"\t\terr: hapBuffer nil in %s",__func__);
	}
	else	{
		CMTime			bufferTime = CMSampleBufferGetPresentationTimeStamp(hapBuffer);
		//NSLog(@"\t\tbufferTime is %@",[(id)CMTimeCopyDescription(kCFAllocatorDefault,bufferTime) autorelease]);
		//	if the time on the sample buffer from the super is invalid, i've read all the samples
		if (CMTIME_COMPARE_INLINE(bufferTime,==,kCMTimeInvalid))	{
		
		}
		//	else if i already tried to read this sample time
		else if (CMTIME_COMPARE_INLINE(bufferTime,==,lastCopiedBufferTime))	{
			NSLog(@"\t\terr: already copied buffer for time %@ in %s, returning nil",CMTimeCopyDescription(kCFAllocatorDefault,bufferTime),__func__);
		}
		//	else there's a valid time on the sample buffer- i should decode a frame for this time, and return a sample buffer with the decoded RGB data!
		else	{
			HapDecoderFrame			*hapFrame = [hapDXTOutput allocFrameForTime:bufferTime];
			if (hapFrame==nil)	{
				NSLog(@"\t\terr:hapFrame nil in %s",__func__);
			}
			else	{
				//NSLog(@"\t\tbuffer copied for time %@",[(id)CMTimeCopyDescription(kCFAllocatorDefault,bufferTime) autorelease]);
				lastCopiedBufferTime = bufferTime;
				returnMe = [hapFrame allocCMSampleBufferFromRGBData];
				if (returnMe==nil)
					NSLog(@"\t\terr: returnMe nil in %s",__func__);
				else	{
					//NSLog(@"\t\tshould be successful! %s",__func__);
				}
				
				hapFrame = nil;
			}
		}
		CFRelease(hapBuffer);
		hapBuffer = NULL;
	}
	return returnMe;
	
}


- (BOOL) outputAsRGB	{
	HapLockLock(&hapLock);
	BOOL		returnMe = (hapDXTOutput==nil) ? NO : [hapDXTOutput outputAsRGB];
	HapLockUnlock(&hapLock);
	return returnMe;
}
- (void) setOutputAsRGB:(BOOL)n	{
	HapLockLock(&hapLock);
	if (hapDXTOutput != nil)
		[hapDXTOutput setOutputAsRGB:n];
	HapLockUnlock(&hapLock);
}


@end
