#import "HapInAVFTestAppDelegate.h"
#import <OpenGL/CGLMacro.h>
//#import <CoreVideo/CoreVideo.h>
//#import <Metal/Metal.h>




@implementation HapInAVFTestAppDelegate
{
	/** tabIndex is stored here because it's bad behaviour to fetch
	 * it when not in main thread and we need it in the renderCallback
	 **/
	NSInteger selectedTabIndex;
	CVMetalTextureCacheRef metalTextureCache;
}


- (id) init {
	self = [super init];
	if (self!=nil)	{
		displayLink = NULL;
		sharedContext = [[NSOpenGLContext alloc] initWithFormat:[self createGLPixelFormat] shareContext:nil];
		player = [[AVPlayer alloc] init];
		[player setActionAtItemEnd:AVPlayerActionAtItemEndPause];
		[player play];
		playerItem = nil;
		nativeAVFOutput = nil;
		hapPlayerOutput = nil;
		
		glTexCacheContext = [[NSOpenGLContext alloc] initWithFormat:[self createGLPixelFormat] shareContext:sharedContext];
		glTexCache = NULL;
		
		hapGLTexture = nil;
		
		hapTexUploadQueue = nil;
		hapMTLTextures = [[NSMutableArray alloc] init];
		hapMTLTexture = nil;

		CVReturn		err = CVOpenGLTextureCacheCreate(kCFAllocatorDefault,
			NULL,
			[glTexCacheContext CGLContextObj],
			[[self createGLPixelFormat] CGLPixelFormatObj],
			NULL,
			&glTexCache);
		if (err!=kCVReturnSuccess)
			NSLog(@"\t\terr %d at CVOpenGLTextureCacheCreate()",err);
		
	}
	return self;
}
- (void) awakeFromNib	{
	@synchronized (self)	{
		//	configure the GL view to use a shared GL context, so it can draw the textures we upload to other contexts
		NSOpenGLContext		*newCtx = [[NSOpenGLContext alloc] initWithFormat:[self createGLPixelFormat] shareContext:sharedContext];
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
		CVDisplayLinkSetOutputCallback(displayLink, displayLinkCallback, (__bridge void * _Nullable)(self));
		CVDisplayLinkStart(displayLink);
	}
	
	//	i want to be the tab view's delegate, so i can respond to tab view changes (and tell the output to enable/disable RGB output)
	[tabView setDelegate:self];
	selectedTabIndex = [tabView indexOfTabViewItem:[tabView selectedTabViewItem]];
}
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	
}
- (void)applicationWillTerminate:(NSNotification *)aNotification {
}


- (void) openDocument:(id)sender	{
	NSOpenPanel		*openPanel = [NSOpenPanel openPanel];
	NSUserDefaults	*def = [NSUserDefaults standardUserDefaults];
	NSString		*openPanelDir = [def objectForKey:@"openPanelDir"];
	if (openPanelDir==nil)
		openPanelDir = [@"~/" stringByExpandingTildeInPath];
	[openPanel setDirectoryURL:[NSURL fileURLWithPath:openPanelDir]];
	[openPanel
		beginSheetModalForWindow:window
		completionHandler:^(NSInteger result)	{
		NSString		*path = (result!=NSModalResponseOK) ? nil : [[openPanel URL] path];
			if (path != nil)	{
				NSUserDefaults		*udef = [NSUserDefaults standardUserDefaults];
				[udef setObject:[path stringByDeletingLastPathComponent] forKey:@"openPanelDir"];
				[udef synchronize];
			}
			//[self loadFileAtPath:path];
			dispatch_async(dispatch_get_main_queue(), ^{
				[self loadFileAtPath:path];
			});
		}];
}


- (void) loadFileAtPath:(NSString *)n	{
	NSLog(@"%s ... %@",__func__,n);
	//	make an asset
	NSURL				*newURL = (n==nil) ? nil : [NSURL fileURLWithPath:n];
	AVAsset				*newAsset = (newURL==nil) ? nil : [AVAsset assetWithURL:newURL];
	//	make a player item
	AVPlayerItem		*newPlayerItem = (newAsset==nil) ? nil : [[AVPlayerItem alloc] initWithAsset:newAsset];
	if (newPlayerItem == nil)	{
		NSLog(@"\t\terr: couldn't make AVPlayerItem in %s",__func__);
		return;
	}
	//	update the status label
	NSArray				*vidTracks = [newAsset tracksWithMediaType:AVMediaTypeVideo];
	for (AVAssetTrack *trackPtr in vidTracks)	{
		NSArray					*trackFormatDescs = [trackPtr formatDescriptions];
		CMFormatDescriptionRef	desc = (trackFormatDescs==nil || [trackFormatDescs count]<1) ? nil : (__bridge CMFormatDescriptionRef)[trackFormatDescs objectAtIndex:0];
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
		if (nativeAVFOutput != nil) {
			if (playerItem != nil)
				[playerItem removeOutput:nativeAVFOutput];
		}
		//	else there's no output- create one
		else	{
			NSDictionary		*pba = @{
				(NSString*)kCVPixelBufferPixelFormatTypeKey: @( kCVPixelFormatType_32BGRA ),
				(NSString*)kCVPixelBufferIOSurfaceOpenGLFBOCompatibilityKey: @( YES ),
				(NSString*)kCVPixelBufferMetalCompatibilityKey: @( YES )
			};
			nativeAVFOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pba];
			[nativeAVFOutput setSuppressesPlayerRendering:YES];
		}
		
		//	if there's a hap output, remove it from the "old" item
		if (hapPlayerOutput != nil)	{
			if (playerItem != nil)
				[playerItem removeOutput:hapPlayerOutput];
		}
		//	else there's no hap output- create one
		else	{
			hapPlayerOutput = [[AVPlayerItemHapDXTOutput alloc] init];
			[hapPlayerOutput setSuppressesPlayerRendering:YES];
			//	if the user's displaying the the NSImage/CPU tab, we want this output to output as RGB
			[hapPlayerOutput setOutputAsRGB:(selectedTabIndex==1)];
		}
		
		//	unregister as an observer for the "old" item's play-to-end notifications
		NSNotificationCenter	*nc = [NSNotificationCenter defaultCenter];
		if (playerItem != nil)
			[nc removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:playerItem];
		
		if (hapGLTexture!=nil)	{
			hapGLTexture = nil;
		}
		
		//	add the outputs to the new player item
		[newPlayerItem addOutput:nativeAVFOutput];
		[newPlayerItem addOutput:hapPlayerOutput];
		//	tell the player to start playing the new player item
		if ([NSThread isMainThread])
			[player replaceCurrentItemWithPlayerItem:newPlayerItem];
		else
			[player performSelectorOnMainThread:@selector(replaceCurrentItemWithPlayerItem:) withObject:newPlayerItem waitUntilDone:YES];
		//	register to receive notifications that the new player item has played to its end
		if (newPlayerItem != nil)
			[nc addObserver:self selector:@selector(itemDidPlayToEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:newPlayerItem];
		
		//	release the "old" player item, retain a ptr to the "new" player item
		playerItem = (newPlayerItem==nil) ? nil : newPlayerItem;
		
		[player setRate:1.0];
	}
}


//	this is called when you change the tabs in the tab view
- (void) tabView:(NSTabView *)tv didSelectTabViewItem:(NSTabViewItem *)item {
	NSInteger		selIndex = [tv indexOfTabViewItem:item];
	selectedTabIndex = [tabView indexOfTabViewItem:[tabView selectedTabViewItem]];
	//	if the user's displaying the the NSImage/CPU tab, we want this output to output as RGB
	if (selIndex==1)
		[hapPlayerOutput setOutputAsRGB:YES];
	else if (selIndex==0)
		[hapPlayerOutput setOutputAsRGB:NO];
	else if (selIndex==2) // METAL
		[hapPlayerOutput setOutputAsRGB:NO];
}


//	this is called by the displaylink's C callback- this drives rendering
- (void) renderCallback {
	@synchronized (self)	{
		//	try to get a hap decoder frame- it returns a nil quickly if the player it's attached to doesn't have a hap track.
		CMTime					outputTime = [hapPlayerOutput itemTimeForMachAbsoluteTime:mach_absolute_time()];
		HapDecoderFrame			*dxtFrame = [hapPlayerOutput allocFrameClosestToTime:outputTime];
		//HapDecoderFrame			*dxtFrame = [hapPlayerOutput allocFrameForTime:outputTime];
		if (dxtFrame!=nil)	{
			//	if there's no hap texture, make one
			if (hapGLTexture==nil)	{
				CGLContextObj		newCtx = NULL;
				CGLError			err = CGLCreateContext([[self createGLPixelFormat] CGLPixelFormatObj], [sharedContext CGLContextObj], &newCtx);
				if (err!=kCGLNoError)
					NSLog(@"\t\terr %u at CGLCreateContext() in %s",err,__func__);
				else	{
					hapGLTexture = [[HapGLPixelBufferTexture alloc] initWithContext:newCtx];
					if (hapGLTexture==nil)
						NSLog(@"\t\terr: couldn't create HapPixelBufferContext in %s",__func__);
					CGLReleaseContext(newCtx);
				}
			}
			
			NSSize					imgSize = [dxtFrame imgSize];
			NSSize					dxtImgSize = [dxtFrame dxtImgSize];
			if (selectedTabIndex == 0)	{
				if (hapGLTexture!=nil)	{
					//	pass the decoded frame to the hap texture
					[hapGLTexture setDecodedFrame:dxtFrame];
					//	draw the texture in the GL view
					NSSize					dxtTexSize;
					// On NVIDIA hardware there is a massive slowdown if DXT textures aren't POT-dimensioned, so we use POT-dimensioned backing
					//	NOTE: NEEDS TESTING. this used to be the case- but this API is only available on 10.10+, so this may have been fixed.
					int						tmpInt;
					tmpInt = 1;
					while (tmpInt < dxtImgSize.width)
						tmpInt = tmpInt<<1;
					dxtTexSize.width = tmpInt;
					tmpInt = 1;
					while (tmpInt < dxtImgSize.height)
						tmpInt = tmpInt<<1;
					dxtTexSize.height = tmpInt;
					
					if ([hapGLTexture textureCount]>1)	{
						[glView
							drawTexture:[hapGLTexture textureNames][0]
							target:GL_TEXTURE_2D
							alphaTexture:[hapGLTexture textureNames][1]
							alphaTarget:GL_TEXTURE_2D
							imageSize:imgSize
							textureSize:dxtTexSize
							flipped:YES
							usingShader:[hapGLTexture shaderProgramObject]];
					}
					else	{
						[glView
							drawTexture:[hapGLTexture textureNames][0]
							target:GL_TEXTURE_2D
							imageSize:imgSize
							textureSize:dxtTexSize
							flipped:YES
							usingShader:[hapGLTexture shaderProgramObject]];
					}
				}
			}
			else if (selectedTabIndex == 1)	{
				//	if the frame has RGB data attached to it, make an NSBitmapImageRep & NSImage from the data, then draw it in the NSImageView
				void				*rgbData = [dxtFrame rgbData];
				size_t				rgbDataSize = [dxtFrame rgbDataSize];
				if (rgbData==nil)	{
					NSLog(@"\t\terr: rgb data nil in %s",__func__);
				}
				else	{
					NSBitmapImageRep	*bitmapRep = [[NSBitmapImageRep alloc]
						initWithBitmapDataPlanes:NULL
						pixelsWide:(NSUInteger)imgSize.width
						pixelsHigh:(NSUInteger)imgSize.height
						bitsPerSample:8
						samplesPerPixel:4
						hasAlpha:YES
						isPlanar:NO
						colorSpaceName:NSCalibratedRGBColorSpace
						bitmapFormat:0
						bytesPerRow:rgbDataSize/(NSUInteger)imgSize.height
						bitsPerPixel:32];
					if (bitmapRep==nil)
						NSLog(@"\t\terr: bitmap rep nil, %s",__func__);
					else	{
						memcpy([bitmapRep bitmapData], rgbData, rgbDataSize);
						NSImage				*newImg = [[NSImage alloc] initWithSize:imgSize];
						[newImg addRepresentation:bitmapRep];
						//	draw the NSImage in the view
						dispatch_async(dispatch_get_main_queue(), ^{
							[imgView setImage:newImg];
						});
						
						newImg = nil;
						bitmapRep = nil;
					}
				}
			}
			else if(selectedTabIndex==2)	  {
				id<MTLDevice>			viewDevice = metalView.device;
				
				//	make sure we have an upload queue that works with the view's device...
				if (hapTexUploadQueue != nil && hapTexUploadQueue.device != viewDevice)
					hapTexUploadQueue = nil;
				if (hapTexUploadQueue == nil)	{
					hapTexUploadQueue = [viewDevice newCommandQueue];
				}
				
				//	if we have a texture, but its frame differs from the decoded frame we're going to try drawing, just free it- the view that draws it is responsible for retaining its own copy.  we need to start uploading this new image data to a new texture ("new"- likely pooled).
				if (hapMTLTexture != nil && hapMTLTexture.frame != dxtFrame)	{
					hapMTLTexture = nil;
				}
				
				//	if we still have a hap metal texture...
				if (hapMTLTexture != nil)	{
					//	intentionally blank- the image data has already been uploaded to the texture, and will be passed to the view when the commnad buffer pushing the data to the GPU completes
				}
				//	else we don't have a hap metal texture- we need to create one and populate it...
				else	{
					hapMTLTexture = [self getHapMTLPixelBufferTexture];
					
					//	when the command buffer that populates the texture completes, pass the texture to the view for display
					id<MTLCommandBuffer>	cmdBuffer = [hapTexUploadQueue commandBuffer];
					[hapMTLTexture populateWithHapDecoderFrame:dxtFrame inCommandBuffer:cmdBuffer];
					[cmdBuffer addCompletedHandler:^(id<MTLCommandBuffer> completedCB)	{
						[metalView displayPixelBufferTexture:hapMTLTexture flipped:NO];
					}];
					[cmdBuffer commit];
				}
			}
			
			dxtFrame = nil;
		}

		//	try to get a CV pixel buffer (returns immediately if we're not using the native AVF output side of things: this chunk of code only executes if we're playing back NON-hap video files supported by AVFoundation!)
		CMTime					frameTime = [nativeAVFOutput itemTimeForMachAbsoluteTime:mach_absolute_time()];
		if (nativeAVFOutput!=nil && [nativeAVFOutput hasNewPixelBufferForItemTime:frameTime])	{
			CMTime					frameDisplayTime = kCMTimeZero;
			CVPixelBufferRef		nativeAVFPB = [nativeAVFOutput copyPixelBufferForItemTime:frameTime itemTimeForDisplay:&frameDisplayTime];
			if (nativeAVFPB==NULL)
				NSLog(@"\t\tERR: unable to copy pixel buffer from nativeAVFOutput");
			else	{
				//	if we want to use opengl to display the buffer...
				if (selectedTabIndex==0)	{
					//	make a CV GL texture from the pixel buffer
					CVOpenGLTextureRef		newTex = NULL;
					CVReturn				err = CVOpenGLTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
						glTexCache,
						nativeAVFPB,
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
				}
				//	else we want to use NSImage to display the buffer...
				else if (selectedTabIndex==1)	{
					size_t				pbBytesPerRow = CVPixelBufferGetBytesPerRow(nativeAVFPB);
					NSSize				imgSize = NSMakeSize(CVPixelBufferGetWidth(nativeAVFPB), CVPixelBufferGetHeight(nativeAVFPB));
					NSBitmapImageRep	*bitmapRep = [[NSBitmapImageRep alloc]
						initWithBitmapDataPlanes:NULL
						pixelsWide:(NSUInteger)imgSize.width
						pixelsHigh:(NSUInteger)imgSize.height
						bitsPerSample:8
						samplesPerPixel:4
						hasAlpha:YES
						isPlanar:NO
						colorSpaceName:NSCalibratedRGBColorSpace
						bitmapFormat:0
						bytesPerRow:pbBytesPerRow
						bitsPerPixel:32];
					if (bitmapRep==nil)
						NSLog(@"\t\terr: bitmap rep nil, %s",__func__);
					else	{
						CVPixelBufferLockBaseAddress(nativeAVFPB, kCVPixelBufferLock_ReadOnly);
						size_t				bitmapBytesPerRow = [bitmapRep bytesPerRow];
						size_t				minBytesPerRow = fminl(pbBytesPerRow, bitmapBytesPerRow);
						void				*readAddr = CVPixelBufferGetBaseAddress(nativeAVFPB);
						void				*writeAddr = [bitmapRep bitmapData];
						for (int i=0; i<imgSize.height; ++i)	{
							memcpy(writeAddr, readAddr, minBytesPerRow);
							writeAddr += bitmapBytesPerRow;
							readAddr += pbBytesPerRow;
						}
						CVPixelBufferUnlockBaseAddress(nativeAVFPB, kCVPixelBufferLock_ReadOnly);
						
						NSImage				*newImg = [[NSImage alloc] initWithSize:imgSize];
						[newImg addRepresentation:bitmapRep];
						//	draw the NSImage in the view
						[imgView setImage:newImg];
					
						newImg = nil;
						bitmapRep = nil;
					}
					
				}
				//	else we're using metal to display the buffer...
				else if (selectedTabIndex==2)	 {
					
					if (metalTextureCache==NULL)	{
						CVReturn		cvReturn = CVMetalTextureCacheCreate(
							kCFAllocatorDefault,
							nil,
							metalView.device,
							nil,
							&metalTextureCache);
						if (cvReturn != kCVReturnSuccess)	{
							NSLog(@"\t\terr %d at CVMetalTextureCacheCreate(). Abort render.",cvReturn);
							return;
						}
					}
					CVMetalTextureRef		metalTextureRef;
					CGSize			textureSize = CVImageBufferGetEncodedSize(nativeAVFPB);
					CVReturn		cvReturn = CVMetalTextureCacheCreateTextureFromImage(
						kCFAllocatorDefault,
						metalTextureCache,
						nativeAVFPB,
						nil,
						metalView.colorPixelFormat,
						textureSize.width,
						textureSize.height,
						0,
						&metalTextureRef);
					if (cvReturn == kCVReturnSuccess)	{
						[metalView displayCVMetalTextureRef:metalTextureRef flipped:NO];
						CVBufferRelease(metalTextureRef);
					}
					else	{
						NSLog(@"\t\terr %d at CVMetalTextureCacheCreateTextureFromImage()",cvReturn);
					}
					
				}
				
				CVPixelBufferRelease(nativeAVFPB);
			}
		}
		
		/*		THIS IS FLAGGED AS A LEAK BY STATIC ANALYSIS...		*/
		CVOpenGLTextureCacheFlush(glTexCache,0);
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
	return [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
}


- (void) poolFreedPixelBufferTexture:(HapMTLPixelBufferTexture *)n	{
	if (n == nil)
		return;
	@synchronized (self)	{
		[hapMTLTextures addObject:n];
	}
}
- (HapMTLPixelBufferTexture *) getHapMTLPixelBufferTexture	{
	HapMTLPixelBufferTexture		*returnMe = nil;
	@synchronized (self)	{
		if (hapMTLTextures.count > 0)	{
			returnMe = hapMTLTextures[0];
			[hapMTLTextures removeObjectAtIndex:0];
		}
	}
	if (returnMe == nil)	{
		returnMe = [[HapMTLPixelBufferTexture alloc] initWithDevice:metalView.device];
	}
	return returnMe;
}


@end




CVReturn displayLinkCallback(CVDisplayLinkRef displayLink, 
	const CVTimeStamp *inNow, 
	const CVTimeStamp *inOutputTime, 
	CVOptionFlags flagsIn, 
	CVOptionFlags *flagsOut, 
	void *displayLinkContext)
{
	@autoreleasepool	{
		[(__bridge HapInAVFTestAppDelegate *)displayLinkContext renderCallback];
	}
	return kCVReturnSuccess;
}
void pixelBufferReleaseCallback(void *releaseRefCon, const void *baseAddress)	{
	HapDecoderFrame		*decoderFrame = (HapDecoderFrame *)CFBridgingRelease(releaseRefCon);
	decoderFrame = nil;
}
