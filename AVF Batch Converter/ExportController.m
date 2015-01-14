#import "ExportController.h"
#import "FileListController.h"
#import "FileSettingsController.h"
#import "DestinationController.h"




@interface ExportController ()
- (void) startExporting;
- (void) stopExporting;
- (void) updateProgressMethod;
- (void) transcodeNextFile;
@property (assign,readwrite) BOOL exporting;
@end




@implementation ExportController


- (id) init	{
	self = [super init];
	if (self!=nil)	{
		transcoder = [[VVAVFTranscoder alloc] init];
		[transcoder setDelegate:self];
		exporting = NO;
		appIsActive = YES;
		waitingToCloseProgressWindow = NO;
		[[NSNotificationCenter defaultCenter]
			addObserver:self
			selector:@selector(applicationWillBecomeActive:)
			name:NSApplicationWillBecomeActiveNotification
			object:nil];
		[[NSNotificationCenter defaultCenter]
			addObserver:self
			selector:@selector(applicationWillResignActive:)
			name:NSApplicationWillResignActiveNotification
			object:nil];
	}
	return self;
}
- (void) applicationWillBecomeActive:(NSNotification *)note	{
	[self setAppIsActive:YES];
	if ([self waitingToCloseProgressWindow])	{
		[mainWindow endSheet:progressWindow returnCode:NSModalResponseContinue];
		[self setWaitingToCloseProgressWindow:NO];
	}
}
- (void) applicationWillResignActive:(NSNotification *)note	{
	[self setAppIsActive:NO];
}
/*------------------------------------*/
- (void) startExporting	{
	//	make sure that there's something to export- bail if errors or no files
	if ([fileListController okayToStartExport])	{
		[self setExporting:YES];
		//	tell the file list controller to stop watching files/folders for changes
		[fileListController stopWatchingAllPaths];
		//	tell the destination controller to stop watching files/folders for changes
		[destinationController stopWatchingAllPaths];
		
		[mainWindow
			beginCriticalSheet:progressWindow
			completionHandler:^(NSModalResponse returnCode){
			
			}];
		
		[self transcodeNextFile];
		[self updateProgressMethod];
	}
}
- (void) stopExporting	{
	[self setExporting:NO];
	if ([self appIsActive])
		[mainWindow endSheet:progressWindow returnCode:NSModalResponseContinue];
	else
		[self setWaitingToCloseProgressWindow:YES];
	//	update the list of filenames...
	[fileListController updateDstFileNames];
	//	update the table view
	[dstTableView deselectAll:nil];
	[dstTableView reloadData];
}
- (void) updateProgressMethod	{
	if ([self exporting])	{
		[fileProgressIndicator setDoubleValue:[transcoder normalizedProgress]];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
			[self updateProgressMethod];
		});
	}
}
- (void) transcodeNextFile	{
	//NSLog(@"%s",__func__);
	
	//	run through the files, find a file to export
	BOOL				foundAFile = NO;
	int					fileCount = 1;
	NSArray				*fileArray = [fileListController fileArray];
	for (FileHolder *filePtr in fileArray)	{
		//	if this file needs to be converted
		if (![filePtr conversionDone] && [filePtr srcFileExists])	{
			foundAFile = YES;
			dispatch_async(dispatch_get_main_queue(), ^{
				//	update the progress text fields and progress indicators
				[totalProgressField setStringValue:[NSString stringWithFormat:@"File %d of %ld",fileCount,(unsigned long)[fileArray count]]];
				[fileNameField setStringValue:[filePtr srcFileName]];
				[totalProgressIndicator setDoubleValue:(float)fileCount/(float)[fileArray count]];
				[fileProgressIndicator setDoubleValue:0.0];
				//	actually start transcoding the file
				[transcoder transcodeFileAtPath:[filePtr fullSrcPath] toPath:[destinationController fullDstPathForFile:filePtr]];
			});
			break;
		}
		++fileCount;
	}
	
	//	if i couldn't find a file to export
	if (!foundAFile)	{
		[self stopExporting];
	}
}
@synthesize exporting;
/*------------------------------------*/
- (IBAction) exportButtonClicked:(id)sender	{
	[self startExporting];
}
/*------------------------------------*/
- (void) setAudioSettingsDict:(NSDictionary *)n	{
	[transcoder setAudioExportSettings:n];
}
- (void) setVideoSettingsDict:(NSDictionary *)n	{
	[transcoder setVideoExportSettings:n];
}
/*------------------------------------*/
- (IBAction) pauseToggleUsed:(id)sender	{
	[transcoder setPaused:([pauseToggle intValue]==NSOnState) ? YES : NO];
}
- (IBAction) cancelClicked:(id)sender	{
	//	clear the transcoder
	[transcoder cancel];
	[transcoder setPaused:NO];
	[self stopExporting];
	//	update the  "pause" button (if it's paused, i have to un-pause so the loop picks up the cancel)
	if ([pauseToggle intValue] == NSOnState)
		[pauseToggle setIntValue:NSOffState];
}
/*------------------------------------*/
- (void) finishedTranscoding:(id)finished	{
	//NSLog(@"%s",__func__);
	NSArray		*fileArray = [fileListController fileArray];
	for (FileHolder *filePtr in fileArray)	{
		//	if this is the file i just finished transcoding
		if ([filePtr srcFileExists] && [[finished srcPath] isEqualToString:[filePtr fullSrcPath]] && ![filePtr conversionDone])	{
			//	flag it as being done converting
			[filePtr setConversionDone:YES];
			[filePtr setConvertedFilePath:[finished dstPath]];
			//	start transcoding the next file!
			dispatch_async(dispatch_get_main_queue(), ^{
				[self transcodeNextFile];
			});
			break;
		}
	}
}


@synthesize appIsActive;
@synthesize waitingToCloseProgressWindow;


@end
