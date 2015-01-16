#import "CMBlockBufferPool.h"




CMMemoryPoolRef		_HIAVFMemPool = NULL;
CFAllocatorRef		_HIAVFMemPoolAllocator = NULL;
OSSpinLock			_HIAVFMemPoolLock = OS_SPINLOCK_INIT;







