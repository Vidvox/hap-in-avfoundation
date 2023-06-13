//
//  HapMTLPixelBufferTexture.h
//  HapInAVF Test App
//
//  Created by testadmin on 6/8/23.
//  Copyright © 2023 Vidvox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <HapInAVFoundation/HapInAVFoundation.h>

NS_ASSUME_NONNULL_BEGIN




/*		- data storage class that handles creation of id<MTLTextures> used for hap decoding
		- intended to be cached/kept around locally per-playback-source
		- stores textures that are populated from a HapDecoderFrame instance
			- will create textures from scratch if existing textures are nil, the wrong format, or the wrong size
			- you should probably cache this object to cache the textures associated with it
			- textures are populated via 'populateWithHapDecoderFrame:inCommandBuffer:'
			- use -[MTLRenderCommandEncoder useResource:usage:stages:] to ensure that the textures are flagged for use by your encoder and that their contents will be updated when your shader executes!
*/




@interface HapMTLPixelBufferTexture : NSObject

+ (instancetype) createWithDevice:(id<MTLDevice>)inDevice;

+ (MTLPixelFormat) pixelFormatForHapTextureFormat:(enum HapTextureFormat)n;

- (instancetype) initWithDevice:(id<MTLDevice>)inDevice;

//	cmd buffer is optional.  if you pass a cmd buffer, this method creates a blit encoder that it uses to synchronize the texture's CPU/GPU resources.
- (void) populateWithHapDecoderFrame:(HapDecoderFrame *)n inCommandBuffer:(__nullable id<MTLCommandBuffer>)inCB;

@property (strong,readonly) id<MTLDevice> device;
@property (strong,readonly) id<MTLTexture> textureA;	//	managed resource, must explicitly sycnchronize
@property (strong,readonly) id<MTLTexture> textureB;	//	managed resource, must explicitly sycnchronize

@property (weak,readonly) HapDecoderFrame * frame;	//	we store a weak ref to the frame here, so outside objects can check to see if they need to allocate a new frame or not

@property (assign,readonly) OSType codecSubType;	//	like 'kHapCodecSubType', etc- interpret this value to determine how many textures receiver has & what kind of textures they are
@property (assign,readonly) CGSize dxtImgSize;	//	the size of the textures- rounded up to the nearest multiple of
@property (assign,readonly) CGSize imgSize;	//	the size of the image (which may be < the size of the texture)

@end




NS_ASSUME_NONNULL_END
