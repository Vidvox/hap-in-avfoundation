#import "CMBlockBufferPool.h"




CMMemoryPoolRef		_HIAVFMemPool = NULL;
CFAllocatorRef		_HIAVFMemPoolAllocator = NULL;
os_unfair_lock	_HIAVFMemPoolLock = OS_UNFAIR_LOCK_INIT;







