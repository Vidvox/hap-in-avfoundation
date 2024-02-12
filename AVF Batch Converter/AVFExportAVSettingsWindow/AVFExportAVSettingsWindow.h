//
//  AVFExportAVSettingsWindow.h
//  VVAVFExport-TestApp
//
//  Created by testadmin on 5/4/22.
//

#import <Cocoa/Cocoa.h>

#import "AVFExportSettingsAudioVC.h"
#import "AVFExportSettingsVideoVC.h"

NS_ASSUME_NONNULL_BEGIN




//	keys that can appear in any (audio/video) settings dict
extern NSString * const		kAVFExportStripMediaKey;	//	indicates that the media of this type should be stripped, if present

//	keys that can appear ONLY in VIDEO settings dicts
extern NSString * const		kAVFExportMultiPassEncodeKey;	//	indicates that the codec (h.264) should use multi-pass encoding
extern NSString * const		kAVFExportVideoResolutionKey;	//	get/set an NSSize-as-NSValue at this key that describes the resolution of the video being encoded.  used to populate the UI with default values.

//	keys that can appear ONLY in AUDIO settings dicts
extern NSString * const		kAVFExportAudioSampleRateKey;	//	describes the sample rate of the audio being encoded.  used to populate the UI with default values.




/*		window controller- provides a GUI that users interact with to produce dictionaries populated with 
		settings for AVFoundation export.
		
		class method opens the window- pass dicts to populate UI with an initial state.  when user finishes 
		interacting with the UI, the block will be executed and passed a return code (did user cancel?), as 
		well as separate dicts that describe audio + video settings
*/




@interface AVFExportAVSettingsWindow : NSWindowController

//	the completion handler's args are (NSModalResponse) return code, (NSString*) lengthy description, (NSDictionary*) audio settings, (NSDictionary*) video settings
+ (void) openModalForWindow:(NSWindow *)inParentWin audioSettings:(NSDictionary *)inAudioDict videoSettings:(NSDictionary *)inVideoDict completionHandler:(void (^)(NSModalResponse, NSString*, NSDictionary*, NSDictionary*))inCH;

+ (instancetype) createWithAudioSettings:(NSDictionary *)inAudioDict videoSettings:(NSDictionary *)inVideoDict;

@property (strong,readonly) AVFExportSettingsAudioVC * audioVC;
@property (strong,readonly) AVFExportSettingsVideoVC * videoVC;

@end




NS_ASSUME_NONNULL_END
