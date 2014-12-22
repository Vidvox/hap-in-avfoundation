#import "CMBlockBufferPool.h"




@implementation MemObject

+ (id) createWithSize:(size_t)n	{
	if (n<=0)
		return nil;
	id		returnMe = [[MemObject alloc] initWithSize:n];
	return (returnMe==nil) ? nil : [returnMe autorelease];
}
+ (id) createWithPtr:(void *)n sized:(size_t)s	{
	id		returnMe = [[MemObject alloc] initWithPtr:n sized:s];
	return (returnMe==nil) ? nil : [returnMe autorelease];
}
- (id) initWithSize:(size_t)n	{
	self = [super init];
	if (self!=nil)	{
		size = n;
		mem = nil;
		if (n<=0)
			goto BAIL;
		mem = malloc(size);
	}
	return self;
BAIL:
	[self release];
	return nil;
}
- (id) initWithPtr:(void *)n sized:(size_t)s	{
	self = [super init];
	if (self!=nil)	{
		size = 0;
		mem = nil;
		if (n==nil)
			goto BAIL;
		size = s;
		mem = n;
	}
	return self;
BAIL:
	[self release];
	return nil;
}
- (void) dealloc	{
	if (mem!=nil)	{
		free(mem);
		mem = nil;
	}
	[super dealloc];
}
- (void) setMem:(void *)n	{
	mem = n;
}
- (void *) mem	{
	return mem;
}
- (size_t) size	{
	return size;
}

@end

/*
void* CMBlockBufferPool_MemCreate(void *refCon, size_t sizeInBytes)	{
	
}
*/
void CMBlockBufferPool_MemDestroy(void *refCon, void *doomedMemoryBlock, size_t sizeInBytes)	{
	[(id)refCon returnToPoolMemory:doomedMemoryBlock sized:sizeInBytes];
	//	when i made the block buffer, i retained the pool (the refCon) so it would exist until the block buffer is freed: release it now...
	[(id)refCon release];
}








@implementation CMBlockBufferPool

- (id) init	{
	self = [super init];
	if (self!=nil)	{
		lock = OS_SPINLOCK_INIT;
		array = [[NSMutableArray arrayWithCapacity:0] retain];
		bufferLength = 1;
		maxPoolSize = 8;
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
	if (array!=nil)	{
		[array release];
		array = nil;
	}
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
	else
		mem = malloc(localBufferLength);
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
- (void *) allocMemory	{
	void		*returnMe = NULL;
	OSSpinLockLock(&lock);
	//	pull a mem object from the array- if the array is empty, allocate memory
	MemObject			*foundObj = (array==nil || [array count]<1) ? nil : [array objectAtIndex:0];
	if (foundObj!=nil)	{
		returnMe = [foundObj mem];
		[foundObj setMem:nil];
		[array removeObjectIdenticalTo:foundObj];
	}
	else
		returnMe = malloc(bufferLength);
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
		[array addObject:[MemObject createWithPtr:m sized:s]];
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

