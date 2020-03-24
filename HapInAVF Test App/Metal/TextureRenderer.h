#import <Foundation/Foundation.h>

@import Metal;

@interface TextureRenderer : NSObject

- (instancetype)initWithDevice:(id<MTLDevice>)device colorPixelFormat:(MTLPixelFormat)colorPixelFormat;
- (instancetype)initWithDevice:(id<MTLDevice>)device colorPixelFormat:(MTLPixelFormat)colorPixelFormat customFragment:(id<MTLFunction>)customFragment numberOfExtraColorAttachments:(int)numberOfExtraColorAttachments;

- (void)renderFromTexture:(id<MTLTexture>)offScreenTexture inTexture:(id<MTLTexture>)texture onCommandBuffer:(id<MTLCommandBuffer>)commandBuffer;
- (void)renderFromTexture:(id<MTLTexture>)offScreenTexture inTexture:(id<MTLTexture>)texture onCommandBuffer:(id<MTLCommandBuffer>)commandBuffer andViewport:(MTLViewport)viewport;
- (void)renderFromTexture:(id<MTLTexture>)offScreenTexture extraColorAttachements:(NSArray<id<MTLTexture>>*)extraTextures inTexture:(id<MTLTexture>)texture onCommandBuffer:(id<MTLCommandBuffer>)commandBuffer;

@property (readwrite) bool flip;
@property (readonly) id<MTLFunction> fragment;
@property (readwrite, nonatomic) MTLClearColor clearColor;

@end

