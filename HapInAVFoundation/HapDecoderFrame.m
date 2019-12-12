#import "HapDecoderFrame.h"
#import "HapCodecSubTypes.h"
#import "PixelFormats.h"
#import "HapPlatform.h"
#import "Utility.h"
#import "hap.h"
#import "CMBlockBufferPool.h"



/*
void CMBlockBuffer_FreeHapDecoderFrame(void *refCon, void *doomedMemoryBlock, size_t sizeInBytes)	{
	//	'refCon' is the HapDecoderFrame instance which contains the data that is backing this block buffer...
	[(id)refCon release];
}
*/
void CVPixelBuffer_FreeHapDecoderFrame(void *releaseRefCon, const void *baseAddress)	{
	//	'releaseRefCon' is the HapDecoderFrame instance which contains the data that is backing this pixel buffer...
	[(id)releaseRefCon release];
}

#define FourCCLog(n,f) NSLog(@"%@, %c%c%c%c",n,(int)((f>>24)&0xFF),(int)((f>>16)&0xFF),(int)((f>>8)&0xFF),(int)((f>>0)&0xFF))




@implementation HapDecoderFrame


+ (void) initialize	{
	//	make sure the CMMemoryPool used by this framework exists
	os_unfair_lock_lock(&_HIAVFMemPoolLock);
	if (_HIAVFMemPool==NULL)
		_HIAVFMemPool = CMMemoryPoolCreate(NULL);
	if (_HIAVFMemPoolAllocator==NULL)
		_HIAVFMemPoolAllocator = CMMemoryPoolGetAllocator(_HIAVFMemPool);
	os_unfair_lock_unlock(&_HIAVFMemPoolLock);
}
- (id) initWithHapSampleBuffer:(CMSampleBufferRef)sb	{
	self = [self initEmptyWithHapSampleBuffer:sb];
	dxtDatas[0] = CFAllocatorAllocate(_HIAVFMemPoolAllocator, dxtMinDataSizes[0], 0);
	dxtDataSizes[0] = dxtMinDataSizes[0];
	if (dxtMinDataSizes[1]>0)	{
		dxtDatas[1] = CFAllocatorAllocate(_HIAVFMemPoolAllocator, dxtMinDataSizes[1], 0);
		dxtDataSizes[1] = dxtMinDataSizes[1];
	}
	userInfo = (id)CFDataCreateWithBytesNoCopy(NULL, dxtDatas[0], dxtMinDataSizes[0], _HIAVFMemPoolAllocator);
	return self;
}
- (id) initEmptyWithHapSampleBuffer:(CMSampleBufferRef)sb	{
	self = [super init];
	if (self != nil)	{
		hapSampleBuffer = NULL;
		codecSubType = 0;
		imgSize = NSMakeSize(0,0);
		dxtPlaneCount = 0;
		dxtDatas[0] = nil;
		dxtDatas[1] = nil;
		dxtMinDataSizes[0] = 0;
		dxtMinDataSizes[1] = 0;
		dxtDataSizes[0] = 0;
		dxtDataSizes[1] = 0;
		dxtPixelFormats[0] = 0;
		dxtPixelFormats[1] = 0;
		dxtImgSize = NSMakeSize(0,0);
		dxtTextureFormats[0] = 0;
		dxtTextureFormats[1] = 0;
		rgbData = nil;
		rgbMinDataSize = 0;
		rgbDataSize = 0;
		rgbPixelFormat = kCVPixelFormatType_32BGRA;
		rgbImgSize = NSMakeSize(0,0);
		atomicLock = OS_UNFAIR_LOCK_INIT;
		userInfo = nil;
		decoded = NO;
		age = 0;
		
		hapSampleBuffer = sb;
		if (hapSampleBuffer==NULL)	{
			NSLog(@"\t\terr, bailing- hapSampleBuffer nil in %s",__func__);
			goto BAIL;
		}
		CFRetain(hapSampleBuffer);
		
		//NSLog(@"\t\tthis frame's time is %@",[(id)CMTimeCopyDescription(kCFAllocatorDefault, CMSampleBufferGetPresentationTimeStamp(hapSampleBuffer)) autorelease]);
		CMFormatDescriptionRef	desc = (sb==NULL) ? NULL : CMSampleBufferGetFormatDescription(sb);
		if (desc==NULL)	{
			NSLog(@"\t\terr, bailing- desc nil in %s",__func__);
			if (!CMSampleBufferIsValid(sb))
				NSLog(@"\t\terr: as a note, the sample buffer wasn't valid in %s",__func__);
			goto BAIL;
		}
		//NSLog(@"\t\textensions are %@",CMFormatDescriptionGetExtensions(desc));
		CMVideoDimensions	vidDims = CMVideoFormatDescriptionGetDimensions(desc);
		imgSize = NSMakeSize(vidDims.width, vidDims.height);
		//CGSize			tmpSize = CMVideoFormatDescriptionGetPresentationDimensions(desc, true, false);
		//imgSize = NSMakeSize(tmpSize.width, tmpSize.height);
		dxtImgSize = NSMakeSize(roundUpToMultipleOf4(imgSize.width), roundUpToMultipleOf4(imgSize.height));
		//rgbDataSize = 32 * imgSize.width * imgSize.height / 8;
		rgbDataSize = 32 * dxtImgSize.width * dxtImgSize.height / 8;
		//rgbImgSize = imgSize;
		rgbImgSize = dxtImgSize;
		//NSLog(@"\t\timgSize is %f x %f",imgSize.width,imgSize.height);
		//NSLog(@"\t\tdxtImgSize is %f x %f",dxtImgSize.width,dxtImgSize.height);
		codecSubType = CMFormatDescriptionGetMediaSubType(desc);
		dxtMinDataSizes[0] = dxtBytesForDimensions(dxtImgSize.width, dxtImgSize.height, codecSubType);
		switch (codecSubType)	{
		case kHapCodecSubType:
			dxtPlaneCount = 1;
			dxtPixelFormats[0] = kHapCVPixelFormat_RGB_DXT1;
			dxtPixelFormats[1] = 0;
			dxtMinDataSizes[1] = 0;
			break;
		case kHapAlphaCodecSubType:
			dxtPlaneCount = 1;
			dxtPixelFormats[0] = kHapCVPixelFormat_RGBA_DXT5;
			dxtPixelFormats[1] = 0;
			dxtMinDataSizes[1] = 0;
			break;
		case kHapYCoCgCodecSubType:
			dxtPlaneCount = 1;
			dxtPixelFormats[0] = kHapCVPixelFormat_YCoCg_DXT5;
			dxtPixelFormats[1] = 0;
			dxtMinDataSizes[1] = 0;
			break;
		case kHapYCoCgACodecSubType:
			dxtPlaneCount = 2;
			dxtPixelFormats[0] = kHapCVPixelFormat_CoCgXY;
			dxtPixelFormats[1] = kHapCVPixelFormat_A_RGTC1;
			dxtMinDataSizes[1] = dxtBytesForDimensions(dxtImgSize.width, dxtImgSize.height, kHapAOnlyCodecSubType);
			break;
		case kHapAOnlyCodecSubType:
			dxtPlaneCount = 1;
			dxtPixelFormats[0] = kHapCVPixelFormat_A_RGTC1;
			dxtPixelFormats[1] = 0;
			dxtMinDataSizes[1] = 0;
			break;
		}
		rgbMinDataSize = 32 * imgSize.width * imgSize.height / 8;
	}
	return self;
	BAIL:
	[self release];
	return nil;
}
- (void) dealloc	{
	if (hapSampleBuffer != nil)	{
		CFRelease(hapSampleBuffer);
		hapSampleBuffer = NULL;
	}
	dxtDatas[0] = NULL;
	dxtDatas[1] = NULL;
	rgbData = NULL;
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
	//return [NSString stringWithFormat:@"<HapDecoderFrame, %d/%d, %f x %f, %@>",dxtTextureFormats[0],dxtTextureFormats[1],dxtImgSize.width,dxtImgSize.height,[(id)CMTimeCopyDescription(kCFAllocatorDefault,presentationTime) autorelease]];
	return [NSString stringWithFormat:@"<HapDecoderFrame, %@>",[(id)CMTimeCopyDescription(kCFAllocatorDefault,presentationTime) autorelease]];
}

- (BOOL) isEqual:(HapDecoderFrame *)n	{
	if (self == n)
		return YES;
	if (n == nil)
		return NO;
	CMSampleBufferRef		remoteSampleBuffer = [n hapSampleBuffer];
	if (hapSampleBuffer == NULL || remoteSampleBuffer==NULL)
		return NO;
	
	CMTime		myTime = CMSampleBufferGetPresentationTimeStamp(hapSampleBuffer);
	CMTime		remoteTime = CMSampleBufferGetPresentationTimeStamp(remoteSampleBuffer);
	if (CMTIME_COMPARE_INLINE(myTime,==,remoteTime))
		return YES;
	return NO;
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
- (int) dxtPlaneCount	{
	return dxtPlaneCount;
}
- (void **) dxtDatas	{
	return dxtDatas;
}
- (size_t *) dxtMinDataSizes	{
	return dxtMinDataSizes;
}
- (size_t *) dxtDataSizes	{
	return dxtDataSizes;
}
- (OSType *) dxtPixelFormats	{
	return dxtPixelFormats;
}
- (NSSize) dxtImgSize	{
	return dxtImgSize;
}
- (enum HapTextureFormat *) dxtTextureFormats	{
	return dxtTextureFormats;
}
- (void) setRGBData:(void *)n	{
	rgbData = n;
}
- (void *) rgbData	{
	return rgbData;
}
- (size_t) rgbMinDataSize	{
	return rgbDataSize;
}
- (void) setRGBDataSize:(size_t)n	{
	rgbDataSize = n;
}
- (size_t) rgbDataSize	{
	return rgbDataSize;
}
- (void) setRGBPixelFormat:(OSType)n	{
	if (n!=kCVPixelFormatType_32BGRA && n!=kCVPixelFormatType_32RGBA)	{
		NSString		*errFmtString = [NSString stringWithFormat:@"\t\tERR in %s, can't use new format:",__func__];
		FourCCLog(errFmtString,n);
		return;
	}
	rgbPixelFormat = n;
}
- (OSType) rgbPixelFormat	{
	return rgbPixelFormat;
}
- (void) setRGBImgSize:(NSSize)n	{
	rgbImgSize = n;
}
- (NSSize) rgbImgSize	{
	return rgbImgSize;
}
- (CMTime) presentationTime	{
	return ((hapSampleBuffer==NULL) ? kCMTimeInvalid : CMSampleBufferGetPresentationTimeStamp(hapSampleBuffer));
}
- (BOOL) containsTime:(CMTime)n	{
	if (hapSampleBuffer==NULL)
		return NO;
	CMTimeRange		timeRange = CMTimeRangeMake(CMSampleBufferGetPresentationTimeStamp(hapSampleBuffer),CMSampleBufferGetDuration(hapSampleBuffer));
	if (CMTimeRangeContainsTime(timeRange,n))
		return YES;
	return NO;
}


- (CMSampleBufferRef) allocCMSampleBufferFromRGBData	{
	//NSLog(@"%s ... %@",__func__,self);
	//	if there's no RGB data, bail immediately
	if (rgbData==nil)	{
		NSLog(@"\t\terr: no RGB data, can't alloc a CMSampleBufferRef, %s",__func__);
		return NULL;
	}
	CMSampleBufferRef		returnMe = NULL;
	//	make a CVPixelBufferRef from my RGB data
	CVReturn				cvErr = kCVReturnSuccess;
	NSDictionary			*pixelBufferAttribs = [NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithInteger:kCVPixelFormatType_32BGRA], kCVPixelBufferPixelFormatTypeKey,
		[NSNumber numberWithInteger:(NSUInteger)rgbImgSize.width], kCVPixelBufferWidthKey,
		[NSNumber numberWithInteger:(NSUInteger)rgbImgSize.height], kCVPixelBufferHeightKey,
		[NSNumber numberWithInteger:rgbDataSize/(NSUInteger)rgbImgSize.height], kCVPixelBufferBytesPerRowAlignmentKey,
		nil];
	CVPixelBufferRef		cvPixRef = NULL;
	cvErr = CVPixelBufferCreateWithBytes(NULL,
		(size_t)rgbImgSize.width,
		(size_t)rgbImgSize.height,
		rgbPixelFormat,
		rgbData,
		rgbDataSize/(size_t)rgbImgSize.height,
		CVPixelBuffer_FreeHapDecoderFrame,
		self,
		(CFDictionaryRef)pixelBufferAttribs,
		&cvPixRef);
	if (cvErr!=kCVReturnSuccess || cvPixRef==NULL)	{
		NSLog(@"\t\terr %d at CVPixelBufferCreateWithBytes() in %s",cvErr,__func__);
		NSLog(@"\t\tattribs were %@",pixelBufferAttribs);
		NSLog(@"\t\tsize was %ld x %ld",(size_t)rgbImgSize.width,(size_t)rgbImgSize.height);
		NSLog(@"\t\trgbPixelFormat passed to method is %u",(unsigned int)rgbPixelFormat);
	}
	else	{
		//	retain self, to ensure that this HapDecoderFrame instance will persist at least until the CVPixelBufferRef frees it!
		[self retain];
		
		//	make a CMFormatDescriptionRef that describes the RGB data
		CMFormatDescriptionRef		desc = NULL;
		//NSDictionary				*bufferExtensions = [NSDictionary dictionaryWithObjectsAndKeys:
		//	[NSNumber numberWithUnsignedLong:rgbDataSize/(size_t)rgbImgSize.height], @"CVBytesPerRow",
			//@"SMPTE_C", @"CVImageBufferColorPrimaries",
			//[NSNumber numberWithDouble:2.199996948242188], kCMFormatDescriptionExtension_GammaLevel,
			//kCVImageBufferTransferFunction_UseGamma, kCVImageBufferTransferFunctionKey,
			//kCVImageBufferYCbCrMatrix_ITU_R_601_4, kCVImageBufferYCbCrMatrixKey,
			//[NSNumber numberWithInt:2], kCMFormatDescriptionExtension_Version,
		//	nil];
		OSStatus					osErr = CMVideoFormatDescriptionCreateForImageBuffer(NULL,
			cvPixRef,
			&desc);
		if (osErr!=noErr || desc==NULL)
			NSLog(@"\t\terr %d at CMVideoFormatDescriptionCreate() in %s",(int)osErr,__func__);
		else	{
			//NSLog(@"\t\textensions of created fmt desc are %@",CMFormatDescriptionGetExtensions(desc));
			//FourCCLog(@"\t\tmedia sub-type of fmt desc is",CMFormatDescriptionGetMediaSubType(desc));
			//	get the timing info from the hap sample buffer
			CMSampleTimingInfo		timing;
			CMSampleBufferGetSampleTimingInfo(hapSampleBuffer, 0, &timing);
			timing.duration = kCMTimeInvalid;
			//timing.presentationTimeStamp = kCMTimeInvalid;
			timing.decodeTimeStamp = kCMTimeInvalid;
			//	make a CMSampleBufferRef from the CVPixelBufferRef
			osErr = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault,
				cvPixRef,
				desc,
				&timing,
				&returnMe);
			if (osErr!=noErr || returnMe==NULL)
				NSLog(@"\t\terr %d at CMSampleBufferCreateForImageBuffer() in %s",(int)osErr,__func__);
			else	{
				//NSLog(@"\t\tsuccessfully allocated a CMSampleBuffer from the RGB data in me! %@/%s",self,__func__);
			}
			
			
			CFRelease(desc);
			desc = NULL;
		}
		
		
		CVPixelBufferRelease(cvPixRef);
		cvPixRef = NULL;
	}
	
	return returnMe;
}


- (void) setUserInfo:(id)n	{
	os_unfair_lock_lock(&atomicLock);
	if (n!=userInfo)	{
		if (userInfo!=nil)
			[userInfo release];
		userInfo = n;
		if (userInfo!=nil)
			[userInfo retain];
	}
	os_unfair_lock_unlock(&atomicLock);
}
- (id) userInfo	{
	id		returnMe = nil;
	os_unfair_lock_lock(&atomicLock);
	returnMe = userInfo;
	os_unfair_lock_unlock(&atomicLock);
	return returnMe;
}
- (void) setDecoded:(BOOL)n	{
	os_unfair_lock_lock(&atomicLock);
	decoded = n;
	os_unfair_lock_unlock(&atomicLock);
}
- (BOOL) decoded	{
	BOOL		returnMe = NO;
	os_unfair_lock_lock(&atomicLock);
	returnMe = decoded;
	os_unfair_lock_unlock(&atomicLock);
	return returnMe;
}
- (void) incrementAge	{
	os_unfair_lock_lock(&atomicLock);
	++age;
	os_unfair_lock_unlock(&atomicLock);
}
- (int) age	{
	int		returnMe = 0;
	os_unfair_lock_lock(&atomicLock);
	returnMe = age;
	os_unfair_lock_unlock(&atomicLock);
	return returnMe;
}


@end
