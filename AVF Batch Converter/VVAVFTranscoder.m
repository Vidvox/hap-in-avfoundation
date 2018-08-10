#import "VVAVFTranscoder.h"




#define FourCCLog(n,f) NSLog(@"%@, %c%c%c%c",n,(int)((f>>24)&0xFF),(int)((f>>16)&0xFF),(int)((f>>8)&0xFF),(int)((f>>0)&0xFF))




@interface VVAVFTranscoder ()
- (void) _finishWritingAndCleanUpShop;
- (void) clear;
@end




@implementation VVAVFTranscoder


- (id) init	{
	self = [super init];
	if (self!=nil)	{
		//NSLog(@"\t\tCMVideoFormatDescription extensions common with img buffers are %@",CMVideoFormatDescriptionGetExtensionKeysCommonWithImageBuffers());
		pthread_mutexattr_t		attr;
		pthread_mutexattr_init(&attr);
		pthread_mutexattr_settype(&attr,PTHREAD_MUTEX_RECURSIVE);
		pthread_mutex_init(&theLock,&attr);
		pthread_mutexattr_destroy(&attr);
		paused = NO;
		srcAsset = nil;
		reader = nil;
		readerOutputs = [[NSMutableArray arrayWithCapacity:0] retain];
		writerQueue = dispatch_queue_create("VVAVFTranscoder", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, DISPATCH_QUEUE_PRIORITY_HIGH, -1));
		writer = nil;
		writerInputs = [[NSMutableArray arrayWithCapacity:0] retain];
		videoExportSettings = nil;
		audioExportSettings = nil;
		durationInSeconds = 0.0;
		normalizedProgress = 0.0;
		unexpectedErr = NO;
		delegate = nil;
		srcPath = nil;
		dstPath = nil;
		errorString = nil;
	}
	return self;
}
- (void) dealloc	{
	pthread_mutex_lock(&theLock);
	delegate = nil;
	pthread_mutex_unlock(&theLock);
	
	[self clear];
	
	pthread_mutex_lock(&theLock);
	if (writerQueue!=nil)
		dispatch_release(writerQueue);
	if (writerInputs!=nil)	{
		[writerInputs release];
		writerInputs = nil;
	}
	if (readerOutputs!=nil)	{
		[readerOutputs release];
		readerOutputs = nil;
	}
	if (srcPath!=nil)	{
		[srcPath release];
		srcPath = nil;
	}
	if (dstPath!=nil)	{
		[dstPath release];
		dstPath = nil;
	}
	if (errorString!=nil)	{
		[errorString release];
		errorString = nil;
	}
	pthread_mutex_unlock(&theLock);
	
	pthread_mutex_destroy(&theLock);
	[super dealloc];
}
- (void) transcodeFileAtPath:(NSString *)src toPath:(NSString *)dst	{
	//NSLog(@"%s ... %@ -> %@",__func__,src,dst);
	if (src==nil || dst==nil)
		return;
	
	//	clear everything out first
	[self clear];
	
	NSNull			*nsnull = [NSNull null];
	//	figure out where i'll be exporting to, make sure the directory exists, bail if i can't write to the destination
	NSFileManager	*fm = [NSFileManager defaultManager];
	NSError			*err = nil;
	//NSString		*baseFolder = [[NSString stringWithFormat:@"~/Documents/VVAVFTranscodeTest/%@",[[src lastPathComponent] stringByDeletingPathExtension]] stringByExpandingTildeInPath];
	NSString		*baseFolder = [dst stringByDeletingLastPathComponent];
	BOOL			baseFolderIsDir = NO;
	if (![fm fileExistsAtPath:baseFolder isDirectory:&baseFolderIsDir] || !baseFolderIsDir)	{
		if (![fm createDirectoryAtPath:baseFolder withIntermediateDirectories:YES attributes:nil error:&err])	{
			NSLog(@"\t\terr, couldn't create directory in %s. err is %@",__func__,err);
			[self _cancelAndCleanUpShop];
			return;
		}
	}
	//	if i can't make a source asset from the passed file, bail and clear
	AVAsset			*newSrcAsset = [AVAsset assetWithURL:[NSURL fileURLWithPath:src]];
	if (newSrcAsset==nil)	{
		NSLog(@"\t\terr, couldn't make asset in %s for path %@",__func__,src);
		[self _cancelAndCleanUpShop];
		return;
	}
	//	if i can't make an asset reader from the new source asset, bail and clear
	NSError			*nsErr = nil;
	AVAssetReader	*newReader = [AVAssetReader assetReaderWithAsset:newSrcAsset error:&nsErr];
	if (newReader==nil || nsErr!=nil)	{
		NSLog(@"\t\terr: couldn't make asset reader in %s: %@",__func__,nsErr);
		[self _cancelAndCleanUpShop];
		return;
	}
	//	if there's already a file at the destination, move it to the trash
	//NSString		*dstName = [[NSString stringWithFormat:@"%@/%@.mov",baseFolder,[src lastPathComponent]] stringByExpandingTildeInPath];
	//NSLog(@"\t\tshould be writing movie to %@",dst);
	//	if the dest file already exists, move it to the trash
	if ([fm fileExistsAtPath:dst isDirectory:nil])	{
		//NSLog(@"\t\tdst movie already exists, moving to trash...");
		[fm removeItemAtPath:dst error:nil];
	}
	//	if i can't make an asset writer, bail and clear
	AVAssetWriter		*newWriter = [AVAssetWriter
		assetWriterWithURL:[NSURL fileURLWithPath:dst]
		fileType:AVFileTypeQuickTimeMovie
		error:&nsErr];
	if (newWriter==nil || nsErr!=nil)	{
		NSLog(@"\t\terr: couldn't make asset writer in %s: %@",__func__,nsErr);
		[self _cancelAndCleanUpShop];
		return;
	}
	
	//	get the audio & video export settings from the export settings controller, bail if they're nil or empty
	pthread_mutex_lock(&theLock);
	NSMutableDictionary		*baseVideoExportSettings = (videoExportSettings==nil) ? [NSMutableDictionary dictionaryWithCapacity:0] : [[videoExportSettings mutableCopy] autorelease];
	NSMutableDictionary		*baseAudioExportSettings = (audioExportSettings==nil) ? [NSMutableDictionary dictionaryWithCapacity:0] : [[audioExportSettings mutableCopy] autorelease];
	pthread_mutex_unlock(&theLock);
	if (baseVideoExportSettings==nil)	{
		NSLog(@"\t\terr: base video settings nil in %s",__func__);
		[self _cancelAndCleanUpShop];
		return;
	}
	if (baseAudioExportSettings==nil)	{
		NSLog(@"\t\terr: base audio settings nil in %s",__func__);
		[self _cancelAndCleanUpShop];
		return;
	}
	
	//	i need to remove the multi-pass stuff from the base video export settings dict
	NSNumber				*baseVideoMultiPassExportNum = [baseVideoExportSettings objectForKey:VVAVVideoMultiPassEncodeKey];
	BOOL					baseVideoMultiPassExport = NO;
	if (baseVideoMultiPassExportNum!=nil)	{
		if ([baseVideoMultiPassExportNum boolValue])
			baseVideoMultiPassExport = YES;
		[baseVideoExportSettings removeObjectForKey:VVAVVideoMultiPassEncodeKey];
	}
	//NSLog(@"\t\tbaseVideoExportSettings are %@",baseVideoExportSettings);
	//NSLog(@"\t\tbaseAudioExportSettings are %@",baseAudioExportSettings);
	
	//	lock, and make all the actual readers, reader outputs, writers, and writer inputs- then start it.
	pthread_mutex_lock(&theLock);
	{
		if (srcPath!=nil)	{
			[srcPath release];
			srcPath = nil;
		}
		srcPath = [src retain];
		if (dstPath!=nil)	{
			[dstPath release];
			dstPath = nil;
		}
		dstPath = [dst retain];
		
		if (srcAsset!=nil)
			[srcAsset release];
		srcAsset = [newSrcAsset retain];
		durationInSeconds = CMTimeGetSeconds([srcAsset duration]);
		normalizedProgress = 0.0;
		unexpectedErr = NO;
		
		if (reader!=nil)
			[reader release];
		reader = [newReader retain];
		
		if (writer!=nil)
			[writer release];
		writer = [newWriter retain];
		
		//	'readerOutputs' and 'writerInputs' are ordered to correspond directly to the order of the tracks in this array
		NSArray			*tracks = [srcAsset tracks];
		//	these dicts describe the standard reader output format if i need to transcode video or audio
		NSDictionary	*videoReadNormalizedOutputSettings = [NSDictionary dictionaryWithObjectsAndKeys:
			//[NSNumber numberWithInteger:kCVPixelFormatType_32BGRA], kCVPixelBufferPixelFormatTypeKey,	//	BGRA/RGBA stops working sometime at or before 8k resolution!
			//[NSNumber numberWithInteger:kCVPixelFormatType_32RGBA], kCVPixelBufferPixelFormatTypeKey,
			[NSNumber numberWithInteger:kCVPixelFormatType_32ARGB], kCVPixelBufferPixelFormatTypeKey,
			nil];
		NSDictionary	*audioReadNormalizedOutputSettings = [NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithInteger:kAudioFormatLinearPCM], AVFormatIDKey,
			[NSNumber numberWithInteger:32], AVLinearPCMBitDepthKey,
			[NSNumber numberWithBool:NO], AVLinearPCMIsBigEndianKey,
			[NSNumber numberWithBool:YES], AVLinearPCMIsFloatKey,
			[NSNumber numberWithBool:YES], AVLinearPCMIsNonInterleaved,
			//XXX, kLinearPCMFormatFlagIsPacked,	//	Synonym for kAudioFormatFlagIsPacked
			//XXX, kLinearPCMFormatFlagIsAlignedHigh,	//	Synonym for kAudioFormatFlagIsAlignedHigh.
			//XXX, kLinearPCMFormatFlagIsNonMixable,	//	Synonym for kAudioFormatFlagIsNonMixable.
			//XXX, kLinearPCMFormatFlagsAreAllClear, //	Synonym for kAudioFormatFlagsAreAllClear.
			//XXX, kLinearPCMFormatFlagsSampleFractionShift,
			//XXX, kLinearPCMFormatFlagsSampleFractionMask,
			nil];
		
		//	these are NSNumber/BOOLs, if YES the corresponding track needs to be transcoded.  populated when i make the track reader outputs.
		NSMutableArray	*trackTranscodeFlags = [NSMutableArray arrayWithCapacity:0];
		NSNumber		*stripVideoNum = [baseVideoExportSettings objectForKey:VVAVStripMediaKey];
		NSNumber		*stripAudioNum = [baseAudioExportSettings objectForKey:VVAVStripMediaKey];
		
		
		//	run through all the tracks, making an output for each and populating the track transcode flags
		for (AVAssetTrack *trackPtr in tracks)	{
			AVAssetReaderOutput		*newOutput = nil;
			BOOL					transcodeThisTrack = YES;
			//	if the track isn't playable and isn't hap, log it and skip the transcode- we can't do anything with it
			if (![trackPtr isPlayable] && ![trackPtr isHapTrack])	{
				NSLog(@"\t\terr: track %@ isn't playable, will be skipping transcode regardless in %s",trackPtr,__func__);
				transcodeThisTrack = NO;
			}
			//	else the track is either playable or hap, and i need to investigate further...
			else	{
				NSArray					*formatDescriptions = [trackPtr formatDescriptions];
				NSUInteger				formatDescriptionsCount = (formatDescriptions==nil) ? 0 : [formatDescriptions count];
				//CMFormatDescriptionRef	trackFmt = NULL;
				//	if there are no format descriptions- or too many format descriptions- then i don't know what to do, and will skip the transcode
				if (formatDescriptionsCount==0)	{
					if (formatDescriptionsCount==0)
						NSLog(@"\t\tERR: track %@ doesn't have any format descriptions, skipping transcode regardless in %s",trackPtr,__func__);
					//else
					//	NSLog(@"\t\tERR: track %@ has too many format descriptions, skipping transcode regardless in %s",trackPtr,__func__);
					transcodeThisTrack = NO;
				}
				//	else the format descriptions look okay, and i need to investigate further...
				else	{
					//	if i'm here, there's exactly one format description for the track- use it to determine if i'm transcoding this track or not
					//trackFmt = (CMFormatDescriptionRef)[formatDescriptions objectAtIndex:0];
					
					NSString				*trackMediaType = [trackPtr mediaType];
					//	if it's a video track, i need to investigate further...
					if (trackMediaType!=nil && [trackMediaType isEqualToString:AVMediaTypeVideo])	{
						NSString			*exportCodecString = [baseVideoExportSettings objectForKey:AVVideoCodecKey];
						//OSType				exportCodec = (exportCodecString==nil) ? 0 : VVPackFourCC_fromChar((char *)[exportCodecString UTF8String]);
						//OSType				trackCodec = CMFormatDescriptionGetMediaSubType(trackFmt);
						
						//	if the export settings specify a resolution, and that resolution doesn't match this track's resolution, we need to perform the transcode step
						CMFormatDescriptionRef	trackFmt = (CMFormatDescriptionRef)[formatDescriptions objectAtIndex:0];
						NSNumber			*tmpNum = nil;
						NSSize				exportSize = NSMakeSize(-1,-1);
						CMVideoDimensions		vidDims = CMVideoFormatDescriptionGetDimensions(trackFmt);
						NSSize				trackSize = NSMakeSize(vidDims.width, vidDims.height);
						
						tmpNum = [baseVideoExportSettings objectForKey:AVVideoWidthKey];
						if (tmpNum != nil)
							exportSize.width = [tmpNum doubleValue];
						tmpNum = [baseVideoExportSettings objectForKey:AVVideoHeightKey];
						if (tmpNum != nil)
							exportSize.height = [tmpNum doubleValue];
						
						if (exportSize.width>0 && exportSize.height>0 && !NSEqualSizes(exportSize,trackSize))	{
							transcodeThisTrack = YES;
						}
						
						//	if the export settings don't specify a codec, skip the transcode on the track
						if (exportCodecString==nil)	{
							//NSLog(@"\t\texport directions explicitly state to skip transcode on track %@",trackPtr);
							transcodeThisTrack = NO;
						}
						//	if i'm stripping video, i'm not transcoding and this is a null track
						if (stripVideoNum!=nil && [stripVideoNum boolValue])	{
							transcodeThisTrack = NO;
							newOutput = (AVAssetReaderOutput *)nsnull;
						}
						/*
						//	else if the specified codec matches the track's current codec
						else if (exportCodec==trackCodec)	{
							NSNumber			*tmpNum = nil;
							NSSize				exportSize;
							NSSize				trackSize;
							//	if i'm either not resizing, or the new size matches the track's size, skip the transcode on this track
							CMVideoDimensions		vidDims = CMVideoFormatDescriptionGetDimensions(trackFmt);
							trackSize = NSMakeSize(vidDims.width, vidDims.height);
							tmpNum = [baseVideoExportSettings objectForKey:AVVideoWidthKey];
							exportSize.width = [tmpNum doubleValue];
							tmpNum = [baseVideoExportSettings objectForKey:AVVideoHeightKey];
							exportSize.height = [tmpNum doubleValue];
							if (tmpNum==nil || NSEqualSizes(exportSize,trackSize))	{
								//NSLog(@"\t\texport description matches source description, skipping transcode on track %@",trackPtr);
								transcodeThisTrack = NO;
							}
						}
						*/
						//	if i'm transcoding this track, i have to make an output that produces RGB data of some sort
						if (transcodeThisTrack)	{
							if ([trackPtr isHapTrack])
								newOutput = [[AVAssetReaderHapTrackOutput alloc] initWithTrack:trackPtr outputSettings:videoReadNormalizedOutputSettings];
							else
								newOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:trackPtr outputSettings:videoReadNormalizedOutputSettings];
							//	if i'm going to try to do multi-pass encoding, the reader output needs to support random access
							if (baseVideoMultiPassExport)
								[newOutput setSupportsRandomAccess:YES];
						}
					}
					//	else if it's an audio track, i need to investigate further...
					else if (trackMediaType!=nil && [trackMediaType isEqualToString:AVMediaTypeAudio])	{
						//NSLog(@"\t\taudio track %@ has extensions %@",trackPtr,CMFormatDescriptionGetExtensions(trackFmt));
						NSNumber			*exportFormatNum = [baseAudioExportSettings objectForKey:AVFormatIDKey];
						//OSType				exportFormat = (exportFormatNum==nil) ? 0 : (OSType)[exportFormatNum integerValue];
						//OSType				trackFormat = CMFormatDescriptionGetMediaSubType(trackFmt);
						//AudioStreamBasicDescription		*trackDescription = (AudioStreamBasicDescription*)CMAudioFormatDescriptionGetStreamBasicDescription(trackFmt);
						//	if the export settings don't specify an audio format, skip the transcode on the track
						if (exportFormatNum==nil)	{
							//NSLog(@"\t\texport description explicitly state to skip transcode on track %@",trackPtr);
							transcodeThisTrack = NO;
						}
						if (stripAudioNum!=nil && [stripAudioNum boolValue])	{
							transcodeThisTrack = NO;
							newOutput = (AVAssetReaderOutput *)nsnull;
						}
						/*
						//	else if the specified codec matches the track's current codec
						else if (exportFormat==trackFormat)	{
							NSNumber			*tmpNum = nil;
							Float64				trackSampleRate = trackDescription->mSampleRate;
							//	if i'm either not resampling, or the new sample rate matches the track's sample rate, skip the transcode on this track
							tmpNum = [baseAudioExportSettings objectForKey:AVSampleRateKey];
							if (tmpNum==nil || [tmpNum integerValue]==trackSampleRate)	{
								//NSLog(@"\t\texport description matches source description, skipping transcode on track %@",trackPtr);
								transcodeThisTrack = NO;
							}
						}
						*/
						
						//	if i'm transcoding this track, i have to make an output that produces RGB data of some sort
						if (transcodeThisTrack)
							newOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:trackPtr outputSettings:audioReadNormalizedOutputSettings];
					}
					else if ([trackMediaType isEqualToString:AVMediaTypeText] || [trackMediaType isEqualToString:AVMediaTypeClosedCaption] || [trackMediaType isEqualToString:AVMediaTypeSubtitle] || [trackMediaType isEqualToString:AVMediaTypeTimecode] || [trackMediaType isEqualToString:AVMediaTypeMetadata] || [trackMediaType isEqualToString:AVMediaTypeMuxed])	{
						transcodeThisTrack = NO;
					}
					//	else it's an unknown track type- i need to skip the transcode
					else	{
						NSLog(@"\t\terr: track %@ isn't used by this software, skipping transcode and stripping in %s",trackPtr,__func__);
						transcodeThisTrack = NO;
						newOutput = (AVAssetReaderOutput *)nsnull;
					}
				}
				
			}
			
			//	if there's no output, and i'm not transcoding, make a generic output that will just copy the raw samples (no decoding)
			if (newOutput==nil && !transcodeThisTrack)
				newOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:trackPtr outputSettings:nil];
			//	if there's still no output, just add a null ptr and log the problem
			if (newOutput==nil)	{
				NSLog(@"\t\terr: couldn't make output for track %@ in %s",trackPtr,__func__);
				[readerOutputs addObject:[NSNull null]];
			}
			//	else if there's an output but it's an nsnull, add it (i'm stripping this track instead of copying or transcoding it)
			else if (newOutput==(AVAssetReaderOutput *)nsnull)	{
				[readerOutputs addObject:nsnull];
			}
			else	{
				//	if the reader couldn't add the output, add a null ptr and log the problem
				if (![reader canAddOutput:newOutput])	{
					NSLog(@"\t\terr: reader couldn't add output for track %@ in %s",trackPtr,__func__);
					[readerOutputs addObject:[NSNull null]];
				}
				//	else everything's good- add the reader output
				else	{
					//NSLog(@"\t\tmade asset reader output for track %@",trackPtr);
					[reader addOutput:newOutput];
					[readerOutputs addObject:newOutput];
				}
				[newOutput release];
				newOutput = nil;
			}
			//	store a passthru value for other tracks to reference
			[trackTranscodeFlags addObject:[NSNumber numberWithBool:transcodeThisTrack]];
		}
		
		
		//	tell the asset reader to start reading
		[reader startReading];
		
		
		//	run through each of the reader outputs- create a writer input for each one
		int				localIndex = 0;
		for (AVAssetReaderTrackOutput *readerOutput in readerOutputs)	{
			BOOL			transcodeThisTrack = [[trackTranscodeFlags objectAtIndex:localIndex] boolValue];
			//	if the output is an NSNull placeholder, just add a null input
			if (readerOutput==(AVAssetReaderTrackOutput *)[NSNull null])
				[writerInputs addObject:[NSNull null]];
			//	else try to make an input for the output...
			else	{
				AVAssetTrack				*assetTrack = [readerOutput track];
				//NSLog(@"\t\tmaking a writer input for track %@ and reader output %@",assetTrack,readerOutput);
				AVAssetWriterInput			*newInput = nil;
				//	if this is a video track
				if ([[assetTrack mediaType] isEqualToString:AVMediaTypeVideo])	{
					//	if i'm not transcoding, just add a simple generic input
					if (!transcodeThisTrack)	{
						//NSLog(@"\t\twriter input for track %@ should be skipping transcode...",assetTrack);
						newInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:nil];
					}
					//	else the track needs to be transcoded, and i need to specify settings for the writer input
					else	{
						NSMutableDictionary		*outputSettings = [NSMutableDictionary dictionaryWithCapacity:0];
						[outputSettings addEntriesFromDictionary:baseVideoExportSettings];
						//	if i'm not explicitly setting the size in the base export settings, i need to add the video track's size
						NSSize					vidTrackSize = NSMakeSize([assetTrack naturalSize].width, [assetTrack naturalSize].height);
						if ([outputSettings objectForKey:AVVideoWidthKey]==nil)	{
							[outputSettings setObject:[NSNumber numberWithInteger:vidTrackSize.width] forKey:AVVideoWidthKey];
							[outputSettings setObject:[NSNumber numberWithInteger:vidTrackSize.height] forKey:AVVideoHeightKey];
						}
						
						//NSLog(@"\t\tvideo output settings are %@",outputSettings);
						//	if i'm going to be writing to a hap track, i need to make an asset writer hap input
						NSString		*codecString = [outputSettings objectForKey:AVVideoCodecKey];
						if (codecString!=nil && ([codecString isEqualToString:AVVideoCodecHap] || [codecString isEqualToString:AVVideoCodecHapAlpha] || [codecString isEqualToString:AVVideoCodecHapQ] || [codecString isEqualToString:AVVideoCodecHapQAlpha] || [codecString isEqualToString:AVVideoCodecHapAlphaOnly]))
							newInput = [[[AVAssetWriterHapInput alloc] initWithOutputSettings:outputSettings] autorelease];
						//	else i'm making a writer input for an AVFoundation-supported codec
						else	{
							newInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:outputSettings];
							//	if the writer input supports multi-pass encoding, and the settings dict specified multi-pass encoding, set that up now
							if (baseVideoMultiPassExport)	{
								//NSLog(@"\t\tmulti-pass encoding is enabled");
								[newInput setPerformsMultiPassEncodingIfSupported:YES];
							}
						}
					}
				}
				//	else if this is an audio track
				else if ([[assetTrack mediaType] isEqualToString:AVMediaTypeAudio])	{
					if (transcodeThisTrack)	{
						NSArray					*formatDescriptions = [assetTrack formatDescriptions];
						CMFormatDescriptionRef	trackFmt = (CMFormatDescriptionRef)[formatDescriptions objectAtIndex:0];
						NSMutableDictionary		*outputSettings = [NSMutableDictionary dictionaryWithCapacity:0];
						[outputSettings addEntriesFromDictionary:baseAudioExportSettings];
						//	if i'm not explicitly setting the sample rate & number of channels in the export settings, i need to supply the track's current sample rate
						AudioStreamBasicDescription		*trackDescription = (AudioStreamBasicDescription*)CMAudioFormatDescriptionGetStreamBasicDescription(trackFmt);
						if ([outputSettings objectForKey:AVSampleRateKey]==nil)
							[outputSettings setObject:[NSNumber numberWithDouble:trackDescription->mSampleRate] forKey:AVSampleRateKey];
						if ([outputSettings objectForKey:AVNumberOfChannelsKey]==nil)
							[outputSettings setObject:[NSNumber numberWithInteger:trackDescription->mChannelsPerFrame] forKey:AVNumberOfChannelsKey];
						//	i need to copy the channel mapping from the track's format description to the output settings (we want to make sure this is preserved)
						if (trackFmt==NULL)
							NSLog(@"\t\terr: audio track format null in %s",__func__);
						else	{
							size_t				layoutSize;
							AudioChannelLayout	*layout = (AudioChannelLayout *)CMAudioFormatDescriptionGetChannelLayout(trackFmt, &layoutSize);
							if (layout==nil)
								NSLog(@"\t\terr: audio channel layout in format was nil in %s",__func__);
							else	{
								NSData				*layoutAsData = [NSData dataWithBytes:layout length:layoutSize];
								if (layoutAsData==nil)
									NSLog(@"\t\terr: audio channel layout data nil in %s",__func__);
								else
									[outputSettings setObject:layoutAsData forKey:AVChannelLayoutKey];
							}
						}
						//NSLog(@"\t\taudio output settings are %@",outputSettings);
						newInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:outputSettings];
					}
					else	{
						newInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:nil];
					}
				}
				//	else this is an "other"-type track
				else	{
					newInput = [AVAssetWriterInput assetWriterInputWithMediaType:[assetTrack mediaType] outputSettings:nil];
				}
				
				//	if i didn't make a new input, add an NSNull placeholder to the array of inputs
				if (newInput == nil)	{
					[writerInputs addObject:[NSNull null]];
				}
				else	{
					if (![writer canAddInput:newInput])	{
						NSLog(@"\t\terr: couldn't add writer input for track %@ in %s",assetTrack,__func__);
						NSLog(@"\t\toutputSettings were %@",[newInput outputSettings]);
						//	insert an NSNull as a placeholder so i can associated audio/video tracks by index
						[writerInputs addObject:[NSNull null]];
					}
					else	{
						[writer addInput:newInput];
						[writerInputs addObject:newInput];
					}
				}
			}
			++localIndex;
		}
		
		
		//	tell the writer to start writing
		[writer startWriting];
		
		
		//NSLog(@"\t\tabout to start, outputs are %@, inputs are %@",readerOutputs,writerInputs);
		//	start the session (this actually starts processing data)
		[writer startSessionAtSourceTime:kCMTimeZero];
		
		
		//	run through the writer inputs, configuring each input to request data on a queue
		localIndex = 0;
		__block id					bss = self;
		NSEnumerator				*outputIt = nil;
		AVAssetReaderTrackOutput	*output = nil;
		NSEnumerator				*inputIt = nil;
		AVAssetWriterInput			*input = nil;
		
		//	now run through the inputs/outputs again, beginning the conversion process for everything
		outputIt = [readerOutputs objectEnumerator];
		output = [outputIt nextObject];
		inputIt = [writerInputs objectEnumerator];
		input = [inputIt nextObject];
		while (output!=nil && input!=nil)	{
			__block AVAssetReaderTrackOutput	*localOutput = output;
			__block AVAssetWriterInput			*localInput = input;
			//NSLog(@"\t\trunning through, output is %@, input is %@",localOutput,localInput);
			if ((id)localOutput!=(id)nsnull && (id)localInput!=(id)nsnull)	{
				//	if i'm not doing a multi-pass export, just tell the input to start requesting media.
				//	THIS IS ONLY NECESSARY BECAUSE OF HapInAVFoundation, WHICH DOESN'T PLAY NICE WITH respondToEachPassDescriptionOnQueue:usingBlock:
				if (!baseVideoMultiPassExport)	{
					__block NSUInteger		skippedBufferCount = 0;
					__block NSUInteger		renderedVideoFrameCount = 0;
					[localInput requestMediaDataWhenReadyOnQueue:writerQueue usingBlock:^{
						//NSLog(@"%s-requestMediaDataWhenReadyOnQueue:",__func__);
						//pthread_mutex_lock(&theLock);
						//BOOL		localPaused = paused;
						//pthread_mutex_unlock(&theLock);
						//if (localPaused)
						//	return;
						NSUInteger				runCount = 0;	//	if we don't limit the # of frames we write, this loop will actually write every frame, which prevents cancel or pause from working
						BOOL					isVideoTrack = ([localInput mediaType]==AVMediaTypeVideo) ? YES : NO;
						while ([localInput isReadyForMoreMediaData] && [writer status]==AVAssetWriterStatusWriting && runCount<5)	{
							CMSampleBufferRef		newRef = ([reader status]!=AVAssetReaderStatusReading) ? NULL : [localOutput copyNextSampleBuffer];
							//	prior to 10.14, really large images don't fail or error out, the asset reader just pretends everything's okay-
							//	we have to work around this by looking explicitly for an image and making sure it exists and is valid
							BOOL					imgBufferIsFineOrIrrelevant = YES;
							if (isVideoTrack)	{
								CVImageBufferRef		tmpImgBuffer = (newRef==NULL) ? NULL : CMSampleBufferGetImageBuffer(newRef);
								if (tmpImgBuffer == NULL)
									imgBufferIsFineOrIrrelevant = NO;
							}
							
							if (newRef!=NULL && imgBufferIsFineOrIrrelevant)	{
								//NSLog(@"\t\tcopied buffer at time %@",[(id)CMTimeCopyDescription(kCFAllocatorDefault,CMSampleBufferGetPresentationTimeStamp(newRef)) autorelease]);
								pthread_mutex_lock(&theLock);
								CMTime				tmpTime = CMSampleBufferGetPresentationTimeStamp(newRef);
								if (CMTIME_IS_VALID(tmpTime))
									normalizedProgress = CMTimeGetSeconds(tmpTime)/durationInSeconds;
								if (normalizedProgress>=1.0)
									normalizedProgress = 0.99;
								//NSLog(@"\t\tnormalizedProgress now %0.3f",normalizedProgress);
								pthread_mutex_unlock(&theLock);
								skippedBufferCount = 0;
								if (isVideoTrack)
									++renderedVideoFrameCount;
								[localInput appendSampleBuffer:newRef];
								CFRelease(newRef);
								newRef = NULL;
							}
							else	{
								++skippedBufferCount;
								//NSLog(@"\t\tunable to copy the buffer, skippedBufferCount is now %ld",skippedBufferCount);
								if (skippedBufferCount>4)	{
									//NSLog(@"\t\tmarking input as finished in single-pass export");
									[localInput markAsFinished];
									pthread_mutex_lock(&theLock);
									{
										//	if this was a video track, and it didn't render any video frames, and the img buffer wasn't fine- something went wrong!
										if (isVideoTrack && renderedVideoFrameCount==0 && !imgBufferIsFineOrIrrelevant)	{
											unexpectedErr = YES;
											if (errorString != nil)
												[errorString release];
											errorString = [@"Problem retrieving image buffer from AVFoundation" retain];
										}
										
										[readerOutputs removeObjectAtIndex:[readerOutputs indexOfObjectIdenticalTo:localOutput]];
										[writerInputs removeObjectAtIndex:[writerInputs indexOfObjectIdenticalTo:localInput]];
										
										int			readerOutputsCount = 0;
										int			writerInputsCount = 0;
										for (id tmpOutput in readerOutputs)	{
											if (tmpOutput!=nil && tmpOutput!=nsnull)
												++readerOutputsCount;
										}
										for (id tmpInput in writerInputs)	{
											if (tmpInput!=nil && tmpInput!=nsnull)
												++writerInputsCount;
										}
										
										if (readerOutputsCount==0 || writerInputsCount==0)	{
											[writer finishWritingWithCompletionHandler:^{
												[bss _finishWritingAndCleanUpShop];
											}];
										}
									}
									pthread_mutex_unlock(&theLock);
								}
								break;
							}
							++runCount;
						}
					}];
				}
				//	else i'm doing multi-pass export- i need to configure the input to respond to changes in the pass description...
				else	{
					__block NSUInteger		inputPassIndex = 0;	//	start at -1 because this will get incremented before the request block that references it will be called for the first time
					[localInput respondToEachPassDescriptionOnQueue:writerQueue usingBlock:^{
						//NSLog(@"%s-respondToEachPassDescriptionOnQueue:usingBlock:, input type is %@",__func__,[localInput mediaType]);
						__block NSUInteger						skippedBufferCount = 0;
						__block NSUInteger						renderedVideoFrameCount = 0;
						AVAssetWriterInputPassDescription		*tmpDesc = [localInput currentPassDescription];
						//NSLog(@"\t\tcurrent pass description is %@",tmpDesc);
						//	if there's no pass description, mark the input as being finished and remove them
						if (tmpDesc==nil)	{
							//NSLog(@"\t\tno pass description, marking input as finished");
							[localInput markAsFinished];
							pthread_mutex_lock(&theLock);
							{
								[readerOutputs removeObjectAtIndex:[readerOutputs indexOfObjectIdenticalTo:localOutput]];
								[writerInputs removeObjectAtIndex:[writerInputs indexOfObjectIdenticalTo:localInput]];
								//	if there aren't any more inputs or outputs, we're done- clean up and finish
								if ([readerOutputs count]==0 || [writerInputs count]==0)	{
									[writer finishWritingWithCompletionHandler:^{
										[bss _finishWritingAndCleanUpShop];
									}];
								}
							}
							pthread_mutex_unlock(&theLock);
						}
						//	else there's a pass description, which means i need to do reading/writing/probably encoding
						else	{
							//NSLog(@"\t\tthere's a pass description, inputPassIndex is %lu",(unsigned long)inputPassIndex);
							
							//	if this isn't the first pass, before proceeding we need to reset the reader output to the time range of the pass description
							if (inputPassIndex>0)	{
								//	you can't resetForReadingTimeRanges until all the samples have been read from the output (until copyNextSampleBuffer returns NULL), so make sure this has happened...
								CMSampleBufferRef		junkBuffer = NULL;
								do	{
									if (junkBuffer!=NULL)	{
										CFRelease(junkBuffer);
										junkBuffer = NULL;
									}
									junkBuffer = [localOutput copyNextSampleBuffer];
								} while (junkBuffer!=NULL);
								
								//	sometimes, AVF gives conflicting time ranges, so we need to wrap this with an exception handler...
								@try	{
									if (errorString!=nil)	{
										[errorString release];
										errorString = nil;
									}
									[localOutput resetForReadingTimeRanges:[tmpDesc sourceTimeRanges]];
								}
								//	if i caught an exception, store an error string, then cancel
								@catch (NSException *err)	{
									NSLog(@"\t\terr: caught exception resetting time range, %@",err);
									errorString = [[err description] retain];
									dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
										[bss _cancelAndCleanUpShop];
									});
								}
							}
							
							
							//	if there's no error string, tell the writer input to begin requesting media data...
							if (errorString==nil)	{
								[localInput requestMediaDataWhenReadyOnQueue:writerQueue usingBlock:^{
									//NSLog(@"%s-requestMediaDataWhenReadyOnQueue:usingBlock:, input is %@",__func__,localInput);
									//pthread_mutex_lock(&theLock);
									//BOOL		localPaused = paused;
									//pthread_mutex_unlock(&theLock);
									//if (localPaused)
									//	return;
									NSUInteger				runCount = 0;	//	if we don't limit the # of frames we write, this loop will actually write every frame, which prevents cancel or pause from working
									BOOL					isVideoTrack = ([localInput mediaType]==AVMediaTypeVideo) ? YES : NO;
									while ([localInput isReadyForMoreMediaData] && [writer status]==AVAssetWriterStatusWriting && runCount<5)	{
										CMSampleBufferRef		newRef = [localOutput copyNextSampleBuffer];
										//	prior to 10.14, really large images don't fail or error out, the asset reader just pretends everything's okay-
										//	we have to work around this by looking explicitly for an image and making sure it exists and is valid
										BOOL					imgBufferIsFineOrIrrelevant = YES;
										if (isVideoTrack)	{
											CVImageBufferRef		tmpImgBuffer = (newRef==NULL) ? NULL : CMSampleBufferGetImageBuffer(newRef);
											if (tmpImgBuffer == NULL)
												imgBufferIsFineOrIrrelevant = NO;
										}
										
										if (newRef!=NULL && imgBufferIsFineOrIrrelevant)	{
											//NSLog(@"\t\tcopied buffer at time %@",[(id)CMTimeCopyDescription(kCFAllocatorDefault,CMSampleBufferGetPresentationTimeStamp(newRef)) autorelease]);
											pthread_mutex_lock(&theLock);
											CMTime		tmpTime = CMSampleBufferGetPresentationTimeStamp(newRef);
											double		tmpProgress = 0.0;
											if (CMTIME_IS_VALID(tmpTime))
												tmpProgress = (CMTimeGetSeconds(tmpTime)/durationInSeconds)/2.0;
											normalizedProgress = (inputPassIndex==1) ? tmpProgress : 0.5+tmpProgress;
											if (normalizedProgress>=1.0)
												normalizedProgress = 0.99;
											//NSLog(@"\t\ttmpProgress for input %p is %0.3f, passIndex is %ld, normalizedProgress now %0.3f",localInput,tmpProgress,inputPassIndex,normalizedProgress);
											pthread_mutex_unlock(&theLock);
											skippedBufferCount = 0;
											if (isVideoTrack)
												++renderedVideoFrameCount;
											[localInput appendSampleBuffer:newRef];
											CFRelease(newRef);
											newRef = NULL;
										}
										else	{
											++skippedBufferCount;
											//NSLog(@"\t\tunable to copy the buffer, skippedBufferCount is now %ld",skippedBufferCount);
											if (skippedBufferCount>4)	{
												[localInput markCurrentPassAsFinished];
												
												//	if this was a video track, and it didn't render any video frames, and the img buffer wasn't fine- something went wrong!
												if (isVideoTrack && renderedVideoFrameCount==0 && !imgBufferIsFineOrIrrelevant)	{
													unexpectedErr = YES;
													if (errorString != nil)
														[errorString release];
													errorString = [@"Problem retrieving image buffer from AVFoundation" retain];
												}
											}
											break;
										}
										++runCount;
									}
								}];
							}
						}
						
						//	increment the input pass index (tracked so i know when to reset the reading time ranges on the reader)
						++inputPassIndex;
					}];
				}
			}
			output = [outputIt nextObject];
			input = [inputIt nextObject];
			++localIndex;
		}
	}
	pthread_mutex_unlock(&theLock);
}
- (void) setPaused:(BOOL)p	{
	pthread_mutex_lock(&theLock);
	if (paused!=p)	{
		paused = p;
		if (writerQueue!=NULL)	{
			if (paused)
				dispatch_suspend(writerQueue);
			else
				dispatch_resume(writerQueue);
		}
	}
	pthread_mutex_unlock(&theLock);
}
- (void) cancel	{
	//[self clear];
	dispatch_async(writerQueue, ^{
		[self clear];
	});
}
- (void) _finishWritingAndCleanUpShop	{
	//NSLog(@"%s",__func__);
	pthread_mutex_lock(&theLock);
	id<VVAVFTranscoderDelegate>		localDelegate = delegate;
	if (reader != nil)	{
		[reader cancelReading];
		[reader release];
		reader = nil;
	}
	[readerOutputs removeAllObjects];
	
	for (AVAssetReaderOutput *output in readerOutputs)	{
		[output markConfigurationAsFinal];
	}
	
	if (writer != nil)	{
		//if (![writer finishWriting])
		//	NSLog(@"\t\tERR: couldn't finish writing in %s",__func__);
		[writer release];
		writer = nil;
	}
	[writerInputs removeAllObjects];
	if (srcAsset!=nil)	{
		[srcAsset release];
		srcAsset = nil;
	}
	normalizedProgress = (unexpectedErr) ? 0.0 : 1.0;
	//NSLog(@"\t\tnormalizedProgress now %0.3f",normalizedProgress);
	pthread_mutex_unlock(&theLock);
	
	//	if there was an unexpected error, move the file at "dstPath" (if it exists) to the trash
	if (unexpectedErr)	{
		NSFileManager		*fm = [NSFileManager defaultManager];
		if ([fm fileExistsAtPath:dstPath])	{
			[fm trashItemAtURL:[NSURL fileURLWithPath:dstPath] resultingItemURL:nil error:nil];
		}
	}
	
	if (localDelegate!=nil)
		[localDelegate finishedTranscoding:self];
}
- (void) _cancelAndCleanUpShop	{
	pthread_mutex_lock(&theLock);
	id<VVAVFTranscoderDelegate>		localDelegate = delegate;
	if (writer != nil)	{
		[writer cancelWriting];
		[writer release];
		writer = nil;
	}
	if (reader != nil)	{
		[reader cancelReading];
		[reader release];
		reader = nil;
	}
	[writerInputs removeAllObjects];
	[readerOutputs removeAllObjects];
	if (srcAsset!=nil)	{
		[srcAsset release];
		srcAsset = nil;
	}
	
	normalizedProgress = 0.0;
	//NSLog(@"\t\tnormalizedProgress now %0.3f",normalizedProgress);
	pthread_mutex_unlock(&theLock);
	
	//	because we're cancelling, move the file at "dstPath" (if it exists) to the trash
	NSFileManager		*fm = [NSFileManager defaultManager];
	if ([fm fileExistsAtPath:dstPath])	{
		[fm trashItemAtURL:[NSURL fileURLWithPath:dstPath] resultingItemURL:nil error:nil];
	}
	
	if (localDelegate!=nil)
		[localDelegate finishedTranscoding:self];
}
- (void) clear	{
	//	if there's a writer/etc, cancel the writing, remove the writer input, then free everything
	pthread_mutex_lock(&theLock);
	//id<VVAVFTranscoderDelegate>		localDelegate = delegate;
	if (writer != nil)	{
		[writer cancelWriting];
		[writer release];
		writer = nil;
	}
	if (reader != nil)	{
		[reader cancelReading];
		[reader release];
		reader = nil;
	}
	[writerInputs removeAllObjects];
	[readerOutputs removeAllObjects];
	if (srcAsset!=nil)	{
		[srcAsset release];
		srcAsset = nil;
	}
	if (srcPath!=nil)	{
		[srcPath release];
		srcPath = nil;
	}
	if (dstPath!=nil)	{
		[dstPath release];
		dstPath = nil;
	}
	if (errorString!=nil)	{
		[errorString release];
		errorString = nil;
	}
	pthread_mutex_unlock(&theLock);
	
	//if (localDelegate!=nil)
	//	[localDelegate finishedTranscoding:self];
}


- (void) setVideoExportSettings:(NSMutableDictionary *)n	{
	pthread_mutex_lock(&theLock);
	if (videoExportSettings!=nil)
		[videoExportSettings release];
	videoExportSettings = (n==nil) ? nil : [n retain];
	pthread_mutex_unlock(&theLock);
}
- (void) setAudioExportSettings:(NSMutableDictionary *)n	{
	pthread_mutex_lock(&theLock);
	if (audioExportSettings!=nil)
		[audioExportSettings release];
	audioExportSettings = (n==nil) ? nil : [n retain];
	pthread_mutex_unlock(&theLock);
}


- (double) normalizedProgress	{
	double		returnMe = 0.0;
	pthread_mutex_lock(&theLock);
	returnMe = normalizedProgress;
	pthread_mutex_unlock(&theLock);
	return returnMe;
}


- (void) setDelegate:(id<VVAVFTranscoderDelegate>)n	{
	pthread_mutex_lock(&theLock);
	delegate = n;
	pthread_mutex_unlock(&theLock);
}
- (id<VVAVFTranscoderDelegate>) delegate	{
	id<VVAVFTranscoderDelegate>		returnMe = nil;
	pthread_mutex_lock(&theLock);
	returnMe = delegate;
	pthread_mutex_unlock(&theLock);
	return returnMe;
}
- (NSString *) srcPath	{
	NSString		*returnMe = nil;
	pthread_mutex_lock(&theLock);
	returnMe = (srcPath==nil) ? nil : [[srcPath retain] autorelease];
	pthread_mutex_unlock(&theLock);
	return returnMe;
}
- (NSString *) dstPath	{
	NSString		*returnMe = nil;
	pthread_mutex_lock(&theLock);
	returnMe = (dstPath==nil) ? nil : [[dstPath retain] autorelease];
	pthread_mutex_unlock(&theLock);
	return returnMe;
}
- (NSString *) errorString	{
	NSString		*returnMe = nil;
	pthread_mutex_lock(&theLock);
	returnMe = (errorString==nil) ? nil : [[errorString retain] autorelease];
	pthread_mutex_unlock(&theLock);
	return returnMe;
}


@end








/*
OSType VVPackFourCC_fromChar(char *charPtr)	{
	return (OSType)(charPtr[0]<<24 | charPtr[1]<<16 | charPtr[2]<<8 | charPtr[3]);
}
*/
