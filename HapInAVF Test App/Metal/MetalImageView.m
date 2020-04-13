#import "MetalImageView.h"
#import "TextureRenderer.h"


@implementation MetalImageView
{
    id<MTLTexture> _image;
    BOOL _needsReshape;
    BOOL _srgb;
    BOOL _flip;
    TextureRenderer *textureRenderer;
    id<MTLCommandQueue> commandQueue;
    id<MTLTexture> threadSafeImage;
}

- (void)awakeFromNib
{
    self.device = MTLCreateSystemDefaultDevice();
    [self initRenderingRessources];
    commandQueue = [self.device newCommandQueue];
    self.flip = NO;
}

- (void)initRenderingRessources
{
    self.colorPixelFormat = self.srgb ? MTLPixelFormatBGRA8Unorm_sRGB : MTLPixelFormatBGRA8Unorm;
    textureRenderer = [[TextureRenderer alloc] initWithDevice:self.device colorPixelFormat:self.colorPixelFormat];
    textureRenderer.flip = self.flip;
    textureRenderer.clearColor = MTLClearColorMake(1, 0, 0, 1);
}

- (void)dealloc
{
    _image = nil;
    [super dealloc];
}

// Disable internal timer clock with these two methods
- (BOOL)enableSetNeedsDisplay
{
    return YES;
}
- (BOOL)isPaused
{
    return YES;
}

- (NSSize)renderSize
{
    if( [NSView instancesRespondToSelector:@selector(convertRectToBacking:)] )
    {
        // 10.7+
        return [self convertSizeToBacking:[self bounds].size];
    }
    else return [self bounds].size;
}

- (MTLViewport)viewportForFrameWidth:(int)frameWidth frameHeight:(int)frameHeight viewWidth:(int)viewWidth viewHeight:(int)viewHeight
{
    const float frameRatio = (float)frameWidth / (float)frameHeight;
    const float viewportRatio = (float)viewWidth / (float)viewHeight;
    
    // If view ratio bigger = wider = black bars on left/right = maximum height and centered width
    if( frameRatio < viewportRatio )
    {
        const int allowedWidthForRatio = frameRatio * viewHeight;
        const float freeWidthSpace = (viewWidth - allowedWidthForRatio)/2.0;
        NSScreen		*thisScreen = [[self window] screen];
        NSRect			tmpRect = NSMakeRect(freeWidthSpace, 0.0, viewWidth-(2.0*freeWidthSpace), viewHeight);
        tmpRect = [thisScreen convertRectToBacking:tmpRect];
        MTLViewport		returnMe = { tmpRect.origin.x, tmpRect.origin.y, tmpRect.size.width, tmpRect.size.height, -1.0, 1.0 };
        return returnMe;
    }
    // if view ratio smaller = taller = black bars on top/bottom = maximum width and centered height
    else if ( viewportRatio < frameRatio )
    {
        const float allowedHeightForRatio = viewWidth / frameRatio;
        const float freeHeightSpace = (viewHeight - allowedHeightForRatio)/2.0;
        NSScreen		*thisScreen = [[self window] screen];
        NSRect			tmpRect = NSMakeRect(0.0, freeHeightSpace, viewWidth, viewHeight-(2.0*freeHeightSpace));
        tmpRect = [thisScreen convertRectToBacking:tmpRect];
        MTLViewport		returnMe = { tmpRect.origin.x, tmpRect.origin.y, tmpRect.size.width, tmpRect.size.height, -1.0, 1.0 };
        return returnMe;
    }
    // perfect equality
    else
    {
        return (MTLViewport) {0.0, 0.0, viewWidth*2, viewHeight*2, -1.0, 1.0 };
    }
}

- (void)drawRect:(NSRect)dirtyRect
{
    @autoreleasepool
    {
        if( !self.currentDrawable.texture )
        {
            NSLog(@"WARN: current drawable is not available. skip frame render.");
            return;
        }
        
        // If there's a valid render pass descriptor, use it to render to the current drawable.
        if( _image != nil )
        {
            const id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
            const MTLViewport viewport = [self viewportForFrameWidth:(int)_image.width frameHeight:(int)_image.height viewWidth:self.bounds.size.width viewHeight:self.bounds.size.height];
            [textureRenderer renderFromTexture:_image inTexture:self.currentDrawable.texture onCommandBuffer:commandBuffer andViewport:viewport];
            // Register the drawable's presentation.
            [commandBuffer presentDrawable:self.currentDrawable];
            // Finalize your onscreen CPU work and commit the command buffer to a GPU.
            [commandBuffer commit];
            [commandBuffer waitUntilCompleted];
        }
    }
}

- (void)setUnsafeImage:(id<MTLTexture>)unsafeImage
{
    // A thread safe texture is lazy initialized and re-used, making the assumption that if won't change often
    // Note: this optimisation won't work properly if multiple actors tries to use it in different render loops
    if( threadSafeImage == nil || threadSafeImage.pixelFormat != unsafeImage.pixelFormat || threadSafeImage.width != unsafeImage.width || threadSafeImage.height != unsafeImage.height )
    {
        NSLog(@"lazy thread safe image init");
        MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:unsafeImage.pixelFormat
                                                                                                     width:unsafeImage.width
                                                                                                    height:unsafeImage.height
                                                                                                 mipmapped:NO];
        textureDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        textureDescriptor.storageMode = MTLStorageModePrivate; // GPU only for better performance
        threadSafeImage = [self.device newTextureWithDescriptor:textureDescriptor];
    }
    
    const id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    const id<MTLBlitCommandEncoder> blitCommandEncoder = [commandBuffer blitCommandEncoder];
    blitCommandEncoder.label = @"MetalImageView setUnsafeImage Blit Command Encoder";
    [blitCommandEncoder copyFromTexture:unsafeImage sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(unsafeImage.width, unsafeImage.height, 1) toTexture:threadSafeImage destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0, 0, 0)];
    [blitCommandEncoder endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];
    self.image = threadSafeImage;
}


- (void)setSrgb:(BOOL)srgb
{
    _srgb = srgb;
#warning MTO: workaround to keep KVO in main thread
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self willChangeValueForKey:@"srgb"];
        [self didChangeValueForKey:@"srgb"];
    }];
    [self initRenderingRessources];
}

- (BOOL)srgb
{
    return _srgb;
}

- (void)setFlip:(BOOL)flip
{
    _flip = flip;
#warning MTO: workaround to keep KVO in main thread
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self willChangeValueForKey:@"flip"];
        [self didChangeValueForKey:@"flip"];
    }];
    textureRenderer.flip = flip;
}

- (BOOL)flip
{
    return _flip;
}

@end
