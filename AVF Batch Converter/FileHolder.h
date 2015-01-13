#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <HapInAVFoundation/HapInAVFoundation.h>
/*

	this class encapsulates a file- its original path, destination file name, and error string

*/

@interface FileHolder : NSObject {
	NSString		*parentDirectoryPath;
	NSString		*srcFileName;
	NSString		*dstFileName;
	NSString		*errorString;
	BOOL			conversionDone;
	NSString		*convertedFilePath;
	BOOL			srcFileExists;
}

+ (id) createWithPath:(NSString *)p;
- (id) initWithPath:(NSString *)p;

@property (readonly) NSString *fullSrcPath;
@property (readonly) NSString *parentDirectoryPath;
@property (readonly) NSString *srcFileName;
@property (retain,readwrite) NSString *dstFileName;
@property (retain,readwrite) NSString *errorString;
@property (assign,readwrite) BOOL conversionDone;
@property (retain,readwrite) NSString *convertedFilePath;
@property (assign,readwrite) BOOL srcFileExists;

@end
