#import <Foundation/Foundation.h>
#import <HapInAVFoundation/HapInAVFoundation.h>
#import "MetalImageView.h"

NS_ASSUME_NONNULL_BEGIN

@interface MetalHapDisplayer : NSObject

- (void)displayFrame:(HapDecoderFrame*)dxtFrame inView:(MetalImageView*)metalView;

@end

NS_ASSUME_NONNULL_END
