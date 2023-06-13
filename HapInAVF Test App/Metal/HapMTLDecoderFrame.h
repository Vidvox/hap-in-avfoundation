//
//  HapMTLDecoderFrame.h
//  HapInAVF Test App
//
//  Created by testadmin on 6/8/23.
//  Copyright © 2023 Vidvox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <HapInAVFoundation/HapInAVFoundation.h>

NS_ASSUME_NONNULL_BEGIN




@interface HapMTLDecoderFrame : HapDecoderFrame

- (instancetype) initWithDevice:(id<MTLDevice>)d hapSampleBuffer:(CMSampleBufferRef)sb;

- (instancetype) initWithHapSampleBuffer:(CMSampleBufferRef)sb __attribute__((unavailable("Use -[HapMTLDecoderFrame initWithDevice:hapSampleBuffer:] instead")));

- (instancetype) initEmptyWithHapSampleBuffer:(CMSampleBufferRef)sb __attribute__((unavailable("Use -[HapMTLDecoderFrame initWithHapSampleBuffer] instead")));

@end




NS_ASSUME_NONNULL_END
