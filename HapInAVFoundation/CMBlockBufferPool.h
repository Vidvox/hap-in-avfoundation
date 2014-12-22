#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>




/*		simple holder for allocated blocks of memory, exists mainly to track size and facilitate use of void* with NSObjects		*/

@interface MemObject : NSObject	{
	size_t		size;
	void		*mem;
}

+ (id) createWithSize:(size_t)n;
+ (id) createWithPtr:(void *)n sized:(size_t)s;

- (id) initWithSize:(size_t)n;
- (id) initWithPtr:(void *)n sized:(size_t)s;
- (void) setMem:(void *)n;
- (void *) mem;
- (size_t) size;

@end

void CMBlockBufferPool_MemDestroy(void *refCon, void *doomedMemoryBlock, size_t sizeInBytes);




/*		used to pool and allocate memory used to back CMBlockBuffer instances of a particular size in bytes		*/

@interface CMBlockBufferPool : NSObject	{
	OSSpinLock				lock;	//	used to lock stuff
	NSMutableArray			*array;	//	array, contains MemObject instances
	size_t					bufferLength;	//	the length of the buffers that are created, in bytes
	NSUInteger				maxPoolSize;	//	the max # of elements allowed in the pool
	CMBlockBufferCustomBlockSource	*blockSrc;	//	CMBlockBuffers created by this pool use this for their deallocation callback
}

- (CMBlockBufferRef) allocBlockBuffer;
- (void *) allocMemory;
- (void) returnToPoolMemory:(void *)m sized:(NSUInteger)s;
- (void) setBufferLength:(size_t)n;
- (size_t) bufferLength;
- (void) setMaxPoolSize:(NSUInteger)n;

@end
