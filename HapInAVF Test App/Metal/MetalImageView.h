#import <Cocoa/Cocoa.h>
#import <MetalKit/MTKView.h>

@interface MetalImageView : MTKView

@property (readwrite, assign) id<MTLTexture> image;
// Returns the dimensions the view will render at, including any adjustment for a high-resolution display
@property (readonly, nonatomic) NSSize renderSize;
@property (readwrite, nonatomic) BOOL srgb;
@property (readwrite, nonatomic) BOOL needsReshape;
@property (readwrite, nonatomic) BOOL flip;

// Uses a blit of the image provided
- (void)setUnsafeImage:(id<MTLTexture>)unsafeImage;

@end
