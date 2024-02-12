//
//  HapMTKView.m
//  HapInAVF Test App
//
//  Created by testadmin on 6/8/23.
//  Copyright © 2023 Vidvox. All rights reserved.
//

#import "HapMTKView.h"
#import "HapMTKViewShaderTypes.h"




//	here are a bunch of simple macros for doing some basic 2D geometric ops on NSRect/CGRect structures
#define VVPOINT NSPoint
#define VVMAKEPOINT NSMakePoint
#define VVRECT NSRect
#define VVMAKERECT NSMakeRect
#define VVSIZE NSSize
#define VVADDPOINT(a,b) (VVMAKEPOINT((a.x+b.x),(a.y+b.y)))
#define VVSUBPOINT(a,b) (VVMAKEPOINT((a.x-b.x),(a.y-b.y)))
//	when we're creating, moving, and sizing rects, it's useful to be able to specify the operations relative to anchor points on the rects.
typedef NS_ENUM(NSUInteger, VVRectAnchor)	{
	VVRectAnchor_Center = 0,
	VVRectAnchor_TL,	//	top-left corner
	VVRectAnchor_TR,	//	top-right corner
	VVRectAnchor_BL,	//	bottom-left corner
	VVRectAnchor_BR,	//	bottom-right corner
	VVRectAnchor_TM,	//	middle of top top side
	VVRectAnchor_RM,	//	middle of right side
	VVRectAnchor_BM,	//	middle of bottom side
	VVRectAnchor_LM		//	middle of left side
};
//	these functions express rectangles using the above anchor point concept
static inline VVPOINT VVRectGetAnchorPoint(VVRECT inRect, VVRectAnchor inAnchor);
//	the function definitions
static inline VVPOINT VVRectGetAnchorPoint(VVRECT inRect, VVRectAnchor inAnchor)	{
	VVPOINT		returnMe = inRect.origin;
	switch (inAnchor)	{
	case VVRectAnchor_Center:
		returnMe = VVADDPOINT( inRect.origin, VVMAKEPOINT(inRect.size.width/2.,inRect.size.height/2.) );
		break;
	case VVRectAnchor_TL:
		returnMe = VVADDPOINT( inRect.origin, VVMAKEPOINT(0., inRect.size.height) );
		break;
	case VVRectAnchor_TR:
		returnMe = VVADDPOINT( inRect.origin, VVMAKEPOINT(inRect.size.width, inRect.size.height) );
		break;
	case VVRectAnchor_BL:
		//	do nothing- rect's origin is already the bottom left!
		break;
	case VVRectAnchor_BR:
		returnMe = VVADDPOINT( inRect.origin, VVMAKEPOINT(inRect.size.width, 0.) );
		break;
	case VVRectAnchor_TM:
		returnMe = VVADDPOINT( inRect.origin, VVMAKEPOINT(inRect.size.width/2., inRect.size.height) );
		break;
	case VVRectAnchor_RM:
		returnMe = VVADDPOINT( inRect.origin, VVMAKEPOINT(inRect.size.width, inRect.size.height/2.) );
		break;
	case VVRectAnchor_BM:
		returnMe = VVADDPOINT( inRect.origin, VVMAKEPOINT(inRect.size.width/2., 0.) );
		break;
	case VVRectAnchor_LM:
		returnMe = VVADDPOINT( inRect.origin, VVMAKEPOINT(0., inRect.size.height/2.) );
		break;
	}
	return returnMe;
}





@interface HapMTKView ()
@property (strong,nullable) HapMTLPixelBufferTexture * hapTexToDisplay;
@property (assign,nullable) CVMetalTextureRef cvTexToDisplay;
@property (readwrite) BOOL flipV;

@property (strong,readwrite,nullable) id<MTLRenderPipelineState> pso;
@property (strong,readwrite) id<MTLCommandQueue> commandQueue;
@property (readwrite) CGSize viewportSize;
@property (strong) id<MTLBuffer> mvpBuffer;
- (void) reloadRenderingResources;
@end




@implementation HapMTKView


- (void) awakeFromNib	{
	self.device = MTLCreateSystemDefaultDevice();
}


- (void) displayPixelBufferTexture:(HapMTLPixelBufferTexture *)n flipped:(BOOL)inFlipped	{
	if (n == nil)
		return;
	@synchronized (self)	{
		_hapTexToDisplay = nil;
		if (_cvTexToDisplay != NULL)	{
			CVBufferRelease(_cvTexToDisplay);
			_cvTexToDisplay = NULL;
		}
		
		_hapTexToDisplay = n;
		_flipV = inFlipped;
	}
}
- (void) displayCVMetalTextureRef:(CVMetalTextureRef)n flipped:(BOOL)inFlipped	{
	if (n == NULL)
		return;
	@synchronized (self)	{
		_hapTexToDisplay = nil;
		if (_cvTexToDisplay != NULL)	{
			CVBufferRelease(_cvTexToDisplay);
			_cvTexToDisplay = NULL;
		}
		
		_cvTexToDisplay = CVBufferRetain(n);
		_flipV = inFlipped;
	}
}


- (void) drawRect:(NSRect)dirtyRect	{
	//NSLog(@"%s",__func__);
	
	//	get a local copy of the mvpBuffer and our various texture-related properties
	id<MTLDevice>		device = self.device;
	HapMTLPixelBufferTexture		*hapTexToDisplay = nil;
	CVMetalTextureRef	cvTexToDisplay = NULL;
	BOOL				flipV = NO;
	CGSize				viewportSize = CGSizeMake(4,4);
	id<MTLBuffer>		mvpBuffer = nil;
	id<MTLTexture>		textureA = nil;
	id<MTLTexture>		textureB = nil;
	id<MTLRenderPipelineState>		localPSO;
	
	@synchronized (self)	{
		hapTexToDisplay = self.hapTexToDisplay;
		cvTexToDisplay = self.cvTexToDisplay;
		if (cvTexToDisplay != NULL)
			CVBufferRetain(cvTexToDisplay);
		flipV = self.flipV;
		viewportSize = self.viewportSize;
		
		if (_mvpBuffer == nil)	{
			double			left = 0.0;
			double			right = viewportSize.width;
			double			top = viewportSize.height;
			double			bottom = 0.0;
			double			far = 1.0;
			double			near = -1.0;
			BOOL		invertV = YES;
			BOOL		invertH = NO;
			if (invertV)	{
				top = 0.0;
				bottom = viewportSize.height;
			}
			if (invertH)	{
				right = 0.0;
				left = viewportSize.width;
			}
			matrix_float4x4			mvp = simd_matrix_from_rows(
				//	left-handed coordinate ortho!
				//simd_make_float4(	2.0/(right-left),	0.0,				0.0,				(right+left)/(left-right) ),
				//simd_make_float4(	0.0,				2.0/(top-bottom),	0.0,				(top+bottom)/(bottom-top) ),
				//simd_make_float4(	0.0,				0.0,				2.0/(far-near),	(near)/(near-far) ),
				//simd_make_float4(	0.0,				0.0,				0.0,				1.0 )
				
				//	right-handed coordinate ortho!
				simd_make_float4(	2.0/(right-left),	0.0,				0.0,				(right+left)/(left-right) ),
				simd_make_float4(	0.0,				2.0/(top-bottom),	0.0,				(top+bottom)/(bottom-top) ),
				simd_make_float4(	0.0,				0.0,				-2.0/(far-near),	(near)/(near-far) ),
				simd_make_float4(	0.0,				0.0,				0.0,				1.0 )
				
			);
			_mvpBuffer = [device newBufferWithBytes:&mvp length:sizeof(mvp) options:MTLResourceStorageModeShared];
		}
		//	get a local handle to the property's underlying data buffer to work with for this render pass
		mvpBuffer = _mvpBuffer;
		localPSO = self.pso;
	}
	
	//	if we're here and we don't have a texture or anything to display, just bail immediately
	if (hapTexToDisplay == nil && cvTexToDisplay == NULL)	{
		//NSLog(@"nothing to display, %s",__func__);
		return;
	}
	CGSize			imageSize;
	CGRect			imgRect;
	if (hapTexToDisplay != nil)	{
		imageSize = hapTexToDisplay.imgSize;
		imgRect = CGRectMake( 0, 0, imageSize.width, imageSize.height );
	}
	else if (cvTexToDisplay != nil)	{
		//	...this is the only way i could figure to get the dims of the texture- non of the CoreVideo-provided functions for querying properties of CVMetalTextureRef/CVImageBufferRef returned accurate values.
		id<MTLTexture>		backingTexture = CVMetalTextureGetTexture(cvTexToDisplay);
		imageSize = CGSizeMake(backingTexture.width, backingTexture.height);
		imgRect = CGRectMake( 0, 0, imageSize.width, imageSize.height );
		backingTexture = nil;
	}
	
	
	
#define CAPTURE 0
#if CAPTURE
	MTLCaptureManager		*cm = nil;
	static int				counter = 0;
	++counter;
	if (counter == 10)
		cm = [MTLCaptureManager sharedCaptureManager];
	MTLCaptureDescriptor		*desc = [[MTLCaptureDescriptor alloc] init];
	desc.captureObject = self.commandQueue;
	
	if (cm != nil)	{
		if ([cm startCaptureWithDescriptor:desc error:nil])	{
			NSLog(@"SUCCESS: started capturing metal data");
		}
		else	{
			NSLog(@"ERR: couldn't start capturing metal data");
		}
	}
	else	{
	}
#endif
	
	
	//	make a command buffer, get the current drawable
	id<MTLCommandBuffer>	cmdBuffer = [self commandBuffer];
	id<CAMetalDrawable>		currentDrawable = self.currentDrawable;
	
	//	make the render encoder!
	MTLRenderPassDescriptor		*passDesc = [MTLRenderPassDescriptor new];
	passDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
	passDesc.colorAttachments[0].clearColor = MTLClearColorMake(1, 0, 0, 1);
	passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
	passDesc.colorAttachments[0].texture = currentDrawable.texture;
	id<MTLRenderCommandEncoder>		renderEncoder = [cmdBuffer renderCommandEncoderWithDescriptor:passDesc];
	[renderEncoder setRenderPipelineState:localPSO];
	
	//	calculate the rect in which the texture will draw in our local bounds- this will form the basis of our geometry
	NSRect			drawRect = NSZeroRect;
	double			dstAspect = viewportSize.width/viewportSize.height;
	double			srcAspect = imageSize.width/imageSize.height;
	if (dstAspect > srcAspect)	{
		drawRect.size.height = viewportSize.height;
		drawRect.size.width = drawRect.size.height * srcAspect;
	}
	else if (dstAspect < srcAspect)	{
		drawRect.size.width = viewportSize.width;
		drawRect.size.height = drawRect.size.width / srcAspect;
	}
	else	{
		drawRect.size = NSMakeSize(viewportSize.width, viewportSize.height);
	}
	drawRect.origin.x = (viewportSize.width-drawRect.size.width)/2.;
	drawRect.origin.y = (viewportSize.height-drawRect.size.height)/2.;
	
	//	populate some vertexes with the geometry + texture coords.  we'll be drawing a quad using triangle strip primitives, so we need 4 vertices.
	HapMTKViewVertex		verts[4];	//	order is TL, BL, TR, BR
	VVRectAnchor			anchors[] = { VVRectAnchor_TL, VVRectAnchor_BL, VVRectAnchor_TR, VVRectAnchor_BR };
	VVRectAnchor			flipVAnchors[] = { VVRectAnchor_BL, VVRectAnchor_TL, VVRectAnchor_BR, VVRectAnchor_TR };
	for (int i=0; i<4; ++i)	{
		const CGPoint		tmpGeo = VVRectGetAnchorPoint( drawRect, anchors[i] );
		const CGPoint		tmpTex = (flipV) ? VVRectGetAnchorPoint( imgRect, flipVAnchors[i] ) : VVRectGetAnchorPoint( imgRect, anchors[i] );
		verts[i].geometry = simd_make_float2(tmpGeo.x, tmpGeo.y);
		verts[i].texCoord = simd_make_float2(tmpTex.x, tmpTex.y);
	}
	[renderEncoder setVertexBytes:verts length:sizeof(verts) atIndex:HapMTKViewVSIndex_VertexData];
	
	//	make an image description struct, populate it such that it describes the image we're asking the shader to describe
	HapMTKViewImageDescription		imageDesc;
	if (hapTexToDisplay != nil)	{
		switch (hapTexToDisplay.codecSubType)	{
		case kHapCodecSubType:			imageDesc.imageType = HapMTKViewImageType_Sampleable;		break;
		case kHapAlphaCodecSubType:		imageDesc.imageType = HapMTKViewImageType_Sampleable;		break;
		case kHapYCoCgCodecSubType:		imageDesc.imageType = HapMTKViewImageType_YCoCg;			break;
		case kHapYCoCgACodecSubType:	imageDesc.imageType = HapMTKViewImageType_YCoCgA;			break;
		case kHapAOnlyCodecSubType:		imageDesc.imageType = HapMTKViewImageType_Sampleable;		break;
		case kHap7AlphaCodecSubType:	imageDesc.imageType = HapMTKViewImageType_Sampleable;		break;
		case kHapHDRRGBCodecSubType:	imageDesc.imageType = HapMTKViewImageType_Sampleable;		break;
		}
		
		textureA = hapTexToDisplay.textureA;
		textureB = hapTexToDisplay.textureB;
		if (textureB == nil)
			textureB = textureA;
	}
	else if (cvTexToDisplay != NULL)	{
		imageDesc.imageType = HapMTKViewImageType_Sampleable;
		textureA = CVMetalTextureGetTexture(cvTexToDisplay);
		textureB = textureA;
	}
	
	//	only proceed if we have a texture to display
	if (textureA != nil || textureB != nil)	{
		[renderEncoder setFragmentBytes:&imageDesc length:sizeof(imageDesc) atIndex:HapMTKViewFSIndex_ImageDescription];
		
		//	attach the buffer(s) and texture(s) we'll be drawing to the render encoder
		[renderEncoder setVertexBuffer:mvpBuffer offset:0 atIndex:HapMTKViewVSIndex_MVPMatrix];
		[renderEncoder setFragmentTexture:textureA atIndex:HapMTKViewFSIndex_TextureA];
		[renderEncoder setFragmentTexture:textureB atIndex:HapMTKViewFSIndex_TextureB];
		
		//	ensure the encoder has been explicitly made aware when and where it needs to use the various buffer data
		[renderEncoder useResource:mvpBuffer usage:MTLResourceUsageRead stages:MTLRenderStageVertex];
		[renderEncoder useResource:textureA usage:MTLResourceUsageRead stages:MTLRenderStageFragment];
		[renderEncoder useResource:textureB usage:MTLResourceUsageRead stages:MTLRenderStageFragment];
		
		//	ensure that the various resources we'll use aren't released during render
		[cmdBuffer addCompletedHandler:^(id<MTLCommandBuffer> completedCB)	{
			//	make sure the texture's we're working with are properly displayed...
			HapMTLPixelBufferTexture		*tmpTex = hapTexToDisplay;
			tmpTex = nil;
			if (cvTexToDisplay != NULL)	{
				CVBufferRelease(cvTexToDisplay);
			}
			//	make sure the mvp buffer's retained...
			id<MTLBuffer>		tmpMVPBuffer = mvpBuffer;
			tmpMVPBuffer = nil;
		}];
		
		//	draw the vertices!
		[renderEncoder
			drawPrimitives:MTLPrimitiveTypeTriangleStrip
			vertexStart:0
			vertexCount:4];
	}
	
	//	we're done- end encoding, present the drawable, and then commit the command buffer
	[renderEncoder endEncoding];
	[cmdBuffer presentDrawable:currentDrawable];
	[cmdBuffer commit];
	
#if CAPTURE
	if (cm != nil)	{
		NSLog(@"STOPPING CAPTURE, WAITING TO BE COMPLETE...");
		[cm stopCapture];
		[cmdBuffer waitUntilCompleted];
	}
#endif
}


- (void) reloadRenderingResources	{
	@synchronized (self)	{
		NSError				*nsErr = nil;
		NSBundle			*myBundle = [NSBundle bundleForClass:[self class]];
		id<MTLLibrary>		defaultLibrary = [self.device newDefaultLibraryWithBundle:myBundle error:&nsErr];
		if (defaultLibrary==nil || nsErr != nil)
			NSLog(@"ERR: (%@) acquiring new default lib in %s",nsErr,__func__);
		id<MTLFunction>		vertFunc = [defaultLibrary newFunctionWithName:@"HapMTKViewVertShader"];
		id<MTLFunction>		fragFunc = [defaultLibrary newFunctionWithName:@"HapMTKViewFragShader"];
	
		MTLRenderPipelineDescriptor		*psDesc = [[MTLRenderPipelineDescriptor alloc] init];
		//psDesc.previewLabel = @"VVMTLImgBufferView pipeline";
		psDesc.vertexFunction = vertFunc;
		psDesc.fragmentFunction = fragFunc;
		psDesc.colorAttachments[0].pixelFormat = self.colorPixelFormat;
		
		//	commented out- this was an attempt to make MTLImgBufferRectView "transparent" (0 alpha would display view behind it)
		psDesc.alphaToCoverageEnabled = NO;
		psDesc.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
		psDesc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
		//psDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
		//psDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
		psDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
		psDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
		psDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
		psDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
		psDesc.colorAttachments[0].blendingEnabled = YES;
	
		self.pso = [self.device newRenderPipelineStateWithDescriptor:psDesc error:&nsErr];
		if (_pso==nil || nsErr != nil)
			NSLog(@"ERR: (%@) while making new pso in %s",nsErr,__func__);
		
		self.commandQueue = [self.device newCommandQueue];
		
		NSWindow		*tmpWin = self.window;
		NSScreen		*tmpScreen = tmpWin.screen;
		CGFloat			scale = tmpScreen.backingScaleFactor;
		CGSize			viewportSize = self.bounds.size;
		viewportSize.width *= scale;
		viewportSize.height *= scale;
		self.viewportSize = viewportSize;
		
		self.mvpBuffer = nil;
		CGColorSpaceRef		cs = CGColorSpaceCreateDeviceRGB();
		self.colorspace = cs;
		CGColorSpaceRelease(cs);
		
		self.clearColor = MTLClearColorMake(0., 0., 1., 1.);
	}
}


- (id<MTLCommandBuffer>) commandBuffer	{
	@synchronized (self)	{
		return [self.commandQueue commandBuffer];
	}
}


// Disable internal timer clock with these two methods
- (BOOL) enableSetNeedsDisplay	{
	return YES;
}
- (BOOL) isPaused	{
	return YES;
}
- (void) setDevice:(id<MTLDevice>)n	{
	BOOL		changed = (self.device != n);
	[super setDevice:n];
	if (changed)	{
		[self reloadRenderingResources];
	}
}


- (void) viewDidMoveToWindow	{
	[super viewDidMoveToWindow];
	[self reloadRenderingResources];
}
- (void) viewDidChangeBackingProperties	{
	//NSLog(@"%s ... %@",__func__,self);
	[super viewDidChangeBackingProperties];
	[self reloadRenderingResources];
}
- (void) setFrameSize:(NSSize)n	{
	[super setFrameSize:n];
	[self reloadRenderingResources];
}
- (void) setBoundsSize:(NSSize)n	{
	[super setBoundsSize:n];
	[self reloadRenderingResources];
}


@end
