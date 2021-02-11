#ifndef Macros_h
#define Macros_h




//	if the min deployment target is >= 10.12, we can use unfair lock
#if (__MAC_OS_X_VERSION_MIN_REQUIRED >= 101200)
	#import "os/lock.h"
	#define HapLock os_unfair_lock
	#define HAP_LOCK_INIT OS_UNFAIR_LOCK_INIT
	#define HapLockLock(n) os_unfair_lock_lock(n)
	#define HapLockUnlock(n) os_unfair_lock_unlock(n)
//	else the min deployment target is < 10.12, we have to use spinlock
#else
	#define HapLock OSSpinLock
	#define HAP_LOCK_INIT OS_SPINLOCK_INIT
	#define HapLockLock(n) OSSpinLockLock(n)
	#define HapLockUnlock(n) OSSpinLockUnlock(n)
#endif




#endif /* Macros_h */
