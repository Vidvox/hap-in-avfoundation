//
//  HapMetalDXTDecoder.m
//  HapInAVFoundation
//
//  Created by testadmin on 2/16/24.
//  Copyright © 2024 Vidvox. All rights reserved.
//

#import "HapMetalDXTDecoder.h"
#import <simd/simd.h>




@interface HapMetalDXTDecoder ()
@property (strong) id<MTLDevice> device;
@property (strong) id<MTLComputePipelineState> pso;
@end




@implementation HapMetalDXTDecoder

+ (instancetype) createWithDevice:(id<MTLDevice>)n	{
	return [[HapMetalDXTDecoder alloc] initWithDevice:n];
}

- (instancetype) initWithDevice:(id<MTLDevice>)n	{
	self = [super init];
	if (n == nil)
		self = nil;
	if (self != nil)	{
		self.device = n;
		
		NSError		*nsErr = nil;
		id<MTLLibrary>		defaultLib = [self.device newDefaultLibraryWithBundle:[NSBundle bundleForClass:self.class] error:&nsErr];
		if (defaultLib == nil)	{
			NSLog(@"ERR: (%@) making default lib in %s",nsErr,__func__);
			self = nil;
			return self;
		}
		
		id<MTLFunction>		func = [defaultLib newFunctionWithName:@"HapMetalBC7toRGBA"];
		if (func == nil)	{
			NSLog(@"ERR: unable to locate function in %s",__func__);
			self = nil;
			return self;
		}
		
		self.pso = [self.device
			newComputePipelineStateWithFunction:func
			error:&nsErr];
		if (self.pso == nil)	{
			NSLog(@"ERR: (%@) unable to make PSO in %s",nsErr,__func__);
			self = nil;
			return self;
		}
	}
	return self;
}

- (void) decodeTexture:(id<MTLTexture>)srcTex toBuffer:(id<MTLBuffer>)dstBuffer bufferImageSize:(NSSize)inDstSize bufferBytesPerRow:(uint32_t)inDstBytesPerRow bufferPixelFormat:(MTLPixelFormat)inDstPixelFormat inCommandBuffer:(id<MTLCommandBuffer>)cb	{
	if (cb == nil)	{
		NSLog(@"ERR: cmd buffer nil in %s",__func__);
		return;
	}
	if (srcTex==nil || dstBuffer==nil)	{
		NSLog(@"ERR: src (%@) or dst (%@) missing in %s",srcTex,dstBuffer,__func__);
		return;
	}
	
	id<MTLComputeCommandEncoder>	encoder = [cb computeCommandEncoder];
	[encoder setComputePipelineState:self.pso];
	[encoder setTexture:srcTex atIndex:0];
	[encoder setBuffer:dstBuffer offset:0 atIndex:0];
	[encoder setBytes:&inDstBytesPerRow length:sizeof(inDstBytesPerRow) atIndex:1];
	vector_uint2		dstRes = simd_make_uint2( round(inDstSize.width), round(inDstSize.height) );
	[encoder setBytes:&dstRes length:sizeof(dstRes) atIndex:2];
	bool		dstBGRAFlag = (inDstPixelFormat == MTLPixelFormatBGRA8Unorm);
	[encoder setBytes:&dstBGRAFlag length:sizeof(dstBGRAFlag) atIndex:3];
	
	NSUInteger		threadGroupDimension = (NSUInteger)sqrt( (double)self.pso.maxTotalThreadsPerThreadgroup );
	MTLSize		threadGroupSize = MTLSizeMake( threadGroupDimension, threadGroupDimension, 1 );	//	threadGroupSize.width * threadGroupSize.height * threadGroupSize.depth MUST BE <= max total threads per threadgroup!
	MTLSize		shaderEvalSize = MTLSizeMake( 2, 2, 1 );	//	we're going to use 'gather' to fetch 2x2 blocks of pixels from the source texture (four reads/writes per shader invocation)
	
	MTLSize		numGroups = MTLSizeMake(
		srcTex.width / shaderEvalSize.width / threadGroupDimension + 1,
		srcTex.height / shaderEvalSize.height / threadGroupDimension + 1,
		1);
	
	[encoder dispatchThreadgroups:numGroups threadsPerThreadgroup:threadGroupSize];
	
	[encoder endEncoding];
}


@end
