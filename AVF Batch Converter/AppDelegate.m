#import "AppDelegate.h"


/*
@interface AppDelegate ()
@property (weak) IBOutlet NSWindow *window;
@end
*/


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
}
- (void) appQuittingNotification:(NSNotification *)note	{
	//NSLog(@"%s",__func__);
}
- (void)applicationWillTerminate:(NSNotification *)aNotification {
	// Insert code here to tear down your application
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
