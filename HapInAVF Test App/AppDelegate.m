#import "AppDelegate.h"
#import <OpenGL/CGLMacro.h>




@implementation AppDelegate


- (id) init	{
	self = [super init];
	if (self!=nil)	{
		displayLink = NULL;
		sharedContext = [[NSOpenGLContext alloc] initWithFormat:[self createGLPixelFormat] shareContext:nil];
		player = [[AVPlayer alloc] initWithPlayerItem:nil];
		[player setActionAtItemEnd:AVPlayerActionAtItemEndPause];
		[player play];
		playerItem = nil;
		texCacheContext = [[NSOpenGLContext alloc] initWithFormat:[self createGLPixelFormat] shareContext:sharedContext];
		texCache = NULL;
		nativeAVFOutput = nil;
		hapTexture = nil;
		hapOutput = nil;
		
		CVReturn		err = CVOpenGLTextureCacheCreate(kCFAllocatorDefault,
			NULL,
			[texCacheContext CGLContextObj],
			[[self createGLPixelFormat] CGLPixelFormatObj],
			NULL,
			&texCache);
		if (err!=kCVReturnSuccess)
			NSLog(@"\t\terr %d at CVOpenGLTextureCacheCreate()",err);
		
	}
	return self;
}
- (void) awakeFromNib	{
	@synchronized (self)	{
		//	configure the GL view to use a shared GL context, so it can draw the textures we upload to other contexts
		NSOpenGLContext		*newCtx = [[[NSOpenGLContext alloc] initWithFormat:[self createGLPixelFormat] shareContext:sharedContext] autorelease];
		[glView setOpenGLContext:newCtx];
		[newCtx setView:glView];
		[glView reshape];
	}
	
	//	make the displaylink, which will drive rendering
	CVReturn				err = kCVReturnSuccess;
	CGOpenGLDisplayMask		totalDisplayMask = 0;
	GLint					virtualScreen = 0;
	GLint					displayMask = 0;
	NSOpenGLPixelFormat		*format = [self createGLPixelFormat];
	
	for (virtualScreen=0; virtualScreen<[format numberOfVirtualScreens]; ++virtualScreen)	{
		[format getValues:&displayMask forAttribute:NSOpenGLPFAScreenMask forVirtualScreen:virtualScreen];
		totalDisplayMask |= displayMask;
	}
	err = CVDisplayLinkCreateWithOpenGLDisplayMask(totalDisplayMask, &displayLink);
	if (err)	{
		NSLog(@"\t\terr %d creating display link in %s",err,__func__);
		displayLink = NULL;
	}
	else	{
		CVDisplayLinkSetOutputCallback(displayLink, displayLinkCallback, self);
		CVDisplayLinkStart(displayLink);
	}
}
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	
}
- (void)applicationWillTerminate:(NSNotification *)aNotification {
}


- (void) openDocument:(id)sender	{
	NSOpenPanel		*openPanel = [[NSOpenPanel openPanel] retain];
	NSUserDefaults	*def = [NSUserDefaults standardUserDefaults];
	NSString		*openPanelDir = [def objectForKey:@"openPanelDir"];
	if (openPanelDir==nil)
		openPanelDir = [@"~/" stringByExpandingTildeInPath];
	[openPanel setDirectoryURL:[NSURL fileURLWithPath:openPanelDir]];
	[openPanel
		beginSheetModalForWindow:window
		completionHandler:^(NSInteger result)	{
			NSString		*path = (result!=NSFileHandlingPanelOKButton) ? nil : [[openPanel URL] path];
			if (path != nil)	{
				NSUserDefaults		*udef = [NSUserDefaults standardUserDefaults];
				[udef setObject:[path stringByDeletingLastPathComponent] forKey:@"openPanelDir"];
				[udef synchronize];
			}
			//[self loadFileAtPath:path];
			dispatch_async(dispatch_get_main_queue(), ^{
				[self loadFileAtPath:path];
			});
			[openPanel release];
		}];
}


- (void) loadFileAtPath:(NSString *)n	{
	NSLog(@"%s ... %@",__func__,n);
	//	make an asset
	NSURL				*newURL = (n==nil) ? nil : [NSURL fileURLWithPath:n];
	AVAsset				*newAsset = (newURL==nil) ? nil : [AVAsset assetWithURL:newURL];
	//	make a player item
	AVPlayerItem		*newPlayerItem = (newAsset==nil) ? nil : [[[AVPlayerItem alloc] initWithAsset:newAsset] autorelease];
	if (newPlayerItem == nil)	{
		NSLog(@"\t\terr: couldn't make AVPlayerItem in %s",__func__);
		return;
	}
	//	update the status label
	NSArray				*vidTracks = [newAsset tracksWithMediaType:AVMediaTypeVideo];
	for (AVAssetTrack *trackPtr in vidTracks)	{
		NSArray					*trackFormatDescs = [trackPtr formatDescriptions];
		CMFormatDescriptionRef	desc = (trackFormatDescs==nil || [trackFormatDescs count]<1) ? nil : (CMFormatDescriptionRef)[trackFormatDescs objectAtIndex:0];
		if (desc==nil)
			NSLog(@"\t\terr: desc nil in %s",__func__);
		else	{
			OSType		fourcc = CMFormatDescriptionGetMediaSubType(desc);
			char		destChars[5];
			destChars[0] = (fourcc>>24) & 0xFF;
			destChars[1] = (fourcc>>16) & 0xFF;
			destChars[2] = (fourcc>>8) & 0xFF;
			destChars[3] = (fourcc) & 0xFF;
			destChars[4] = 0;
			[statusField setStringValue:[NSString stringWithFormat:@"codec sub-type is '%@'",[NSString stringWithCString:destChars encoding:NSASCIIStringEncoding]]];
			break;
		}
	}
	
	@synchronized (self)	{
		//	if there's an output, remove it from the "old" item
		if (nativeAVFOutput != nil)	{
			if (playerItem != nil)
				[playerItem removeOutput:nativeAVFOutput];
		}
		//	else there's no output- create one
		else	{
			NSDictionary				*pba = [NSDictionary dictionaryWithObjectsAndKeys:
				//NUMINT(kCVPixelFormatType_422YpCbCr8), kCVPixelBufferPixelFormatTypeKey,
				//NUMINT(kCVPixelFormatType_32BGRA), kCVPixelBufferPixelFormatTypeKey,
				//NUMINT(FOURCC_PACK('D','X','t','1')), kCVPixelBufferPixelFormatTypeKey,
				[NSNumber numberWithBool:YES], kCVPixelBufferIOSurfaceOpenGLFBOCompatibilityKey,
				//NUMINT(dims.width), kCVPixelBufferWidthKey,
				//NUMINT(dims.height), kCVPixelBufferHeightKey,
				nil];
			nativeAVFOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pba];
			[nativeAVFOutput setSuppressesPlayerRendering:YES];
		}
		
		//	if there's a hap output, remove it from the "old" item
		if (hapOutput != nil)	{
			if (playerItem != nil)
				[playerItem removeOutput:hapOutput];
		}
		//	else there's no hap output- create one
		else	{
			hapOutput = [[AVPlayerItemHapDXTOutput alloc] init];
			[hapOutput setSuppressesPlayerRendering:YES];
		}
		
		//	unregister as an observer for the "old" item's play-to-end notifications
		NSNotificationCenter	*nc = [NSNotificationCenter defaultCenter];
		if (playerItem != nil)
			[nc removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:playerItem];
		
		//	add the outputs to the new player item
		[newPlayerItem addOutput:nativeAVFOutput];
		[newPlayerItem addOutput:hapOutput];
		//	tell the player to start playing the new player item
		if ([NSThread isMainThread])
			[player replaceCurrentItemWithPlayerItem:newPlayerItem];
		else
			[player performSelectorOnMainThread:@selector(replaceCurrentItemWithPlayerItem:) withObject:newPlayerItem waitUntilDone:YES];
		//	register to receive notifications that the new player item has played to its end
		if (newPlayerItem != nil)
			[nc addObserver:self selector:@selector(itemDidPlayToEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:newPlayerItem];
		
		//	release the "old" player item, retain a ptr to the "new" player item
		if (playerItem!=nil)
			[playerItem release];
		playerItem = (newPlayerItem==nil) ? nil : [newPlayerItem retain];
		
		[player setRate:1.0];
	}
}
//	this is called by the displaylink's C callback- this drives rendering
- (void) renderCallback	{
	@synchronized (self)	{
		//	try to get a hap decoder frame- it returns a nil quickly if the player it's attached to doesn't have a hap track.
		HapDecoderFrame			*dxtFrame = [hapOutput allocFrameClosestToTime:[hapOutput itemTimeForMachAbsoluteTime:mach_absolute_time()]];
		if (dxtFrame!=nil)	{
			//	if there's no hap texture, make one
			if (hapTexture==nil)	{
				CGLContextObj		newCtx = NULL;
				CGLError			err = CGLCreateContext([[self createGLPixelFormat] CGLPixelFormatObj], [sharedContext CGLContextObj], &newCtx);
				if (err!=kCGLNoError)
					NSLog(@"\t\terr %u at CGLCreateContext() in %s",err,__func__);
				else	{
					hapTexture = [[HapPixelBufferTexture alloc] initWithContext:newCtx];
					if (hapTexture==nil)
						NSLog(@"\t\terr: couldn't create HapPixelBufferContext in %s",__func__);
					CGLReleaseContext(newCtx);
				}
			}
			if (hapTexture!=nil)	{
				//	make a CVPixelBufferRef from the dxt frame i got from the decoder (the pixel buffer ref actually retains the dxt frame)
				CVPixelBufferRef		cvpb = NULL;
				NSSize					imgSize = [dxtFrame imgSize];
				NSSize					dxtImgSize = [dxtFrame dxtImgSize];
				NSSize					dxtTexSize;
				int						tmpInt;
				tmpInt = 1;
				while (tmpInt < dxtImgSize.width)
					tmpInt = tmpInt<<1;
				dxtTexSize.width = tmpInt;
				tmpInt = 1;
				while (tmpInt < dxtImgSize.height)
					tmpInt = tmpInt<<1;
				dxtTexSize.height = tmpInt;
				size_t					dxtDataSize = [dxtFrame dxtMinDataSize];
				NSDictionary			*pba = [NSDictionary dictionaryWithObjectsAndKeys:
					[NSNumber numberWithInt:[dxtFrame dxtPixelFormat]], kCVPixelBufferPixelFormatTypeKey,
					[NSNumber numberWithInt:dxtImgSize.width], kCVPixelBufferWidthKey,
					[NSNumber numberWithInt:dxtImgSize.height], kCVPixelBufferHeightKey,
					[NSNumber numberWithInt:dxtImgSize.width-imgSize.width], kCVPixelBufferExtendedPixelsRightKey,
					[NSNumber numberWithInt:dxtImgSize.height-imgSize.height], kCVPixelBufferExtendedPixelsBottomKey,
					[NSNumber numberWithBool:YES], kCVPixelBufferOpenGLCompatibilityKey,
					nil];
				CVReturn				cvErr = CVPixelBufferCreateWithBytes(NULL,
					dxtImgSize.width,
					dxtImgSize.height,
					[dxtFrame dxtPixelFormat],
					[dxtFrame dxtData],
					dxtDataSize/dxtImgSize.height,
					pixelBufferReleaseCallback,
					dxtFrame,
					(CFDictionaryRef)pba,
					&cvpb);
				if (cvErr!=kCVReturnSuccess)
					NSLog(@"\t\terr %d at CVPixelBufferCreateWithBytes() in %s",cvErr,__func__);
				else	{
					//	retain the HapDecoderFrame instance an extra time (i passed it to the CVPB, which will release the frame when the pixel buffer is freed)
					[dxtFrame retain];
					
					//	push the pixel buffer to the texture (this actually uploads it to the texture)
					[hapTexture setBuffer:cvpb];
					//	draw the texture in the GL view
					[glView
						drawTexture:[hapTexture textureName]
						target:GL_TEXTURE_2D
						imageSize:imgSize
						textureSize:dxtTexSize
						flipped:YES
						usingShader:[hapTexture shaderProgramObject]];
					
					//	release the pixel buffer (it is retained by the hap texture- and the pixel buffer is retaining the HapDecoderFrame, which contains the actual DXT data...)
					CVPixelBufferRelease(cvpb);
					cvpb = NULL;
				}
			}
			[dxtFrame release];
		}
		//	try to get a CV pixel buffer
		CMTime					frameTime = [nativeAVFOutput itemTimeForMachAbsoluteTime:mach_absolute_time()];
		if (nativeAVFOutput!=nil && [nativeAVFOutput hasNewPixelBufferForItemTime:frameTime])	{
			CMTime					frameDisplayTime = kCMTimeZero;
			CVPixelBufferRef		pb = [nativeAVFOutput copyPixelBufferForItemTime:frameTime itemTimeForDisplay:&frameDisplayTime];
			if (pb==NULL)
				NSLog(@"\t\tERR: unable to copy pixel buffer from nativeAVFOutput");
			else	{
				
				//	make a CV GL texture from the pixel buffer
				CVOpenGLTextureRef		newTex = NULL;
				CVReturn				err = CVOpenGLTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
					texCache,
					pb,
					NULL,
					&newTex);
				if (err == kCVReturnSuccess)	{
					//	draw the CV GL texture in the GL view
					CGSize		texSize = CVImageBufferGetEncodedSize(newTex);
					[glView
						drawTexture:CVOpenGLTextureGetName(newTex)
						sized:NSMakeSize(texSize.width,texSize.height)
						flipped:CVOpenGLTextureIsFlipped(newTex)];
					
					CVOpenGLTextureRelease(newTex);
				}
				else
					NSLog(@"\t\terr %d at CVOpenGLTextureCacheCreateTextureFromImage()",err);
				
				CVPixelBufferRelease(pb);
			}
		}
		
		/*		THIS IS FLAGGED AS A LEAK BY STATIC ANALYSIS...		*/
		CVOpenGLTextureCacheFlush(texCache,0);
		/*		...but it isn't.  analysis thinks that "pb" is an id with a retain count, rather than a CFType that needs to be released by a special function (CVPixelBufferRelease())		*/
	}
	
}
- (void) itemDidPlayToEnd:(NSNotification *)note	{
	@synchronized (self)	{
		[player seekToTime:kCMTimeZero];
		[player setRate:1.0];
	}
}


- (NSOpenGLPixelFormat *) createGLPixelFormat	{
	GLuint				glDisplayMaskForAllScreens = 0;
	CGDirectDisplayID	dspys[10];
	CGDisplayCount		count = 0;
	if (CGGetActiveDisplayList(10,dspys,&count)==kCGErrorSuccess)	{
		for (int i=0; i<count; ++i)
			glDisplayMaskForAllScreens |= CGDisplayIDToOpenGLDisplayMask(dspys[i]);
	}
	
	NSOpenGLPixelFormatAttribute	attrs[] = {
		NSOpenGLPFAAccelerated,
		NSOpenGLPFAScreenMask,glDisplayMaskForAllScreens,
		NSOpenGLPFANoRecovery,
		NSOpenGLPFAAllowOfflineRenderers,
		0};
	return [[[NSOpenGLPixelFormat alloc] initWithAttributes:attrs] autorelease];
}


@end




CVReturn displayLinkCallback(CVDisplayLinkRef displayLink, 
	const CVTimeStamp *inNow, 
	const CVTimeStamp *inOutputTime, 
	CVOptionFlags flagsIn, 
	CVOptionFlags *flagsOut, 
	void *displayLinkContext)
{
	NSAutoreleasePool		*pool =[[NSAutoreleasePool alloc] init];
	[(AppDelegate *)displayLinkContext renderCallback];
	[pool release];
	return kCVReturnSuccess;
}
void pixelBufferReleaseCallback(void *releaseRefCon, const void *baseAddress)	{
	HapDecoderFrame		*decoderFrame = (HapDecoderFrame *)releaseRefCon;
	[decoderFrame release];
}
