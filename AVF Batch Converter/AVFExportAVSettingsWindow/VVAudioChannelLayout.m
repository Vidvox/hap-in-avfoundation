//
//  VVAudioChannelLayout.m
//  VVAudioKit
//
//  Created by David Lublin on 8/12/15.
//  Copyright (c) 2015 VIDVOX. All rights reserved.
//

#import "VVAudioChannelLayout.h"

@implementation VVAudioChannelLayout



+ (instancetype) createWithAudioChannelLayout:(AudioChannelLayout *)acl layoutSize:(UInt32)size	{
	VVAudioChannelLayout	*returnMe = [[VVAudioChannelLayout alloc] initWithAudioChannelLayout:acl layoutSize:size];
	
	return returnMe;
}
- (instancetype) initWithAudioChannelLayout:(AudioChannelLayout *)acl layoutSize:(UInt32)size	{
	if (self = [super init])	{
		audioChannelLayout = NULL;
		channelLayoutSize = 0;
		[self _setAudioChannelLayout:acl layoutSize:size];
		//channelLayoutSize = size;
		//[self printLayoutTag];
		return self;
	}
	
	NSLog(@"\t\tERR: BAIL %s",__func__);
	self = nil;
	return nil;
}
+ (instancetype) createWithCopyFromAudioChannelLayout:(AudioChannelLayout *)acl layoutSize:(UInt32)size	{
	VVAudioChannelLayout	*returnMe = [[VVAudioChannelLayout alloc] initWithCopyFromAudioChannelLayout:acl layoutSize:size];
	
	return returnMe;
}
- (instancetype) initWithCopyFromAudioChannelLayout:(AudioChannelLayout *)acl layoutSize:(UInt32)size	{
	if (self = [super init])	{
		audioChannelLayout = NULL;
		channelLayoutSize = 0;
		[self _copyAudioChannelLayout:acl layoutSize:size];
		//channelLayoutSize = size;
		//[self printLayoutTag];
		return self;
	}
	
	NSLog(@"\t\tERR: BAIL %s",__func__);
	self = nil;
	return nil;
}
+ (instancetype) createWithData:(NSData *) d	{
	VVAudioChannelLayout	*returnMe = [[VVAudioChannelLayout alloc] initWithData:d];
	
	return returnMe;
}
- (instancetype) initWithData:(NSData *) d	{
	if (self = [super init])	{
		audioChannelLayout = NULL;
		[self _setAudioChannelLayoutFromData:d];
		//[self printLayoutTag];
		return self;
	}
	
	NSLog(@"\t\tERR: BAIL %s",__func__);
	self = nil;
	return nil;
}
+ (instancetype) createWithPreferredLayoutForChannelCount:(int)count	{
	VVAudioChannelLayout	*returnMe = [[VVAudioChannelLayout alloc] initWithPreferredLayoutForChannelCount:count];

	return returnMe;
}
- (instancetype) initWithPreferredLayoutForChannelCount:(int)count	{
	if (self = [super init])	{
		//	if it is mono or stereo use the channel layout tag
		if (count <=2)	{
			channelLayoutSize = sizeof(AudioChannelLayout);
			audioChannelLayout = malloc(channelLayoutSize);
			audioChannelLayout->mChannelLayoutTag = (count == 1) ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo;

		}
		//	if it is multi-channel set everything to mono channels
		else	{
			channelLayoutSize = sizeof(AudioChannelLayout)+count*sizeof(AudioChannelDescription);
			audioChannelLayout = malloc(channelLayoutSize);
			audioChannelLayout->mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions;
			audioChannelLayout->mNumberChannelDescriptions = count;
			for (int i=0;i<count;++i)	{
				//audioChannelLayout->mChannelDescriptions[i].mChannelLabel = kAudioChannelLabel_Discrete_0 + i;
				audioChannelLayout->mChannelDescriptions[i].mChannelLabel = kAudioChannelLabel_Mono;
				audioChannelLayout->mChannelDescriptions[i].mChannelFlags = kAudioChannelFlags_AllOff;
			}
		}
		return self;
	}
	
	NSLog(@"\t\tERR: BAIL %s",__func__);
	self = nil;
	return nil;
}
+ (instancetype) createWithAudioChannelLayoutTag:(AudioChannelLayoutTag)tag	{
	VVAudioChannelLayout	*returnMe = [[VVAudioChannelLayout alloc] initWithAudioChannelLayoutTag:tag];

	return returnMe;
}
- (instancetype) initWithAudioChannelLayoutTag:(AudioChannelLayoutTag)tag	{
	if (self = [super init])	{
		channelLayoutSize = sizeof(AudioChannelLayout);
		audioChannelLayout = malloc(channelLayoutSize);
		audioChannelLayout->mChannelLayoutTag = tag;
		return self;
	}
	
	NSLog(@"\t\tERR: BAIL %s",__func__);
	self = nil;
	return nil;
}
- (void) dealloc	{
	if (audioChannelLayout != NULL)	{
		free(audioChannelLayout);
		audioChannelLayout = NULL;
	}
	
}
+ (instancetype) createWithChannelDescriptionsForChannelCount:(int)count	{
	VVAudioChannelLayout	*returnMe = [[VVAudioChannelLayout alloc] initWithChannelDescriptionsForChannelCount:count];

	return returnMe;
}
- (instancetype) initWithChannelDescriptionsForChannelCount:(int)count	{
	if (self = [super init])	{
		channelLayoutSize = sizeof(AudioChannelLayout)+count*sizeof(AudioChannelDescription);
		audioChannelLayout = malloc(channelLayoutSize);
		audioChannelLayout->mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions;
		audioChannelLayout->mNumberChannelDescriptions = count;
		for (int i=0;i<count;++i)	{
			//audioChannelLayout->mChannelDescriptions[i].mChannelLabel = kAudioChannelLabel_Discrete_0 + i;
			audioChannelLayout->mChannelDescriptions[i].mChannelLabel = kAudioChannelLabel_Mono;
			audioChannelLayout->mChannelDescriptions[i].mChannelFlags = kAudioChannelFlags_AllOff;
		}
		//NSLog(@"\t\tcreated layout with size %d for count %d",channelLayoutSize,count);
		return self;
	}
	
	NSLog(@"\t\tERR: BAIL %s",__func__);
	self = nil;
	return nil;
}
- (AudioChannelLayout *) audioChannelLayout	{
	return audioChannelLayout;
}
- (UInt32) channelLayoutSize	{
	return channelLayoutSize;
}
- (NSData *) audioChannelLayoutAsData	{
	NSData		*layoutAsData = nil;
	if ((audioChannelLayout != NULL)&&(channelLayoutSize > 0))
		layoutAsData = [NSData dataWithBytes:audioChannelLayout length:channelLayoutSize];
	return layoutAsData;
}
- (void) _setAudioChannelLayout:(AudioChannelLayout *) acl layoutSize:(int)size	{
	if (audioChannelLayout != NULL)	{
		free(audioChannelLayout);
		audioChannelLayout = NULL;
		channelLayoutSize = 0;
	}
	if ((acl != nil)&&(size>0))	{
		audioChannelLayout = acl;
		channelLayoutSize = size;
	}
	//audioChannelLayout = acl;
}
- (void) _copyAudioChannelLayout:(AudioChannelLayout *) acl layoutSize:(int)size	{
	if (audioChannelLayout != NULL)	{
		free(audioChannelLayout);
		audioChannelLayout = NULL;
		channelLayoutSize = 0;
	}
	if ((acl != nil)&&(size>0))	{
		audioChannelLayout = malloc(size);
		memcpy(audioChannelLayout,acl,size);
		channelLayoutSize = size;
	}
}
- (void) _setAudioChannelLayoutFromData:(NSData *)d	{
	if (audioChannelLayout != NULL)	{
		free(audioChannelLayout);
		audioChannelLayout = NULL;
	}
	if ((d != nil)&&([d length]>0))	{
		audioChannelLayout = malloc([d length]);
		memcpy(audioChannelLayout,[d bytes],[d length]);
	}
}
- (void) printLayoutTag	{
	if (audioChannelLayout == NULL)
		return;
	NSString		*tmpString = [NSString stringWithFormat:@"Other layout type %d",(unsigned int)audioChannelLayout->mChannelLayoutTag];
	switch (audioChannelLayout->mChannelLayoutTag)	{
		case kAudioChannelLayoutTag_Mono:
			tmpString = @"Mono";
			break;
		case kAudioChannelLayoutTag_Stereo:
			tmpString = @"Stereo";
			break;
		case kAudioChannelLayoutTag_StereoHeadphones:
			tmpString = @"Stereo Headphones";
			break;
		case kAudioChannelLayoutTag_UseChannelDescriptions:
			tmpString = @"Channel Descriptions";
			break;
		case kAudioChannelLayoutTag_UseChannelBitmap:
			tmpString = @"Channel Bitmap";
			break;
	}
	NSLog(@"\t\t%@",tmpString);
}

@end
