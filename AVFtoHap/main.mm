#import <Foundation/Foundation.h>
#import <HapInAVFoundation/HapInAVFoundation.h>
#import "VVAVFTranscoder.h"

#include <iostream>

using namespace std;



/*		this class exists because we want something to receive the delegate callback when the transcoder has completed its task		*/
@interface TranscoderDelegate : NSObject <VVAVFTranscoderDelegate>
@property (assign,readwrite) BOOL finished;
@end

@implementation TranscoderDelegate
- (id) init	{
	self = [super init];
	if (self != nil)	{
		[self setFinished:NO];
	}
	return self;
}
- (void) finishedTranscoding:(id)finished	{
	[self setFinished:YES];
}
@end




void usage()	{
	cout << "Usage:" << endl;
	cout << "\t" << "AVFtoHap -c [H|A|Q|QA] -f input_path output_path" << endl;
	cout << endl;
	cout << "\t" << "-c\toptional codec switch- Hap (H), Hap Alpha (A), HapQ (Q), HapQ Alpha (QA)" << endl;
	cout << "\t" << "-f\tif a file exists at output_path, move it to the trash (instead of erroring out)" << endl;
	cout << endl;
	cout << "Notes:" << endl;
	cout << "\t" << "- If no output format is specified, the output file will be Hap" << endl;
	cout << "\t" << "- Audio tracks will be copied" << endl;
	cout << "\t" << "- Output file has a single chunk" << endl;
	cout << endl;
	cout << "Returns:" << endl;
	cout << "\t" << "0 on success" << endl;
	cout << "\t" << "1 if problem parsing input" << endl;
	cout << "\t" << "2 if file problem (input missing or output already exists and -f switch not present)" << endl;
	cout << "\t" << "3 if problem during transcode" << endl;
}




int main(int argc, const char * argv[]) {
	//cout << __PRETTY_FUNCTION__ << endl;
	NSAutoreleasePool		*pool = [[NSAutoreleasePool alloc] init];
	const char		**tmpPtr = argv;
	for (int i=0; i<argc; ++i)	{
		//cout << "\targ " << i << " is " << argv[i] << endl;
		//cout << "\targ " << i << " is " << *tmpPtr << endl;
		++tmpPtr;
	}
	
	if (argc < 3)	{
		cout << "ERR: not enough arguments (" << argc-1 << ", min is 2)" << endl;
		usage();
		return 1;
	}
	
	
	NSDictionary	*videoOutputSettings = nil;
	BOOL			removeExistingFiles = NO;
	NSString		*inputFilePath = nil;
	NSString		*outputFilePath = nil;
	const char		**tmpCStr = argv;
	++tmpCStr;
	while (*tmpCStr != NULL)	{
		NSString		*tmpStr = [NSString stringWithUTF8String:*tmpCStr];
		if ([tmpStr isEqualToString:@"-c"])	{
			++tmpCStr;
			tmpStr = [NSString stringWithUTF8String:*tmpCStr];
			if ([tmpStr isEqualToString:@"H"])	{
				videoOutputSettings = @{
					AVVideoCodecKey: AVVideoCodecHap,
					AVVideoCompressionPropertiesKey: @{
						AVVideoQualityKey: @0.75,
						AVHapVideoChunkCountKey: @1
					},
				};
			}
			else if ([tmpStr isEqualToString:@"A"])	{
				videoOutputSettings = @{
					AVVideoCodecKey: AVVideoCodecHapAlpha,
					AVVideoCompressionPropertiesKey: @{
						AVVideoQualityKey: @0.75,
						AVHapVideoChunkCountKey: @1
					},
				};
			}
			else if ([tmpStr isEqualToString:@"Q"])	{
				videoOutputSettings = @{
					AVVideoCodecKey: AVVideoCodecHapQ,
					AVVideoCompressionPropertiesKey: @{
						AVVideoQualityKey: @0.75,
						AVHapVideoChunkCountKey: @1
					},
				};
			}
			else if ([tmpStr isEqualToString:@"QA"])	{
				videoOutputSettings = @{
					AVVideoCodecKey: AVVideoCodecHapQAlpha,
					AVVideoCompressionPropertiesKey: @{
						AVVideoQualityKey: @0.75,
						AVHapVideoChunkCountKey: @1
					},
				};
			}
			else	{
				cout << "ERR: codec switch value (" << *tmpCStr << ") not understood" << endl;
				usage();
				return 1;
			}
			++tmpCStr;
		}
		else if ([tmpStr isEqualToString:@"-f"])	{
			removeExistingFiles = YES;
			++tmpCStr;
		}
		//	else it's an unrecognized switch, so it should be a file path of some sort
		else	{
			tmpStr = [tmpStr stringByExpandingTildeInPath];
			NSURL		*tmpURL = [NSURL fileURLWithPath:tmpStr];
			tmpStr = [tmpURL path];
			NSFileManager		*fm = [NSFileManager defaultManager];
			if (inputFilePath == nil)	{
				if (![fm fileExistsAtPath:tmpStr])	{
					cout << "ERR: no file exists for input path (" << *tmpCStr << ")" << endl;
					usage();
					return 2;
				}
				inputFilePath = tmpStr;
				++tmpCStr;
			}
			else if (outputFilePath == nil)	{
				if ([fm fileExistsAtPath:tmpStr])	{
					if (removeExistingFiles)	{
						NSError		*nsErr = nil;
						if (![fm trashItemAtURL:tmpURL resultingItemURL:nil error:&nsErr])	{
							cout << "ERR: problem moving file to trash (" << [[nsErr description] UTF8String] << ")" << endl;
							usage();
							return 2;
						}
						else	{
							outputFilePath = tmpStr;
							//	we're ready to export!
							break;
						}
					}
					else	{
						cout << "ERR: file already exists at output path (" << *tmpCStr << ")" << endl;
						usage();
						return 2;
					}
				}
				else	{
					outputFilePath = tmpStr;
					//	we're ready to export!
					break;
				}
			}
		}
	}
	
	if (inputFilePath==nil || outputFilePath==nil)	{
		cout << "ERR: input or output file missing" << endl;
		usage();
		return 2;
	}
	
	if (videoOutputSettings == nil)	{
		videoOutputSettings = @{
			AVVideoCodecKey: AVVideoCodecHap,
			AVVideoCompressionPropertiesKey: @{
				AVVideoQualityKey: @0.75,
				AVHapVideoChunkCountKey: @1
			},
		};
	}
	
	TranscoderDelegate	*del = [[TranscoderDelegate alloc] init];
	VVAVFTranscoder		*trans = [[VVAVFTranscoder alloc] init];
	[trans setVideoExportSettings:videoOutputSettings];
	[trans setAudioExportSettings:nil];
	[trans setDelegate:del];
	[trans transcodeFileAtPath:inputFilePath toPath:outputFilePath];
	
	
	while ([[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]])	{
		if (![del finished])	{
			//NSLog(@"\t\tdelegate isn't finished (%0.2f%%)",[trans normalizedProgress]*100.);
		}
		else	{
			[pool release];
			pool = [[NSAutoreleasePool alloc] init];
			break;
		}
	}
	
	return 0;
}
