#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>




/*		simple holder for allocated blocks of memory, exists mainly to track size and facilitate use of void* with NSObjects		*/

@interface MemObject : NSObject <NSCopying>	{
	size_t		size;
	void		*mem;
	id			pool;	//	retained- the pool which created me (or nil)
}

+ (id) createWithSize:(size_t)n pool:(id)p;
+ (id) createWithPtr:(void *)n sized:(size_t)s pool:(id)p;

- (id) initWithSize:(size_t)n pool:(id)p;
- (id) initWithPtr:(void *)n sized:(size_t)s pool:(id)p;
- (void *) mem;
- (size_t) size;

@end



@interface MemObjectPool : NSObject	{
	OSSpinLock				lock;	//	used to lock stuff
	NSMutableArray			*array;	//	array, contains MemObject instances
	size_t					bufferLength;	//	the length of the buffers that are created, in bytes
	NSUInteger				maxPoolSize;	//	the max # of elements allowed in the pool
}

- (void *) allocMemory;
- (MemObject *) allocMemObject;
- (void) returnToPoolMemory:(void *)m sized:(NSUInteger)s;
- (void) returnMemObjectToPool:(MemObject *)m;
- (void) setBufferLength:(size_t)n;
- (size_t) bufferLength;
- (void) setMaxPoolSize:(NSUInteger)n;

@end


void CMBlockBufferPool_MemDestroy(void *refCon, void *doomedMemoryBlock, size_t sizeInBytes);

/*		used to pool and allocate memory used to back CMBlockBuffer instances of a particular size in bytes		*/

@interface CMBlockBufferPool : MemObjectPool	{
	CMBlockBufferCustomBlockSource	*blockSrc;	//	CMBlockBuffers created by this pool use this for their deallocation callback
}

- (CMBlockBufferRef) allocBlockBuffer;

@end
