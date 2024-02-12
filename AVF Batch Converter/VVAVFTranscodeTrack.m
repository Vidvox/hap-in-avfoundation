//
//  VVAVFTranscodeTrack.m
//  VVAVFTranscodeTestApp
//
//  Created by testadmin on 2/8/24.
//

#import "VVAVFTranscodeTrack.h"




@implementation VVAVFTranscodeTrack

+ (instancetype) create	{
	return [[VVAVFTranscodeTrack alloc] init];
}

- (instancetype) init	{
	self = [super init];
	if (self != nil)	{
	}
	return self;
}

- (NSString *) description	{
	return [NSString stringWithFormat:@"<VVAVFTranscodeTrack %p %@, %ld>",self,_mediaType,(unsigned long)_passIndex];
}

@end
