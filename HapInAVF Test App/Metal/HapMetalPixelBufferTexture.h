#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <HapInAVFoundation/HapInAVFoundation.h>
#import <Metal/Metal.h>

/**
 A class to maintain a DXT-compressed texture for upload of DXT frames from CoreVideo pixel-buffers.
 Scaled YCoCg DXT5 requires a shader to convert color values when it is drawn.
 */
@interface HapMetalPixelBufferTexture : NSObject
{
@private
    id<MTLDevice> device;
    id<MTLTexture> textureLayerOne;
    id<MTLTexture> textureLayerTwo;
    HapDecoderFrame *decodedFrame;
    BOOL frameValid;
}

- (id)initWithDevice:(id<MTLDevice>)device;
- (void)setDecodedFrame:(HapDecoderFrame*)newFrame onCommandBuffer:(id<MTLCommandBuffer>)commandBuffer;
- (id<MTLFunction>)fragmentForFrame;

@property (retain, readonly) HapDecoderFrame *decodedFrame;
@property (readonly) int textureCount;
@property (readonly) NSArray<id<MTLTexture>> *texturesArray;
@property (readonly) BOOL srgb;

@end
