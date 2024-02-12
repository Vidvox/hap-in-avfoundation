//
//  HapMetalDXTDecoder.h
//  HapInAVFoundation
//
//  Created by testadmin on 2/16/24.
//  Copyright © 2024 Vidvox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN




@interface HapMetalDXTDecoder : NSObject

+ (instancetype) createWithDevice:(id<MTLDevice>)n;
- (instancetype) initWithDevice:(id<MTLDevice>)n;

- (void) decodeTexture:(id<MTLTexture>)srcTex toBuffer:(id<MTLBuffer>)dstBuffer bufferImageSize:(NSSize)inDstSize bufferBytesPerRow:(uint32_t)inDstBytesPerRow bufferPixelFormat:(MTLPixelFormat)inDstPixelFormat inCommandBuffer:(id<MTLCommandBuffer>)cb;

@end




NS_ASSUME_NONNULL_END
