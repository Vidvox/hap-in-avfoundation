//
//  VVAVFTranscodeTrack.h
//  VVAVFTranscodeTestApp
//
//  Created by testadmin on 2/8/24.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN




@interface VVAVFTranscodeTrack : NSObject

+ (instancetype) create;

- (instancetype) init;

@property (strong) dispatch_queue_t queue;

@property (strong) AVAssetTrack * track;

@property (strong) AVAssetReaderOutput * output;

@property (strong) AVAssetWriterInput * input;

@property (strong) NSString * mediaType;	//	AVMediaType
@property (readwrite) NSUInteger passIndex;
@property (readwrite) NSInteger skippedBufferCount;
@property (readwrite) NSInteger processedBufferCount;
@property (readwrite) BOOL audioFirstSampleFlag;
@property (readwrite) BOOL timecodeFirstSampleFlag;
@property (readwrite) BOOL finished;

@end




NS_ASSUME_NONNULL_END
