#import "FileHolder.h"




@implementation FileHolder


+ (id) createWithPath:(NSString *)p	{
	FileHolder		*returnMe = nil;
	returnMe = [[FileHolder alloc] initWithPath:p];
	if (returnMe == nil)
		return nil;
	return [returnMe autorelease];
}
- (id) initWithPath:(NSString *)p	{
	self = [super init];
	{
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
			[self release];
			return nil;
		}
		
		NSMutableString		*localParentDirPath = nil;
		srcFileName = [[p lastPathComponent] retain];
		
		localParentDirPath = [p mutableCopy];
		[localParentDirPath
			replaceOccurrencesOfString:srcFileName
			withString:@""
			options:NSBackwardsSearch
			range:NSMakeRange(0,[localParentDirPath length])];
		parentDirectoryPath = [localParentDirPath copy];
		[localParentDirPath release];
		
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
		[parentDirectoryPath release];
		parentDirectoryPath = nil;
	}
	if (srcFileName != nil)	{
		[srcFileName release];
		srcFileName = nil;
	}
	if (dstFileName != nil)	{
		[dstFileName release];
		dstFileName = nil;
	}
	if (statusString != nil)	{
		[statusString release];
		statusString = nil;
	}
	if (errorString != nil)	{
		[errorString release];
		errorString = nil;
	}
	if (convertedFilePath != nil)	{
		[convertedFilePath release];
		convertedFilePath = nil;
	}
	[super dealloc];
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
