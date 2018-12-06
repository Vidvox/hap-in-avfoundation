#import "VVAVFExportBasicSettingsCtrlr.h"




NSString *const		VVAVStripMediaKey = @"VVAVStripMediaKey";
NSString *const		VVAVVideoMultiPassEncodeKey = @"VVAVVideoMultiPassEncodeKey";




#import <AppKit/AppKit.h>
//	not actually a macro- a function to replace NSRunAlertPanel, which is deprecated in 10.10
NSInteger VVRunAlertPanel(NSString *title, NSString *msg, NSString *btnA, NSString *btnB, NSString *btnC);
NSInteger VVRunAlertPanelSuppressString(NSString *title, NSString *msg, NSString *btnA, NSString *btnB, NSString *btnC, NSString *suppressString, BOOL *returnSuppressValue);




@implementation NSTabView (NSTabViewAdditions)
- (NSInteger) selectedTabViewItemIndex	{
	NSInteger		returnMe = -1;
	NSTabViewItem	*selectedItem = [self selectedTabViewItem];
	if (selectedItem!=nil)	{
		returnMe = [self indexOfTabViewItem:selectedItem];
	}
	return returnMe;
}
@end

@implementation NSPopUpButton (NSPopUpButtonAdditions)
- (BOOL) selectItemWithRepresentedObject:(id)n	{
	if (n==nil)
		return NO;
	BOOL		returnMe = NO;
	NSArray		*items = [self itemArray];
	for (NSMenuItem *itemPtr in items)	{
		id			itemRepObj = [itemPtr representedObject];
		if (itemRepObj!=nil && [itemRepObj isEqualTo:n])	{
			returnMe = YES;
			[self selectItem:itemPtr];
			break;
		}
	}
	return returnMe;
}
@end




@implementation VVAVFExportBasicSettingsCtrlr


- (id) init	{
	//NSLog(@"%s",__func__);
	if (self = [super init])	{
		displayVideoDims = NSMakeSize(4,3);
		displayAudioResampleRate = 44100;
		canPerformMultiplePasses = YES;
		//	create the nib from my class name
		theNib = [[NSNib alloc] initWithNibNamed:[self className] bundle:[NSBundle bundleForClass:[self class]]];
		//	unpack the nib, instantiating the object
		[theNib instantiateWithOwner:self topLevelObjects:&nibTopLevelObjects];
		//	retain the array of top-level objects (they have to be explicitly freed later)
		[nibTopLevelObjects retain];
		return self;
	}
	[self release];
	return nil;
}
- (void) awakeFromNib	{
	
	
	//	populate the codec pop-up button.  each item's representedObject should be the string of the codec type...
	[vidCodecPUB removeAllItems];
	NSMenuItem				*newItem = nil;
	NSMenu					*theMenu = [vidCodecPUB menu];
	newItem = [[NSMenuItem alloc] initWithTitle:@"PJPEG" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoCodecJPEG];
	[theMenu addItem:[newItem autorelease]];
	newItem = [[NSMenuItem alloc] initWithTitle:@"H264" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoCodecH264];
	[theMenu addItem:[newItem autorelease]];
	newItem = [[NSMenuItem alloc] initWithTitle:@"ProRes 422" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoCodecAppleProRes422];
	[theMenu addItem:[newItem autorelease]];
	newItem = [[NSMenuItem alloc] initWithTitle:@"ProRes 4444" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoCodecAppleProRes4444];
	[theMenu addItem:[newItem autorelease]];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Hap" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoCodecHap];
	[theMenu addItem:[newItem autorelease]];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Hap Alpha" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoCodecHapAlpha];
	[theMenu addItem:[newItem autorelease]];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Hap Q" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoCodecHapQ];
	[theMenu addItem:[newItem autorelease]];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Hap Q Alpha" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoCodecHapQAlpha];
	[theMenu addItem:[newItem autorelease]];
	
	
	//	populate the h.264 video profiles pop-up button- again, the representedObject is the string of the property...
	[h264ProfilesPUB removeAllItems];
	theMenu = [h264ProfilesPUB menu];
	
	
	newItem = [[NSMenuItem alloc] initWithTitle:@"Baseline Profile 3.0" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoProfileLevelH264Baseline30];
	[theMenu addItem:[newItem autorelease]];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Baseline Profile 3.1" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoProfileLevelH264Baseline31];
	[theMenu addItem:[newItem autorelease]];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Baseline Profile 4.1" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoProfileLevelH264Baseline41];
	[theMenu addItem:[newItem autorelease]];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Baseline Profile Auto Level" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoProfileLevelH264BaselineAutoLevel];
	[theMenu addItem:[newItem autorelease]];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Main Profile 3.0" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoProfileLevelH264Main30];
	[theMenu addItem:[newItem autorelease]];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Main Profile 3.1" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoProfileLevelH264Main31];
	[theMenu addItem:[newItem autorelease]];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Main Profile 3.2" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoProfileLevelH264Main32];
	[theMenu addItem:[newItem autorelease]];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Main Profile 4.1" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoProfileLevelH264Main41];
	[theMenu addItem:[newItem autorelease]];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Main Profile Auto Level" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoProfileLevelH264MainAutoLevel];
	[theMenu addItem:[newItem autorelease]];
	newItem = [[NSMenuItem alloc] initWithTitle:@"High Profile 4.0" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoProfileLevelH264High40];
	[theMenu addItem:[newItem autorelease]];
	newItem = [[NSMenuItem alloc] initWithTitle:@"High Profile 4.1" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoProfileLevelH264High41];
	[theMenu addItem:[newItem autorelease]];
	newItem = [[NSMenuItem alloc] initWithTitle:@"High Profile Auto Level" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoProfileLevelH264HighAutoLevel];
	[theMenu addItem:[newItem autorelease]];
	//	select a default h.264 profile
	[h264ProfilesPUB selectItemAtIndex:[[[h264ProfilesPUB menu] itemArray] count]-1];
	
	[hapChunkField setStringValue:@"1"];
	[hapChunkField setEnabled:NO];
	[hapQChunkField setStringValue:@"1"];
	[hapQChunkField setEnabled:NO];
	
	//	select a video codec (PJPEG by default), trigger a UI item method to set everything up with a default value
	[vidCodecPUB selectItemAtIndex:0];
	[self vidCodecPUBUsed:vidCodecPUB];
	
	
	[vidWidthField setStringValue:@"40"];
	[vidHeightField setStringValue:@"30"];
	
	
	[audioCodecPUB removeAllItems];
	theMenu = [audioCodecPUB menu];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Linear PCM" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:[NSNumber numberWithInteger:kAudioFormatLinearPCM]];
	[theMenu addItem:[newItem autorelease]];
	newItem = [[NSMenuItem alloc] initWithTitle:@"AAC" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:[NSNumber numberWithInteger:kAudioFormatMPEG4AAC]];
	[theMenu addItem:[newItem autorelease]];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Apple Lossless" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:[NSNumber numberWithInteger:kAudioFormatAppleLossless]];
	[theMenu addItem:[newItem autorelease]];
	
	[audioCodecPUB selectItemAtIndex:0];
	[self audioCodecPUBUsed:audioCodecPUB];
	
	
	unsigned long		pcmBitDepths[] = {8,16,24,32};
	[pcmBitsPUB removeAllItems];
	theMenu = [pcmBitsPUB menu];
	for (int i=0; i<4; ++i)	{
		newItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%ld",pcmBitDepths[i]] action:nil keyEquivalent:@""];
		[newItem setRepresentedObject:[NSNumber numberWithUnsignedLong:pcmBitDepths[i]]];
		[theMenu addItem:[newItem autorelease]];
	}
	[pcmBitsPUB selectItemAtIndex:1];
	[self pcmBitsPUBUsed:pcmBitsPUB];
	
	
	[aacBitrateStrategyPUB removeAllItems];
	theMenu = [aacBitrateStrategyPUB menu];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Constant bitrate" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVAudioBitRateStrategy_Constant];
	[theMenu addItem:[newItem autorelease]];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Long-Term Average" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVAudioBitRateStrategy_LongTermAverage];
	[theMenu addItem:[newItem autorelease]];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Variable Constrained" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVAudioBitRateStrategy_VariableConstrained];
	[theMenu addItem:[newItem autorelease]];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Variable bitrate" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVAudioBitRateStrategy_Variable];
	[theMenu addItem:[newItem autorelease]];
	[aacBitrateStrategyPUB selectItemAtIndex:0];
	
	
	//	i can't populate the aac bitrate menu programmatically- the values it returns don't actually work, so just stick with a list of known-good bitrates (from quicktime)
	//[self populateMenu:[aacBitratePUB menu] withItemsForAudioProperty:kAudioFormatProperty_AvailableEncodeBitRates ofAudioFormat:kAudioFormatMPEG4AAC];
	unsigned long		kbpsBitrates[] = {16,20,24,28,32,40,48,56,64,72,80,96,112,128,144,160,192,224,256,288,320};
	[aacBitratePUB removeAllItems];
	theMenu = [aacBitratePUB menu];
	for (int i=0; i<21; ++i)	{
		newItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%ld",kbpsBitrates[i]] action:nil keyEquivalent:@""];
		[newItem setRepresentedObject:[NSNumber numberWithUnsignedLong:kbpsBitrates[i]*1000]];
		[theMenu addItem:[newItem autorelease]];
	}
	[aacBitratePUB selectItemWithTitle:@"160"];
	
	
	unsigned long		hintBitDepths[] = {16,20,24,32};
	[losslessBitDepthPUB removeAllItems];
	theMenu = [losslessBitDepthPUB menu];
	for (int i=0; i<4; ++i)	{
		newItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%ld",hintBitDepths[i]] action:nil keyEquivalent:@""];
		[newItem setRepresentedObject:[NSNumber numberWithUnsignedLong:hintBitDepths[i]]];
		[theMenu addItem:[newItem autorelease]];
	}
	[losslessBitDepthPUB selectItemAtIndex:0];
	
	
	//	the AAC encoder is the only encoder that ONLY works with a limited and explicit set of sample rates, so i'm going to use that as the list of values in the PUB
	[self populateMenu:[audioResamplePUB menu] withItemsForAudioProperty:kAudioFormatProperty_AvailableEncodeSampleRates ofAudioFormat:kAudioFormatMPEG4AAC];
	[audioResamplePUB selectItemAtIndex:7];	//	actuall selects 44.1 khz
	[self audioResamplePUBUsed:audioResamplePUB];
}
- (void) dealloc	{
	//	free this (i retained it explicitly earlier)
	if (nibTopLevelObjects != nil)	{
		[nibTopLevelObjects release];
		nibTopLevelObjects = nil;
	}
	//	release the nib
	if (theNib != nil)	{
		[theNib release];
		theNib = nil;
	}
	[super dealloc];
}


- (NSMutableDictionary *) createVideoOutputSettingsDict	{
	NSMutableDictionary		*returnMe = [NSMutableDictionary dictionaryWithCapacity:0];
	switch ([vidCategoryTabView selectedTabViewItemIndex])	{
	//	no transcoding
	case 0:	{
		switch ([vidNoTranscodeMatrix selectedRow])	{
		//	strip video
		case 0:
			[returnMe setObject:@YES forKey:VVAVStripMediaKey];
			break;
		//	copy video
		case 1:
			break;
		}
		break;
	}
	//	transcoding
	case 1:
		{
			//	video codec
			NSString		*codecString = [[vidCodecPUB selectedItem] representedObject];
			[returnMe setObject:codecString forKey:AVVideoCodecKey];
			//	pjpeg
			if ([codecString isEqualToString:AVVideoCodecJPEG])	{
				NSMutableDictionary		*compProps = [NSMutableDictionary dictionaryWithCapacity:0];
				[returnMe setObject:compProps forKey:AVVideoCompressionPropertiesKey];
				[compProps setObject:[NSNumber numberWithDouble:[pjpegQualitySlider doubleValue]] forKey:AVVideoQualityKey];
			}
			//	h264
			else if ([codecString isEqualToString:AVVideoCodecH264])	{
				NSMutableDictionary		*compProps = [NSMutableDictionary dictionaryWithCapacity:0];
				[returnMe setObject:compProps forKey:AVVideoCompressionPropertiesKey];
				
				[compProps setObject:[[h264ProfilesPUB selectedItem] representedObject] forKey:AVVideoProfileLevelKey];
				
				if ([h264KeyframesMatrix selectedRow]==1)	{
					NSString		*tmpString = [h264KeyframesField stringValue];
					NSUInteger		tmpVal = 24;
					if (tmpString!=nil)
						tmpVal = [tmpString integerValue];
					if (tmpVal<1)
						tmpVal = 1;
					[compProps setObject:[NSNumber numberWithInteger:tmpVal] forKey:AVVideoMaxKeyFrameIntervalKey];
				}
				
				if ([h264BitrateMatrix selectedRow]==1)	{
					NSString		*tmpString = [h264BitrateField stringValue];
					double			tmpVal = (tmpString==nil) ? 0.0 : [tmpString doubleValue];
					if (tmpVal <=0.0)
						tmpVal = 4096.0;
					[h264BitrateField setStringValue:[NSString stringWithFormat:@"%0.2f",tmpVal]];
					[compProps setObject:[NSNumber numberWithDouble:tmpVal*1024.0] forKey:AVVideoAverageBitRateKey];
				}
				
				if (![h264MultiPassButton isHidden] && [h264MultiPassButton intValue]==NSOnState)
					[returnMe setObject:[NSNumber numberWithBool:YES] forKey:VVAVVideoMultiPassEncodeKey];
			}
			//	prores 422
			else if ([codecString isEqualToString:AVVideoCodecAppleProRes422])	{
			}
			//	prores 4444
			else if ([codecString isEqualToString:AVVideoCodecAppleProRes4444])	{
			}
			//	hap
			else if ([codecString isEqualToString:AVVideoCodecHap])	{
				NSMutableDictionary		*compProps = [NSMutableDictionary dictionaryWithCapacity:0];
				[returnMe setObject:compProps forKey:AVVideoCompressionPropertiesKey];
				[compProps setObject:[NSNumber numberWithDouble:[hapQualitySlider doubleValue]] forKey:AVVideoQualityKey];
				if ([hapChunkMatrix selectedRow]==0)	{
					[returnMe setObject:[NSNumber numberWithInteger:1] forKey:AVHapVideoChunkCountKey];
				}
				else	{
					int			tmpInt = [[hapChunkField stringValue] intValue];
					tmpInt = fmaxl(fminl(tmpInt, HAPQMAXCHUNKS), 1);
					[compProps setObject:[NSNumber numberWithInteger:tmpInt] forKey:AVHapVideoChunkCountKey];
				}
			}
			//	hap alpha
			else if ([codecString isEqualToString:AVVideoCodecHapAlpha])	{
				NSMutableDictionary		*compProps = [NSMutableDictionary dictionaryWithCapacity:0];
				[returnMe setObject:compProps forKey:AVVideoCompressionPropertiesKey];
				[compProps setObject:[NSNumber numberWithDouble:[hapQualitySlider doubleValue]] forKey:AVVideoQualityKey];
				if ([hapChunkMatrix selectedRow]==0)	{
					[returnMe setObject:[NSNumber numberWithInteger:1] forKey:AVHapVideoChunkCountKey];
				}
				else	{
					int			tmpInt = [[hapChunkField stringValue] intValue];
					tmpInt = fmaxl(fminl(tmpInt, HAPQMAXCHUNKS), 1);
					[compProps setObject:[NSNumber numberWithInteger:tmpInt] forKey:AVHapVideoChunkCountKey];
				}
			}
			//	hap Q
			else if ([codecString isEqualToString:AVVideoCodecHapQ])	{
				NSMutableDictionary		*compProps = [NSMutableDictionary dictionaryWithCapacity:0];
				[returnMe setObject:compProps forKey:AVVideoCompressionPropertiesKey];
				if ([hapQChunkMatrix selectedRow]==0)	{
					[returnMe setObject:[NSNumber numberWithInteger:1] forKey:AVHapVideoChunkCountKey];
				}
				else	{
					int			tmpInt = [[hapQChunkField stringValue] intValue];
					tmpInt = fmaxl(fminl(tmpInt, HAPQMAXCHUNKS), 1);
					[compProps setObject:[NSNumber numberWithInteger:tmpInt] forKey:AVHapVideoChunkCountKey];
				}
			}
			//	hap q alpha
			else if ([codecString isEqualToString:AVVideoCodecHapQAlpha])	{
				NSMutableDictionary		*compProps = [NSMutableDictionary dictionaryWithCapacity:0];
				[returnMe setObject:compProps forKey:AVVideoCompressionPropertiesKey];
				if ([hapQChunkMatrix selectedRow]==0)	{
					[returnMe setObject:[NSNumber numberWithInteger:1] forKey:AVHapVideoChunkCountKey];
				}
				else	{
					int			tmpInt = [[hapQChunkField stringValue] intValue];
					tmpInt = fmaxl(fminl(tmpInt, HAPQMAXCHUNKS), 1);
					[compProps setObject:[NSNumber numberWithInteger:tmpInt] forKey:AVHapVideoChunkCountKey];
				}
			}
			
			
			switch ([vidDimsTabView selectedTabViewItemIndex])	{
			//	no resizing
			case 0:
				break;
			//	resizing
			case 1:
				[returnMe setObject:[NSNumber numberWithInteger:[vidWidthField integerValue]] forKey:AVVideoWidthKey];
				[returnMe setObject:[NSNumber numberWithInteger:[vidHeightField integerValue]] forKey:AVVideoHeightKey];
				break;
			}
		}
		break;
	}
	return returnMe;
}
- (NSMutableDictionary *) createAudioOutputSettingsDict	{
	NSMutableDictionary		*returnMe = [NSMutableDictionary dictionaryWithCapacity:0];
	switch ([audioCategoryTabView selectedTabViewItemIndex])	{
	//	no transcoding
	case 0:
		switch ([audioNoTranscodeMatrix selectedRow])	{
		//	strip audio
		case 0:
			[returnMe setObject:@YES forKey:VVAVStripMediaKey];
			break;
		//	copy video
		case 1:
			break;
		}
		break;
	//	transcoding
	case 1:
		{
			//	audio format
			NSNumber		*formatIDNum = [[audioCodecPUB selectedItem] representedObject];
			[returnMe setObject:formatIDNum forKey:AVFormatIDKey];
			switch ([formatIDNum intValue])	{
			case kAudioFormatLinearPCM:
				[returnMe setObject:[[pcmBitsPUB selectedItem] representedObject] forKey:AVLinearPCMBitDepthKey];
				[returnMe setObject:[NSNumber numberWithBool:([pcmLittleEndianButton intValue]==NSOnState)?NO:YES] forKey:AVLinearPCMIsBigEndianKey];
				[returnMe setObject:[NSNumber numberWithBool:([pcmFloatingPointButton intValue]==NSOnState)?YES:NO] forKey:AVLinearPCMIsFloatKey];
				//[returnMe setObject:[NSNumber numberWithBool:([pcmInterleavedButton intValue]==NSOnState)?YES:NO] forKey:AVLinearPCMIsNonInterleaved];
				[returnMe setObject:[NSNumber numberWithBool:NO] forKey:AVLinearPCMIsNonInterleaved];
				
				//	this key doesn't work with AAC, so i have to add it everywhere else...
				[returnMe setObject:AVSampleRateConverterAlgorithm_Mastering forKey:AVSampleRateConverterAlgorithmKey];
				break;
			case kAudioFormatMPEG4AAC:
			//case kAudioFormatMPEGLayer3:
				[returnMe setObject:[[aacBitrateStrategyPUB selectedItem] representedObject] forKey:AVEncoderBitRateStrategyKey];
				if ([aacBitratePUB isEnabled])
					[returnMe setObject:[[aacBitratePUB selectedItem] representedObject] forKey:AVEncoderBitRateKey];
				break;
			case kAudioFormatAppleLossless:
				
				//	bitrate key is ignored for variable bitrate
				//if ([losslessBitDepthPUB isEnabled])
					[returnMe setObject:[[losslessBitDepthPUB selectedItem] representedObject] forKey:AVEncoderBitDepthHintKey];
				
				
				//if ([aacBitratePUB isEnabled])
				//	[returnMe setObject:[[aacBitratePUB selectedItem] representedObject] forKey:AVEncoderBitRateKey];
				
				//	AVEncoderBitDepthHintKey must be included
				//[returnMe setObject:[NSNumber numberWithInt:32] forKey:AVEncoderBitDepthHintKey];
				
				//	this key doesn't work with AAC, so i have to add it everywhere else...
				[returnMe setObject:AVSampleRateConverterAlgorithm_Mastering forKey:AVSampleRateConverterAlgorithmKey];
				break;
			}
			
			//[returnMe setObject:AVSampleRateConverterAlgorithm_Mastering forKey:AVSampleRateConverterAlgorithmKey];
			
			
			switch ([audioResampleTabView selectedTabViewItemIndex])	{
			//	no resampling
			case 0:
				break;
			//	resampling
			case 1:
				[returnMe setObject:[NSNumber numberWithInteger:[audioResampleField integerValue]] forKey:AVSampleRateKey];
				break;
			}
		}
		break;
	}
	return returnMe;
}
- (void) populateUIWithVideoSettingsDict:(NSDictionary *)n	{
	//NSLog(@"%s ... %@",__func__,n);
	NSString		*codecString = nil;
	NSString		*tmpString = nil;
	NSNumber		*tmpNum = nil;
	
	codecString = [n objectForKey:AVVideoCodecKey];
	if (codecString==nil)	{
		[vidCategoryTabView selectTabViewItemAtIndex:0];
		tmpNum = [n objectForKey:VVAVStripMediaKey];
		if (tmpNum!=nil && [tmpNum boolValue])
			[vidNoTranscodeMatrix selectCellAtRow:0 column:0];
		else
			[vidNoTranscodeMatrix selectCellAtRow:1 column:0];
	}
	else if ([codecString isEqualToString:AVVideoCodecJPEG])	{
		[vidCategoryTabView selectTabViewItemAtIndex:1];
		[vidCodecPUB selectItemWithTitle:@"PJPEG"];
		[self vidCodecPUBUsed:vidCodecPUB];
		NSDictionary	*props = [n objectForKey:AVVideoCompressionPropertiesKey];
		if (props!=nil)	{
			tmpNum = [props objectForKey:AVVideoQualityKey];
			if (tmpNum!=nil)
				[pjpegQualitySlider setDoubleValue:[tmpNum doubleValue]];
		}
	}
	//	h264
	else if ([codecString isEqualToString:AVVideoCodecH264])	{
		[vidCategoryTabView selectTabViewItemAtIndex:1];
		[vidCodecPUB selectItemWithTitle:@"H264"];
		[self vidCodecPUBUsed:vidCodecPUB];
		NSDictionary	*props = [n objectForKey:AVVideoCompressionPropertiesKey];
		if (props!=nil)	{
			tmpString = [props objectForKey:AVVideoProfileLevelKey];
			if (tmpString!=nil)
				[h264ProfilesPUB selectItemWithRepresentedObject:tmpString];
			
			tmpNum = [props objectForKey:AVVideoMaxKeyFrameIntervalKey];
			if (tmpNum==nil)
				[h264KeyframesMatrix selectCellAtRow:0 column:0];
			else	{
				[h264KeyframesMatrix selectCellAtRow:1 column:0];
				[h264KeyframesField setStringValue:[NSString stringWithFormat:@"%ld",(long)[tmpNum integerValue]]];
			}
			[self h264KeyframesMatrixUsed:h264KeyframesMatrix];
			
			tmpNum = [props objectForKey:AVVideoAverageBitRateKey];
			if (tmpNum==nil)
				[h264BitrateMatrix selectCellAtRow:0 column:0];
			else	{
				[h264BitrateMatrix selectCellAtRow:1 column:0];
				[h264BitrateField setStringValue:[NSString stringWithFormat:@"%0.2f",[tmpNum doubleValue]/1024.0]];
			}
			[self h264BitrateMatrixUsed:h264BitrateMatrix];
			
			if (![h264MultiPassButton isHidden])	{
				tmpNum = [n objectForKey:VVAVVideoMultiPassEncodeKey];
				[h264MultiPassButton setIntValue:(tmpNum==nil || [tmpNum intValue]!=NSOnState) ? NSOffState : NSOnState];
			}
		}
	}
	//	prores 422
	else if ([codecString isEqualToString:AVVideoCodecAppleProRes422])	{
		[vidCategoryTabView selectTabViewItemAtIndex:1];
		[vidCodecPUB selectItemWithTitle:@"ProRes 422"];
		[self vidCodecPUBUsed:vidCodecPUB];
	}
	//	prores 4444
	else if ([codecString isEqualToString:AVVideoCodecAppleProRes4444])	{
		[vidCategoryTabView selectTabViewItemAtIndex:1];
		[vidCodecPUB selectItemWithTitle:@"ProRes 4444"];
		[self vidCodecPUBUsed:vidCodecPUB];
	}
	//	hap
	else if ([codecString isEqualToString:AVVideoCodecHap])	{
		[vidCategoryTabView selectTabViewItemAtIndex:1];
		[vidCodecPUB selectItemWithTitle:@"Hap"];
		[self vidCodecPUBUsed:vidCodecPUB];
		NSDictionary	*props = [n objectForKey:AVVideoCompressionPropertiesKey];
		if (props!=nil)	{
			tmpNum = [props objectForKey:AVVideoQualityKey];
			if (tmpNum!=nil)
				[hapQualitySlider setDoubleValue:[tmpNum doubleValue]];
		}
	}
	//	hap alpha
	else if ([codecString isEqualToString:AVVideoCodecHapAlpha])	{
		[vidCategoryTabView selectTabViewItemAtIndex:1];
		[vidCodecPUB selectItemWithTitle:@"Hap Alpha"];
		[self vidCodecPUBUsed:vidCodecPUB];
		NSDictionary	*props = [n objectForKey:AVVideoCompressionPropertiesKey];
		if (props!=nil)	{
			tmpNum = [props objectForKey:AVVideoQualityKey];
			if (tmpNum!=nil)
				[hapQualitySlider setDoubleValue:[tmpNum doubleValue]];
		}
	}
	//	hap Q
	else if ([codecString isEqualToString:AVVideoCodecHapQ])	{
		[vidCategoryTabView selectTabViewItemAtIndex:1];
		[vidCodecPUB selectItemWithTitle:@"Hap Q"];
		[self vidCodecPUBUsed:vidCodecPUB];
	}
	//	hap Q alpha
	else if ([codecString isEqualToString:AVVideoCodecHapQAlpha])	{
		[vidCategoryTabView selectTabViewItemAtIndex:1];
		[vidCodecPUB selectItemWithTitle:@"Hap Q Alpha"];
		[self vidCodecPUBUsed:vidCodecPUB];
	}
	
	//	this code needs to run if i'm using hap
	if ([codecString isEqualToString:AVVideoCodecHap] || [codecString isEqualToString:AVVideoCodecHapAlpha])	{
		NSDictionary	*props = [n objectForKey:AVVideoCompressionPropertiesKey];
		if (props != nil)	{
			tmpNum = [props objectForKey:AVHapVideoChunkCountKey];
			if (tmpNum == nil)	{
				[hapChunkMatrix selectCellAtRow:0 column:0];
				[hapChunkField setStringValue:@"1"];
				[hapChunkField setEnabled:NO];
			}
			else	{
				if ([tmpNum intValue]==0 || [tmpNum intValue]==1)	{
					[hapChunkMatrix selectCellAtRow:0 column:0];
					[hapChunkField setStringValue:@"1"];
					[hapChunkField setEnabled:NO];
				}
				else	{
					[hapChunkMatrix selectCellAtRow:1 column:0];
					[hapChunkField setStringValue:[NSString stringWithFormat:@"%d",[tmpNum intValue]]];
					[hapChunkField setEnabled:YES];
				}
			}
		}
	}
	//	this code needs to run if i'm using hap Q or hap Q alpha
	if ([codecString isEqualToString:AVVideoCodecHapQ] || [codecString isEqualToString:AVVideoCodecHapQAlpha])	{
		NSDictionary	*props = [n objectForKey:AVVideoCompressionPropertiesKey];
		if (props != nil)	{
			tmpNum = [props objectForKey:AVHapVideoChunkCountKey];
			if (tmpNum == nil)	{
				[hapQChunkMatrix selectCellAtRow:0 column:0];
				[hapQChunkField setStringValue:@"1"];
				[hapQChunkField setEnabled:NO];
			}
			else	{
				if ([tmpNum intValue]==0 || [tmpNum intValue]==1)	{
					[hapQChunkMatrix selectCellAtRow:0 column:0];
					[hapQChunkField setStringValue:@"1"];
					[hapQChunkField setEnabled:NO];
				}
				else	{
					[hapQChunkMatrix selectCellAtRow:1 column:0];
					[hapQChunkField setStringValue:[NSString stringWithFormat:@"%d",[tmpNum intValue]]];
					[hapQChunkField setEnabled:YES];
				}
			}
		}
	}
	
	
	tmpNum = [n objectForKey:AVVideoWidthKey];
	if (tmpNum==nil)
		[self noResizeVideoClicked:nil];
	else	{
		[self resizeVideoTextFieldUsed:nil];
		[vidWidthField setStringValue:[NSString stringWithFormat:@"%ld",(long)[tmpNum integerValue]]];
	}
	tmpNum = [n objectForKey:AVVideoHeightKey];
	if (tmpNum==nil)
		[self noResizeVideoClicked:nil];
	else	{
		[self resizeVideoTextFieldUsed:nil];
		[vidHeightField setStringValue:[NSString stringWithFormat:@"%ld",(long)[tmpNum integerValue]]];
	}
}
- (void) populateUIWithAudioSettingsDict:(NSDictionary *)n	{
	NSNumber		*formatNum = nil;
	NSString		*tmpString = nil;
	NSNumber		*tmpNum = nil;
	
	formatNum = [n objectForKey:AVFormatIDKey];
	if (formatNum==nil)	{
		[audioCategoryTabView selectTabViewItemAtIndex:0];
		tmpNum = [n objectForKey:VVAVStripMediaKey];
		if (tmpNum!=nil && [tmpNum boolValue])
			[audioNoTranscodeMatrix selectCellAtRow:0 column:0];
		else
			[audioNoTranscodeMatrix selectCellAtRow:1 column:0];
	}
	else	{
		[audioCategoryTabView selectTabViewItemAtIndex:1];
		[audioCodecPUB selectItemWithRepresentedObject:formatNum];
		[self audioCodecPUBUsed:audioCodecPUB];
		switch ([formatNum intValue])	{
		case kAudioFormatLinearPCM:
			tmpNum = [n objectForKey:AVLinearPCMBitDepthKey];
			if (tmpNum!=nil)	{
				[pcmBitsPUB selectItemWithRepresentedObject:tmpNum];
				[self pcmBitsPUBUsed:pcmBitsPUB];
			}
			tmpNum = [n objectForKey:AVLinearPCMIsBigEndianKey];
			if (tmpNum!=nil)
				[pcmLittleEndianButton setIntValue:([tmpNum boolValue]) ? NSOffState : NSOnState];
			tmpNum = [n objectForKey:AVLinearPCMIsFloatKey];
			if (tmpNum!=nil)
				[pcmFloatingPointButton setIntValue:([tmpNum boolValue]) ? NSOnState : NSOffState];
			break;
		case kAudioFormatMPEG4AAC:
			tmpString = [n objectForKey:AVEncoderBitRateStrategyKey];
			if (tmpString!=nil)	{
				[aacBitrateStrategyPUB selectItemWithRepresentedObject:tmpString];
				[self aacBitrateStrategyPUBUsed:aacBitrateStrategyPUB];
			}
			tmpNum = [n objectForKey:AVEncoderBitRateKey];
			if (tmpNum!=nil)	{
				[aacBitratePUB selectItemWithRepresentedObject:tmpNum];
			}
			break;
		case kAudioFormatAppleLossless:
			tmpNum = [n objectForKey:AVEncoderBitDepthHintKey];
			if (tmpNum!=nil)	{
				[losslessBitDepthPUB selectItemWithRepresentedObject:tmpNum];
			}
			break;
		}
		
		tmpNum = [n objectForKey:AVSampleRateKey];
		if (tmpNum==nil)
			[self noResampleAudioClicked:nil];
		else	{
			[self resampleAudioClicked:nil];
			[audioResampleField setStringValue:[NSString stringWithFormat:@"%ld",(long)[tmpNum integerValue]]];
		}
	}
}


- (NSString *) lengthyVideoDescription	{
	NSString		*returnMe = nil;
	switch ([vidCategoryTabView selectedTabViewItemIndex])	{
	//	no transcoding
	case 0:	{
		switch ([vidNoTranscodeMatrix selectedRow])	{
		//	strip
		case 0:
			returnMe = @"Video tracks will be stripped.";
			break;
		//	copy
		case 1:
			returnMe = @"Video tracks will be copied (but not processed).";
			break;
		}
		break;
	}
	//	transcoding
	case 1:
		{
			//	video codec
			NSString		*codecString = [[vidCodecPUB selectedItem] representedObject];
			//	pjpeg
			if ([codecString isEqualToString:AVVideoCodecJPEG])	{
				returnMe = [NSString stringWithFormat:@"PJPEG, %ld%%.",(unsigned long)(100.0*[pjpegQualitySlider doubleValue])];
			}
			//	h264
			else if ([codecString isEqualToString:AVVideoCodecH264])	{
				returnMe = [NSString stringWithFormat:@"h264, %@.",[h264ProfilesPUB titleOfSelectedItem]];
				
				if ([h264KeyframesMatrix selectedRow]==1)	{
					NSString		*tmpString = [h264KeyframesField stringValue];
					returnMe = [NSString stringWithFormat:@"%@ Keyframe every %@.",returnMe,tmpString];
				}
				
				if ([h264BitrateMatrix selectedRow]==1)	{
					NSString		*tmpString = [h264BitrateField stringValue];
					returnMe = [NSString stringWithFormat:@"%@ %@ kbps.",returnMe,tmpString];
				}
				
				if (![h264MultiPassButton isHidden] && [h264MultiPassButton intValue]==NSOnState)
					returnMe = [NSString stringWithFormat:@"%@ Multipass.",returnMe];
			}
			//	prores 422
			else if ([codecString isEqualToString:AVVideoCodecAppleProRes422])	{
				returnMe = @"ProRes 422.";
			}
			//	prores 4444
			else if ([codecString isEqualToString:AVVideoCodecAppleProRes4444])	{
				returnMe = @"ProRes 4444.";
			}
			//	hap
			else if ([codecString isEqualToString:AVVideoCodecHap])	{
				returnMe = [NSString stringWithFormat:@"Hap, %ld%%.",(unsigned long)(100.0*[hapQualitySlider doubleValue])];
			}
			//	hap alpha
			else if ([codecString isEqualToString:AVVideoCodecHapAlpha])	{
				returnMe = [NSString stringWithFormat:@"Hap Alpha, %ld%%.",(unsigned long)(100.0*[hapQualitySlider doubleValue])];
			}
			//	hap Q
			else if ([codecString isEqualToString:AVVideoCodecHapQ])	{
				returnMe = @"HapQ.";
			}
			//	hap Q alpha
			else if ([codecString isEqualToString:AVVideoCodecHapQAlpha])	{
				returnMe = @"HapQ Alpha.";
			}
			
			
			switch ([vidDimsTabView selectedTabViewItemIndex])	{
			//	no resizing
			case 0:
				break;
			//	resizing
			case 1:
				returnMe = [NSString stringWithFormat:@"%@ Sized to %ld x %ld.",returnMe,(long)[vidWidthField integerValue],(long)[vidHeightField integerValue]];
				break;
			}
		}
		break;
	}
	return returnMe;
}
- (NSString *) lengthyAudioDescription	{
	NSString		*returnMe = nil;
	switch ([audioCategoryTabView selectedTabViewItemIndex])	{
	case 0:
		switch ([audioNoTranscodeMatrix selectedRow])	{
		//	strip
		case 0:
			returnMe = @"Audio tracks will be stripped.";
			break;
		//	copy
		case 1:
			returnMe = @"Audio tracks will be copied (but not processed).";
			break;
		}
		break;
	case 1:
		{
			NSNumber		*formatIDNum = [[audioCodecPUB selectedItem] representedObject];
			switch ([formatIDNum integerValue])	{
			case kAudioFormatLinearPCM:
				if ([pcmLittleEndianButton intValue]==NSOnState)
					returnMe = [NSString stringWithFormat:@"PCM %@ bit, little-endian",[pcmBitsPUB titleOfSelectedItem]];
				else
					returnMe = [NSString stringWithFormat:@"PCM %@ bit, big-endian",[pcmBitsPUB titleOfSelectedItem]];
				if ([pcmFloatingPointButton intValue]==NSOnState)
					returnMe = [NSString stringWithFormat:@"%@ float",returnMe];
				break;
			case kAudioFormatMPEG4AAC:
				returnMe = @"AAC";
				returnMe = [NSString stringWithFormat:@"%@, %@",returnMe,[aacBitrateStrategyPUB titleOfSelectedItem]];
				if ([aacBitratePUB isEnabled])
					returnMe = [NSString stringWithFormat:@"%@, %@ kbps.",returnMe,[aacBitratePUB titleOfSelectedItem]];
				break;
			case kAudioFormatAppleLossless:
				returnMe = [NSString stringWithFormat:@"Apple Lossless, %@ bit",[losslessBitDepthPUB titleOfSelectedItem]];
				break;
			}
			break;
		}
	}
	return returnMe;
}


- (void) setDisplayVideoDims:(NSSize)n	{
	displayVideoDims = n;
}
- (void) setDisplayAudioResampleRate:(NSUInteger)n	{
	displayAudioResampleRate = n;
}


- (IBAction) transcodeVideoClicked:(id)sender	{
	[vidCategoryTabView selectTabViewItemAtIndex:1];
}
- (IBAction) noTranscodeVideoClicked:(id)sender	{
	[vidCategoryTabView selectTabViewItemAtIndex:0];
}
- (IBAction) vidCodecPUBUsed:(id)sender	{
	NSString		*selectedRepObj = [[sender selectedItem] representedObject];
	if ([selectedRepObj isEqualToString:AVVideoCodecJPEG])	{
		[vidCodecTabView selectTabViewItemAtIndex:1];
	}
	else if ([selectedRepObj isEqualToString:AVVideoCodecH264])	{
		[vidCodecTabView selectTabViewItemAtIndex:2];
	}
	else if ([selectedRepObj isEqualToString:AVVideoCodecAppleProRes422])	{
		[vidCodecTabView selectTabViewItemAtIndex:0];
	}
	else if ([selectedRepObj isEqualToString:AVVideoCodecAppleProRes4444])	{
		[vidCodecTabView selectTabViewItemAtIndex:0];
	}
	else if ([selectedRepObj isEqualToString:AVVideoCodecHap])	{
		[vidCodecTabView selectTabViewItemAtIndex:3];
	}
	else if ([selectedRepObj isEqualToString:AVVideoCodecHapAlpha])	{
		[vidCodecTabView selectTabViewItemAtIndex:3];
	}
	else if ([selectedRepObj isEqualToString:AVVideoCodecHapQ])	{
		[vidCodecTabView selectTabViewItemAtIndex:4];
	}
	else if ([selectedRepObj isEqualToString:AVVideoCodecHapQAlpha])	{
		[vidCodecTabView selectTabViewItemAtIndex:4];
	}
}
- (IBAction) h264KeyframesMatrixUsed:(id)sender	{
	if ([h264KeyframesMatrix selectedRow]==0)	{
		[h264KeyframesField setEnabled:NO];
	}
	else	{
		[h264KeyframesField setEnabled:YES];
		NSString		*tmpString = [h264KeyframesField stringValue];
		if (tmpString==nil || [tmpString integerValue]<1)
			[h264KeyframesField setStringValue:@"24"];
	}
}
- (IBAction) h264KeyframesFieldUsed:(id)sender	{
	NSString		*tmpString = [h264KeyframesField stringValue];
	if (tmpString==nil || [tmpString integerValue]<1)
		[h264KeyframesField setStringValue:@"24"];
}
- (IBAction) h264BitrateMatrixUsed:(id)sender	{
	if ([h264BitrateMatrix selectedRow]==0)	{
		[h264BitrateField setEnabled:NO];
	}
	else	{
		[h264BitrateField setEnabled:YES];
		NSString		*tmpString = [h264BitrateField stringValue];
		if (tmpString==nil || [tmpString doubleValue]<=0.0)
			[h264BitrateField setStringValue:@"4096.0"];
	}
}
- (IBAction) h264BitrateFieldUsed:(id)sender	{
	NSString		*tmpString = [h264BitrateField stringValue];
	if (tmpString==nil || [tmpString doubleValue]<=0.0)
		[h264BitrateField setStringValue:@"4096.0"];
}
- (IBAction) hapChunkMatrixUsed:(id)sender	{
	if ([hapChunkMatrix selectedRow] <= 0)	{
		[hapChunkField setStringValue:@"1"];
		[hapChunkField setEnabled:NO];
	}
	else	{
		[hapChunkField setEnabled:YES];
	}
}
- (IBAction) hapChunkFieldUsed:(id)sender	{
	BOOL			needsCorrection = YES;
	NSString		*tmpString = [hapChunkField stringValue];
	int				tmpInt = 1;
	if (tmpString!=nil && [tmpString length]<1)
		tmpString = nil;
	if (tmpString!=nil)	{
		tmpInt = [tmpString intValue];
		if (tmpInt > HAPQMAXCHUNKS)
			tmpInt = HAPQMAXCHUNKS;
		else if (tmpInt >= 1)
			needsCorrection = NO;
		else
			tmpInt = 1;
	}
	
	if (needsCorrection)	{
		[hapChunkField setStringValue:[NSString stringWithFormat:@"%d",tmpInt]];
	}
	
	if (tmpInt > (8))	{
		NSUserDefaults	*def = [NSUserDefaults standardUserDefaults];
		NSNumber		*tmpNum = [def objectForKey:@"hideChunkWarning"];
		BOOL			doNotShowAgain = (tmpNum==nil) ? NO : [tmpNum boolValue];
		if (!doNotShowAgain)	{
			VVRunAlertPanelSuppressString(@"Caution", @"If the number of cores being played back exceeds the number of logical cores available during playback, performance will get worse- not better!", @"I'll keep that in mind!", nil, nil, @"Do not show this again", &doNotShowAgain);
			if (doNotShowAgain)
				[def setObject:[NSNumber numberWithBool:YES] forKey:@"hideChunkWarning"];
			else
				[def removeObjectForKey:@"hideChunkWarning"];
			[def synchronize];
		}
	}
}
- (IBAction) hapQChunkMatrixUsed:(id)sender	{
	if ([hapQChunkMatrix selectedRow] <= 0)	{
		[hapQChunkField setStringValue:@"1"];
		[hapQChunkField setEnabled:NO];
	}
	else	{
		[hapQChunkField setEnabled:YES];
	}
}
- (IBAction) hapQChunkFieldUsed:(id)sender	{
	BOOL			needsCorrection = YES;
	NSString		*tmpString = [hapQChunkField stringValue];
	int				tmpInt = 1;
	if (tmpString!=nil && [tmpString length]<1)
		tmpString = nil;
	if (tmpString!=nil)	{
		tmpInt = [tmpString intValue];
		if (tmpInt > HAPQMAXCHUNKS)
			tmpInt = HAPQMAXCHUNKS;
		else if (tmpInt >= 1)
			needsCorrection = NO;
		else
			tmpInt = 1;
	}
	
	if (needsCorrection)	{
		[hapQChunkField setStringValue:[NSString stringWithFormat:@"%d",tmpInt]];
	}
}
- (IBAction) resizeVideoClicked:(id)sender	{
	[vidDimsTabView selectTabViewItemAtIndex:1];
}
- (IBAction) noResizeVideoClicked:(id)sender	{
	[vidDimsTabView selectTabViewItemAtIndex:0];
}
- (IBAction) resizeVideoTextFieldUsed:(id)sender	{
	NSString		*tmpString = nil;
	NSInteger		tmpVal;
	
	tmpString = [vidWidthField stringValue];
	tmpVal = (tmpString==nil) ? -1 : [tmpString integerValue];
	if (tmpVal<=0)
		[vidWidthField setStringValue:[NSString stringWithFormat:@"%ld",(unsigned long)displayVideoDims.width]];
	tmpString = [vidHeightField stringValue];
	tmpVal = (tmpString==nil) ? -1 : [tmpString integerValue];
	if (tmpVal<=0)
		[vidHeightField setStringValue:[NSString stringWithFormat:@"%ld",(unsigned long)displayVideoDims.height]];
	
}


- (IBAction) transcodeAudioClicked:(id)sender	{
	[audioCategoryTabView selectTabViewItemAtIndex:1];
}
- (IBAction) noTranscodeAudioClicked:(id)sender	{
	[audioCategoryTabView selectTabViewItemAtIndex:0];
}
- (IBAction) audioCodecPUBUsed:(id)sender	{
	//NSLog(@"%s",__func__);
	NSMenuItem		*selectedItem = [audioCodecPUB selectedItem];
	uint32_t		audioFormat = (uint32_t)[[selectedItem representedObject] integerValue];
	switch (audioFormat)	{
	case kAudioFormatLinearPCM:
		[audioCodecTabView selectTabViewItemAtIndex:1];
		break;
	case kAudioFormatMPEG4AAC:
		[audioCodecTabView selectTabViewItemAtIndex:2];
		
		//	AAC only works with a limited set of sample rates, so when i switch to it i need to run through the pop-up button and make sure that one of its options are selected
		//	get the value of the audioResampleField as a string-converted-to-an-integer
		NSString		*audioResampleFieldString = [audioResampleField stringValue];
		NSUInteger		audioResampleFieldInt = (audioResampleFieldString==nil) ? 48000 : [audioResampleFieldString integerValue];
		//	run through items in the audioResamplePUB- if the item's repObj value is >= the text field's integer value, select that item from the audioResamplePUB
		BOOL			foundItem = NO;
		for (NSMenuItem *itemPtr in [[audioResamplePUB menu] itemArray])	{
			NSNumber		*tmpNum = [itemPtr representedObject];
			if (tmpNum!=nil && [tmpNum integerValue]>=audioResampleFieldInt)	{
				[audioResamplePUB selectItem:itemPtr];
				foundItem = YES;
			}
		}
		if (!foundItem)
			[audioResamplePUB selectItemAtIndex:[[[audioResamplePUB menu] itemArray] count]-1];
		[self audioResamplePUBUsed:audioResamplePUB];
		break;
	case kAudioFormatAppleLossless:
		[audioCodecTabView selectTabViewItemAtIndex:3];
		break;
	}
}
- (IBAction) pcmBitsPUBUsed:(id)sender	{
	NSUInteger		newBitdepth = [[pcmBitsPUB titleOfSelectedItem] integerValue];
	switch (newBitdepth)	{
	case 8:
		[pcmFloatingPointButton setIntValue:NSOffState];
		[pcmFloatingPointButton setEnabled:NO];
		break;
	case 16:
		[pcmFloatingPointButton setIntValue:NSOffState];
		[pcmFloatingPointButton setEnabled:NO];
		break;
	case 24:
		[pcmFloatingPointButton setIntValue:NSOffState];
		[pcmFloatingPointButton setEnabled:NO];
		break;
	case 32:
		[pcmFloatingPointButton setEnabled:YES];
		break;
	}
}
- (IBAction) aacBitrateStrategyPUBUsed:(id)sender	{
	[aacBitratePUB setEnabled:([[aacBitrateStrategyPUB selectedItem] representedObject]!=AVAudioBitRateStrategy_Variable) ? YES : NO];
}
- (IBAction) resampleAudioClicked:(id)sender	{
	[audioResampleTabView selectTabViewItemAtIndex:1];
}
- (IBAction) noResampleAudioClicked:(id)sender	{
	[audioResampleTabView selectTabViewItemAtIndex:0];
}
- (IBAction) audioResamplePUBUsed:(id)sender	{
	NSNumber		*tmpNum = [[audioResamplePUB selectedItem] representedObject];
	NSUInteger		newSampleRate = (tmpNum==nil) ? 0.0 : [tmpNum unsignedLongValue];
	if (newSampleRate!=0)
		[audioResampleField setStringValue:[NSString stringWithFormat:@"%ld",(unsigned long)newSampleRate]];
}
- (IBAction) resampleAudioTextFieldUsed:(id)sender	{
	//NSLog(@"%s",__func__);
	NSString		*newValString = [audioResampleField stringValue];
	NSUInteger		intVal = (newValString==nil) ? 0.0 : [newValString integerValue];
	//	if the audio format is AAC then i can only work with a specific and limited set of sample rates, so i need to verify the value in this field
	if ([[[audioCodecPUB selectedItem] representedObject] integerValue]==kAudioFormatMPEG4AAC)	{
		//	run through the items in the audioResamplePUB- if the item's repObj value is >= the text field's integer value, select that item from the audioResamplePUB
		BOOL			foundItem = NO;
		for (NSMenuItem *itemPtr in [[audioResamplePUB menu] itemArray])	{
			NSNumber		*tmpNum = [itemPtr representedObject];
			if (tmpNum!=nil && [tmpNum integerValue]>=intVal)	{
				[audioResamplePUB selectItem:itemPtr];
				foundItem = YES;
			}
		}
		if (!foundItem)
			[audioResamplePUB selectItemAtIndex:[[[audioResamplePUB menu] itemArray] count]-1];
		[self audioResamplePUBUsed:audioResamplePUB];
	}
	//	else the audio format is either PCM or apple lossless- i just need to make sure the new val is between 8 and 192
	else	{
		if (intVal<8000)
			intVal = 8000;
		else if (intVal>192000)
			intVal = 192000;
		[audioResampleField setStringValue:[NSString stringWithFormat:@"%ld",(unsigned long)intVal]];
		//if (intVal<8 || intVal>192)
		//	[self audioResamplePUBUsed:audioResamplePUB];
	}
	
	
	
}


- (void) populateMenu:(NSMenu *)popMenu withItemsForAudioProperty:(uint32_t)popQueryProperty ofAudioFormat:(uint32_t)popAudioFormat	{
	if (popMenu!=nil)	{
		[popMenu removeAllItems];
		
		OSStatus		osErr = noErr;
		uint32_t		replySize;
		osErr = AudioFormatGetPropertyInfo(popQueryProperty, sizeof(popAudioFormat), &popAudioFormat, (UInt32 *)&replySize);
		if (osErr!=noErr)	{
			NSLog(@"\t\terr %d at AudioFormatGetProperty() in %s",(int)osErr,__func__);
			NSLog(@"\t\tproperty is %c%c%c%c", (int)((popQueryProperty>>24)&0xFF), (int)((popQueryProperty>>16)&0xFF), (int)((popQueryProperty>>8)&0xFF), (int)((popQueryProperty>>0)&0xFF));
			NSLog(@"\t\tformat is %c%c%c%c", (int)((popAudioFormat>>24)&0xFF), (int)((popAudioFormat>>16)&0xFF), (int)((popAudioFormat>>8)&0xFF), (int)((popAudioFormat>>0)&0xFF));
		}
		else	{
			void			*replyData = malloc(replySize);
			osErr = AudioFormatGetProperty(popQueryProperty, sizeof(popAudioFormat), &popAudioFormat, (UInt32 *)&replySize, replyData);
			if (osErr!=noErr)	{
				NSLog(@"\t\terr %d at AudioFormatGetProperty() in %s",(int)osErr,__func__);
				NSLog(@"\t\tproperty is %c%c%c%c", (int)((popQueryProperty>>24)&0xFF), (int)((popQueryProperty>>16)&0xFF), (int)((popQueryProperty>>8)&0xFF), (int)((popQueryProperty>>0)&0xFF));
				NSLog(@"\t\tformat is %c%c%c%c", (int)((popAudioFormat>>24)&0xFF), (int)((popAudioFormat>>16)&0xFF), (int)((popAudioFormat>>8)&0xFF), (int)((popAudioFormat>>0)&0xFF));
			}
			else	{
				//NSLog(@"\t\treplySize is %u, sizeof(AudioValueRange) is %ld",replySize,sizeof(AudioValueRange));
				//NSLog(@"\t\ttheoretically, there are %ld strcuts",replySize/sizeof(AudioValueRange));
				int					rangeCount = replySize/sizeof(AudioValueRange);
				AudioValueRange		*rangePtr = replyData;
				for (int i=0; i<rangeCount; ++i)	{
					//NSLog(@"\t\trange %d is %f / %f",i,rangePtr->mMinimum,rangePtr->mMaximum);
					NSUInteger			tmpInt = rangePtr->mMaximum;
					NSMenuItem			*tmpItem = [[[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%ld",(unsigned long)tmpInt] action:nil keyEquivalent:@""] autorelease];
					[tmpItem setRepresentedObject:[NSNumber numberWithInteger:tmpInt]];
					[popMenu addItem:tmpItem];
					++rangePtr;
				}
			}
			free(replyData);
		}
	}
}


- (void) setCanPerformMultiplePasses:(BOOL)n	{
	canPerformMultiplePasses = n;
	[h264MultiPassButton setHidden:(canPerformMultiplePasses) ? NO : YES];
}
- (NSView *) settingsView	{
	return settingsView;
}


@end








@interface NSAlert (NSAlertAdditions)
- (NSInteger) runModalForWindow:(NSWindow *)aWindow;
@end
@implementation NSAlert (NSAlertAdditions)
- (NSInteger) runModalForWindow:(NSWindow *)aWindow {
	__block NSInteger		returnMe = 0;
	__block id				bss = self;
	//	this code is in a block because it must be executed on the main thread (AppKit isn't threadsafe)
	void		(^tmpBlock)(void) = ^(void)	{
		//	configure the buttons to trigger a method we're adding to NSAlert in this category
		for (NSButton *button in [bss buttons]) {
			[button setTarget:bss];
			[button setAction:@selector(closeAlertsAppModalSession:)];
		}
		//	open the sheet as modal for the passed window
		[bss beginSheetModalForWindow:aWindow completionHandler:nil];
		//	start a modal session for the window- this will ensure that any events outside the window are ignored
		returnMe = [NSApp runModalForWindow:[bss window]];
	
		//	...execution won't pass this point until the NSApp modal session above is ended (happens when a button is clicked)...
	
		//	end the sheet we began with 'beginSheetModalForWindow'
		[NSApp endSheet:[bss window]];
	};
	//	execute the block, ensuring that it happens synchronously and on the main thread
	if (![NSThread isMainThread])
		dispatch_sync(dispatch_get_main_queue(), tmpBlock);
	else
		tmpBlock();
	return returnMe;
}
- (IBAction) closeAlertsAppModalSession:(id)sender {
	NSUInteger		senderButtonIndex = [[self buttons] indexOfObject:sender];
	NSInteger		returnMe = 0;
	if (senderButtonIndex == NSAlertFirstButtonReturn)
		returnMe = NSAlertFirstButtonReturn;
	else if (senderButtonIndex == NSAlertSecondButtonReturn)
		returnMe = NSAlertSecondButtonReturn;
	else if (senderButtonIndex == NSAlertThirdButtonReturn)
		returnMe = NSAlertThirdButtonReturn;
	else
		returnMe = NSAlertThirdButtonReturn + (senderButtonIndex - 2);
	
	[NSApp stopModalWithCode:returnMe];
}
@end


NSInteger VVRunAlertPanel(NSString *title, NSString *msg, NSString *btnA, NSString *btnB, NSString *btnC)	{
	return VVRunAlertPanelSuppressString(title, msg, btnA, btnB, btnC, nil, NULL);
}
NSInteger VVRunAlertPanelSuppressString(NSString *title, NSString *msg, NSString *btnA, NSString *btnB, NSString *btnC, NSString *suppressString, BOOL *returnSuppressValue)	{
	__block NSInteger		returnMe;
	NSAlert			*macroLocalAlert = [NSAlert alertWithError:[NSError
		errorWithDomain:@""
		code:0
		userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
			title, NSLocalizedDescriptionKey,
			msg, NSLocalizedRecoverySuggestionErrorKey,
			nil]]];
	[macroLocalAlert setAlertStyle:NSWarningAlertStyle];
	if (btnA!=nil && [btnA length]>0)
		[macroLocalAlert addButtonWithTitle:btnA];
	if (btnB!=nil && [btnB length]>0)
		[macroLocalAlert addButtonWithTitle:btnB];
	if (btnC!=nil && [btnC length]>0)
		[macroLocalAlert addButtonWithTitle:btnC];
	
	BOOL		showsSuppressionButton = (suppressString!=nil && [suppressString length]>0) ? YES : NO;
	if (showsSuppressionButton)	{
		[macroLocalAlert setShowsSuppressionButton:YES];
		NSButton		*tmpButton = [macroLocalAlert suppressionButton];
		if (tmpButton != nil)	{
			[tmpButton setTitle:suppressString];
			[tmpButton setIntValue:NSOffState];
		}
	}
	else	{
		[macroLocalAlert setShowsSuppressionButton:NO];
	}
	
	//	so, -[NSAlert runModal] should be handling all this- but we can't do that, because sometimes NSAlert will display the modal dialog on the non-main screen.  to work around this, we have to create an invisible window on the main screen, and attach the alert to it as a sheet that uses a modal session to restrict user interaction.
	NSRect			mainScreenRect = [[[NSScreen screens] objectAtIndex:0] frame];
	//NSRect			clearWinRect = NSMakeRect(VVMIDX(mainScreenRect)-250, (mainScreenRect.size.height*0.66) + mainScreenRect.origin.y - 100, 500, 200);
	NSRect			clearWinRect = NSMakeRect((mainScreenRect.size.width/2.0+mainScreenRect.origin.x)-250, (mainScreenRect.size.height*0.66) + mainScreenRect.origin.y - 100, 500, 200);
	NSWindow		*clearWin = [[NSWindow alloc] initWithContentRect:clearWinRect styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
	[clearWin setHasShadow:NO];
	[clearWin setOpaque:NO];
	[clearWin setBackgroundColor:[NSColor clearColor]];
		//[clearWin useOptimizedDrawing:YES];
	[clearWin setHidesOnDeactivate:YES];
	[clearWin setLevel:NSModalPanelWindowLevel];
	[clearWin setIgnoresMouseEvents:YES];
	
	//NSLog(@"\t\ttelling the app to run a modal session for the clear window...");
	returnMe = [macroLocalAlert runModalForWindow:clearWin];
	
	//	get rid of the clear window...
	[clearWin orderOut:nil];
	[clearWin release];
	clearWin = nil;
	
	if (showsSuppressionButton && returnSuppressValue!=NULL)	{
		*returnSuppressValue = ([[macroLocalAlert suppressionButton] intValue]==NSOnState) ? YES : NO;
	}
	
	return returnMe;
}
