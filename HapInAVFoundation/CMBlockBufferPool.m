#import "CMBlockBufferPool.h"




@interface MemObject ()
- (void) setMem:(void *)n;
- (void) setSize:(size_t)n;
- (void) setPool:(id)n;
@end


@implementation MemObject

+ (id) createWithSize:(size_t)n pool:(id)p	{
	if (n<=0)
		return nil;
	id		returnMe = [[MemObject alloc] initWithSize:n pool:p];
	return (returnMe==nil) ? nil : [returnMe autorelease];
}
+ (id) createWithPtr:(void *)n sized:(size_t)s pool:(id)p	{
	id		returnMe = [[MemObject alloc] initWithPtr:n sized:s pool:p];
	return (returnMe==nil) ? nil : [returnMe autorelease];
}
- (id) initWithSize:(size_t)n pool:(id)p	{
	self = [super init];
	if (self!=nil)	{
		size = n;
		mem = nil;
		pool = nil;
		if (n<=0)
			goto BAIL;
		NSLog(@"\t\tactually allocating mem, %s",__func__);
		mem = malloc(size);
		pool = (p==nil) ? nil : [p retain];
	}
	return self;
BAIL:
	[self release];
	return nil;
}
- (id) initWithPtr:(void *)n sized:(size_t)s pool:(id)p	{
	self = [super init];
	if (self!=nil)	{
		size = s;
		mem = nil;
		pool = nil;
		if (n==nil)
			goto BAIL;
		mem = n;
		pool = (p==nil) ? nil : [p retain];
	}
	return self;
BAIL:
	[self release];
	return nil;
}
- (void) dealloc	{
	if (pool!=nil)	{
		[pool returnMemObjectToPool:self];
		[pool release];
	}
	if (mem!=nil)	{
		free(mem);
		mem = nil;
	}
	[super dealloc];
}
- (id) copyWithZone:(NSZone *)z	{
	id		returnMe = [[MemObject alloc] initWithPtr:mem sized:size pool:pool];
	return returnMe;
}
- (void) setMem:(void *)n	{
	mem = n;
}
- (void) setSize:(size_t)n	{
	size = n;
}
- (void) setPool:(id)n	{
	if (pool!=nil)
		[pool release];
	pool = (n==nil) ? nil : [n retain];
}
- (void *) mem	{
	return mem;
}
- (size_t) size	{
	return size;
}

@end








@implementation MemObjectPool

- (id) init	{
	self = [super init];
	if (self!=nil)	{
		lock = OS_SPINLOCK_INIT;
		array = [[NSMutableArray arrayWithCapacity:0] retain];
		bufferLength = 1;
		maxPoolSize = 8;
	}
	return self;
}
- (void) dealloc	{
	OSSpinLockLock(&lock);
	if (array!=nil)	{
		[array release];
		array = nil;
	}
	OSSpinLockUnlock(&lock);
	[super dealloc];
}
- (void *) allocMemory	{
	void		*returnMe = NULL;
	OSSpinLockLock(&lock);
	//	pull a mem object from the array
	MemObject			*foundObj = (array==nil || [array count]<1) ? nil : [array objectAtIndex:0];
	//	if i found a mem obj, steal its mem and then dispose of it
	if (foundObj!=nil)	{
		returnMe = [foundObj mem];
		[foundObj setMem:nil];
		[array removeObjectIdenticalTo:foundObj];
	}
	//	else there's nothing for me in the array- just allocate memory
	else	{
		NSLog(@"\t\tactually allocating mem, %s",__func__);
		returnMe = malloc(bufferLength);
	}
	OSSpinLockUnlock(&lock);
	return returnMe;
}
- (MemObject *) allocMemObject	{
	MemObject	*returnMe = nil;
	OSSpinLockLock(&lock);
	//	pull a mem object from the array
	MemObject			*foundObj = (array==nil || [array count]<1) ? nil : [array objectAtIndex:0];
	//	retain it, set me as its pool, remove it from the array
	if (foundObj!=nil)	{
		returnMe = [foundObj retain];
		[returnMe setPool:self];
		[array removeObjectIdenticalTo:foundObj];
	}
	else	{
		NSLog(@"\t\tactually allocating mem, %s",__func__);
		returnMe = [[MemObject alloc] initWithPtr:malloc(bufferLength) sized:bufferLength pool:self];
	}
	OSSpinLockUnlock(&lock);
	return returnMe;
}
- (void) returnToPoolMemory:(void *)m sized:(NSUInteger)s	{
	if (m==nil || s==0)
		return;
	OSSpinLockLock(&lock);
	//	if the array is "full", or the size of the memory i'm returning isn't the size of this pool, free the memory i'm returning
	if ([array count]>=maxPoolSize || s!=bufferLength)
		free(m);
	//	else there's room in the array for more- make a mem object, stick it in the array
	else
		[array addObject:[MemObject createWithPtr:m sized:s pool:nil]];
	OSSpinLockUnlock(&lock);
}
- (void) returnMemObjectToPool:(MemObject *)m	{
	if (m==nil)
		return;
	OSSpinLockLock(&lock);
	if ([array count]<maxPoolSize && [m size]==bufferLength)	{
		MemObject		*copy = [m copy];
		[copy setPool:nil];
		[array addObject:copy];
		[copy release];
		[m setMem:nil];
		[m setSize:0];
	}
	OSSpinLockUnlock(&lock);
}
- (void) setBufferLength:(size_t)n	{
	OSSpinLockLock(&lock);
	if (n!=bufferLength)	{
		[array removeAllObjects];
		bufferLength = n;
	}
	OSSpinLockUnlock(&lock);
}
- (size_t) bufferLength	{
	OSSpinLockLock(&lock);
	size_t			returnMe = bufferLength;
	OSSpinLockUnlock(&lock);
	return returnMe;
}
- (void) setMaxPoolSize:(NSUInteger)n	{
	OSSpinLockLock(&lock);
	//	if the pool size has decreased, run through all the mem object arrays in the dict, adjusting their sizes
	if (n<maxPoolSize)	{
		maxPoolSize = n;
		while ([array count]>maxPoolSize)
			[array removeObjectAtIndex:0];
	}
	OSSpinLockUnlock(&lock);
}

@end








void CMBlockBufferPool_MemDestroy(void *refCon, void *doomedMemoryBlock, size_t sizeInBytes)	{
	[(id)refCon returnToPoolMemory:doomedMemoryBlock sized:sizeInBytes];
	//	when i made the block buffer, i retained the pool (the refCon) so it would exist until the block buffer is freed: release it now...
	[(id)refCon release];
}


@implementation CMBlockBufferPool

- (id) init	{
	self = [super init];
	if (self!=nil)	{
		blockSrc = malloc(sizeof(CMBlockBufferCustomBlockSource));
		blockSrc->version = 0;
		blockSrc->AllocateBlock = nil;
		blockSrc->FreeBlock = CMBlockBufferPool_MemDestroy;
		blockSrc->refCon = self;
	}
	return self;
}
- (void) dealloc	{
	OSSpinLockLock(&lock);
	free(blockSrc);
	OSSpinLockUnlock(&lock);
	[super dealloc];
}
- (CMBlockBufferRef) allocBlockBuffer	{
	CMBlockBufferRef	returnMe = NULL;
	void				*mem = nil;
	size_t				localBufferLength = 0;
	
	OSSpinLockLock(&lock);
	localBufferLength = bufferLength;
	//	pull a mem object from the array- if the array is empty, allocate memory
	MemObject			*foundObj = (array==nil || [array count]<1) ? nil : [array objectAtIndex:0];
	if (foundObj!=nil)	{
		mem = [foundObj mem];
		[foundObj setMem:nil];
		[array removeObjectIdenticalTo:foundObj];
	}
	else	{
		NSLog(@"\t\tactually allocating mem, %s",__func__);
		mem = malloc(localBufferLength);
	}
	//	make the block buffer
	OSStatus			osErr = CMBlockBufferCreateWithMemoryBlock(NULL,
		mem,
		localBufferLength,
		NULL,
		blockSrc,
		0,
		localBufferLength,
		kCMBlockBufferAssureMemoryNowFlag,
		&returnMe);
	OSSpinLockUnlock(&lock);
	
	if (osErr!=noErr || returnMe==NULL)	{
		NSLog(@"\t\terr %d creating the block buffer in %s",(int)osErr,__func__);
		[self returnToPoolMemory:mem sized:localBufferLength];
		return nil;
	}
	//	if i'm here, i've successfully created a CMBlockBufferRef that is now the holder for the memory i'm pooling
	//	retain myself- i want the block buffer to "retain" the pool that created it (the buffer will release the pool when it is destroyed)
	[self retain];
	return returnMe;
}

@end

