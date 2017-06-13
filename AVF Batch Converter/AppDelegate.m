#import "AppDelegate.h"


/*
@interface AppDelegate ()
@property (weak) IBOutlet NSWindow *window;
@end
*/


IOPMAssertionID		noSleepAssertionID = 0;




@implementation AppDelegate


- (id) init	{
	self = [super init];
	{
		VTRegisterProfessionalVideoWorkflowVideoDecoders();
	}
	return self;
}
- (void) awakeFromNib	{
	//	register to receive notifications that the app is about to quit
	[[NSNotificationCenter defaultCenter]
		addObserver:self
		selector:@selector(appQuittingNotification:)
		name:NSApplicationWillTerminateNotification
		object:nil];
}
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	//NSLog(@"AppController:applicationDidFinishLaunching:");
	NSUserDefaults		*def = [NSUserDefaults standardUserDefaults];
	//int					launchCount = 0;
	
	//	if the application hasn't been launched before...
	if ([def objectForKey:@"FirstTimeLaunchFlag"] == nil)	{
		//	make a flag so i know it's been launched before
		[def setObject:[NSNumber numberWithBool:YES] forKey:@"FirstTimeLaunchFlag"];
	}
	else	{
	}
	//	update the actual prefs file
	[def synchronize];
	
	//	make sure that the machine doesn't sleep while this app is running
	CFStringRef			reasonForActivity = CFSTR("AVF Batch Exporter is running.");
	IOReturn			success = IOPMAssertionCreateWithName(
		kIOPMAssertionTypeNoDisplaySleep,
		kIOPMAssertionLevelOn,
		reasonForActivity,
		&noSleepAssertionID);
	if (success == kIOReturnSuccess)	{
		//Add the work you need to do without
		//  the system sleeping here.
	}
	else
		NSLog(@"\t\terr %d making no-sleep assertion in %s",success,__func__);
}
- (void) appQuittingNotification:(NSNotification *)note	{
	//NSLog(@"%s",__func__);
}
- (void)applicationWillTerminate:(NSNotification *)aNotification {
	//	let the computer sleep again
	IOReturn			success;
	success = IOPMAssertionRelease(noSleepAssertionID);
}
- (IBAction) aboutWindowUsed:(id)sender	{
	NSLog(@"%s",__func__);
	[NSApp
		beginSheet:aboutWindow
		modalForWindow:window
		modalDelegate:nil
		didEndSelector:nil
		contextInfo:nil];
	[aboutWindow makeKeyAndOrderFront:nil];
}
- (IBAction) aboutWindowDismiss:(id)sender	{
	[aboutWindow orderOut:nil];
	[NSApp endSheet:aboutWindow returnCode:0];
	
	//CGDisplayRestoreColorSyncSettings();
}


@end
