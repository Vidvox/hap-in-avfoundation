#import <Foundation/Foundation.h>
#import "VVAVFExportBasicSettingsCtrlr.h"




@interface FileSettingsController : NSObject	{
	IBOutlet id						exportController;
	
	IBOutlet NSWindow				*mainWindow;
	IBOutlet NSWindow				*settingsWindow;
	IBOutlet NSView					*settingsViewHolder;
	
	IBOutlet NSTextField			*videoDescriptionField;
	IBOutlet NSTextField			*audioDescriptionField;
	IBOutlet NSPopUpButton			*loadSavedExportSettingsPUB;
	IBOutlet NSPopUpButton			*deleteSavedExportSettingsPUB;
	
	IBOutlet NSWindow				*saveSettingsWindow;
	IBOutlet NSTextField			*saveSettingsField;
	
	VVAVFExportBasicSettingsCtrlr	*transcoderSettings;
}

- (void) loadSavedSettingsFromDefaults;

- (IBAction) settingsButtonClicked:(id)sender;
- (IBAction) closeSettingsButtonClicked:(id)sender;
- (void) pushSettingsToExportController;
- (IBAction) loadSavedExportSettingsPUBUsed:(id)sender;

- (IBAction) saveCurrentSettingsClicked:(id)sender;
- (IBAction) deleteSettingClicked:(id)sender;
- (IBAction) cancelSaveSettingsClicked:(id)sender;
- (IBAction) proceedSaveSettingsClicked:(id)sender;

@end
