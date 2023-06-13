//
//  HapMTLDecoderFrame.m
//  HapInAVF Test App
//
//  Created by testadmin on 6/8/23.
//  Copyright © 2023 Vidvox. All rights reserved.
//

#import "HapMTLDecoderFrame.h"




@interface HapMTLDecoderFrame ()
@property (strong) id<MTLTexture> textureA;
@property (strong) id<MTLTexture> textureB;
@end




@implementation HapMTLDecoderFrame


- (instancetype) initWithDevice:(id<MTLDevice>)d hapSampleBuffer:(CMSampleBufferRef)sb	{
	self = [super initEmptyWithHapSampleBuffer:sb];
	
	if (d == nil)
		self = nil;
	
	if (self != nil)	{
		//	figure out how many textures we need to make and make them
		//	populate the various dxt-related data and size vars
	}
	
	return self;
}


- (instancetype) initWithHapSampleBuffer:(CMSampleBufferRef)sb	{
	return nil;
}

- (instancetype) initEmptyWithHapSampleBuffer:(CMSampleBufferRef)sb	{
	return nil;
}


@end
