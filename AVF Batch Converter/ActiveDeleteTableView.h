#import <Cocoa/Cocoa.h>


@protocol ActiveDeleteTableProtocol
- (void) tableView:(NSTableView *)tv deleteRowIndexes:(NSIndexSet *)i;
@end


@interface ActiveDeleteTableView : NSTableView {

}

- (void) keyDown:(NSEvent *)event;

@end
