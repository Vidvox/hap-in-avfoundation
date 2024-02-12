#import "FileNameController.h"
#import "FileListController.h"




@implementation FileNameController


- (void) awakeFromNib	{
	NSUserDefaults		*def = [NSUserDefaults standardUserDefaults];
	NSString			*stringPtr = nil;
	
	//	check the user defaults, populate the fields if appropriate
	stringPtr = [def objectForKey:@"removeField"];
	if (stringPtr != nil)
		[removeField setStringValue:stringPtr];
	
	stringPtr = [def objectForKey:@"appendField"];
	if (stringPtr != nil)
		[appendField setStringValue:stringPtr];
	
	stringPtr = [def objectForKey:@"prefixField"];
	if (stringPtr != nil)
		[prefixField setStringValue:stringPtr];
	
	//	register to receive notifications that the app is about to quit
	[[NSNotificationCenter defaultCenter]
		addObserver:self
		selector:@selector(appQuittingNotification:)
		name:NSApplicationWillTerminateNotification
		object:nil];
}
/*------------------------------------*/
- (IBAction) fieldUpdated:(id)sender	{
	[fileListController updateDstFileNames];
	//	update the table view
	[dstTableView deselectAll:nil];
	[dstTableView reloadData];
}
/*------------------------------------*/
- (void) appQuittingNotification:(NSNotification *)note	{
	NSUserDefaults		*def = [NSUserDefaults standardUserDefaults];
	NSString			*stringPtr = nil;
	
	//	save the contents of the fields to the user defaults
	stringPtr = [removeField stringValue];
	if (stringPtr == nil)
		stringPtr = @"";
	[def setObject:stringPtr forKey:@"removeField"];
	
	stringPtr = [appendField stringValue];
	if (stringPtr == nil)
		stringPtr = @"";
	[def setObject:stringPtr forKey:@"appendField"];
	
	stringPtr = [prefixField stringValue];
	if (stringPtr == nil)
		stringPtr = @"";
	[def setObject:stringPtr forKey:@"prefixField"];
	
	//	save the user defaults to disk
	[def synchronize];
}
/*------------------------------------*/
- (NSString *) getDstNameForOrigName:(NSString *)o	{
	NSMutableString		*dstFileName = nil;
	//NSString			*fullDstPath = nil;
	NSString			*returnMe = nil;
	
	dstFileName = [o mutableCopy];
	//	run the remove/append/prefix stuff
	if ([removeField stringValue] != nil)	{
		[dstFileName
			replaceOccurrencesOfString:[removeField stringValue]
			withString:@""
			options:NSBackwardsSearch
			range:NSMakeRange(0,[dstFileName length])];
	}
	if ([appendField stringValue] != nil)
		[dstFileName appendString:[appendField stringValue]];
	if ([prefixField stringValue] != nil)
		[dstFileName insertString:[prefixField stringValue] atIndex:0];
	
	returnMe = [NSString stringWithString:dstFileName];
	dstFileName = nil;
	return returnMe;
	//return [dstFileName autorelease];
}


@end
