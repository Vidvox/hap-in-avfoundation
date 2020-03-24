#import "MetalHapDisplayer.h"
#import "TextureRenderer.h"
#import "HapMetalPixelBufferTexture.h"

@implementation MetalHapDisplayer
{
    HapMetalPixelBufferTexture *pixelBufferTexture;
    TextureRenderer *textureRenderer;
    MTLPixelFormat pixelFormat;
    id<MTLCommandQueue> commandQueue;
    id<MTLDevice> device;
    id<MTLTexture> visualisationTexture;
}

- (void)displayFrame:(HapDecoderFrame*)dxtFrame inView:(MetalImageView*)view
{
    // Lazy Inits & updates
    NSSize frameSize = [dxtFrame imgSize];
    if( device != view.device || commandQueue == nil || pixelBufferTexture == nil )
    {
        NSLog(@"lazy init steady ressources");
        device = view.device;
        commandQueue = [device newCommandQueue];
        pixelBufferTexture = [[HapMetalPixelBufferTexture alloc] initWithDevice:device];
        pixelFormat = view.colorPixelFormat;
    }
    
    
    /// RENDER
    const id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    commandBuffer.label = @"Metal Decode HAP Command Buffer";
    [pixelBufferTexture setDecodedFrame:dxtFrame onCommandBuffer:commandBuffer];
    
    const id<MTLFunction> fragmentForFrame = [pixelBufferTexture fragmentForFrame];
    // last minute textureRenderer lazy init
    if( view.srgb != pixelBufferTexture.srgb )
    {
        view.srgb = pixelBufferTexture.srgb;
        visualisationTexture = [self createTextureForDevice:device width:frameSize.width height:frameSize.height pixelFormat:pixelFormat];
    }
    
    const int numberOfTexturesInFrame = pixelBufferTexture.textureCount;
    
    if( visualisationTexture == nil || frameSize.width != visualisationTexture.width || frameSize.height != frameSize.height )
    {
        NSLog(@"lazy init visualisation texture (volatile)");
        visualisationTexture = [self createTextureForDevice:device width:frameSize.width height:frameSize.height pixelFormat:pixelFormat];
    }
    if( textureRenderer == nil || textureRenderer.fragment != fragmentForFrame )
    {
        NSLog(@"lazy init textureRenderer (volatile)");
        textureRenderer = [[TextureRenderer alloc] initWithDevice:device colorPixelFormat:pixelFormat customFragment:fragmentForFrame numberOfExtraColorAttachments:numberOfTexturesInFrame-1];
    }
    
    const id<MTLTexture> textureToRender = [pixelBufferTexture.texturesArray objectAtIndex:0];
    if( numberOfTexturesInFrame == 1 )
    {
        [textureRenderer renderFromTexture:textureToRender inTexture:visualisationTexture onCommandBuffer:commandBuffer];
    }
    else if( numberOfTexturesInFrame == 2 )
    {
        [textureRenderer renderFromTexture:textureToRender extraColorAttachements:@[[pixelBufferTexture.texturesArray objectAtIndex:1]] inTexture:visualisationTexture onCommandBuffer:commandBuffer];
    }
    else
    {
        NSLog(@"this is unexpected");
        return;
    }
    
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull _)
     {
         view.image = visualisationTexture;
         [[NSOperationQueue mainQueue] addOperationWithBlock:^{
             [view setNeedsDisplay:YES];
         }];
     }];
    [commandBuffer commit];
}

#pragma mark Pure utils

- (id<MTLTexture>)createTextureForDevice:(id<MTLDevice>)theDevice width:(int)width height:(int)height pixelFormat:(MTLPixelFormat)thePixelFormat
{
    MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:thePixelFormat
                                                                                                 width:width
                                                                                                height:height
                                                                                             mipmapped:NO];
    textureDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    textureDescriptor.storageMode = MTLStorageModePrivate; // GPU only for better performance
    id<MTLTexture> texture = [theDevice newTextureWithDescriptor:textureDescriptor];
    return texture;
}

@end
