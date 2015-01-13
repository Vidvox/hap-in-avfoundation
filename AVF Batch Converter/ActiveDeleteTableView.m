#import "ActiveDeleteTableView.h"




@implementation ActiveDeleteTableView


- (void) keyDown:(NSEvent *)event	{
	NSString			*keyString;
	unichar			keyChar;
	
	keyString = [event charactersIgnoringModifiers];
	keyChar = [keyString characterAtIndex:0];
	
	switch(keyChar)	{
		case 0177:		//	delete key
		case NSDeleteFunctionKey:
		case NSDeleteCharFunctionKey:
			[(id <ActiveDeleteTableProtocol>)[self dataSource] tableView:self deleteRowIndexes:[self selectedRowIndexes]];
			break;
		default:
			[super keyDown:event];
	}
}


@end
