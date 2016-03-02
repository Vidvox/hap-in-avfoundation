#import "HapEncoderFrame.h"




@implementation HapEncoderFrame


- (NSString *) description	{
	return [NSString stringWithFormat:@"<HapEncoderFrame %@, %d>",[(id)CMTimeCopyDescription(NULL,timing.presentationTimeStamp) autorelease], encoded];
}
+ (id) createWithPresentationTime:(CMTime)t	{
	id		returnMe = [[HapEncoderFrame alloc] initWithPresentationTime:t];
	return (returnMe==nil) ? nil : [returnMe autorelease];
}
- (id) initWithPresentationTime:(CMTime)t	{
	self = [super init];
	if (self!=nil)	{
		block = NULL;
		length = 0;
		format = NULL;
		timing.duration = kCMTimeInvalid;
		timing.presentationTimeStamp = t;
		timing.decodeTimeStamp = kCMTimeInvalid;
		encoded = NO;
	}
	return self;
}
- (void) dealloc	{
	if (block!=NULL)	{
		CFRelease(block);
		block = NULL;
	}
	if (format!=NULL)	{
		CFRelease(format);
		format = NULL;
	}
	[super dealloc];
}
- (BOOL) addEncodedBlockBuffer:(CMBlockBufferRef)b withLength:(size_t)s formatDescription:(CMFormatDescriptionRef)f	{
	if (f==NULL)
		NSLog(@"\t\terr: trying to add a block buffer with a nil format, %s",__func__);
	BOOL		returnMe = NO;
	if ([self encoded])
		NSLog(@"\t\tERR: trying to add block buffer to encoded frame, %s",__func__);
	else	{
		if (b!=NULL && f!=NULL && s>0)	{
			if (block!=NULL)
				CFRelease(block);
			block = b;
			CFRetain(block);
			length = s;
			if (format!=NULL)
				CFRelease(format);
			format = f;
			CFRetain(format);
			[self setEncoded:YES];
		}
	}
	return returnMe;
}
- (CMSampleBufferRef) allocCMSampleBufferWithNextFramePresentationTime:(CMTime)n	{
	return [self allocCMSampleBufferWithDurationTimeValue:(n.value - timing.presentationTimeStamp.value)];
}
- (CMSampleBufferRef) allocCMSampleBufferWithDurationTimeValue:(CMTimeValue)n	{
	if (format==NULL)	{
		NSLog(@"\t\terr: returning a null sbuf, format nil in %s.  ptime was %@",__func__,[(id)CMTimeCopyDescription(kCFAllocatorDefault,timing.presentationTimeStamp) autorelease]);
		if (block==NULL)
			NSLog(@"\t\terr: the block was also nil, encoded was %d",[self encoded]);
		return NULL;
	}
	//	populate the duration member of the timing struct, then set its value
	timing.duration = timing.presentationTimeStamp;
	timing.duration.value = n;
	//	create a sample buffer
	CMSampleBufferRef		hapSampleBuffer = NULL;
	OSStatus				osErr = noErr;
	osErr = CMSampleBufferCreate(kCFAllocatorDefault,
		block,
		true,
		NULL,
		NULL,
		format,
		1,
		1,
		&timing,
		1,
		&length,
		&hapSampleBuffer);
	if (osErr!=noErr || hapSampleBuffer==NULL)	{
		NSLog(@"\t\terr %d at CMSampleBufferCreate() in %s",(int)osErr,__func__);
		hapSampleBuffer = NULL;
	}
	return hapSampleBuffer;
}
- (CMTime) presentationTime	{
	return timing.presentationTimeStamp;
}
//	synthesized so we get automatic atomicity for this var
@synthesize encoded;


@end
