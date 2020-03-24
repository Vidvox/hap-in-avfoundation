#import "HapMetalPixelBufferTexture.h"
#import <HapInAVFoundation/HapInAVFoundation.h>
#import "MetalShaderTypes.h"
#define FourCCLog(n,f) NSLog(@"%@, %c%c%c%c",n,(int)((f>>24)&0xFF),(int)((f>>16)&0xFF),(int)((f>>8)&0xFF),(int)((f>>0)&0xFF))


@implementation HapMetalPixelBufferTexture
{
    id<MTLFunction> fragmentFunctionScaledCoCgYToRGBA;
    id<MTLFunction> fragmentFunctionScaledCoCgYPlusAToRGBA;
    id<MTLFunction> fragmentFunctionDefault;
    BOOL _srgb;
}

- (id)initWithDevice:(id<MTLDevice>)theDevice
{
    self = [super init];
    if( self )
    {
        device = theDevice;
        textureLayerOne = nil;
        textureLayerTwo = nil;
        decodedFrame = nil;
        frameValid = NO;
        id<MTLLibrary> defaultLibrary = [device newDefaultLibrary];
        fragmentFunctionScaledCoCgYToRGBA = [defaultLibrary newFunctionWithName:@"textureToScreenSamplingShader_ScaledCoCgYToRGBA"];
        fragmentFunctionScaledCoCgYPlusAToRGBA = [defaultLibrary newFunctionWithName:@"textureToScreenSamplingShader_ScaledCoCgYPlusAToRGBA"];
        fragmentFunctionDefault = [defaultLibrary newFunctionWithName:@"textureToScreenSamplingShader"];
    }
    return self;
}

- (void)updateIsSrgbForTexturePixelFormat:(MTLPixelFormat)mtlPixelFormat
{
    switch( mtlPixelFormat )
    {
        case MTLPixelFormatBC1_RGBA_sRGB:
            _srgb = YES;
            break;
        case MTLPixelFormatBC3_RGBA:
            _srgb = NO;
            break;
        case MTLPixelFormatBC4_RUnorm:
            _srgb = NO;
            break;
        default:
            NSLog(@"issrgb default case not expected: %lu", mtlPixelFormat);
            _srgb = NO;
    }
}

- (MTLPixelFormat)convertToMetalPixelFormat:(int)hapTextureFormat
{
    /*
     Metal equivalents
     // S3TC/DXT
     BC1_RGBA = 130,
     BC1_RGBA_sRGB = 131,
     BC2_RGBA = 132,
     BC2_RGBA_sRGB = 133,
     BC3_RGBA = 134,
     BC3_RGBA_sRGB = 135,
     
     // RGTC
     BC4_RUnorm = 140,
     BC4_RSnorm = 141,
     BC5_RGUnorm = 142,
     BC5_RGSnorm = 143,
     */
    switch( hapTextureFormat )
    {
        case HapTextureFormat_RGB_DXT1:
            return MTLPixelFormatBC1_RGBA_sRGB;
        case HapTextureFormat_RGBA_DXT5:
            return MTLPixelFormatBC3_RGBA;
        case HapTextureFormat_YCoCg_DXT5:
            return MTLPixelFormatBC3_RGBA;
        case HapTextureFormat_A_RGTC1:
            return MTLPixelFormatBC4_RUnorm;
        default:
            NSLog(@"unhandled case, expect crash soon: %i", hapTextureFormat);
            return MTLPixelFormatBGRA8Unorm;
    }
}

- (void)dealloc
{
    textureLayerOne = nil;
    textureLayerTwo = nil;
    if( decodedFrame != nil )
    {
        [decodedFrame release];
        decodedFrame = nil;
    }
    [super dealloc];
}

- (id<MTLTexture>)createTextureWithFormat:(MTLPixelFormat)format width:(int)width height:(int)height
{
    MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format
                                                                                                 width:width
                                                                                                height:height
                                                                                             mipmapped:NO];
    textureDescriptor.usage = MTLTextureUsageShaderRead;
    textureDescriptor.storageMode = MTLStorageModeManaged;
    const id<MTLTexture> newTexture = [device newTextureWithDescriptor:textureDescriptor];
    return newTexture;
}

- (id<MTLTexture>)textureForIndex:(int)index
{
    if( index==0 )
    {
        return textureLayerOne;
    }
    else if( index==1 )
    {
        return textureLayerTwo;
    }
    else
    {
        return nil;
    }
}

// Must happen inside an initialised commandBuffer
- (void)setDecodedFrame:(HapDecoderFrame *)newFrame onCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    [newFrame retain];
    [decodedFrame release];
    decodedFrame = newFrame;
    frameValid = NO;
    
    if( decodedFrame == NULL )
    {
        NSLog(@"\t\terr: decodedFrame nil, bailing. %s",__func__);
        return;
    }
    
    const NSSize tmpSize = [decodedFrame dxtImgSize];
    const int roundedWidth = tmpSize.width;
    const int roundedHeight = tmpSize.height;
    
    if( roundedWidth % 4 != 0 || roundedHeight % 4 != 0 )
    {
        NSLog(@"\t\terr: width isn't a multiple of 4, bailing. %s",__func__);
        return;
    }
    
    const int textureCount = [decodedFrame dxtPlaneCount];
    OSType *dxtPixelFormats = [decodedFrame dxtPixelFormats];
    MTLPixelFormat newInternalFormat;
    size_t *dxtDataSizes = [decodedFrame dxtDataSizes];
    void **dxtBaseAddresses = [decodedFrame dxtDatas];
    
    for( int texIndex=0; texIndex<textureCount; ++texIndex )
    {
        unsigned int bitsPerPixel = 0;
        switch( dxtPixelFormats[texIndex] )
        {
            case kHapCVPixelFormat_RGB_DXT1:
                newInternalFormat = [self convertToMetalPixelFormat:HapTextureFormat_RGB_DXT1];
                bitsPerPixel = 4;
                break;
            case kHapCVPixelFormat_RGBA_DXT5:
            case kHapCVPixelFormat_YCoCg_DXT5:
                newInternalFormat = [self convertToMetalPixelFormat:HapTextureFormat_RGBA_DXT5];
                bitsPerPixel = 8;
                break;
            case kHapCVPixelFormat_CoCgXY:
                if( texIndex==0 )
                {
                    newInternalFormat = [self convertToMetalPixelFormat:HapTextureFormat_RGBA_DXT5];
                    bitsPerPixel = 8;
                }
                else
                {
                    newInternalFormat = [self convertToMetalPixelFormat:HapTextureFormat_A_RGTC1];
                    bitsPerPixel = 4;
                }
                break;
            case kHapCVPixelFormat_YCoCg_DXT5_A_RGTC1:
                if( texIndex==0 )
                {
                    newInternalFormat = [self convertToMetalPixelFormat:HapTextureFormat_RGBA_DXT5];
                    bitsPerPixel = 8;
                }
                else
                {
                    newInternalFormat = [self convertToMetalPixelFormat:HapTextureFormat_A_RGTC1];
                    bitsPerPixel = 4;
                }
                break;
            case kHapCVPixelFormat_A_RGTC1:
                newInternalFormat = [self convertToMetalPixelFormat:HapTextureFormat_A_RGTC1];
                bitsPerPixel = 4;
                break;
            default:
                // we don't support non-DXT pixel buffers
                NSLog(@"\t\terr: unrecognized pixel format (%X) at index %d in %s",dxtPixelFormats[texIndex],texIndex,__func__);
                FourCCLog(@"\t\tpixel format fourcc is",dxtPixelFormats[texIndex]);
                frameValid = NO;
                return;
                break;
        }
        
        [self updateIsSrgbForTexturePixelFormat:newInternalFormat];
        
        const int bytesPerRow = (roundedWidth * bitsPerPixel) / 8;
        const GLsizei newDataLength = (int)(bytesPerRow * roundedHeight);
        const size_t actualBufferSize = dxtDataSizes[texIndex];
        
        // make sure the buffer's at least as big as necessary
        if( actualBufferSize < newDataLength )
        {
            NSLog(@"\t\terr: new data length incorrect, %d vs %ld in %s",newDataLength,actualBufferSize,__func__);
            frameValid = NO;
            return;
        }
        frameValid = YES;
        
        GLvoid *baseAddress = dxtBaseAddresses[texIndex];
        
        // Lazy texture creation & update
        if( [self textureForIndex:texIndex] == nil ||
           roundedWidth != [self textureForIndex:texIndex].width ||
           roundedHeight != [self textureForIndex:texIndex].height ||
           newInternalFormat != [self textureForIndex:texIndex].pixelFormat )
        {
            id<MTLTexture> newTexture = [self createTextureWithFormat:newInternalFormat width:roundedWidth height:roundedHeight];
            newTexture.label = [NSString stringWithFormat:@"Hap Texture index %i", texIndex];
            if( texIndex==0 )
            {
                textureLayerOne = newTexture;
            }
            else if( texIndex==1 )
            {
                textureLayerTwo = newTexture;
            }
            else
            {
                NSLog(@"ERR: Index should be 1 or 2. Got %i.", texIndex);
                @throw NSInternalInconsistencyException;
            }
        }
        
#warning MTO: this *4 is unexpected, but it works
        const int workingBytesPerRow = bytesPerRow*4;
        MTLRegion region = MTLRegionMake2D(0, 0, roundedWidth, roundedHeight);
        [[self textureForIndex:texIndex] replaceRegion:region mipmapLevel:0 withBytes:baseAddress bytesPerRow:workingBytesPerRow];
    }
}

- (HapDecoderFrame *)decodedFrame
{
    return decodedFrame;
}

- (int)textureCount
{
    return [decodedFrame dxtPlaneCount];
}

- (NSArray<id<MTLTexture>>*)texturesArray
{
    if( textureLayerTwo != nil )
    {
        return @[textureLayerOne, textureLayerTwo];
    }
    else
    {
        return @[textureLayerOne];
    }
}

- (id<MTLFunction>)fragmentForFrame
{
    if( frameValid && decodedFrame!=nil )
    {
        OSType codecSubType = [decodedFrame codecSubType];
        if( codecSubType==kHapYCoCgCodecSubType )
        {
            return fragmentFunctionScaledCoCgYToRGBA;
        }
        else if( codecSubType == kHapYCoCgACodecSubType )
        {
            return fragmentFunctionScaledCoCgYPlusAToRGBA;
        }
        // rgb
        else
        {
            return fragmentFunctionDefault;
        }
    }
    else
    {
        NSLog(@"unexpected invalid frame");
        return fragmentFunctionDefault;
    }
}

@end
