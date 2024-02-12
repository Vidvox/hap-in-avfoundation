#import "FileHolder.h"




@implementation FileHolder


+ (id) createWithPath:(NSString *)p	{
	return [[FileHolder alloc] initWithPath:p];
}
- (id) initWithPath:(NSString *)p	{
	self = [super init];
	if (self != nil)	{
		parentDirectoryPath = nil;
		srcFileName = nil;
		dstFileName = nil;
		statusString = nil;
		errorString = nil;
		conversionDone = NO;
		convertedFilePath = nil;
		srcFileExists = NO;
		
		NSURL		*tmpURL = [NSURL fileURLWithPath:p];
		AVAsset		*tmpAsset = [AVAsset assetWithURL:tmpURL];
		if (![tmpAsset isPlayable] && ![tmpAsset containsHapVideoTrack])	{
			self = nil;
			return self;
		}
		NSMutableString		*localParentDirPath = nil;
		srcFileName = [p lastPathComponent];
		
		localParentDirPath = [p mutableCopy];
		[localParentDirPath
			replaceOccurrencesOfString:srcFileName
			withString:@""
			options:NSBackwardsSearch
			range:NSMakeRange(0,[localParentDirPath length])];
		parentDirectoryPath = [localParentDirPath copy];
		localParentDirPath = nil;
		
		dstFileName = nil;
		errorString = nil;
		conversionDone = NO;
		convertedFilePath = nil;
		srcFileExists = YES;
	}
	return self;
}
- (void) dealloc	{
	if (parentDirectoryPath != nil)	{
		parentDirectoryPath = nil;
	}
	if (srcFileName != nil)	{
		srcFileName = nil;
	}
	if (dstFileName != nil)	{
		dstFileName = nil;
	}
	if (statusString != nil)	{
		statusString = nil;
	}
	if (errorString != nil)	{
		errorString = nil;
	}
	if (convertedFilePath != nil)	{
		convertedFilePath = nil;
	}
}

- (NSString *) fullSrcPath	{
	return [NSString stringWithFormat:@"%@%@",parentDirectoryPath,srcFileName];
}
@synthesize parentDirectoryPath;
@synthesize srcFileName;
@synthesize dstFileName;
@synthesize statusString;
@synthesize errorString;
@synthesize conversionDone;
@synthesize convertedFilePath;
@synthesize srcFileExists;
- (NSString *) description	{
	return [NSString stringWithFormat:@"<FileHolder %@, %d>",[srcFileName lastPathComponent],conversionDone];
}


@end
