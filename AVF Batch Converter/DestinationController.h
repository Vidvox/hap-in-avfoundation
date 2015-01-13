#import <Cocoa/Cocoa.h>
#import "FileHolder.h"
#import "VVKQueue.h"

/*

	this class controls the destination settings (where the files will be saved)

*/

@interface DestinationController : NSObject {
	IBOutlet id				fileListController;
	IBOutlet NSTableView	*dstTableView;
	
	IBOutlet NSButton		*sameAsOriginalToggle;
	IBOutlet NSButton		*chooseButton;
	IBOutlet NSTextField	*destinationPathField;
	
	VVKQueue				*destFolderQueue;
}

- (void) appQuittingNotification:(NSNotification *)note;

- (IBAction) sameAsOriginalToggleUsed:(id)sender;
- (IBAction) chooseButtonUsed:(id)sender;
- (void) file:(NSString *)p changed:(u_int)fflag;
- (void) stopWatchingAllPaths;

- (void) destinationSettingsChanged;
- (NSString *) fullDstPathForFile:(FileHolder *)f;
- (BOOL) sameAsOriginal;

- (NSString *) destinationPathString;

@end
