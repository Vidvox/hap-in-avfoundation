//
//  VVAVFTranscoder.m
//  VVAVFTranscodeTestApp
//
//  Created by testadmin on 2/8/24.
//

#import "VVAVFTranscoder.h"

#import "VVAVFTranscodeTrack.h"

#import <CoreVideo/CoreVideo.h>
#import <HapInAVFoundation/HapInAVFoundation.h>




NSString * const		kVVAVFTranscodeErrorDomain = @"kVVAVFTranscodeErrorDomain";




NSString * const		kVVAVFTranscodeStripMediaKey = @"VVAVStripMediaKey";

NSString * const		kVVAVFTranscodeMultiPassEncodeKey = @"VVAVVideoMultiPassEncodeKey";
NSString * const		kVVAVFTranscodeVideoResolutionKey = @"VVAVVideoResolutionKey";

//NSString * const		kAVFExportAudioSampleRateKey = @"kAVFExportAudioSampleRateKey";




@interface VVAVFTranscoder ()

@property (strong,readwrite) NSURL * src;
@property (strong,readwrite) NSURL * dst;
@property (strong,readwrite) NSDictionary * audioSettings;
@property (strong,readwrite) NSDictionary * videoSettings;

@property (strong) VVAVFTranscoderCompleteHandler completionHandler;

@property (readwrite,atomic) VVAVFTranscoderStatus status;

@property (strong,readwrite) AVAsset * asset;
@property (readwrite,atomic) CMTime assetDuration;
@property (readwrite,atomic) double normalizedProgress;
@property (readwrite,atomic) BOOL multiPassFlag;

@property (strong,readwrite) NSDate * startDate;
@property (strong,readwrite) NSError * error;

@property (strong,readwrite) AVAssetReader * reader;

@property (strong,readwrite) AVAssetWriter * writer;

@property (strong) NSMutableArray<VVAVFTranscodeTrack*> * transcodeTracks;

- (void) _prepareTracks;
- (void) _beginTranscoding;
- (void) _cancel;

- (void) respondToPassDescriptionForTrack:(VVAVFTranscodeTrack *)inTrack;
- (void) requestPassMediaDataForTrack:(VVAVFTranscodeTrack *)inTrack;

- (void) finishJob;

@end




@implementation VVAVFTranscoder

+ (instancetype) createWithSrc:(NSURL *)inSrc dst:(NSURL *)inDst audioSettings:(NSDictionary *)inAudioSettings videoSettings:(NSDictionary *)inVideoSettings completionHandler:(VVAVFTranscoderCompleteHandler)ch	{
	return [[VVAVFTranscoder alloc] initWithSrc:inSrc dst:inDst audioSettings:inAudioSettings videoSettings:inVideoSettings completionHandler:ch];
}
- (instancetype) initWithSrc:(NSURL *)inSrc dst:(NSURL *)inDst audioSettings:(NSDictionary *)inAudioSettings videoSettings:(NSDictionary *)inVideoSettings completionHandler:(VVAVFTranscoderCompleteHandler)ch	{
	NSLog(@"%s",__func__);
	NSLog(@"\t\t%@",inAudioSettings);
	NSLog(@"\t\t%@",inVideoSettings);
	self = [super init];
	
	if (inSrc == nil || inDst == nil /*|| inAudioSettings == nil || inVideoSettings == nil*/)	{
		self = nil;
	}
	
	NSFileManager		*fm = [NSFileManager defaultManager];
	if (![fm fileExistsAtPath:inSrc.path] || [fm fileExistsAtPath:inDst.path])	{
		self = nil;
	}
	
	if (self != nil)	{
		_src = inSrc;
		_dst = inDst;
		_audioSettings = (inAudioSettings==nil) ? @{} : inAudioSettings;
		_videoSettings = (inVideoSettings==nil) ? @{} : inVideoSettings;
		_completionHandler = ch;
		_status = VVAVFTranscoderStatus_Paused;
		_asset = nil;
		//_assetDurationInSeconds = 1.0;
		_assetDuration = CMTimeMakeWithSeconds(1.0, 60000);
		_normalizedProgress = 0.0;
		_error = nil;
		_reader = nil;
		_writer = nil;
		_transcodeTracks = [NSMutableArray arrayWithCapacity:0];
		_paused = YES;
		
		NSError		*nsErr = nil;
		
		//	if we can't make the asset, its reader, or writer, bail
		_asset = [AVAsset assetWithURL:inSrc];
		if (_asset == nil)	{
			NSLog(@"ERR: making asset in %s",__func__);
			self = nil;
			return self;
		}
		//self.assetDurationInSeconds = CMTimeGetSeconds(_asset.duration);
		self.assetDuration = _asset.duration;
		
		_reader = [AVAssetReader assetReaderWithAsset:_asset error:&nsErr];
		if (_reader == nil || nsErr != nil)	{
			NSLog(@"ERR: (%@) making reader in %s",nsErr,__func__);
			self = nil;
			return self;
		}
		
		_writer = [AVAssetWriter assetWriterWithURL:inDst fileType:AVFileTypeQuickTimeMovie error:&nsErr];
		if (_writer == nil || nsErr != nil)	{
			NSLog(@"ERR: (%@) making writer in %s",nsErr,__func__);
			self = nil;
			return self;
		}
		
		//	create the reader outputs and writer inputs
		[self _prepareTracks];
	}
	
	return self;
}

//- (void) dealloc	{
//	NSLog(@"%s",__func__);
//}

- (void) _prepareTracks	{
	//NSLog(@"%s",__func__);
	NSDictionary		*intermediateVideoSettings = @{
		//(NSString*)kCVPixelBufferPixelFormatTypeKey: @( kCVPixelFormatType_32ARGB ),
		//(NSString*)kCVPixelBufferPixelFormatTypeKey: @( kCVPixelFormatType_32RGBA ),
		(NSString*)kCVPixelBufferPixelFormatTypeKey: @( kCVPixelFormatType_32BGRA )
	};
	NSDictionary		*intermediateAudioSettings = @{
		AVFormatIDKey: @(kAudioFormatLinearPCM),
		AVLinearPCMBitDepthKey: @(32),
		AVLinearPCMIsBigEndianKey: @(NO),
		AVLinearPCMIsFloatKey: @(YES),
		AVLinearPCMIsNonInterleaved: @(YES),
		//kLinearPCMFormatFlagIsPacked: @(),	//	Synonym for kAudioFormatFlagIsPacked
		//kLinearPCMFormatFlagIsAlignedHigh: @(),	//	Synonym for kAudioFormatFlagIsAlignedHigh.
		//kLinearPCMFormatFlagIsNonMixable: @(),	//	Synonym for kAudioFormatFlagIsNonMixable.
		//kLinearPCMFormatFlagsAreAllClear: @(), //	Synonym for kAudioFormatFlagsAreAllClear.
		//kLinearPCMFormatFlagsSampleFractionShift: @(),
		//kLinearPCMFormatFlagsSampleFractionMask: @(),
	};
	NSNumber		*stripAudioNum = [_audioSettings objectForKey:kVVAVFTranscodeStripMediaKey];
	if (stripAudioNum == nil)
		stripAudioNum = @(NO);
	NSNumber		*stripVideoNum = [_videoSettings objectForKey:kVVAVFTranscodeStripMediaKey];
	if (stripVideoNum == nil)
		stripVideoNum = @(NO);
	
	NSNumber		*multiPassNum = [_videoSettings objectForKey:kVVAVFTranscodeMultiPassEncodeKey];
	if (multiPassNum == nil)
		multiPassNum = @(NO);
	else	{
		NSMutableDictionary		*tmpDict = [_videoSettings mutableCopy];
		[tmpDict removeObjectForKey:kVVAVFTranscodeMultiPassEncodeKey];
		_videoSettings = [NSDictionary dictionaryWithDictionary:tmpDict];
	}
	_multiPassFlag = multiPassNum.boolValue;
	
	NSValue			*exportSizeVal = nil;
	{
		NSNumber		*tmpWidth = [_videoSettings objectForKey:AVVideoWidthKey];
		NSNumber		*tmpHeight = [_videoSettings objectForKey:AVVideoHeightKey];
		if (tmpWidth != nil && tmpHeight != nil)	{
			exportSizeVal = [NSValue valueWithSize:NSMakeSize(tmpWidth.doubleValue,tmpHeight.doubleValue)];
		}
	}
	
	//NSNumber		*exportSampleRateNum = [_audioSettings objectForKey:AVSampleRateKey];
	
	
	for (AVAssetTrack * trackPtr in _asset.tracks)	{
		BOOL		transcodeThisTrack = YES;
		AVAssetReaderOutput		*readerOutput = nil;
		AVAssetWriterInput		*writerInput = nil;
		
		//	if the track isn't playable and isn't hap, we're going to skip the transcode and just copy it
		if (!trackPtr.isPlayable && !trackPtr.isHapTrack)	{
			NSLog(@"ERR: track %@ is not playable, skipping during transcode in %s",trackPtr,__func__);
			transcodeThisTrack = NO;
			readerOutput = nil;
			writerInput = nil;
		}
		//	else the track is either playable or hap, and i need to investigate further...
		else	{
			NSArray		*fmtDescs = trackPtr.formatDescriptions;
			NSUInteger		fmtDescsCount = (fmtDescs==nil) ? 0 : fmtDescs.count;
			//	if there are no format descriptions- or too many format descriptions- then i don't know what to do, and will skip the transcode
			if (fmtDescsCount==0)	{
				NSLog(@"ERR: track %@ doesn't have any format descriptions, skipping transcode regardless in %s",trackPtr,__func__);
				transcodeThisTrack = NO;
				readerOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:trackPtr outputSettings:nil];
				writerInput = [AVAssetWriterInput assetWriterInputWithMediaType:[trackPtr mediaType] outputSettings:nil];
				
				if (_multiPassFlag)	{
					readerOutput.supportsRandomAccess = YES;
					writerInput.performsMultiPassEncodingIfSupported = YES;
				}
				readerOutput.alwaysCopiesSampleData = NO;
				
				if (readerOutput != nil && writerInput != nil && [_reader canAddOutput:readerOutput] && [_writer canAddInput:writerInput])	{
					[_reader addOutput:readerOutput];
					[_writer addInput:writerInput];
					
					VVAVFTranscodeTrack		*transcodeTrack = [VVAVFTranscodeTrack create];
					transcodeTrack.queue = dispatch_queue_create("VVAVFTranscode otherQueue", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, DISPATCH_QUEUE_PRIORITY_HIGH, -1));
					transcodeTrack.track = trackPtr;
					transcodeTrack.output = readerOutput;
					transcodeTrack.input = writerInput;
					transcodeTrack.mediaType = @"";
					[_transcodeTracks addObject:transcodeTrack];
				}
			}
			//	else the format descriptions look okay, and i need to investigate further...
			else	{
				CMFormatDescriptionRef		trackFmt = (fmtDescsCount<1) ? NULL : (__bridge CMFormatDescriptionRef)[fmtDescs objectAtIndex:0];
				NSString		*trackMediaType = [trackPtr mediaType];
				if (trackMediaType == nil)	{
					NSLog(@"ERR: no track media type found for %@, skipping in %s",trackPtr,__func__);
					transcodeThisTrack = NO;
					readerOutput = nil;
					writerInput = nil;
				}
				//	if it's an audio track, i need to investigate further...
				else if ([trackMediaType isEqualToString:AVMediaTypeAudio])	{
					NSNumber		*formatNum = [_audioSettings objectForKey:AVFormatIDKey];
					if (formatNum == nil)	{
						transcodeThisTrack = NO;
					}
					
					AudioStreamBasicDescription		*asbd = (AudioStreamBasicDescription*)CMAudioFormatDescriptionGetStreamBasicDescription(trackFmt);
					NSMutableDictionary		*localSettings = [_audioSettings mutableCopy];
					//	if i'm not explicitly setting the sample rate & number of channels in the export settings then i need to supply the track's current sample rate and channel layout count
					if ([localSettings objectForKey:AVSampleRateKey] == nil)	{
						[localSettings setObject:@(asbd->mSampleRate) forKey:AVSampleRateKey];
					}
					if ([localSettings objectForKey:AVNumberOfChannelsKey] == nil)	{
						[localSettings setObject:@(asbd->mChannelsPerFrame) forKey:AVNumberOfChannelsKey];
					}
					//	also make sure that we're copying the channel layout from the track (we can only resample the sample rate so far!)
					if (trackFmt != NULL)	{
						size_t		layoutSize = 0;
						AudioChannelLayout		*layout = (AudioChannelLayout*)CMAudioFormatDescriptionGetChannelLayout(trackFmt, &layoutSize);
						if (layout != NULL)	{
							NSData		*layoutAsData = [NSData dataWithBytes:layout length:layoutSize];
							if (layoutAsData != nil)	{
								[localSettings setObject:layoutAsData forKey:AVChannelLayoutKey];
							}
							else
								NSLog(@"ERR: cannot make layout data for track %@ sized %ld in %s",trackPtr,layoutSize,__func__);
						}
						else
							NSLog(@"ERR: no audio layout for track %@ in %s",trackPtr,__func__);
					}
					else
						NSLog(@"ERR: no audio track fmt for track %@ in %s",trackPtr,__func__);
					
					//	if we're stripping the video then we're not transcoding it, no matter what!
					if (stripAudioNum.boolValue)	{
						transcodeThisTrack = NO;
						readerOutput = nil;
						writerInput = nil;
					}
					//	else if we're transcoding the track
					else if (transcodeThisTrack)	{
						readerOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:trackPtr outputSettings:intermediateAudioSettings];
						writerInput = [AVAssetWriterInput assetWriterInputWithMediaType:trackMediaType outputSettings:localSettings];
					}
					//	else we're NOT transcoding the track...
					else	{
						readerOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:trackPtr outputSettings:nil];
						writerInput = [AVAssetWriterInput assetWriterInputWithMediaType:trackMediaType outputSettings:nil];
					}
					
					if (_multiPassFlag)	{
						readerOutput.supportsRandomAccess = YES;
						writerInput.performsMultiPassEncodingIfSupported = YES;
					}
					readerOutput.alwaysCopiesSampleData = NO;
					
					if (readerOutput != nil && writerInput != nil && [_reader canAddOutput:readerOutput] && [_writer canAddInput:writerInput])	{
						[_reader addOutput:readerOutput];
						[_writer addInput:writerInput];
						
						VVAVFTranscodeTrack		*transcodeTrack = [VVAVFTranscodeTrack create];
						transcodeTrack.queue = dispatch_queue_create("VVAVFTranscode audioQueue", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, DISPATCH_QUEUE_PRIORITY_HIGH, -1));
						transcodeTrack.track = trackPtr;
						transcodeTrack.output = readerOutput;
						transcodeTrack.input = writerInput;
						transcodeTrack.mediaType = trackMediaType;
						[_transcodeTracks addObject:transcodeTrack];
					}
				}
				//	if it's a video track, i need to investigate further...
				else if ([trackMediaType isEqualToString:AVMediaTypeVideo])	{
					//	if there isn't a size match then we need to transcode it (even if we aren't changing codec settings)
					CMVideoDimensions		trackDims = CMVideoFormatDescriptionGetDimensions(trackFmt);
					NSSize		trackSize = NSMakeSize(trackDims.width, trackDims.height);
					
					NSMutableDictionary		*localSettings = [_videoSettings mutableCopy];
					//	if there's an explicit export size, and it differs from the track size...
					if (exportSizeVal != nil)	{
						NSSize		exportSize = exportSizeVal.sizeValue;
						if (!NSEqualSizes(trackSize, exportSize))	{
							//	make sure we're transcoding the track...
							transcodeThisTrack = YES;
						}
					}
					//	else there isn't an explicit export size- make sure the track's width + height are included in the video export settings dict!
					else	{
						[localSettings setObject:@(trackSize.width) forKey:AVVideoWidthKey];
						[localSettings setObject:@(trackSize.height) forKey:AVVideoHeightKey];
					}
					
					//	figure out if we're exporting to a hap codec...
					NSString		*codecString = [localSettings objectForKey:AVVideoCodecKey];
					BOOL			exportingToHap = (codecString!=nil 
					&& ([codecString isEqualToString:AVVideoCodecHap]
						|| [codecString isEqualToString:AVVideoCodecHapAlpha]
						|| [codecString isEqualToString:AVVideoCodecHapQ]
						|| [codecString isEqualToString:AVVideoCodecHapQAlpha]
						|| [codecString isEqualToString:AVVideoCodecHapAlphaOnly]
						|| [codecString isEqualToString:AVVideoCodecHap7Alpha]
						|| [codecString isEqualToString:AVVideoCodecHapHDR]
						));
					//NSLog(@"********** disabled hap7 and HDR here, %s",__func__);
					
					//	if we're stripping the video then we're not transcoding it, no matter what!
					if (stripVideoNum.boolValue)	{
						transcodeThisTrack = NO;
						readerOutput = nil;
						writerInput = nil;
					}
					//	else if we're transcoding the track
					else if (transcodeThisTrack)	{
						if (trackPtr.isHapTrack)	{
							readerOutput = [[AVAssetReaderHapTrackOutput alloc] initWithTrack:trackPtr outputSettings:intermediateVideoSettings];
						}
						else	{
							readerOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:trackPtr outputSettings:intermediateVideoSettings];
						}
						
						if (exportingToHap)	{
							writerInput = [[AVAssetWriterHapInput alloc] initWithOutputSettings:localSettings];
						}
						else	{
							writerInput = [AVAssetWriterInput assetWriterInputWithMediaType:trackMediaType outputSettings:localSettings];
						}
					}
					//	else we're NOT transcoding the track...
					else	{
						readerOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:trackPtr outputSettings:nil];
						writerInput = [AVAssetWriterInput assetWriterInputWithMediaType:trackMediaType outputSettings:nil];
					}
					
					if (_multiPassFlag)	{
						readerOutput.supportsRandomAccess = YES;
						writerInput.performsMultiPassEncodingIfSupported = YES;
					}
					readerOutput.alwaysCopiesSampleData = NO;
					
					if (readerOutput != nil && writerInput != nil && [_reader canAddOutput:readerOutput] && [_writer canAddInput:writerInput])	{
						[_reader addOutput:readerOutput];
						[_writer addInput:writerInput];
						
						VVAVFTranscodeTrack		*transcodeTrack = [VVAVFTranscodeTrack create];
						transcodeTrack.queue = dispatch_queue_create("VVAVFTranscode videoQueue", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, DISPATCH_QUEUE_PRIORITY_HIGH, -1));
						transcodeTrack.track = trackPtr;
						transcodeTrack.output = readerOutput;
						transcodeTrack.input = writerInput;
						transcodeTrack.mediaType = trackMediaType;
						[_transcodeTracks addObject:transcodeTrack];
					}
				}
				//	else if it's some other recognized track type...
				else if ([trackMediaType isEqualToString:AVMediaTypeText] || [trackMediaType isEqualToString:AVMediaTypeClosedCaption] || [trackMediaType isEqualToString:AVMediaTypeSubtitle] || [trackMediaType isEqualToString:AVMediaTypeTimecode] || [trackMediaType isEqualToString:AVMediaTypeMetadata] || [trackMediaType isEqualToString:AVMediaTypeMuxed])	{
					transcodeThisTrack = NO;
					readerOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:trackPtr outputSettings:nil];
					writerInput = [AVAssetWriterInput assetWriterInputWithMediaType:trackMediaType outputSettings:nil];
					
					if (_multiPassFlag)	{
						readerOutput.supportsRandomAccess = YES;
						writerInput.performsMultiPassEncodingIfSupported = YES;
					}
					readerOutput.alwaysCopiesSampleData = NO;
					
					if (readerOutput != nil && writerInput != nil && [_reader canAddOutput:readerOutput] && [_writer canAddInput:writerInput])	{
						[_reader addOutput:readerOutput];
						[_writer addInput:writerInput];
						
						VVAVFTranscodeTrack		*transcodeTrack = [VVAVFTranscodeTrack create];
						transcodeTrack.queue = dispatch_queue_create("VVAVFTranscode timecodeQueue", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, DISPATCH_QUEUE_PRIORITY_HIGH, -1));
						transcodeTrack.track = trackPtr;
						transcodeTrack.output = readerOutput;
						transcodeTrack.input = writerInput;
						transcodeTrack.mediaType = trackMediaType;
						[_transcodeTracks addObject:transcodeTrack];
					}
				}
				//	else it's an unknown track type- i need to skip the transcode
				else	{
					NSLog(@"\t\terr: track %@ isn't used by this software, skipping transcode and stripping in %s",trackPtr,__func__);
					transcodeThisTrack = NO;
					readerOutput = nil;
					writerInput = nil;
				}
			}
		}
	}	//	end 'for' loop running across asset tracks
	
	
}
- (void) _beginTranscoding	{
	NSLog(@"%s",__func__);
	
	self.startDate = [NSDate date];
	
	//	start reading and writing
	[_reader startReading];
	[_writer startWriting];
	[_writer startSessionAtSourceTime:kCMTimeZero];
	
	//	if we're NOT doing a multi-pass encode then we may be working with hap- so we need to do a simple, 'requestMediaDataWhenReadyOnQueue' approach
	if (!_multiPassFlag)	{
	}
	//	else this is a multi-pass transcode
	else	{
	}
	
	//	run through the tracks and configure the writer inputs to request data from the reader outputs...
	__weak VVAVFTranscoder		*weakSelf = self;
	for (VVAVFTranscodeTrack * track in _transcodeTracks)	{
		
		__weak VVAVFTranscodeTrack * weakTrack = track;	//	the track retains input which retains block which retains track is a retain loop- we avoid it by making the block "retain" a weak ref...
		
		//	configure it to respond to pass descriptions to support multi-pass rendering
		[track.input respondToEachPassDescriptionOnQueue:track.queue usingBlock:^{
			//VVAVFTranscoder		*bsSelf = weakSelf;
			//VVAVFTranscodeTrack		*bsTrack = weakTrack;
			//if (bsSelf == nil || bsTrack == nil)
			//	return;
			//[bsSelf respondToPassDescriptionForTrack:bsTrack];
			[weakSelf respondToPassDescriptionForTrack:weakTrack];
		}];
		
		
		//track.skippedBufferCount = 0;
		//track.processedBufferCount = 0;
		//[track.input requestMediaDataWhenReadyOnQueue:track.queue usingBlock:^{
		//	//VVAVFTranscoder		*bsSelf = weakSelf;
		//	//VVAVFTranscodeTrack		*bsTrack = weakTrack;
		//	//if (bsSelf == nil || bsTrack == nil)
		//	//	return;
		//	//[bsSelf requestMediaDataForTrack:bsTrack];
		//	[weakSelf requestMediaDataForTrack:weakTrack];
		//}];
	}
	
	//	i have to call this again to actually start processing the data...
	//[_writer startSessionAtSourceTime:kCMTimeZero];
}

- (void) _cancel	{
	NSLog(@"%s",__func__);
	[_reader cancelReading];
	[_writer cancelWriting];
	for (VVAVFTranscodeTrack * track in _transcodeTracks)	{
		[track.output markConfigurationAsFinal];
	}
	[_transcodeTracks removeAllObjects];
}

- (void) respondToPassDescriptionForTrack:(VVAVFTranscodeTrack *)inTrack	{
	//NSLog(@"%s ... %@",__func__,inTrack);
	if (inTrack == nil)
		return;
	inTrack.finished = NO;
	inTrack.skippedBufferCount = 0;
	inTrack.audioFirstSampleFlag = 0;
	inTrack.timecodeFirstSampleFlag = 0;
	
	//inTrack.passIndex = 0;
	
	__weak VVAVFTranscoder		*weakSelf = self;
	__weak VVAVFTranscodeTrack		*weakTrack = inTrack;
	
	//	if there's no input pass description then we're done processing this track!
	AVAssetWriterInputPassDescription		*inputPassDesc = inTrack.input.currentPassDescription;
	if (inputPassDesc == nil)	{
		NSLog(@"\t\tmarking track as finished after %ld buffers...",inTrack.processedBufferCount);
		inTrack.finished = YES;
		//	mark the writer input as finished...
		[inTrack.input markAsFinished];
		
		@synchronized (self)	{
			//	how many tracks are NOT finished?
			int			unfinishedTrackCount = 0;
			for (VVAVFTranscodeTrack * track in _transcodeTracks)	{
				if (!track.finished)
					++unfinishedTrackCount;
			}
			//	if we're finished processing every track...
			if (unfinishedTrackCount == 0)	{
				NSLog(@"\t\tall tracks finished- should be finishing writer...");
				//	tell the writer to end the session, then schedule a block to call our 'finishJob' method to finish cleaning up
				if (self.writer.status == AVAssetWriterStatusWriting)
					[self.writer endSessionAtSourceTime:self.assetDuration];
				
				if (self.writer.status == AVAssetWriterStatusCancelled)	{
					[weakSelf finishJob];
				}
				else	{
					[self.writer finishWritingWithCompletionHandler:^{
						//VVAVFTranscoder		*bsSelf = weakSelf;
						//if (bsSelf == nil)
						//	return;
						//[bsSelf finishJob];
						[weakSelf finishJob];
					}];
				}
			}
		}
	}
	//	else there's an input pass description- we need to configure the input to request data from the output as needed!
	else	{
		//	if this isn't the first pass then we have to reset the reader's time range
		if (inTrack.passIndex > 0)	{
			//NSLog(@"\t\tresetting the time range...");
			//	finish reading anything from the output
			CMSampleBufferRef		junkBuffer = NULL;
			do	{
				if (junkBuffer != NULL)	{
					CFRelease(junkBuffer);
					junkBuffer = NULL;
				}
				junkBuffer = [inTrack.output copyNextSampleBuffer];
			} while (junkBuffer != NULL);
			
			//	reset the output's time ranges, cancel the whole job if there's a problem
			@try	{
				//[inTrack.output resetForReadingTimeRanges:@[[NSValue valueWithCMTimeRange:inTrack.track.timeRange]]];
				[inTrack.output resetForReadingTimeRanges:inputPassDesc.sourceTimeRanges];
			}
			@catch (NSException *exc)	{
				NSString		*tmpString = [NSString stringWithFormat:@"ERR: (%@) responding to pass description in %s",exc,__func__];
				NSLog(@"ERR: %@",tmpString);
				self.error = [NSError errorWithDomain:kVVAVFTranscodeErrorDomain code:0 userInfo:@{ NSLocalizedDescriptionKey: tmpString }];
				self.status = VVAVFTranscoderStatus_Error;
				dispatch_async(dispatch_get_main_queue(), ^{
					@synchronized (self)	{
						[self _cancel];
					}
					if (self.completionHandler != nil)	{
						self.completionHandler(self);
					}
				});
				return;
			}
		}
		
		//NSLog(@"\t\tbeginning to process track...");
		//	configure the track's writer input to request data from its reader output on its queue as needed
		[inTrack.input requestMediaDataWhenReadyOnQueue:inTrack.queue usingBlock:^{
			//VVAVFTranscoder		*bsSelf = weakSelf;
			//VVAVFTranscodeTrack		*bsTrack = weakTrack;
			//if (bsSelf == nil || bsTrack == nil)
			//	return;
			//[bsSelf requestPassMediaDataForTrack:bsTrack];
			[weakSelf requestPassMediaDataForTrack:weakTrack];
		}];
	}
}

- (void) requestPassMediaDataForTrack:(VVAVFTranscodeTrack *)inTrack	{
	//NSLog(@"%s ... %@",__func__,inTrack);
	if (inTrack == nil)
		return;
	
	//__weak VVAVFTranscoder	*weakSelf = self;
	int			limiter = 5;
	while (inTrack.input.isReadyForMoreMediaData && _writer.status==AVAssetWriterStatusWriting && limiter>=0)	{
		--limiter;
		CMSampleBufferRef		newRef = (_reader.status!=AVAssetReaderStatusReading) ? NULL : [inTrack.output copyNextSampleBuffer];
		//	prior to 10.14, really large images don't fail or error out, the asset reader just pretends everything's okay-
		//	we have to work around this by looking explicitly for an image and making sure it exists and is valid
		BOOL		imgBufferIsFineOrIrrelevant = YES;
		BOOL		isVideoTrack = ([inTrack.mediaType isEqualToString:AVMediaTypeVideo]) ? YES : NO;
		if (isVideoTrack)	{
			CVImageBufferRef		tmpImgBuffer = (newRef==NULL) ? NULL : CMSampleBufferGetImageBuffer(newRef);
			if (tmpImgBuffer == NULL)
				imgBufferIsFineOrIrrelevant = NO;
		}
		
		if (newRef != NULL && imgBufferIsFineOrIrrelevant)	{
			inTrack.skippedBufferCount = 0;
			++inTrack.processedBufferCount;
			
			//	since video's likely the bottleneck, we'll use that to calculate progress for this pass as a whole
			CMTime		tmpTime = CMSampleBufferGetPresentationTimeStamp(newRef);
			if (CMTIME_IS_VALID(tmpTime) && isVideoTrack)	{
				double		tmpVal = CMTimeGetSeconds(tmpTime) / CMTimeGetSeconds(self.assetDuration);
				tmpVal = fminl(1.0, tmpVal);
				self.normalizedProgress = tmpVal;
			}
			
			[inTrack.input appendSampleBuffer:newRef];
		}
		else	{
			++inTrack.skippedBufferCount;
			if (inTrack.skippedBufferCount > 10)	{
				
				//	if this was a video track and it didn't render any frames, something went wrong
				if (isVideoTrack && inTrack.processedBufferCount == 0 && !imgBufferIsFineOrIrrelevant)	{
					NSLog(@"ERR: problem processing track %@ for file %@",inTrack.track,_src.lastPathComponent);
				}
				
				//	mark the track (and, specifically, its writer input!) as being finished
				++inTrack.passIndex;
				[inTrack.input markCurrentPassAsFinished];
			}
		}
		
		if (newRef != NULL)	{
			CFRelease(newRef);
			newRef = NULL;
		}
	}
}

- (void) finishJob	{
	//NSLog(@"%s",__func__);
	@synchronized (self)	{
		[_reader cancelReading];
		for (VVAVFTranscodeTrack * track in _transcodeTracks)	{
			[track.output markConfigurationAsFinal];
		}
	}
	
	self.status = VVAVFTranscoderStatus_Complete;
	NSDate		*endDate = [NSDate date];
	double		transcodeDuration = [endDate timeIntervalSinceDate:self.startDate];
	NSLog(@"**** transcode finished, took %0.4f seconds",transcodeDuration);
	NSLog(@"transcode : asset time ratio is %0.4f (lower is better)",transcodeDuration/CMTimeGetSeconds(_assetDuration));
	
	if (_completionHandler != nil)	{
		dispatch_async(dispatch_get_main_queue(), ^{
			self.completionHandler(self);
		});
	}
}

@synthesize paused=_paused;
- (void) setPaused:(BOOL)n	{
	NSLog(@"%s ... %d",__func__,n);
	VVAVFTranscoderStatus		origStatus = self.status;
	//	if we're already complete or we've errored out, bail immediately
	if (origStatus == VVAVFTranscoderStatus_Complete || origStatus == VVAVFTranscoderStatus_Error || origStatus == VVAVFTranscoderStatus_Cancelled)
		return;
	
	BOOL		changed = NO;
	
	@synchronized (self)	{
		changed = (_paused != n);
		_paused = n;
		if (changed)	{
			//	if we should now be paused, suspend the dispatch queues
			if (_paused)	{
				for (VVAVFTranscodeTrack * transcodeTrack in _transcodeTracks)	{
					if (transcodeTrack.queue != NULL)	{
						dispatch_suspend(transcodeTrack.queue);
					}
				}
			}
			//	else we should no longer be paused
			else	{
				//	the first time we un-pause, the job may not even be running yet- if that's the case, we'll need to actually start things
				if (_reader.status == AVAssetReaderStatusUnknown)	{
					//NSLog(@"\t\tfirst time un-pause, beginning to read/write");
					[self _beginTranscoding];
				}
				else	{
					//NSLog(@"\t\talready started, just resuming");
					for (VVAVFTranscodeTrack * transcodeTrack in _transcodeTracks)	{
						if (transcodeTrack.queue != NULL)	{
							dispatch_resume(transcodeTrack.queue);
						}
					}
				}
			}
		}
	}
	
	if (changed)	{
		self.status = (n) ? VVAVFTranscoderStatus_Paused : VVAVFTranscoderStatus_Processing;
	}
}
- (BOOL) paused	{
	@synchronized (self)	{
		return _paused;
	}
}

- (void) cancel	{
	@synchronized (self)	{
		[self _cancel];
	}
	
	self.status = VVAVFTranscoderStatus_Cancelled;
	
	if (_completionHandler != nil)	{
		dispatch_async(dispatch_get_main_queue(), ^{
			self.completionHandler(self);
		});
	}
}

@end
