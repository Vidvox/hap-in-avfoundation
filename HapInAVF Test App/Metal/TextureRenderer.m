#import "TextureRenderer.h"
#import "MetalShaderTypes.h"

@implementation TextureRenderer
{
    vector_uint2 _viewportSize;
    id<MTLRenderPipelineState> pipeline;
    int numberOfExtraColorAttachements;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device colorPixelFormat:(MTLPixelFormat)colorPixelFormat
{
    id<MTLLibrary> defaultLibrary = [device newDefaultLibrary];
    return [self initWithDevice:device colorPixelFormat:colorPixelFormat
                 customFragment:[defaultLibrary newFunctionWithName:@"textureToScreenSamplingShader"]
  numberOfExtraColorAttachments:0];
}

- (instancetype)initWithDevice:(id<MTLDevice>)device colorPixelFormat:(MTLPixelFormat)colorPixelFormat customFragment:(id<MTLFunction>)customFragment numberOfExtraColorAttachments:(int)theNumberOfExtraColorAttachments
{
    self = [super init];
    if( self )
    {
        numberOfExtraColorAttachements = theNumberOfExtraColorAttachments;
        NSError *error = NULL;
        id<MTLLibrary> defaultLibrary = [device newDefaultLibrary];
        
        // Load the vertex/fragment functions from the library
        id <MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"textureToScreenVertexShader"];
        [self willChangeValueForKey:@"fragment"];
        _fragment = customFragment;
        [self didChangeValueForKey:@"fragment"];
        
        // Set up a descriptor for creating a pipeline state object
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.label = @"Texture Renderer Pipeline State Descriptor";
        pipelineStateDescriptor.vertexFunction = vertexFunction;
        pipelineStateDescriptor.fragmentFunction = self.fragment;
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat;
        
        // HAP Blending
        /// (1-videoRGB)*BackRGB + (1)*VideoRGB
        /// (1-videoAlphaAlpha) BackAlpha + (1)*videoAlpha
        pipelineStateDescriptor.colorAttachments[0].blendingEnabled             = YES;
        pipelineStateDescriptor.colorAttachments[0].rgbBlendOperation           = MTLBlendOperationAdd;
        pipelineStateDescriptor.colorAttachments[0].alphaBlendOperation         = MTLBlendOperationAdd;
        
        // Video is here
        pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor        = MTLBlendFactorOne;
        pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor      = MTLBlendFactorOne;
        // Clear color is here
        pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor   = MTLBlendFactorOneMinusSourceAlpha;
        pipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        
        pipeline = [device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        
        if( !pipeline )
        {
            NSLog(@"Failed to created pipeline state, error %@", error);
            return nil;
        }
        
        self.flip = NO;
        self.clearColor = MTLClearColorMake(0, 0, 0, 0);
    }
    return self;
}

- (void)renderFromTexture:(id<MTLTexture>)offScreenTexture inTexture:(id<MTLTexture>)texture onCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    const MTLViewport viewport = (MTLViewport){0.0, 0.0, offScreenTexture.width, offScreenTexture.height, -1.0, 1.0 };
    [self renderFromTexture:offScreenTexture extraColorAttachements:@[] inTexture:texture onCommandBuffer:commandBuffer andViewPort:viewport];
}

- (void)renderFromTexture:(id<MTLTexture>)offScreenTexture inTexture:(id<MTLTexture>)texture onCommandBuffer:(id<MTLCommandBuffer>)commandBuffer andViewport:(MTLViewport)viewport
{
    [self renderFromTexture:offScreenTexture extraColorAttachements:@[] inTexture:texture onCommandBuffer:commandBuffer andViewPort:viewport];
}

- (void)renderFromTexture:(id<MTLTexture>)offScreenTexture extraColorAttachements:(NSArray<id<MTLTexture>>*)extraTextures inTexture:(id<MTLTexture>)texture onCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    const MTLViewport viewport = (MTLViewport){0.0, 0.0, offScreenTexture.width, offScreenTexture.height, -1.0, 1.0 };
    [self renderFromTexture:offScreenTexture extraColorAttachements:extraTextures inTexture:texture onCommandBuffer:commandBuffer andViewPort:viewport];
}

- (void)renderFromTexture:(id<MTLTexture>)offScreenTexture extraColorAttachements:(NSArray<id<MTLTexture>>*)extraTextures inTexture:(id<MTLTexture>)texture onCommandBuffer:(id<MTLCommandBuffer>)commandBuffer andViewPort:(MTLViewport)viewport
{
    if( extraTextures.count != numberOfExtraColorAttachements )
    {
        NSLog(@"Render aborted. Extra textures received:(%lu) should be:(%i)", extraTextures.count, numberOfExtraColorAttachements);
        return;
    }
    if( offScreenTexture == nil )
    {
        NSLog(@"Render aborted. offscreen texture is nil");
        return;
    }
    if( texture == nil )
    {
        NSLog(@"Render aborted. output texture is nil");
        return;
    }
    
    _viewportSize.x = viewport.width;
    _viewportSize.y = viewport.height;
    
    const float w = viewport.width/2;
    const float h = viewport.height/2;
    const float flipValue = self.flip ? -1 : 1;
    
    const AAPLTextureVertex quadVertices[] =
    {
        // Pixel positions, Texture coordinates
        { {  w,   flipValue * h },  { 1.f, 1.f } },
        { { -w,   flipValue * h },  { 0.f, 1.f } },
        { { -w,  flipValue * -h },  { 0.f, 0.f } },
        
        { {  w,  flipValue * h },  { 1.f, 1.f } },
        { { -w,  flipValue * -h },  { 0.f, 0.f } },
        { {  w,  flipValue * -h },  { 1.f, 0.f } },
    };
    
    const NSUInteger numberOfVertices =  sizeof(quadVertices) / sizeof(AAPLTextureVertex);
    MTLRenderPassDescriptor *renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    renderPassDescriptor.colorAttachments[0].texture = texture;
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionDontCare;
    renderPassDescriptor.colorAttachments[0].clearColor = self.clearColor;
    
    
    // Create a render command encoder so we can render into something
    id <MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    renderEncoder.label = @"Texture Renderer Render Encoder";
    [renderEncoder setViewport:viewport];
    [renderEncoder setRenderPipelineState:pipeline];
    [renderEncoder setVertexBytes:quadVertices length:sizeof(quadVertices) atIndex:AAPLVertexInputIndexVertices];
    [renderEncoder setVertexBytes:&_viewportSize length:sizeof(_viewportSize)atIndex:AAPLVertexInputIndexViewportSize];
    [renderEncoder setFragmentTexture:offScreenTexture atIndex:AAPLTextureIndexZero];
    
    // Insert extra color attachements
    [extraTextures
     enumerateObjectsUsingBlock:
     ^(id<MTLTexture> extraTexture, NSUInteger index, BOOL *stop)
     {
#warning MTO: assumption that AAPLTextureIndex enum values & index values are equal
         [renderEncoder setFragmentTexture:extraTexture atIndex:index+1];
     }];
    
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:numberOfVertices];
    [renderEncoder endEncoding];
}

@end
