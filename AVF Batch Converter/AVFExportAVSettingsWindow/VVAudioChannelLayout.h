//
//  VVAudioChannelLayout.h
//  VVAudioKit
//
//  Created by David Lublin on 8/12/15.
//  Copyright (c) 2015 VIDVOX. All rights reserved.
//

#import <Cocoa/Cocoa.h>
//#import <VVBasics/VVBasics.h>
#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/AudioHardware.h>
#import <CoreAudio/CoreAudioTypes.h>


/*
	This is a simple wrapper for an audio channel layout object
*/


@interface VVAudioChannelLayout : NSObject	{

	AudioChannelLayout			*audioChannelLayout;
	UInt32						channelLayoutSize;

}

//	this creates a wrapper for an existing channel layout
//		the layout will be freed when this object is released
+ (instancetype) createWithAudioChannelLayout:(AudioChannelLayout *)acl layoutSize:(UInt32)size;
- (instancetype) initWithAudioChannelLayout:(AudioChannelLayout *)acl layoutSize:(UInt32)size;

//	this creates a copy from an existing channel layout
//		this is useful if the channel layout is 'owned' by something else that might free it, or might be unhappy if we free it
+ (instancetype) createWithCopyFromAudioChannelLayout:(AudioChannelLayout *)acl layoutSize:(UInt32)size;
- (instancetype) initWithCopyFromAudioChannelLayout:(AudioChannelLayout *)acl layoutSize:(UInt32)size;

//	this creates from a data blob
+ (instancetype) createWithData:(NSData *) d;
- (instancetype) initWithData:(NSData *) d;

+ (instancetype) createWithPreferredLayoutForChannelCount:(int)count;
- (instancetype) initWithPreferredLayoutForChannelCount:(int)count;

+ (instancetype) createWithAudioChannelLayoutTag:(AudioChannelLayoutTag)tag;
- (instancetype) initWithAudioChannelLayoutTag:(AudioChannelLayoutTag)tag;

+ (instancetype) createWithChannelDescriptionsForChannelCount:(int)count; 
- (instancetype) initWithChannelDescriptionsForChannelCount:(int)count;

- (AudioChannelLayout *) audioChannelLayout;
- (UInt32) channelLayoutSize;
- (NSData *) audioChannelLayoutAsData;

//	this sets the wrapper around an audio channel layout that we are now responsible to free
- (void) _setAudioChannelLayout:(AudioChannelLayout *) acl layoutSize:(int)size;

//	this creates a copy that we are responsible to free
- (void) _copyAudioChannelLayout:(AudioChannelLayout *) acl layoutSize:(int)size;

//	note that technically this creates a new block of memory and writes into it, effectively making a copy we are responsible to free
- (void) _setAudioChannelLayoutFromData:(NSData *)d;

@end
