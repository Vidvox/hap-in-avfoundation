#import "CMBlockBufferPool.h"




CMMemoryPoolRef		_HIAVFMemPool = NULL;
CFAllocatorRef		_HIAVFMemPoolAllocator = NULL;
HapLock	_HIAVFMemPoolLock = HAP_LOCK_INIT;







