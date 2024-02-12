#import "VVKQueue.h"




@implementation VVKQueue


- (id) init	{
	//NSLog(@"VVKQueue:init:");
	self = [super init];
	if (self != nil)	{
		kqueueFD = kqueue();
		if (kqueueFD == (-1))	{
			NSLog(@"\t\terr creating kqueueFD: %d",kqueueFD);
			self = nil;
			return self;
		}
		
		pathArray = nil;
		fdArray = nil;
		
		@synchronized (self)	{
			pathArray = [NSMutableArray arrayWithCapacity:0];
			fdArray = [NSMutableArray arrayWithCapacity:0];
		}
		
		haltFlag = NO;
		currentlyProcessing = NO;
		
		[NSThread detachNewThreadSelector:@selector(threadLaunch:) toTarget:self withObject:nil];
	}
	
	return self;
}

- (void) dealloc	{
	//NSLog(@"VVKQueue:dealloc:");
	NSEnumerator		*it = [fdArray objectEnumerator];
	NSNumber			*numPtr;
	int					err;
	
	while (numPtr = [it nextObject])	{
		err = close([numPtr intValue]);
		if (err == (-1))
			NSLog(@"\t\terr: couldn't close fd- %d",err);
	}
	
	@synchronized (self)	{
		pathArray = nil;
		fdArray = nil;
	}
	
	haltFlag = YES;
	while (currentlyProcessing)
		pthread_yield_np();
	
	delegate = nil;
}

- (void) watchPath:(NSString *)p	{
	if (p == nil)
		return;
	//NSLog(@"%s ... %@",__func__,p);
	int					fileDescriptor;
	struct kevent		event;
	struct timespec		tmpTime = {0,0};
	
	@synchronized (self)	{
		if ([pathArray containsObject:p])
			return;
		
		fileDescriptor = open([p fileSystemRepresentation], O_EVTONLY, 0);
		if (fileDescriptor < 0)	{
			NSLog(@"\t\terror opening rep. for path to watch ... %@",p);
			return;
		}
		EV_SET(&event,
			fileDescriptor,
			EVFILT_VNODE,
			EV_ADD | EV_ENABLE | EV_CLEAR,
			NOTE_RENAME | NOTE_WRITE | NOTE_DELETE | NOTE_ATTRIB,
			0,
			(__bridge void*)p);
		
		[pathArray addObject:p];
		[fdArray addObject:[NSNumber numberWithInt:fileDescriptor]];
		kevent(kqueueFD, &event, 1, NULL, 0, &tmpTime);
	}
}

- (void) stopWatchingAllPaths	{
	//NSLog(@"%s",__func__);
	@synchronized (self)	{
		NSEnumerator		*it = [fdArray objectEnumerator];
		NSNumber			*anObj;
		while (anObj = [it nextObject])
			close([anObj intValue]);
		[pathArray removeAllObjects];
		[fdArray removeAllObjects];
	}
}

- (void) stopWatchingPath:(NSString *)p	{
	if (p == nil)
		return;
	//NSLog(@"%s ... %@",__func__,p);
	@synchronized (self)	{
		NSUInteger			pathIndex = [pathArray indexOfObject:p];
		int					fileDescriptor;
		
		if (pathIndex == NSNotFound)
			return;
		[pathArray removeObjectAtIndex:pathIndex];
		fileDescriptor = [[fdArray objectAtIndex:pathIndex] intValue];
		close(fileDescriptor);
		[fdArray removeObjectAtIndex:pathIndex];
	}
}

- (void) threadLaunch:(id)sender	{
	//NSLog(@"VVKQueue:threadLaunch:");
	//	the thread will terminate as soon as this method exits!
	@autoreleasepool	{
		//int						poolCount = 0;
		int						fileDescriptor = kqueueFD;
		
		currentlyProcessing = YES;
		while (!haltFlag)	{
			int						n;
			struct kevent			event;
			struct timespec			timeout = {5,0};
			
			n = kevent(kqueueFD, NULL, 0, &event, 1, &timeout);
			if (n > 0)	{
				//NSLog(@"\t\tfound event");
				if (event.filter == EVFILT_VNODE)	{
					if (event.fflags)	{
						NSString		*path = (__bridge NSString *)event.udata;
						//NSLog(@"\t\tfile changed: %@",path);
						if ((delegate != nil) && ([delegate respondsToSelector:@selector(file:changed:)]))	{
							dispatch_async(dispatch_get_main_queue(), ^{
								[(id <VVKQueueDelegateProtocol>)self->delegate file:path changed:event.fflags];
							});
						}
					}
				}
			}
			
		}
		
		close(fileDescriptor);
		currentlyProcessing = NO;
	}
}

- (void) setDelegate:(id)n	{
	delegate = n;
}


@end
