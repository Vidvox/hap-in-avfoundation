#import <Cocoa/Cocoa.h>
#import <OpenGL/OpenGL.h>
#import <AVFoundation/AVFoundation.h>
#import <HapInAVFoundation/HapInAVFoundation.h>
#import "GLView.h"
#import "HapGLPixelBufferTexture.h"
#import "HapMTLPixelBufferTexture.h"
#import "HapMTKView.h"




@interface HapInAVFTestAppDelegate : NSObject <NSApplicationDelegate,NSTabViewDelegate> {
	CVDisplayLinkRef			displayLink;	//	this "drives" rendering
	NSOpenGLContext				*sharedContext; //	all GL contexts share this, so textures from one contact can be used in others
	IBOutlet NSWindow			*window;
	IBOutlet NSTabView			*tabView;
	IBOutlet GLView				*glView;
	IBOutlet NSImageView		*imgView;
	IBOutlet HapMTKView			*metalView;
	IBOutlet NSTextField		*statusField;
	
	AVPlayer					*player;
	AVPlayerItem				*playerItem;
	AVPlayerItemVideoOutput		*nativeAVFOutput;	//	this video output is used to play back non-hap content
	AVPlayerItemHapDXTOutput	*hapPlayerOutput; //	works similarly to "nativeAVFOutput"- it's a subclass of AVPlayerItemOutput, you add it to a player item and ask it for new frames (instances of HapDecoderFrame)
	
	NSOpenGLContext				*glTexCacheContext;	//	this and the associated texture cache are used to create GL textures from non-hap content played back by AVFoundation
	CVOpenGLTextureCacheRef		glTexCache;
	
	HapGLPixelBufferTexture		*hapGLTexture;	//	this class uploads the DXT data in a decoded instance of HapDecoderFrame into a GL texture.	 this is also where the shader that draws YCoCg DXT data as RGB is loaded.	this class was copied from the hap/quicktime sample app
	
	id<MTLCommandQueue>			hapTexUploadQueue;
	//	this class uploads the DXT data in a decoded instance of HapDecoderFrame into an id<MTLTexture>.
	HapMTLPixelBufferTexture	*hapMTLTexture;
	//	when we're done with 'hapMTLTexture' we stick it in this array (and when we need a new one, we try to pull from this array first).  functions as crude texture pool to minimize asset creation at runtime.
	NSMutableArray<HapMTLPixelBufferTexture*>	*hapMTLTextures;
}

- (void) loadFileAtPath:(NSString *)n;
- (void) renderCallback;
- (void) itemDidPlayToEnd:(NSNotification *)note;

- (NSOpenGLPixelFormat *) createGLPixelFormat;

- (void) poolFreedPixelBufferTexture:(HapMTLPixelBufferTexture *)n;
- (HapMTLPixelBufferTexture *) getHapMTLPixelBufferTexture;

@end




CVReturn displayLinkCallback(CVDisplayLinkRef displayLink, const CVTimeStamp *inNow, const CVTimeStamp *inOutputTime, CVOptionFlags flagsIn, CVOptionFlags *flagsOut, void *displayLinkContext);
void pixelBufferReleaseCallback(void *releaseRefCon, const void *baseAddress);
