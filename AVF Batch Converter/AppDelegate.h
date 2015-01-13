#import <Cocoa/Cocoa.h>
#import <VideoToolbox/VTProfessionalVideoWorkflow.h>




@interface AppDelegate : NSObject <NSApplicationDelegate>	{
	IBOutlet NSWindow		*window;
	IBOutlet NSPanel		*aboutWindow;
}

- (IBAction) aboutWindowUsed:(id)sender;
- (IBAction) aboutWindowDismiss:(id)sender;

@end

