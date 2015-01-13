#import <Cocoa/Cocoa.h>
#import <sys/types.h>
#import <sys/event.h>
#import <pthread.h>


/*

let's give credit where credit's due:

i learned how kqueues work by reading stuff online and looking at other
peoples' uses of kqueues.  this class (and my understanding of kqueues)
was shaped significantly by the "UKKQueue" class, by M. Uli Kusterer.

if you don't want to write your own cocoa implementation of kqueues, you
should really look for this class- it's well-written, does much more than
this paltry, bare-bones implementation, and is highly functional.

thanks, Uli!

*/


@protocol VVKQueueDelegateProtocol
- (void) file:(NSString *)p changed:(u_int)fflag;
@end


@interface VVKQueue : NSObject {
	int					kqueueFD;
	NSMutableArray		*pathArray;
	NSMutableArray		*fdArray;
	id					delegate;
	
	BOOL				haltFlag;
	BOOL				currentlyProcessing;
}

- (void) watchPath:(NSString *)p;
- (void) stopWatchingPath:(NSString *)p;
- (void) stopWatchingAllPaths;

- (void) setDelegate:(id)n;

@end
