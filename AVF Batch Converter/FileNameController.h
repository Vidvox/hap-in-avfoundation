#import <Cocoa/Cocoa.h>

/*

	this class manages the modifications that will be made to file names

*/

@interface FileNameController : NSObject {
	IBOutlet id					fileListController;
	IBOutlet NSTableView		*dstTableView;
	
	IBOutlet NSTextField		*removeField;
	IBOutlet NSTextField		*appendField;
	IBOutlet NSTextField		*prefixField;
}

- (IBAction) fieldUpdated:(id)sender;
- (void) appQuittingNotification:(NSNotification *)note;

- (NSString *) getDstNameForOrigName:(NSString *)o;

@end
