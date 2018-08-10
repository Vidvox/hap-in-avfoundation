#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <pthread.h>
#import <HapInAVFoundation/HapInAVFoundation.h>
#import "VVAVFExportBasicSettingsCtrlr.h"




@protocol VVAVFTranscoderDelegate
- (void) finishedTranscoding:(id)finished;
@end




@interface VVAVFTranscoder : NSObject	{
	pthread_mutex_t			theLock;
	BOOL					paused;
	AVAsset					*srcAsset;
	AVAssetReader			*reader;
	NSMutableArray			*readerOutputs;
	dispatch_queue_t		writerQueue;
	AVAssetWriter			*writer;
	NSMutableArray			*writerInputs;
	NSDictionary			*videoExportSettings;
	NSDictionary			*audioExportSettings;
	
	double					durationInSeconds;	//	duration of the asset being transcoded, in seconds.  used to calculate progress.
	double					normalizedProgress;
	BOOL					unexpectedErr;
	
	id<VVAVFTranscoderDelegate>		delegate;	//	NOT retained
	
	NSString				*srcPath;
	NSString				*dstPath;
	NSString				*errorString;
}

- (void) transcodeFileAtPath:(NSString *)src toPath:(NSString *)dst;
- (void) setPaused:(BOOL)p;
- (void) cancel;

- (void) setVideoExportSettings:(NSDictionary *)n;
- (void) setAudioExportSettings:(NSDictionary *)n;

//	this is an ESTIMATE, and if AVFoundation decides to process the tracks serially (instead of concurrently) this may go from 0-1 a couple times.  use the delegate method for callbacks when transcoding has finished.
- (double) normalizedProgress;

@property (assign,readwrite) id<VVAVFTranscoderDelegate> delegate;
@property (readonly) NSString *srcPath;
@property (readonly) NSString *dstPath;
@property (readonly) NSString *errorString;

@end








OSType VVPackFourCC_fromChar(char *charPtr);
