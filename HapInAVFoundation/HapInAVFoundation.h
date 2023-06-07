#import <Cocoa/Cocoa.h>

#import <CoreMedia/CoreMedia.h>
#import <AVFoundation/AVFoundation.h>

#include <HapInAVFoundation/HapPlatform.h>




/*			if you're reading this, these are the headers that you're probably going to want to look at			*/

#include <HapInAVFoundation/PixelFormats.h>
#include <HapInAVFoundation/HapCodecSubTypes.h>

#import <HapInAVFoundation/CMBlockBufferPool.h>

#import <HapInAVFoundation/AVPlayerItemHapDXTOutput.h>
#import <HapInAVFoundation/AVAssetReaderHapTrackOutput.h>
#import <HapInAVFoundation/HapDecoderFrame.h>
#import <HapInAVFoundation/AVPlayerItemAdditions.h>
#import <HapInAVFoundation/AVAssetAdditions.h>

#import <HapInAVFoundation/AVAssetWriterHapInput.h>





#if defined(__APPLE__)
#define HAP_GPU_DECODE
#else
#define HAP_SQUISH_DECODE
#endif

#ifndef HAP_GPU_DECODE
    #ifndef HAP_SQUISH_DECODE
        #error Neither HAP_GPU_DECODE nor HAP_SQUISH_DECODE is defined. #define one or both.
    #endif
#endif







