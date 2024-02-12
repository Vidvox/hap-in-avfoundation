//
//  VVAVFTranscoder.h
//  VVAVFTranscodeTestApp
//
//  Created by testadmin on 2/8/24.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@class VVAVFTranscoder;

NS_ASSUME_NONNULL_BEGIN




typedef void (^VVAVFTranscoderCompleteHandler)(VVAVFTranscoder*);

typedef NS_ENUM(NSUInteger, VVAVFTranscoderStatus)	{
	VVAVFTranscoderStatus_Paused = 0,
	VVAVFTranscoderStatus_Processing,
	VVAVFTranscoderStatus_Complete,
	VVAVFTranscoderStatus_Cancelled,
	VVAVFTranscoderStatus_Error
};


//	keys that can appear in any (audio/video) settings dict
extern NSString * const		kVVAVFTranscodeStripMediaKey;	//	indicates that the media of this type should be stripped, if present

//	keys that can appear ONLY in VIDEO settings dicts
extern NSString * const		kVVAVFTranscodeMultiPassEncodeKey;	//	indicates that the codec (h.264) should use multi-pass encoding
extern NSString * const		kVVAVFTranscodeVideoResolutionKey;	//	get/set an NSSize-as-NSValue at this key that describes the resolution of the video being encoded.  used to populate the UI with default values.

//	keys that can appear ONLY in AUDIO settings dicts
//extern NSString * const		kAVFExportAudioSampleRateKey;	//	describes the sample rate of the audio being encoded.  used to populate the UI with default values.




/*		This is the main class that "does the transcoding"
		
		- It creates and retains instances that need to persist for the duration of the transcoding job, and 
		values that are convenient to calculate once and refer to multiple times.
		- It sets up the transcode (as a series of asynchronous tasks) and manages it (responds to errors, 
		which it exposes as an error variable, and informs its delegate when the job has ended)
		- It's meant to be a throwaway class- you make a job for a given file with a given set of settings, 
		and when the job is complete you release it (instead of reconfiguring it to run with another file).
		
		NOTES:
		
		- on init, creates queues, the reader/writer, and all of the reader outputs/writer inputs necessary- 
		so don't create a job until you're ready to run it!
*/




@interface VVAVFTranscoder : NSObject

+ (instancetype) createWithSrc:(NSURL *)inSrc dst:(NSURL *)inDst audioSettings:(NSDictionary * __nullable)inAudioSettings videoSettings:(NSDictionary * __nullable)inVideoSettings completionHandler:(VVAVFTranscoderCompleteHandler)ch;

- (instancetype) initWithSrc:(NSURL *)inSrc dst:(NSURL *)inDst audioSettings:(NSDictionary * __nullable)inAudioSettings videoSettings:(NSDictionary * __nullable)inVideoSettings completionHandler:(VVAVFTranscoderCompleteHandler)ch;

@property (strong,readonly) NSURL * src;
@property (strong,readonly) NSURL * dst;
@property (strong,readonly) NSDictionary * audioSettings;
@property (strong,readonly) NSDictionary * videoSettings;

@property (readonly,atomic) VVAVFTranscoderStatus status;

@property (strong,readonly) AVAsset * asset;

@property (readonly,atomic) double normalizedProgress;

@property (strong,readonly) NSError * error;

@property (readwrite,atomic) BOOL paused;

- (void) cancel;

@end




NS_ASSUME_NONNULL_END
