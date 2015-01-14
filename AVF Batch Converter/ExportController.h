#import <Cocoa/Cocoa.h>
#import "FileHolder.h"
#import "VVAVFTranscoder.h"

/*

	this class handles the actual file exporting (threads, progress bars, etc.)

*/

@interface ExportController : NSObject <VVAVFTranscoderDelegate> {
	IBOutlet id				fileListController;
	IBOutlet id				fileSettingsController;
	IBOutlet id				destinationController;
	
	IBOutlet NSWindow		*progressWindow;
	IBOutlet NSWindow		*mainWindow;
	
	IBOutlet NSTextField			*totalProgressField;
	IBOutlet NSTextField			*fileNameField;
	IBOutlet NSProgressIndicator	*totalProgressIndicator;
	IBOutlet NSProgressIndicator	*fileProgressIndicator;
	
	IBOutlet NSTableView	*dstTableView;
	IBOutlet NSButton		*pauseToggle;
	BOOL					cancelExportFlag;
	
	VVAVFTranscoder			*transcoder;
	BOOL					exporting;
	
	BOOL					appIsActive;
	BOOL					waitingToCloseProgressWindow;
}

- (IBAction) exportButtonClicked:(id)sender;

- (void) setAudioSettingsDict:(NSDictionary *)n;
- (void) setVideoSettingsDict:(NSDictionary *)n;

- (IBAction) pauseToggleUsed:(id)sender;
- (IBAction) cancelClicked:(id)sender;

@property (assign,readwrite) BOOL appIsActive;
@property (assign,readwrite) BOOL waitingToCloseProgressWindow;

@end
