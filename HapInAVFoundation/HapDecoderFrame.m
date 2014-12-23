#import "HapDecoderFrame.h"
#import "HapCodecSubTypes.h"
#import "PixelFormats.h"
#import "HapPlatform.h"
#import "Utility.h"
#import "hap.h"




/*			Callback for multithreaded Hap decoding			*/
void HapMTDecode(HapDecodeWorkFunction function, void *p, unsigned int count, void *info HAP_ATTR_UNUSED)	{
	dispatch_apply(count, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t index) {
		function(p, (unsigned int)index);
	});
}




@implementation HapDecoderFrame


- (id) initWithHapSampleBuffer:(CMSampleBufferRef)sb	{
	self = [self initEmptyWithHapSampleBuffer:sb];
	dxtData = malloc(dxtMinDataSize);
	dxtDataSize = dxtMinDataSize;
	userInfo = (id)CFDataCreateWithBytesNoCopy(NULL, dxtData, dxtMinDataSize, NULL);
	return self;
}
- (id) initEmptyWithHapSampleBuffer:(CMSampleBufferRef)sb	{
	self = [super init];
	if (self != nil)	{
		hapSampleBuffer = NULL;
		codecSubType = 0;
		imgSize = NSMakeSize(0,0);
		dxtData = nil;
		dxtMinDataSize = 0;
		dxtDataSize = 0;
		dxtPixelFormat = 0;
		dxtImgSize = NSMakeSize(0,0);
		dxtTextureFormat = 0;
		userInfo = nil;
		decoded = NO;
		
		hapSampleBuffer = sb;
		if (hapSampleBuffer==NULL)
			goto BAIL;
		CFRetain(hapSampleBuffer);
		
		//NSLog(@"\t\tthis frame's time is %@",[(id)CMTimeCopyDescription(kCFAllocatorDefault, CMSampleBufferGetPresentationTimeStamp(hapSampleBuffer)) autorelease]);
		CMFormatDescriptionRef	desc = (sb==NULL) ? NULL : CMSampleBufferGetFormatDescription(sb);
		if (desc==NULL)
			goto BAIL;
		//NSLog(@"\t\textensions are %@",CMFormatDescriptionGetExtensions(desc));
		CGSize			tmpSize = CMVideoFormatDescriptionGetPresentationDimensions(desc, true, false);
		imgSize = NSMakeSize(tmpSize.width, tmpSize.height);
		dxtImgSize = NSMakeSize(roundUpToMultipleOf4(imgSize.width), roundUpToMultipleOf4(imgSize.height));
		//NSLog(@"\t\timgSize is %f x %f",imgSize.width,imgSize.height);
		//NSLog(@"\t\tdxtImgSize is %f x %f",dxtImgSize.width,dxtImgSize.height);
		codecSubType = CMFormatDescriptionGetMediaSubType(desc);
		switch (codecSubType)	{
		case kHapCodecSubType:
			dxtPixelFormat = kHapCVPixelFormat_RGB_DXT1;
			break;
		case kHapAlphaCodecSubType:
			dxtPixelFormat = kHapCVPixelFormat_RGBA_DXT5;
			break;
		case kHapYCoCgCodecSubType:
			dxtPixelFormat = kHapCVPixelFormat_YCoCg_DXT5;
			break;
		}
		dxtMinDataSize = dxtBytesForDimensions(dxtImgSize.width, dxtImgSize.height, codecSubType);
	}
	return self;
	BAIL:
	[self release];
	return nil;
}
- (void) dealloc	{
	//NSLog(@"%s",__func__);
	if (hapSampleBuffer != nil)	{
		CFRelease(hapSampleBuffer);
		hapSampleBuffer = NULL;
	}
	dxtData = NULL;
	if (userInfo != nil)	{
		[userInfo release];
		userInfo = nil;
	}
	[super dealloc];
}
- (NSString *) description	{
	if (hapSampleBuffer==nil)
		return @"<HapDecoderFrame>";
	CMTime		presentationTime = CMSampleBufferGetPresentationTimeStamp(hapSampleBuffer);
	return [NSString stringWithFormat:@"<HapDecoderFrame, %d, %f x %f, %@>",dxtTextureFormat,dxtImgSize.width,dxtImgSize.height,[(id)CMTimeCopyDescription(kCFAllocatorDefault,presentationTime) autorelease]];
}
- (CMSampleBufferRef) hapSampleBuffer	{
	return hapSampleBuffer;
}
- (OSType) codecSubType	{
	return codecSubType;
}
- (NSSize) imgSize	{
	return imgSize;
}
- (void) setDXTData:(void *)n	{
	dxtData = n;
}
- (size_t) dxtMinDataSize	{
	return dxtMinDataSize;
}
- (void) setDXTDataSize:(size_t)n	{
	dxtDataSize = n;
}
- (void *) dxtData	{
	return dxtData;
}
- (size_t) dxtDataSize	{
	return dxtDataSize;
}
- (OSType) dxtPixelFormat	{
	return dxtPixelFormat;
}
- (NSSize) dxtImgSize	{
	return dxtImgSize;
}
- (enum HapTextureFormat) dxtTextureFormat	{
	return dxtTextureFormat;
}
- (void) _decode	{
	if (dxtData==nil)	{
		NSLog(@"\t\terr, dxtData nil, can't decode.  %s",__func__);
		return;
	}
	CMBlockBufferRef		dataBlockBuffer = CMSampleBufferGetDataBuffer(hapSampleBuffer);
	OSStatus				cmErr = kCMBlockBufferNoErr;
	size_t					dataBlockBufferAvailableData = 0;
	size_t					dataBlockBufferTotalDataSize = 0;
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
				[self setDecoded:YES];
			}
		}
	}
}
@synthesize userInfo;
@synthesize decoded;


@end
