//
//  AVFExportAVSettingsWindow.m
//  VVAVFExport-TestApp
//
//  Created by testadmin on 5/4/22.
//

#import "AVFExportAVSettingsWindow.h"
#import "AVFExportSettingsAudioVC.h"
#import "AVFExportSettingsVideoVC.h"




NSString * const		kAVFExportStripMediaKey = @"VVAVStripMediaKey";

NSString * const		kAVFExportMultiPassEncodeKey = @"VVAVVideoMultiPassEncodeKey";
NSString * const		kAVFExportVideoResolutionKey = @"VVAVVideoResolutionKey";

NSString * const		kAVFExportAudioSampleRateKey = @"VVAVAudioSampleRateKey";




@interface AVFExportAVSettingsWindow ()

//@property (copy,nullable) void (^completionHandler)(NSModalResponse, NSDictionary*, NSDictionary*);
//- (void) windowClosedWithReturnCode:(NSModalResponse)rc;

@property (weak) IBOutlet NSView * audioUIHolder;
@property (weak) IBOutlet NSView * videoUIHolder;

@property (strong,readwrite) AVFExportSettingsAudioVC * audioVC;
@property (strong,readwrite) AVFExportSettingsVideoVC * videoVC;

- (IBAction) cancelButtonClicked:(id)sender;
- (IBAction) okayButtonClicked:(id)sender;

@end




@implementation AVFExportAVSettingsWindow


+ (void) openModalForWindow:(NSWindow *)inParentWin audioSettings:(NSDictionary *)inAudioDict videoSettings:(NSDictionary *)inVideoDict completionHandler:(void (^)(NSModalResponse, NSString*, NSDictionary*, NSDictionary*))inCH	{
	AVFExportAVSettingsWindow		*win = [AVFExportAVSettingsWindow createWithAudioSettings:inAudioDict videoSettings:inVideoDict];
	if (win == nil)
		return;
	
	//	open the win!
	[inParentWin
		beginSheet:win.window
		completionHandler:^(NSModalResponse returnCode)	{
			AVFExportAVSettingsWindow		*tmpWC = win;
			NSDictionary		*audioDict = [tmpWC.audioVC createAVFSettingsDict];
			NSDictionary		*videoDict = [tmpWC.videoVC createAVFSettingsDict];
			NSString			*videoDesc = tmpWC.videoVC.lengthyDescription;
			//NSLog(@"%@ sheet closing...",self.className);
			//NSLog(@"\t\taudioDict: %@",audioDict);
			//NSLog(@"\t\tvideoDict: %@",videoDict);
			//NSLog(@"\t\tvideoDesc: %@",videoDesc);
			if (inCH != nil)	{
				inCH(returnCode, videoDesc, audioDict, videoDict);
			}
			tmpWC = nil;
		}];
}
+ (instancetype) createWithAudioSettings:(NSDictionary *)inAudioDict videoSettings:(NSDictionary *)inVideoDict	{
	if (![NSThread isMainThread])	{
		[NSException raise:NSInternalInconsistencyException format:@"Must be called on main thread! %s",__func__];
		return nil;
	}
	
	//	make the win, and the VCs
	AVFExportAVSettingsWindow		*returnMe = [[AVFExportAVSettingsWindow alloc] init];
	AVFExportSettingsAudioVC		*audioVC = [[AVFExportSettingsAudioVC alloc] init];
	AVFExportSettingsVideoVC		*videoVC = [[AVFExportSettingsVideoVC alloc] init];
	
	//	populate the VC and window
	[audioVC populateUIWithAVFSettingsDict:inAudioDict];
	[videoVC populateUIWithAVFSettingsDict:inVideoDict];
	
	//	add the VCs to the window!
	NSViewController		*winContentVC = returnMe.contentViewController;
	[winContentVC addChildViewController:audioVC];
	[winContentVC addChildViewController:videoVC];
	
	returnMe.audioVC = audioVC;
	returnMe.videoVC = videoVC;
	
	NSRect			tmpFrame;
	
	tmpFrame = audioVC.view.frame;
	[returnMe.audioUIHolder addSubview:audioVC.view];
	tmpFrame.origin = NSZeroPoint;
	audioVC.view.frame = tmpFrame;
	
	tmpFrame = videoVC.view.frame;
	[returnMe.videoUIHolder addSubview:videoVC.view];
	tmpFrame.origin = NSZeroPoint;
	videoVC.view.frame = tmpFrame;
	
	return returnMe;
}


- (instancetype) init	{	
	//NSLog(@"%s",__func__);
	self = [super initWithWindowNibName:[[self class] className]];
	if (self != nil)	{
		NSWindow		*tmpWin = self.window;
		tmpWin = nil;
	}
	return self;
}
- (void) awakeFromNib	{
}
//- (void) dealloc	{
//	//NSLog(@"%s",__func__);
//	//_completionHandler = nil;
//	//_audioVC = nil;
//	//_videoVC = nil;
//}


- (void)windowDidLoad {
	//NSLog(@"%s",__func__);
	[super windowDidLoad];
	 
	// Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
}


#pragma mark - UI actions


- (IBAction) cancelButtonClicked:(id)sender	{
	//NSLog(@"%s",__func__);
	NSWindow		*sheetParent = self.window.sheetParent;
	if (sheetParent == nil)
		return;
	[sheetParent endSheet:self.window returnCode:NSModalResponseCancel];
}
- (IBAction) okayButtonClicked:(id)sender	{
	//NSLog(@"%s",__func__);
	NSWindow		*sheetParent = self.window.sheetParent;
	if (sheetParent == nil)
		return;
	[sheetParent endSheet:self.window returnCode:NSModalResponseOK];
}


#pragma mark - backend methods


//- (void) windowClosedWithReturnCode:(NSModalResponse)rc	{
//	NSDictionary		*audioDict = [_audioVC createAVFSettingsDict];
//	NSDictionary		*videoDict = [_videoVC createAVFSettingsDict];
//	if (_completionHandler != nil)	{
//		_completionHandler(rc, audioDict, videoDict);
//	}
//}


@end
