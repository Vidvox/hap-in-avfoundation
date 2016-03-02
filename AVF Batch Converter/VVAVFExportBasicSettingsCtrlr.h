#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreAudio/CoreAudio.h>
#import <HapInAVFoundation/HapInAVFoundation.h>




extern NSString *const		VVAVStripMediaKey;
extern NSString *const		VVAVVideoMultiPassEncodeKey;




@interface NSTabView (NSTabViewAdditions)
- (NSInteger) selectedTabViewItemIndex;
@end

@interface NSPopUpButton (NSPopUpButtonAdditions)
- (BOOL) selectItemWithRepresentedObject:(id)n;
@end




@interface VVAVFExportBasicSettingsCtrlr : NSObject	{
	IBOutlet NSView				*settingsView;	//	the NSView that contains all the settings
	
	IBOutlet NSTabView			*vidCategoryTabView;	//	tab view hosting a toggle for selecting whether or not video should be transcoded.  contains everything else video-related.
	IBOutlet NSMatrix			*vidNoTranscodeMatrix;
	IBOutlet NSPopUpButton		*vidCodecPUB;	//	pop-up button for selecting destination video codec
	IBOutlet NSTabView			*vidCodecTabView;	//	tab view, each tab has options for a different video codec
	IBOutlet NSSlider			*pjpegQualitySlider;	//	general-use quality slider in the pjpeg tab of 'vidCodecTabView'
	IBOutlet NSPopUpButton		*h264ProfilesPUB;	//	pop-up button with h.264 profiles in 'vidCodecTabView'
	IBOutlet NSMatrix			*h264KeyframesMatrix;
	IBOutlet NSTextField		*h264KeyframesField;
	IBOutlet NSMatrix			*h264BitrateMatrix;
	IBOutlet NSTextField		*h264BitrateField;
	IBOutlet NSButton			*h264MultiPassButton;
	IBOutlet NSMatrix			*hapQChunkMatrix;
	IBOutlet NSTextField		*hapQChunkField;
	IBOutlet NSTabView			*vidDimsTabView;	//	tab view hosting a toggle for selecting whether or not video should be resized
	IBOutlet NSTextField		*vidWidthField;	//	text field in 'vidDimsTabView', destination width
	IBOutlet NSTextField		*vidHeightField;	//	text field in 'vidDimsTabView', destination height
	
	IBOutlet NSTabView			*audioCategoryTabView;	//	tab view hosting a toggle for selecting whether or not audio should be transcoded
	IBOutlet NSMatrix			*audioNoTranscodeMatrix;
	IBOutlet NSPopUpButton		*audioCodecPUB;	//	representedItem is NSNumber of the OSType with the audio format value (basically a FourCC)
	IBOutlet NSTabView			*audioCodecTabView;	//	tabs contains settings for audio formats
	IBOutlet NSPopUpButton		*pcmBitsPUB;	//	item title is string of integer value
	IBOutlet NSButton			*pcmLittleEndianButton;
	IBOutlet NSButton			*pcmFloatingPointButton;
	IBOutlet NSPopUpButton		*aacBitrateStrategyPUB;	//	item representedObject is a "VAudioBitRateStrategy_*" constant suitable for adding to settings dict
	IBOutlet NSPopUpButton		*aacBitratePUB;	//	item representedObject is NSNumber with actual bitrate suitable for simply adding to a dict
	IBOutlet NSPopUpButton		*losslessBitDepthPUB;	//	item representedObject is NSNumber with actual bit depth sutiable for adding to settings dict
	
	IBOutlet NSTabView			*audioResampleTabView;
	IBOutlet NSPopUpButton		*audioResamplePUB;	//	item title is string or double value, multiple by 1000 and then convert to integer to get sample rate value
	IBOutlet NSTextField		*audioResampleField;
	
	NSSize				displayVideoDims;
	NSUInteger			displayAudioResampleRate;
	BOOL				canPerformMultiplePasses;
	
	//	this class has its own .nib which contains a UI for interacting with the class that may be opened directly in a window, or accessed as an NSView instance for use in other UIs/software
	NSNib				*theNib;
	NSArray				*nibTopLevelObjects;
}

//	creates a dict with settings that reflect the current state of the UI
- (NSMutableDictionary *) createVideoOutputSettingsDict;
- (NSMutableDictionary *) createAudioOutputSettingsDict;
//	populates the UI with values from the passed dict (which is assumed to be similar to the dicts i create)
- (void) populateUIWithVideoSettingsDict:(NSDictionary *)n;
- (void) populateUIWithAudioSettingsDict:(NSDictionary *)n;

- (NSString *) lengthyVideoDescription;
- (NSString *) lengthyAudioDescription;

//	these methods are purely cosmetic- so if i enable video resizing/audio resampling, the default value is useful
- (void) setDisplayVideoDims:(NSSize)n;
- (void) setDisplayAudioResampleRate:(NSUInteger)n;

//	UI methods
- (IBAction) transcodeVideoClicked:(id)sender;
- (IBAction) noTranscodeVideoClicked:(id)sender;
- (IBAction) vidCodecPUBUsed:(id)sender;
- (IBAction) h264KeyframesMatrixUsed:(id)sender;
- (IBAction) h264KeyframesFieldUsed:(id)sender;
- (IBAction) h264BitrateMatrixUsed:(id)sender;
- (IBAction) h264BitrateFieldUsed:(id)sender;
- (IBAction) hapQChunkMatrixUsed:(id)sender;
- (IBAction) hapQChunkFieldUsed:(id)sender;
- (IBAction) resizeVideoClicked:(id)sender;
- (IBAction) noResizeVideoClicked:(id)sender;
- (IBAction) resizeVideoTextFieldUsed:(id)sender;

- (IBAction) transcodeAudioClicked:(id)sender;
- (IBAction) noTranscodeAudioClicked:(id)sender;
- (IBAction) audioCodecPUBUsed:(id)sender;
- (IBAction) pcmBitsPUBUsed:(id)sender;
- (IBAction) aacBitrateStrategyPUBUsed:(id)sender;
- (IBAction) resampleAudioClicked:(id)sender;
- (IBAction) noResampleAudioClicked:(id)sender;
- (IBAction) audioResamplePUBUsed:(id)sender;
- (IBAction) resampleAudioTextFieldUsed:(id)sender;

//- (void) populateMenu:(NSMenu *)popMenu withItemsForAudioProperty:(uint32_t)popQueryProperty ofAudioFormat:(uint32_t)popAudioFormat;
- (void) setCanPerformMultiplePasses:(BOOL)n;

//	returns the NSView which contains all the settings
- (NSView *) settingsView;

@end
