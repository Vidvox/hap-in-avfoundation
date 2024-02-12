#import <Foundation/Foundation.h>
#include <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>


/*

	This is a utility for validating audio formats and other related useful stuff
	Thanks to bangnoise for some of these handy functions!

*/


@interface VVAudioFormatUtilities : NSObject

+ (NSArray *) bitratesForDescription:(AudioStreamBasicDescription)resultASBD bitRateMode:(UInt32)brMode;

@end
