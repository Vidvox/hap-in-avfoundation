//
//  HapMTKView.h
//  HapInAVF Test App
//
//  Created by testadmin on 6/8/23.
//  Copyright © 2023 Vidvox. All rights reserved.
//

#import <MetalKit/MetalKit.h>
#import "HapMTLPixelBufferTexture.h"
#import <CoreVideo/CoreVideo.h>
#import <MetalKit/MetalKit.h>

NS_ASSUME_NONNULL_BEGIN




@interface HapMTKView : MTKView

- (id<MTLCommandBuffer>) commandBuffer;

- (void) displayPixelBufferTexture:(HapMTLPixelBufferTexture *)n flipped:(BOOL)inFlipped;
- (void) displayCVMetalTextureRef:(CVMetalTextureRef)n flipped:(BOOL)inFlipped;

@end




NS_ASSUME_NONNULL_END
