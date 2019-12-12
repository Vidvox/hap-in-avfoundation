#import "AVAssetWriterHapInput.h"
#import <Accelerate/Accelerate.h>
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
NSString *const			AVVideoCodecHapQAlpha = @"HapM";
NSString *const			AVVideoCodecHapAlphaOnly = @"HapA";
NSString *const			AVHapVideoChunkCountKey = @"AVHapVideoChunkCountKey";
NSString *const			AVFallbackFPSKey = @"AVFallbackFPSKey";

#define FourCCLog(n,f) NSLog(@"%@, %c%c%c%c",n,(int)((f>>24)&0xFF),(int)((f>>16)&0xFF),(int)((f>>8)&0xFF),(int)((f>>0)&0xFF))




//	these aren't in the header file because the user-facing API doesn't need to call them
@interface AVAssetWriterHapInput ()
@property (assign,readwrite) CMTime lastEncodedDuration;
- (void) appendEncodedFrames;
- (void *) allocDXTEncoder;
- (void *) allocAlphaEncoder;
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
	os_unfair_lock_lock(&_HIAVFMemPoolLock);
	if (_HIAVFMemPool==NULL)
		_HIAVFMemPool = CMMemoryPoolCreate(NULL);
	if (_HIAVFMemPoolAllocator==NULL)
		_HIAVFMemPoolAllocator = CMMemoryPoolGetAllocator(_HIAVFMemPool);
	os_unfair_lock_unlock(&_HIAVFMemPoolLock);
}
- (id) initWithMediaType:(AVMediaType)mediaType outputSettings:(NSDictionary<NSString *,id> *)outputSettings	{
	NSLog(@"**** ERR: DO NOT USE THIS INIT METHOD (%s)",__func__);
	NSLog(@"AVFoundation does not officially recognize the Hap codec");
	NSLog(@"Please use -[AVAssetWriterHapInput initWithOutputSettings:] instead");
	[self release];
	return nil;
}
- (id) initWithOutputSettings:(NSDictionary *)n	{
	self = [super initWithMediaType:AVMediaTypeVideo outputSettings:nil];
	if (self!=nil)	{
		encodeQueue = NULL;
		exportCodecType = kHapCodecSubType;
		exportPixelFormatsCount = 1;
		exportPixelFormats[0] = kHapCVPixelFormat_RGB_DXT1;
		exportPixelFormats[1] = 0;
		exportTextureTypes[0] = HapTextureFormat_RGB_DXT1;
		exportTextureTypes[1] = 0;
		exportImgSize = NSMakeSize(1,1);
		exportDXTImgSize = NSMakeSize(4,4);
		exportChunkCounts[0] = 1;
		exportChunkCounts[1] = 1;
		exportHighQualityFlag = NO;
		exportSliceCount = 1;
		exportSliceHeight = 4;
		formatConvertPoolLengths[0] = 0;
		formatConvertPoolLengths[1] = 0;
		dxtBufferPoolLengths[0] = 0;
		dxtBufferPoolLengths[1] = 0;
		dxtBufferBytesPerRow[0] = 0;
		dxtBufferBytesPerRow[1] = 0;
		hapBufferPoolLength = 0;
		encoderLock = OS_UNFAIR_LOCK_INIT;
		glDXTEncoder = NULL;
		encoderProgressLock = OS_UNFAIR_LOCK_INIT;
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
		exportHighQualityFlag = NO;
		if (codecString==nil)
			goto BAIL;
		else if ([codecString isEqualToString:AVVideoCodecHap])	{
			hapExport = YES;
			exportCodecType = kHapCodecSubType;
			exportPixelFormatsCount = 1;
			exportPixelFormats[0] = kHapCVPixelFormat_RGB_DXT1;
			exportPixelFormats[1] = 0;
			exportTextureTypes[0] = HapTextureFormat_RGB_DXT1;
			exportTextureTypes[1] = 0;
		}
		else if ([codecString isEqualToString:AVVideoCodecHapAlpha])	{
			hapExport = YES;
			exportCodecType = kHapAlphaCodecSubType;
			exportPixelFormatsCount = 1;
			exportPixelFormats[0] = kHapCVPixelFormat_RGBA_DXT5;
			exportPixelFormats[1] = 0;
			exportTextureTypes[0] = HapTextureFormat_RGBA_DXT5;
			exportTextureTypes[1] = 0;
		}
		else if ([codecString isEqualToString:AVVideoCodecHapQ])	{
			hapExport = YES;
			exportCodecType = kHapYCoCgCodecSubType;
			exportPixelFormatsCount = 1;
			exportPixelFormats[0] = kHapCVPixelFormat_YCoCg_DXT5;
			exportPixelFormats[1] = 0;
			exportTextureTypes[0] = HapTextureFormat_YCoCg_DXT5;
			exportTextureTypes[1] = 0;
		}
		else if ([codecString isEqualToString:AVVideoCodecHapQAlpha])	{
			hapExport = YES;
			exportCodecType = kHapYCoCgACodecSubType;
			exportPixelFormatsCount = 2;
			exportPixelFormats[0] = kHapCVPixelFormat_YCoCg_DXT5;
			exportPixelFormats[1] = kHapCVPixelFormat_A_RGTC1;
			exportTextureTypes[0] = HapTextureFormat_YCoCg_DXT5;
			exportTextureTypes[1] = HapTextureFormat_A_RGTC1;
		}
		else if ([codecString isEqualToString:AVVideoCodecHapAlphaOnly])	{
			hapExport = YES;
			exportCodecType = kHapAOnlyCodecSubType;
			exportPixelFormatsCount = 1;
			exportPixelFormats[0] = kHapCVPixelFormat_A_RGTC1;
			exportPixelFormats[1] = 0;
			exportTextureTypes[0] = HapTextureFormat_A_RGTC1;
			exportTextureTypes[1] = 0;
		}
		if (!hapExport)
			goto BAIL;
		//	if there's a quality key and it's > 0.75, we'll use squish to compress the frames (higher quality, but much slower)
		NSDictionary	*propertiesDict = [n objectForKey:AVVideoCompressionPropertiesKey];
		NSNumber		*qualityNum = (propertiesDict==nil) ? nil : [propertiesDict objectForKey:AVVideoQualityKey];
		if (qualityNum!=nil && [qualityNum floatValue]>=0.80)
			exportHighQualityFlag = YES;
		NSNumber		*chunkNum = (propertiesDict==nil) ? nil : [propertiesDict objectForKey:AVHapVideoChunkCountKey];
		exportChunkCounts[0] = (chunkNum==nil) ? 1 : [chunkNum intValue];
		exportChunkCounts[0] = fmaxl(fminl(exportChunkCounts[0], HAPQMAXCHUNKS), 1);
		exportChunkCounts[1] = exportChunkCounts[0];
		//	if there's a default FPS key, use it
		NSNumber		*fallbackFPSNum = (propertiesDict==nil) ? nil : [n objectForKey:AVFallbackFPSKey];
		fallbackFPS = (fallbackFPSNum==nil) ? 0.0 : [fallbackFPSNum doubleValue];
		
		//	figure out the max dxt frame size in bytes
		NSUInteger		dxtFrameSizeInBytes[2];
		dxtFrameSizeInBytes[0] = dxtBytesForDimensions(exportDXTImgSize.width, exportDXTImgSize.height, exportCodecType);
		dxtFrameSizeInBytes[1] = 0;
		if (exportPixelFormatsCount>1)
			dxtFrameSizeInBytes[1] = dxtBytesForDimensions(exportDXTImgSize.width, exportDXTImgSize.height, kHapAOnlyCodecSubType);
		//NSLog(@"\t\tdxtFrameSizeInBytes is %d",dxtFrameSizeInBytes);
		dxtBufferPoolLengths[0] = dxtFrameSizeInBytes[0];
		dxtBufferPoolLengths[1] = dxtFrameSizeInBytes[1];
		dxtBufferBytesPerRow[0] = dxtBufferPoolLengths[0] / exportDXTImgSize.height;
		dxtBufferBytesPerRow[1] = dxtBufferPoolLengths[1] / exportDXTImgSize.height;
		//	figure out the max hap frame size in bytes
		hapBufferPoolLength = HapMaxEncodedLength(exportPixelFormatsCount, dxtFrameSizeInBytes, exportTextureTypes, exportChunkCounts);
		//NSLog(@"\t\thapBufferPoolLength is %d",hapBufferPoolLength);
		
		//	make a DXT encoder just to make sure we can
		void			*dxtEncoder = [self allocDXTEncoder];
		if (dxtEncoder==NULL)	{
			NSLog(@"\t\terr: couldn't make dxtEncoder, %s",__func__);
			FourCCLog(@"\t\texport codec type was",exportCodecType);
			goto BAIL;
		}
		
		//FourCCLog(@"\t\texportCodecType is",exportCodecType);
		//FourCCLog(@"\t\texportPixelFormat[0] is",exportPixelFormats[0]);
		//FourCCLog(@"\t\texportPixelFormat[1] is",exportPixelFormats[1]);
		//	make a buffer pool for format conversion buffers (i know what the desired pixel format is for the dxt encoder, so i know how big the format conversion buffers have to be)
		
		//	if we aren't using a GL-based DXT encoder (which is "expensive" to delete/recreate), release the DXT encoder
		if (dxtEncoder!=NULL)	{
			encoderInputPxlFmts[0] = ((HapCodecDXTEncoderRef)dxtEncoder)->pixelformat_function(dxtEncoder, exportPixelFormats[0]);
			switch (exportCodecType)	{
			case kHapCodecSubType:
			case kHapAlphaCodecSubType:
			{
				if (exportHighQualityFlag)	{
					HapCodecDXTEncoderDestroy((HapCodecDXTEncoderRef)dxtEncoder);
					dxtEncoder = NULL;
				}
				else	{
					//	do not release the DXT encoder for this case (this is the GL encoder)
					glDXTEncoder = dxtEncoder;
					dxtEncoder = NULL;
				}
				break;
			}
			case kHapYCoCgCodecSubType:
			case kHapYCoCgACodecSubType:
			case kHapAOnlyCodecSubType:
				HapCodecDXTEncoderDestroy((HapCodecDXTEncoderRef)dxtEncoder);
				dxtEncoder = NULL;
				break;
			}
		}
		
		if (exportPixelFormatsCount > 1)	{
			void			*alphaEncoder = [self allocAlphaEncoder];
			if (alphaEncoder==NULL)	{
				NSLog(@"\t\terr: couldn't make alphaEncoder, %s",__func__);
				FourCCLog(@"\t\texport codec type was",exportCodecType);
				goto BAIL;
			}
			else	{
				encoderInputPxlFmts[1] = ((HapCodecDXTEncoderRef)alphaEncoder)->pixelformat_function(alphaEncoder, exportPixelFormats[1]);
				HapCodecDXTEncoderDestroy((HapCodecDXTEncoderRef)alphaEncoder);
				alphaEncoder = NULL;
			}
		}
		
		//FourCCLog(@"\t\tencoderInputPxlFmts[0] is",encoderInputPxlFmts[0]);
		//FourCCLog(@"\t\tencoderInputPxlFmts[1] is",encoderInputPxlFmts[1]);
		encoderInputPxlFmtBytesPerRow[0] = roundUpToMultipleOf16(((uint32_t)exportImgSize.width * 4));
		encoderInputPxlFmtBytesPerRow[1] = 0;
		if (exportPixelFormatsCount>1)
			encoderInputPxlFmtBytesPerRow[1] = roundUpToMultipleOf16(((uint32_t)exportImgSize.width * 4));
		
		formatConvertPoolLengths[0] = encoderInputPxlFmtBytesPerRow[0]*(NSUInteger)(exportImgSize.height);
		formatConvertPoolLengths[1] = 0;
		if (exportPixelFormatsCount>1)
			formatConvertPoolLengths[1] = encoderInputPxlFmtBytesPerRow[1]*(NSUInteger)(exportImgSize.height);
		
		//encodeQueue = dispatch_queue_create("HapEncode", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT, QOS_CLASS_USER_INITIATED, -1));
		encodeQueue = dispatch_queue_create("HapEncode", DISPATCH_QUEUE_CONCURRENT);
		
		switch (exportCodecType)	{
			case kHapCodecSubType:
			case kHapAlphaCodecSubType:
			{
				if (!exportHighQualityFlag)	{
					exportSliceCount = 1;
					exportSliceHeight = exportDXTImgSize.height;
				}
				break;
			}
			case kHapYCoCgCodecSubType:
			case kHapYCoCgACodecSubType:
			case kHapAOnlyCodecSubType:
			default:
				break;
		}
		
		// Slice on DXT row boundaries
		//unsigned int totalDXTRows = roundUpToMultipleOf4(glob->height) / 4;
		unsigned int totalDXTRows = exportDXTImgSize.height / 4;
		unsigned int remainder;
		exportSliceCount = totalDXTRows < 30 ? totalDXTRows : 30;
		exportSliceHeight = (totalDXTRows / exportSliceCount) * 4;
		remainder = (totalDXTRows % exportSliceCount) * 4;
		while (remainder > 0)
		{
			exportSliceCount++;
			if (remainder > exportSliceHeight)
			{
				remainder -= exportSliceHeight;
			}
			else
			{
				remainder = 0;
			}
		}
		
		if ((exportCodecType==kHapCodecSubType || exportCodecType==kHapAlphaCodecSubType) && !exportHighQualityFlag)	{
			exportSliceCount = 1;
			exportSliceHeight = exportDXTImgSize.height;
		}
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
	os_unfair_lock_lock(&encoderProgressLock);
	if (encoderProgressFrames!=nil)	{
		[encoderProgressFrames release];
		encoderProgressFrames = nil;
	}
	os_unfair_lock_unlock(&encoderProgressLock);
	os_unfair_lock_lock(&encoderLock);
	//	release the DXT encoder
	if (glDXTEncoder!=NULL)	{
		HapCodecDXTEncoderDestroy((HapCodecDXTEncoderRef)glDXTEncoder);
		glDXTEncoder = NULL;
	}
	os_unfair_lock_unlock(&encoderLock);
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
		case k32ARGBPixelFormat:
			break;
		default:
			FourCCLog(@"\t\tERR: can't append pixel buffer- required RGBA or BGRA pixel format, but supplied",sourceFormat);
			returnMe = NO;
			break;
		}
	}
	
	//	if i'm done accepting samples (because something marked me as finished), i won't be encoding a frame- but i'll still want to execute the block
	__block HapEncoderFrame		*encoderFrame = nil;
	os_unfair_lock_lock(&encoderProgressLock);
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
	os_unfair_lock_unlock(&encoderProgressLock);
	
	//	retain the pixel buffer i was passed- i'll release it in the block (on the GCD-controlled thread)
	if (pb!=NULL)
		CVPixelBufferRetain(pb);
	
	
	//	assemble a block that will encode the passed pixel buffer- i'll either be dispatching this block (via GCD) or executing it immediately...
    void			(^encodeBlock)(void) = ^(){
		//NSLog(@"%s",__func__);
		//	if there's a pixel buffer to encode, let's take care of that first
		if (pb!=NULL)	{
			//	lock the base address of the pixel buffer
			CVPixelBufferLockBaseAddress(pb,kHapCodecCVPixelBufferLockFlags);
			
			//	get the size of the image in the cvpixelbuffer, we need to compare it to the export size to determine if we need to do a resize...
			NSSize			pbSize = NSMakeSize(CVPixelBufferGetWidth(pb),CVPixelBufferGetHeight(pb));
			
			//	get a ptr to the raw pixel data- i'll either be resizing/converting it or encoding this ptr.
			void			*sourceBuffer = CVPixelBufferGetBaseAddress(pb);
			size_t			sourceBufferBytesPerRow = CVPixelBufferGetBytesPerRow(pb);
			
			//	allocate the resize buffer if i need it
			void			*resizeBuffer = nil;
			if (!NSEqualSizes(pbSize, exportImgSize))	{
				//	make a vImage struct for the pixel buffer we were passed
				vImage_Buffer		pbImage = {
					.data = sourceBuffer,
					.height = pbSize.height,
					.width = pbSize.width,
					.rowBytes = sourceBufferBytesPerRow
				};
				//	make the resize buffer
				size_t			resizeBufferSize = encoderInputPxlFmtBytesPerRow[0] * exportImgSize.height;
				resizeBuffer = CFAllocatorAllocate(_HIAVFMemPoolAllocator, resizeBufferSize, 0);
				//	make a vImage struct for the resize buffer we just allocated
				vImage_Buffer		resizeImage = {
					.data = resizeBuffer,
					.height = exportImgSize.height,
					.width = exportImgSize.width,
					.rowBytes = encoderInputPxlFmtBytesPerRow[0]
				};
				//	scale the pixel buffer's vImage to the resize buffer's vImage
				vImage_Error		vErr = vImageScale_ARGB8888(&pbImage, &resizeImage, NULL, kvImageHighQualityResampling | kvImageDoNotTile);
				if (vErr != kvImageNoError)
					NSLog(@"\t\terr %ld scaling image in %s",vErr,__func__);
				else	{
					//	update the sourceBuffer- we just resized the buffer we were passed, so it should have the same pixel format
					sourceBuffer = resizeImage.data;
					sourceBufferBytesPerRow = resizeImage.rowBytes;
				}
			}
			
			//	allocate any format conversion buffers i may need
			void			*_formatConvertBuffers[2];
			_formatConvertBuffers[0] = nil;
			_formatConvertBuffers[1] = nil;
			void			**formatConvertBuffers = _formatConvertBuffers;	//	this exists because we can't refer to arrays on the stack from within blocks
			for (int i=0; i<exportPixelFormatsCount; ++i)	{
				if (sourceFormat != encoderInputPxlFmts[i])	{
					formatConvertBuffers[i] = CFAllocatorAllocate(_HIAVFMemPoolAllocator, formatConvertPoolLengths[i], 0);
				}
			}
			
			//	allocate the DXT buffer (or buffers) i'll be creating
			void			*dxtBuffer = CFAllocatorAllocate(_HIAVFMemPoolAllocator, dxtBufferPoolLengths[0], 0);
			void			*dxtAlphaBuffer = NULL;
			__block int		intErr = 0;
			//	try to get the default GL-based DXT encoder- if it exists we need to use it (and it's shared)
			os_unfair_lock_lock(&encoderLock);
			void			*targetDXTEncoder = glDXTEncoder;
			void			*targetAlphaEncoder = NULL;
			os_unfair_lock_unlock(&encoderLock);
			void			*newDXTEncoder = NULL;
			void			*newAlphaEncoder = NULL;
			//	if we aren't sharing a GL-based DXT encoder, we need to make a new DXT encoder (which will be freed after this frame is encoded)
			if (targetDXTEncoder == NULL)	{
				newDXTEncoder = [self allocDXTEncoder];
				targetDXTEncoder = newDXTEncoder;
			}
			if (exportPixelFormatsCount > 1)	{
				newAlphaEncoder = [self allocAlphaEncoder];
				targetAlphaEncoder = newAlphaEncoder;
				dxtAlphaBuffer = CFAllocatorAllocate(_HIAVFMemPoolAllocator, dxtBufferPoolLengths[1], 0);
			}
			
			//	...at this point, i've created all the resource i need to convert the pixel buffer to the appropriate pixel format/formats and encode it/them as DXT data
			
			//	make a block that converts a slice from the pixel buffer to DXT.  single block converts both RGB and alpha planes.
			void						(^encodeSliceAsDXTBlock)(size_t index) = ^(size_t index)	{
				//	figure out how tall this slice is going to be (based on the export slice height and the dims of the input img)
				size_t				thisSliceHeight = exportSliceHeight;
				if (((index+1) * exportSliceHeight) > exportImgSize.height)
					thisSliceHeight = exportSliceHeight - (((index+1) * exportSliceHeight) - exportImgSize.height);
				//	run run through the export pixel formats
				for (int i=0; i<exportPixelFormatsCount; ++i)	{
					//	if the source format doesn't match the encoder input format, we're going to have to convert the source into something encoder can work with
					if (sourceFormat != encoderInputPxlFmts[i])	{
						switch (encoderInputPxlFmts[i])	{
						case kHapCVPixelFormat_CoCgXY:
							if (sourceFormat == k32BGRAPixelFormat)	{
								ConvertBGR_ToCoCg_Y8888((uint8_t *)sourceBuffer + (index * exportSliceHeight * sourceBufferBytesPerRow),
									(uint8_t *)formatConvertBuffers[i] + (index * exportSliceHeight * encoderInputPxlFmtBytesPerRow[i]),
									(NSUInteger)exportImgSize.width,
									(NSUInteger)thisSliceHeight,
									sourceBufferBytesPerRow,
									encoderInputPxlFmtBytesPerRow[i],
									0);
							}
							else if (sourceFormat == k32ARGBPixelFormat || sourceFormat == 0x20)	{
								ConvertARGB_ToCoCg_Y8888((uint8_t *)sourceBuffer + (index * exportSliceHeight * sourceBufferBytesPerRow),
									(uint8_t *)formatConvertBuffers[i] + (index * exportSliceHeight * encoderInputPxlFmtBytesPerRow[i]),
									(NSUInteger)exportImgSize.width,
									(NSUInteger)thisSliceHeight,
									sourceBufferBytesPerRow,
									encoderInputPxlFmtBytesPerRow[i],
									0);
							}
							else	{
								ConvertRGB_ToCoCg_Y8888((uint8_t *)sourceBuffer + (index * exportSliceHeight * sourceBufferBytesPerRow),
									(uint8_t *)formatConvertBuffers[i] + (index * exportSliceHeight * encoderInputPxlFmtBytesPerRow[i]),
									(NSUInteger)exportImgSize.width,
									(NSUInteger)thisSliceHeight,
									sourceBufferBytesPerRow,
									encoderInputPxlFmtBytesPerRow[i],
									0);
							}
							break;
						case k32RGBAPixelFormat:
							if (sourceFormat == k32BGRAPixelFormat)	{
								uint8_t			permuteMap[] = {2, 1, 0, 3};
								ImageMath_Permute8888(sourceBuffer + (index * exportSliceHeight * sourceBufferBytesPerRow),
									sourceBufferBytesPerRow,
									formatConvertBuffers[i] + (index * exportSliceHeight * encoderInputPxlFmtBytesPerRow[i]),
									encoderInputPxlFmtBytesPerRow[i],
									(NSUInteger)exportImgSize.width,
									(NSUInteger)thisSliceHeight,
									permuteMap,
									0);
							}
							else if (sourceFormat == k32ARGBPixelFormat || sourceFormat == 0x20)	{
								uint8_t			permuteMap[] = {1, 2, 3, 0};
								ImageMath_Permute8888(sourceBuffer + (index * exportSliceHeight * sourceBufferBytesPerRow),
									sourceBufferBytesPerRow,
									formatConvertBuffers[i] + (index * exportSliceHeight * encoderInputPxlFmtBytesPerRow[i]),
									encoderInputPxlFmtBytesPerRow[i],
									(NSUInteger)exportImgSize.width,
									(NSUInteger)thisSliceHeight,
									permuteMap,
									0);
							}
							else	{
								NSLog(@"\t\terr: unhandled, %s",__func__);
								FourCCLog(@"\t\tsourceFormat is",sourceFormat);
								FourCCLog(@"\t\tencoderInputPxlFmt is",encoderInputPxlFmts[i]);
							}
							break;
						case k32BGRAPixelFormat:
							if (sourceFormat == k32ARGBPixelFormat || sourceFormat == 0x20)	{
								uint8_t			permuteMap[] = {3, 2, 1, 0};
								ImageMath_Permute8888(sourceBuffer + (index * exportSliceHeight * sourceBufferBytesPerRow),
									sourceBufferBytesPerRow,
									formatConvertBuffers[i] + (index * exportSliceHeight * encoderInputPxlFmtBytesPerRow[i]),
									encoderInputPxlFmtBytesPerRow[i],
									(NSUInteger)exportImgSize.width,
									(NSUInteger)thisSliceHeight,
									permuteMap,
									0);
							}
							else	{
								NSLog(@"\t\terr: unhandled, %s",__func__);
								FourCCLog(@"\t\tsourceFormat is",sourceFormat);
								FourCCLog(@"\t\tencoderInputPxlFmt is",encoderInputPxlFmts[i]);
							}
							break;
						default:
							NSLog(@"\t\terr: default case, %s",__func__);
							FourCCLog(@"\t\tsourceFormat is",sourceFormat);
							FourCCLog(@"\t\tencoderInputPxlFmt is",encoderInputPxlFmts[i]);
							break;
						}
					}
				}
				
				//	...at this point, the image data in this "slice" (for both planes) has been converted to a pixel format the DXT encoder can work with
				
				//	encode the data from the RGB plane for this slice as DXT data
				if (targetDXTEncoder != NULL)	{
					//	if we haven't created a new DXT encoder then we're using the GL encoder, which is shared- and must thus be locked
					if (newDXTEncoder == NULL)
						os_unfair_lock_lock(&encoderLock);
					//	slightly different path depending on whether i'm converting the passed pixel buffer...
					if (formatConvertBuffers[0]==nil)	{
						intErr = ((HapCodecDXTEncoderRef)targetDXTEncoder)->encode_function(targetDXTEncoder,
							sourceBuffer + (index * exportSliceHeight * sourceBufferBytesPerRow),
							(unsigned int)sourceBufferBytesPerRow,
							encoderInputPxlFmts[0],
							dxtBuffer + (index * exportSliceHeight * dxtBufferBytesPerRow[0]),
							(unsigned int)exportImgSize.width,
							(unsigned int)thisSliceHeight);
					}
					//	...or if i'm converting the format conversion buffer 
					else	{
						intErr = ((HapCodecDXTEncoderRef)targetDXTEncoder)->encode_function(targetDXTEncoder,
							formatConvertBuffers[0] + (index * exportSliceHeight * encoderInputPxlFmtBytesPerRow[0]),
							(unsigned int)encoderInputPxlFmtBytesPerRow[0],
							encoderInputPxlFmts[0],
							dxtBuffer + (index * exportSliceHeight * dxtBufferBytesPerRow[0]),
							(unsigned int)exportImgSize.width,
							(unsigned int)thisSliceHeight);
					}
					if (newDXTEncoder == NULL)
						os_unfair_lock_unlock(&encoderLock);
				}
				
				//	if it exists, encode the data from the alpha plane for this slice as DXT data
				if (exportPixelFormatsCount>1 && targetAlphaEncoder!=NULL)	{
					//	slightly different path depending on whether i'm converting the passed pixel buffer...
					if (formatConvertBuffers[1]==nil)	{
						
						intErr = ((HapCodecDXTEncoderRef)targetAlphaEncoder)->encode_function(targetAlphaEncoder,
							sourceBuffer + (index * exportSliceHeight * sourceBufferBytesPerRow),
							(unsigned int)sourceBufferBytesPerRow,
							encoderInputPxlFmts[1],
							dxtAlphaBuffer + (index * exportSliceHeight * dxtBufferBytesPerRow[1]),
							(unsigned int)exportImgSize.width,
							(unsigned int)thisSliceHeight);
						
					}
					//	...or if i'm converting the format conversion buffer 
					else	{
						
						intErr = ((HapCodecDXTEncoderRef)targetAlphaEncoder)->encode_function(targetAlphaEncoder,
							formatConvertBuffers[1] + (index * exportSliceHeight * encoderInputPxlFmtBytesPerRow[1]),
							(unsigned int)encoderInputPxlFmtBytesPerRow[1],
							encoderInputPxlFmts[1],
							dxtAlphaBuffer + (index * exportSliceHeight * dxtBufferBytesPerRow[1]),
							(unsigned int)exportImgSize.width,
							(unsigned int)thisSliceHeight);
						
					}
				}
				
			};
			
			//	now i have to execute the conversion block the appropriate number of times...
			if (exportSliceCount == 1)
				encodeSliceAsDXTBlock(0);
			else
				dispatch_apply(exportSliceCount, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), encodeSliceAsDXTBlock);
			
			
			//	unlock the pixel buffer immediately- we're done creating the DXT buffer, and don't need the source pixel buffer's data any longer
			CVPixelBufferUnlockBaseAddress(pb,kHapCodecCVPixelBufferLockFlags);
			
			
			//	if there was an error with the DXT encode, don't proceed
			if (intErr != 0)	{
				NSLog(@"\t\terr %d encoding dxt data in %s, not appending buffer",intErr,__func__);
			}
			//	else there wasn't an error with the DXT encode- we're good to go!
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
						const void			*tmpDXTBuffers[] = {dxtBuffer, dxtAlphaBuffer};
						unsigned int		compressors[] = {HapCompressorSnappy, HapCompressorSnappy};
						hapErr = HapEncode(exportPixelFormatsCount,
							(const void **)tmpDXTBuffers,
							dxtBufferPoolLengths,
							exportTextureTypes,
							compressors,
							exportChunkCounts,
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
                                int depth;
                                switch (exportCodecType) {
                                    case kHapAlphaCodecSubType:
                                    case kHapYCoCgACodecSubType:
                                        depth = 32;
                                        break;
                                    default:
                                        depth = 24;
                                        break;
                                }
								NSDictionary				*bufferExtensions = [NSDictionary dictionaryWithObjectsAndKeys:
									[NSNumber numberWithDouble:2.199996948242188], kCMFormatDescriptionExtension_GammaLevel,
									[NSNumber numberWithInt:depth],kCMFormatDescriptionExtension_Depth,
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
			if (dxtAlphaBuffer!=nil)	{
				CFAllocatorDeallocate(_HIAVFMemPoolAllocator, dxtAlphaBuffer);
				dxtAlphaBuffer = nil;
			}
			if (resizeBuffer != nil)	{
				CFAllocatorDeallocate(_HIAVFMemPoolAllocator, resizeBuffer);
				resizeBuffer = nil;
			}
			if (formatConvertBuffers[0]!=nil)	{
				CFAllocatorDeallocate(_HIAVFMemPoolAllocator, formatConvertBuffers[0]);
				formatConvertBuffers[0] = nil;
			}
			if (formatConvertBuffers[1]!=nil)	{
				CFAllocatorDeallocate(_HIAVFMemPoolAllocator, formatConvertBuffers[1]);
				formatConvertBuffers[1] = nil;
			}
			
			//	release the dxt encoder
			if (newDXTEncoder!=NULL)	{
				HapCodecDXTEncoderDestroy((HapCodecDXTEncoderRef)newDXTEncoder);
				newDXTEncoder = NULL;
			}
			if (newAlphaEncoder!=NULL)	{
				HapCodecDXTEncoderDestroy((HapCodecDXTEncoderRef)newAlphaEncoder);
				newAlphaEncoder = NULL;
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
			if (!returnMe)	{
				CMSampleTimingInfo		sampleTimingInfo;
				CMSampleBufferGetSampleTimingInfo(n, 0, &sampleTimingInfo);
				NSLog(@"\t\tERR: %s, failed to append sampleBuffer at time %@",__func__,[(id)CMTimeCopyDescription(kCFAllocatorDefault, sampleTimingInfo.decodeTimeStamp) autorelease]);
			}
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
	os_unfair_lock_lock(&encoderProgressLock);
	if ([encoderProgressFrames count]==0)
		returnMe = YES;
	os_unfair_lock_unlock(&encoderProgressLock);
	return returnMe;
}
- (void) finishEncoding	{
	os_unfair_lock_lock(&encoderProgressLock);
	BOOL			needsToEncodeMore = NO;
	if (encoderWaitingToRunOut || [encoderProgressFrames count]>0)
		needsToEncodeMore = YES;
	os_unfair_lock_unlock(&encoderProgressLock);
	
	if (needsToEncodeMore)
		[self appendEncodedFrames];
}
- (void)markAsFinished	{
	//NSLog(@"%s",__func__);
	os_unfair_lock_lock(&encoderProgressLock);
	encoderWaitingToRunOut = YES;
	os_unfair_lock_unlock(&encoderProgressLock);
	//	append any encoded frames- if there are frames left over that aren't done encoding yet, this does nothing.  if there aren't any frames left over, it marks the input as finished.
	[self appendEncodedFrames];
}
- (BOOL) isReadyForMoreMediaData	{
	BOOL		returnMe = [super isReadyForMoreMediaData];
	if (returnMe)	{
		os_unfair_lock_lock(&encoderProgressLock);
		if (encoderWaitingToRunOut)	{
			//NSLog(@"\t\tpretending i'm not ready for more data, waiting to run out- %s",__func__);
			returnMe = NO;
		}
		else if ([encoderProgressFrames count]>8)	{
			//NSLog(@"\t\ttoo many frames waiting to be appended, not ready- %s",__func__);
			returnMe = NO;
		}
		os_unfair_lock_unlock(&encoderProgressLock);
	}
	return returnMe;
}
//	synthesized so we get automatic atomicity
@synthesize lastEncodedDuration;

//	runs through the encoder progress frames, getting as many sample buffers as possible and appending them (in order)
- (void) appendEncodedFrames	{
	//NSLog(@"%s",__func__);
	
	os_unfair_lock_lock(&encoderProgressLock);
	if (![super isReadyForMoreMediaData])	{
		NSLog(@"\t\terr: not ready for more media data, %s",__func__);
		[encoderProgressFrames removeAllObjects];
		os_unfair_lock_unlock(&encoderProgressLock);
		
		[super markAsFinished];
	}
	//	first of all, if there's only one sample and i'm waiting to finish- append the last sample and then i'm done (yay!)
	else if (encoderWaitingToRunOut && [encoderProgressFrames count]<=1)	{
		HapEncoderFrame			*lastFrame = nil;
		BOOL					markAsFinished = NO;
		if ([encoderProgressFrames count]<1)
			markAsFinished = YES;
		else	{
			lastFrame = [encoderProgressFrames objectAtIndex:0];
			if (![lastFrame encoded])
				lastFrame = nil;
			else	{
				[lastFrame retain];
				[encoderProgressFrames removeObjectAtIndex:0];
				markAsFinished = YES;
			}
		}
		os_unfair_lock_unlock(&encoderProgressLock);
		
		if (lastFrame != nil)	{
			//	make a hap sample buffer, append it
			CMSampleBufferRef	hapSampleBuffer = NULL;
			CMTime				tmpTime = [self lastEncodedDuration];
			//	if there's no 'lastEncodedDuration'...
			if (tmpTime.value == 0)	{
				//	try to use the fallback FPS- if there isn't one, just use a value of 1...
				if (fallbackFPS <= 0.0)	{
					hapSampleBuffer = [lastFrame allocCMSampleBufferWithDurationTimeValue:1];
				}
				//	else there's a fallback FPS- calculate an appropriate time value given the fallback FPS and the last frame's timescale
				else	{
					hapSampleBuffer = [lastFrame allocCMSampleBufferWithDurationTimeValue:(int)round((1.0/fallbackFPS) / (1.0/(double)[lastFrame presentationTime].timescale))];
				}
			}
			//	else there's a 'lastEncodedDuration'- use it...
			else	{
				hapSampleBuffer = [lastFrame allocCMSampleBufferWithDurationTimeValue:tmpTime.value];
			}
			
			if (hapSampleBuffer==NULL)
				NSLog(@"\t\terr: couldn't make sample buffer from frame duration, %s",__func__);
			else	{
				if (![super appendSampleBuffer:hapSampleBuffer])	{
					CMSampleTimingInfo		sampleTimingInfo;
					CMSampleBufferGetSampleTimingInfo(hapSampleBuffer, 0, &sampleTimingInfo);
					NSLog(@"\t\tERR: %s, failed to append sampleBuffer A at time %@",__func__,[(id)CMTimeCopyDescription(kCFAllocatorDefault, sampleTimingInfo.decodeTimeStamp) autorelease]);
				}
				CFRelease(hapSampleBuffer);
			}
			
			[lastFrame release];
			lastFrame = nil;
		}
		
		if (markAsFinished)	{
			[super markAsFinished];
		}
		
	}
	//	else i'm either not waiting to run out, or there's more than one frame in the array...
	else	{
		os_unfair_lock_unlock(&encoderProgressLock);
		
		//	we want to add as many samples as possible
		while ([super isReadyForMoreMediaData])	{
			//	get the first two frames- if they're both encoded then i can append the first frame
			os_unfair_lock_lock(&encoderProgressLock);
			HapEncoderFrame		*thisFrame = nil;
			HapEncoderFrame		*nextFrame = nil;
			if ([encoderProgressFrames count]>1)	{
				thisFrame = [encoderProgressFrames objectAtIndex:0];
				nextFrame = [encoderProgressFrames objectAtIndex:1];
				if (thisFrame==nil || nextFrame==nil || ![thisFrame encoded] || ![nextFrame encoded])	{
					thisFrame = nil;
					nextFrame = nil;
				}
				else	{
					[thisFrame retain];
					[nextFrame retain];
					[encoderProgressFrames removeObjectAtIndex:0];
				}
			}
			os_unfair_lock_unlock(&encoderProgressLock);
			
			//	if we don't have any frames to work with, break out of the while loop- there's nothing for us to append
			if (thisFrame==nil || nextFrame==nil)
				break;
			//NSLog(@"\t\tthisFrame is %@, nextFrame is %@",thisFrame,nextFrame);
			
			//	tell this frame to create a sample buffer derived from the next frame's presentation time
			CMSampleBufferRef	hapSampleBuffer = [thisFrame allocCMSampleBufferWithNextFramePresentationTime:[nextFrame presentationTime]];
			if (hapSampleBuffer==NULL)
				NSLog(@"\t\terr: couldn't make hap sample buffer from frame, %s, not appending buffer",__func__);
			else	{
				//	save the duration- i need to save the duration because i have to apply a duration to the final frame
				CMSampleTimingInfo		sampleTimingInfo;
				CMSampleBufferGetSampleTimingInfo(hapSampleBuffer, 0, &sampleTimingInfo);
				//NSLog(@"\t\tappending sample at time %@",[(id)CMTimeCopyDescription(kCFAllocatorDefault, sampleTimingInfo.presentationTimeStamp) autorelease]);
				[self setLastEncodedDuration:sampleTimingInfo.duration];
				
				if (![super appendSampleBuffer:hapSampleBuffer])	{
					NSLog(@"\t\tERR: %s, failed to append sampleBuffer B at time %@",__func__,[(id)CMTimeCopyDescription(kCFAllocatorDefault, sampleTimingInfo.decodeTimeStamp) autorelease]);
				}
				
				CFRelease(hapSampleBuffer);
			}
			
			if (thisFrame!=nil)
				[thisFrame release];
			if (nextFrame!=nil)
				[nextFrame release];
		}
		
	}
	
}
- (void *) allocDXTEncoder	{
	void			*returnMe = NULL;
	os_unfair_lock_lock(&encoderProgressLock);
	switch (exportCodecType)	{
	case kHapCodecSubType:
	case kHapAlphaCodecSubType:
	{
		if (exportHighQualityFlag)
			returnMe = HapCodecSquishEncoderCreate(HapCodecSquishEncoderMediumQuality, exportPixelFormats[0]);
		else
			returnMe = HapCodecGLEncoderCreate((unsigned int)exportImgSize.width, (unsigned int)exportImgSize.height, exportPixelFormats[0]);
		break;
	}
	case kHapYCoCgCodecSubType:
	case kHapYCoCgACodecSubType:
		returnMe = HapCodecYCoCgDXTEncoderCreate();
		break;
	case kHapAOnlyCodecSubType:
		break;
	}
	if (returnMe==NULL)	{
		NSLog(@"\t\terr: couldn't make encoder, %s",__func__);
		FourCCLog(@"\t\texport codec type was",exportCodecType);
	}
	os_unfair_lock_unlock(&encoderProgressLock);
	return returnMe;
}
- (void *) allocAlphaEncoder	{
	//	note: only create and return an alpha encoder if appropriate (if i should be exporting a discrete alpha channel)
	void			*returnMe = NULL;
	os_unfair_lock_lock(&encoderProgressLock);
	switch (exportCodecType)	{
	case kHapCodecSubType:
	case kHapAlphaCodecSubType:
		//	intentionally blank, these codecs do not require discrete alpha-channel encoding
		break;
	case kHapYCoCgCodecSubType:
	case kHapYCoCgACodecSubType:
		returnMe = HapCodecSquishEncoderCreate(HapCodecSquishEncoderBestQuality, kHapCVPixelFormat_A_RGTC1);
		break;
	case kHapAOnlyCodecSubType:
		break;
	}
	if (returnMe==NULL)	{
		NSLog(@"\t\terr: couldn't make encoder, %s",__func__);
		FourCCLog(@"\t\texport codec type was",exportCodecType);
	}
	os_unfair_lock_unlock(&encoderProgressLock);
	return returnMe;
}


- (BOOL) canPerformMultiplePasses	{
	return NO;
}
- (void) setPerformsMultiPassEncodingIfSupported:(BOOL)n	{
	[super setPerformsMultiPassEncodingIfSupported:NO];
}


@end
