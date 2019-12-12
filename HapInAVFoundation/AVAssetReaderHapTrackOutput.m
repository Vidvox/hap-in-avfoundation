#import "AVAssetReaderHapTrackOutput.h"
#import "AVAssetAdditions.h"




@implementation AVAssetReaderHapTrackOutput


- (id) initWithTrack:(AVAssetTrack *)trackPtr outputSettings:(NSDictionary *)settings	{
	//NSLog(@"%s ... %p",__func__,self);
	self = [super initWithTrack:trackPtr outputSettings:nil];
	if (self!=nil)	{
		hapLock = OS_UNFAIR_LOCK_INIT;
		hapDXTOutput = nil;
		lastCopiedBufferTime = kCMTimeInvalid;
		if (![trackPtr isHapTrack])	{
			[self release];
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
	os_unfair_lock_lock(&hapLock);
	if (hapDXTOutput!=nil)	{
		[hapDXTOutput release];
		hapDXTOutput = nil;
	}
	os_unfair_lock_unlock(&hapLock);
	[super dealloc];
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
			NSLog(@"\t\terr: already copied buffer for time %@ in %s, returning nil",[(id)CMTimeCopyDescription(kCFAllocatorDefault,bufferTime) autorelease],__func__);
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
				
				[hapFrame release];
				hapFrame = nil;
			}
		}
		CFRelease(hapBuffer);
		hapBuffer = NULL;
	}
	return returnMe;
	
}


- (BOOL) outputAsRGB	{
	os_unfair_lock_lock(&hapLock);
	BOOL		returnMe = (hapDXTOutput==nil) ? NO : [hapDXTOutput outputAsRGB];
	os_unfair_lock_unlock(&hapLock);
	return returnMe;
}
- (void) setOutputAsRGB:(BOOL)n	{
	os_unfair_lock_lock(&hapLock);
	if (hapDXTOutput != nil)
		[hapDXTOutput setOutputAsRGB:n];
	os_unfair_lock_unlock(&hapLock);
}


@end
