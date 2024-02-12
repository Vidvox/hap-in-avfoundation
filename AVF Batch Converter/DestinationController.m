#import "DestinationController.h"
#import "FileListController.h"




@implementation DestinationController


- (id) init	{
	self = [super init];
	destFolderQueue = [[VVKQueue alloc] init];
	[destFolderQueue setDelegate:self];
	return self;
}
- (void) awakeFromNib	{
	NSUserDefaults		*def = [NSUserDefaults standardUserDefaults];
	NSString			*stringPtr = nil;
	NSNumber			*numPtr = nil;
	
	//	check the user defaults, populate the fields
	numPtr = [def objectForKey:@"sameAsOriginalVal"];
	if (numPtr==nil)
		numPtr = [NSNumber numberWithInteger:NSControlStateValueOn];
	if (numPtr != nil)
		[sameAsOriginalToggle setIntValue:[numPtr intValue]];
	stringPtr = [def objectForKey:@"destPath"];
	if (stringPtr != nil)
		[destinationPathField setStringValue:stringPtr];
	//	bump the same as original toggle (this checks the default path & handles visibility)
	[self sameAsOriginalToggleUsed:nil];
	//	register to receive notifications that the app is about to quit
	[[NSNotificationCenter defaultCenter]
		addObserver:self
		selector:@selector(appQuittingNotification:)
		name:NSApplicationWillTerminateNotification
		object:nil];
}
/*------------------------------------*/
- (void) appQuittingNotification:(NSNotification *)note	{
	NSUserDefaults		*def = [NSUserDefaults standardUserDefaults];
	
	//	save the contents of the fields to the user defaults
	[def setObject:[NSNumber numberWithInt:[sameAsOriginalToggle intValue]] forKey:@"sameAsOriginalVal"];
	[def setObject:[destinationPathField stringValue] forKey:@"destPath"];
	
	//	save the user defaults to disk
	[def synchronize];
}
/* --------------------------------------------------------------------------------- */
#pragma mark ---------------------
/* --------------------------------------------------------------------------------- */
- (IBAction) sameAsOriginalToggleUsed:(id)sender	{
	//NSLog(@"%s",__func__);
	//	stop watching everything
	[destFolderQueue stopWatchingAllPaths];
	//	if i'm turning "same as original" on, i'm going to be returning
	if ([sameAsOriginalToggle intValue] == NSControlStateValueOn)	{
		[destinationPathField setHidden:YES];	//	hide the destination field
		[chooseButton setEnabled:NO];			//	disable the 'choose' button
		[self destinationSettingsChanged];		//	update anything that needs to know about changes
		return;
	}
	//	if i'm here, i'm turning 'same as original' off....
	NSString			*destPath = nil;
	BOOL				directoryFlag = NO;
	
	//	check the destination path
	destPath = [destinationPathField stringValue];
	[[NSFileManager defaultManager] fileExistsAtPath:destPath isDirectory:&directoryFlag];
	//	if the dest. path isn't valid/isn't a folder, pop the choose button
	if (!directoryFlag)
		[self chooseButtonUsed:nil];
	//	else if the dest. path is valid & is a folder, un-hide the destination field
	else	{
		[destinationPathField setHidden:NO];	//	un-hide the destination field
		[chooseButton setEnabled:YES];			//	enable the 'choose' button
		[self destinationSettingsChanged];		//	update anything that needs to know about changes
		//	start watching the dest. folder
		[destFolderQueue watchPath:destPath];
	}
}
/*------------------------------------*/
- (IBAction) chooseButtonUsed:(id)sender	{
	//NSLog(@"%s",__func__);
	NSOpenPanel			*openPanel = [NSOpenPanel openPanel];
	
	[openPanel setCanChooseDirectories:YES];
	[openPanel setCanChooseFiles:NO];
	[openPanel setAllowsMultipleSelection:NO];
	[openPanel setTitle:@"Choose the destination for exported movies."];
	[openPanel setAllowedContentTypes:@[]];
	
	//	if the panel ended with something being found, set & un-hide the destination field
	if ([openPanel runModal] == NSModalResponseOK)	{
		[destinationPathField setStringValue:[[[openPanel URLs] lastObject] path]];
		[destinationPathField setHidden:NO];	//	un-hide the destination field
		[chooseButton setEnabled:YES];			//	enable the 'choose' button
		[self destinationSettingsChanged];		//	update anything that needs to know about changes
		//	start watching the dest. folder
		[destFolderQueue stopWatchingAllPaths];
		[destFolderQueue watchPath:[[[openPanel URLs] lastObject] path]];
	}
	//	else if i cancelled out of the panel, re-enable the 'same as original' toggle
	else	{
		[sameAsOriginalToggle setIntValue:NSControlStateValueOn];
		[destinationPathField setHidden:YES];	//	hide the destination field
		[chooseButton setEnabled:NO];			//	disable the 'choose' button
		[self destinationSettingsChanged];		//	update anything that needs to know about changes
	}
}
/*------------------------------------*/
- (void) file:(NSString *)p changed:(u_int)fflag	{
	//[self chooseButtonUsed:chooseButton];
	[self sameAsOriginalToggleUsed:nil];
}
/*------------------------------------*/
- (void) stopWatchingAllPaths	{
	[destFolderQueue stopWatchingAllPaths];
}
/* --------------------------------------------------------------------------------- */
#pragma mark ---------------------
/* --------------------------------------------------------------------------------- */
- (void) destinationSettingsChanged	{
	//NSLog(@"%s",__func__);
	[fileListController updateDstFileNames];
	//	update the table view
	[dstTableView deselectAll:nil];
	[dstTableView reloadData];
}
/*------------------------------------*/
- (NSString *) fullDstPathForFile:(FileHolder *)f	{
	if (f == nil)
		return nil;
	
	if ([self sameAsOriginal])
		return [NSString stringWithFormat:@"%@%@",[f parentDirectoryPath],[f dstFileName]];
	else
		return [NSString stringWithFormat:@"%@%@",[self destinationPathString],[f dstFileName]];
}
/*------------------------------------*/
- (BOOL) sameAsOriginal	{
	if ([sameAsOriginalToggle intValue] == NSControlStateValueOn)
		return YES;
	else
		return NO;
}
/*------------------------------------*/
- (NSString *) destinationPathString	{
	return [[destinationPathField stringValue] stringByAppendingString:@"/"];
}


@end
