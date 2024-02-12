#import "VVAudioFormatUtilities.h"
#import "VVAudioChannelLayout.h"


@implementation VVAudioFormatUtilities

+ (NSArray *) bitratesForDescription:(AudioStreamBasicDescription)resultASBD bitRateMode:(UInt32)brMode	{
	OSStatus				err;
	AudioConverterRef		audioConverter;
	
	//	it doesn't matter what our input ASBD is as long as it is linear PCM!
	AudioStreamBasicDescription			inASBD;
	inASBD.mSampleRate = 44100;
	inASBD.mFormatID = kAudioFormatLinearPCM;
	inASBD.mFormatFlags = kAudioFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsBigEndian | kAudioFormatFlagIsPacked;
	inASBD.mBytesPerPacket = 4;
	inASBD.mFramesPerPacket = 1;
	inASBD.mBytesPerFrame = 4;
	inASBD.mChannelsPerFrame = 2;
	inASBD.mBitsPerChannel = 16;
	
	err = AudioConverterNew(&inASBD, &resultASBD, &audioConverter);
	if (err == kAudioConverterErr_FormatNotSupported)	{
		NSLog(@"\t\terror AudioConverterNew:kAudioConverterErr_FormatNotSupported");
		AudioConverterDispose(audioConverter);
		return @[];
	}
	else if (err == kAudioConverterErr_InvalidInputSize)	{
		NSLog(@"\t\terror AudioConverterNew:kAudioConverterErr_InvalidInputSize");
		AudioConverterDispose(audioConverter);
		return @[];
	}
	else if (err == kAudioConverterErr_InvalidOutputSize)	{
		NSLog(@"\t\terror AudioConverterNew:kAudioConverterErr_InvalidOutputSize");
		AudioConverterDispose(audioConverter);
		return @[];
	}
	else if (err == kAudioConverterErr_InputSampleRateOutOfRange)	{
		NSLog(@"\t\terror AudioConverterNew:kAudioConverterErr_InputSampleRateOutOfRange");
		AudioConverterDispose(audioConverter);
		return @[];
	}
	else if (err == kAudioConverterErr_OutputSampleRateOutOfRange)	{
		NSLog(@"\t\terror AudioConverterNew:kAudioConverterErr_OutputSampleRateOutOfRange");
		AudioConverterDispose(audioConverter);
		return @[];
	}
	else if (err == kAudioConverterErr_OperationNotSupported)	{
		NSLog(@"\t\terror AudioConverterNew:kAudioConverterErr_OperationNotSupported");
		AudioConverterDispose(audioConverter);
		return @[];
	}	
	else if (err == kAudioConverterErr_PropertyNotSupported)	{
		NSLog(@"\t\terror AudioConverterNew:kAudioConverterErr_PropertyNotSupported");
		AudioConverterDispose(audioConverter);
		return @[];
	}
	else if (err == kAudioConverterErr_UnspecifiedError)	{
		NSLog(@"\t\terror AudioConverterNew:kAudioConverterErr_UnspecifiedError");
		AudioConverterDispose(audioConverter);
		return @[];
	}
	else if (err == kAudioConverterErr_BadPropertySizeError)	{
		NSLog(@"\t\terror AudioConverterNew:kAudioConverterErr_BadPropertySizeError");
		AudioConverterDispose(audioConverter);
		return @[];
	}
	else if (err == kAudioConverterErr_RequiresPacketDescriptionsError) {
		NSLog(@"\t\terror AudioConverterNew:kAudioConverterErr_RequiresPacketDescriptionsError");
		AudioConverterDispose(audioConverter);
		return @[];
	}
	else if (err!=noErr)	{
		NSLog(@"\t\terror AudioConverterNew: %d",(int)err);
		//NSLog(@"%f-%d to %f-%d",inputStreamDescription.mSampleRate,inputStreamDescription.mChannelsPerFrame,outputStreamDescription.mSampleRate,outputStreamDescription.mChannelsPerFrame);
		AudioConverterDispose(audioConverter);
		return @[];
	}

	//	now use kAudioConverterApplicableEncodeBitRates
	//UInt32			val = 0;
	Boolean			writeable = NO;
	UInt32			output_size;
	
	UInt32			mode = brMode;
	err = AudioConverterSetProperty(audioConverter, kAudioCodecBitRateFormat, sizeof(mode), &mode);
	if (err!=noErr) {
		AudioConverterDispose(audioConverter);
		return @[];
	}
	err = AudioConverterGetPropertyInfo(audioConverter, kAudioConverterApplicableEncodeBitRates, &output_size, &writeable);
	if (err!=noErr) {
		AudioConverterDispose(audioConverter);
		return @[];
	}
	/*
	if (err!=noErr) {
		NSLog(@"\t\terror GetPropertyInfo kAudioConverterApplicableEncodeBitRates: %d",(int)err);
		AudioConverterDispose(audioConverter);
		return 0;
	}
	*/
	//AudioFormatGetPropertyInfo(kAudioFormatProperty_AvailableEncodeBitRates, sizeof(format), &format, &output_size);
	
	NSMutableArray		*returnMe = [[NSMutableArray alloc] init];
	
	int			count = output_size / sizeof(AudioValueRange);
	if (count > 0)	{
		AudioValueRange			*ranges = malloc(output_size);

		err = AudioConverterGetProperty(audioConverter, kAudioConverterApplicableEncodeBitRates, &output_size, ranges);
		if (err!=noErr) {
			AudioConverterDispose(audioConverter);
			return @[];
		}
		
		for (int i=0; i<count; ++ i)	{
			//	prevent using stuff that is explicitly bogus or out of bounds
			if ((ranges[i].mMinimum >= 8000)&&(ranges[i].mMinimum <= 640000.0)) {
				[returnMe addObject:[NSNumber numberWithDouble:ranges[i].mMinimum]];
			}
		}
		
		free(ranges);
	}

	AudioConverterDispose(audioConverter);

	return returnMe;
}


@end
