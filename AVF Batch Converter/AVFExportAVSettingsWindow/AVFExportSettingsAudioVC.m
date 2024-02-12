//
//  AVFExportSettingsAudioVC.m
//  VVAVFExport-TestApp
//
//  Created by testadmin on 5/4/22.
//

#import "AVFExportSettingsAudioVC.h"
#import "AVFExportAVSettingsWindow.h"
#import "AVFExportSettingsAdditions.h"
#import "VVAudioFormatUtilities.h"




@interface AVFExportSettingsAudioVC ()	{
	NSUInteger			displayAudioResampleRate;
}

@property (weak) IBOutlet NSPopUpButton * audioCodecPUB;	//	representedItem is NSNumber of the OSType with the audio format value (basically a FourCC)
@property (weak) IBOutlet NSTabView * audioCodecTabView;	//	tabs contains settings for audio formats
@property (weak) IBOutlet NSPopUpButton * pcmBitsPUB;	//	item title is string of integer value
@property (weak) IBOutlet NSButton * pcmLittleEndianButton;
@property (weak) IBOutlet NSButton * pcmFloatingPointButton;
@property (weak) IBOutlet NSPopUpButton * aacBitrateStrategyPUB;	//	item representedObject is a "AVAudioBitRateStrategy_*" constant suitable for adding to settings dict
@property (weak) IBOutlet NSPopUpButton * aacBitratePUB;	//	item representedObject is NSNumber with actual bitrate suitable for simply adding to a dict
@property (weak) IBOutlet NSPopUpButton * losslessBitDepthPUB;	//	item representedObject is NSNumber with actual bit depth sutiable for adding to settings dict

@property (weak) IBOutlet NSTabView * audioResampleTabView;
@property (weak) IBOutlet NSPopUpButton * audioResamplePUB;	//	item title is string or double value, multiple by 1000 and then convert to integer to get sample rate value
@property (weak) IBOutlet NSTextField * audioResampleField;

- (IBAction) audioCodecPUBUsed:(id)sender;
- (IBAction) pcmBitsPUBUsed:(id)sender;
- (IBAction) aacBitrateStrategyPUBUsed:(id)sender;
- (IBAction) resampleAudioClicked:(id)sender;
- (IBAction) noResampleAudioClicked:(id)sender;
- (IBAction) audioResamplePUBUsed:(id)sender;
- (IBAction) resampleAudioTextFieldUsed:(id)sender;

- (void) populateMenu:(NSMenu *)popMenu withItemsForAudioProperty:(uint32_t)popQueryProperty ofAudioFormat:(uint32_t)popAudioFormat;

@end




@implementation AVFExportSettingsAudioVC


+ (NSMutableDictionary *) defaultAVFSettingsDict	{
	NSDictionary		*tmpDict = @{
		kAVFExportAudioSampleRateKey: @(44100)
	};
	return [tmpDict mutableCopy];
}


-(instancetype) init	{
	self = [super initWithNibName:[[self class] className] bundle:[NSBundle mainBundle]];
	if (self != nil)	{
		NSView			*tmpView = self.view;
		tmpView = nil;
	}
	return self;
}
- (void) awakeFromNib	{
	NSMenu			*theMenu = nil;
	NSMenuItem		*newItem = nil;
	
	[_audioCodecPUB removeAllItems];
	
	theMenu = [_audioCodecPUB menu];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Linear PCM" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:[NSNumber numberWithInteger:kAudioFormatLinearPCM]];
	[theMenu addItem:newItem];
	newItem = [[NSMenuItem alloc] initWithTitle:@"AAC" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:[NSNumber numberWithInteger:kAudioFormatMPEG4AAC]];
	[theMenu addItem:newItem];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Apple Lossless" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:[NSNumber numberWithInteger:kAudioFormatAppleLossless]];
	[theMenu addItem:newItem];
	
	[_audioCodecPUB selectItemAtIndex:0];
	[self audioCodecPUBUsed:_audioCodecPUB];
	
	
	unsigned long		pcmBitDepths[] = {8,16,24,32};
	[_pcmBitsPUB removeAllItems];
	theMenu = [_pcmBitsPUB menu];
	for (int i=0; i<4; ++i)	{
		newItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%ld",pcmBitDepths[i]] action:nil keyEquivalent:@""];
		[newItem setRepresentedObject:[NSNumber numberWithUnsignedLong:pcmBitDepths[i]]];
		[theMenu addItem:newItem];
	}
	[_pcmBitsPUB selectItemAtIndex:1];
	[self pcmBitsPUBUsed:_pcmBitsPUB];
	
	
	[_aacBitrateStrategyPUB removeAllItems];
	theMenu = [_aacBitrateStrategyPUB menu];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Constant bitrate" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVAudioBitRateStrategy_Constant];
	[theMenu addItem:newItem];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Long-Term Average" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVAudioBitRateStrategy_LongTermAverage];
	[theMenu addItem:newItem];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Variable Constrained" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVAudioBitRateStrategy_VariableConstrained];
	[theMenu addItem:newItem];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Variable bitrate" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVAudioBitRateStrategy_Variable];
	[theMenu addItem:newItem];
	[_aacBitrateStrategyPUB selectItemAtIndex:0];
	
	/*
	//	i can't populate the aac bitrate menu programmatically- the values it returns don't actually work, so just stick with a list of known-good bitrates (from quicktime)
	//[self populateMenu:[aacBitratePUB menu] withItemsForAudioProperty:kAudioFormatProperty_AvailableEncodeBitRates ofAudioFormat:kAudioFormatMPEG4AAC];
	unsigned long		kbpsBitrates[] = {16,20,24,28,32,40,48,56,64,72,80,96,112,128,144,160,192,224,256,288,320};
	[aacBitratePUB removeAllItems];
	theMenu = [aacBitratePUB menu];
	for (int i=0; i<21; ++i)	{
		newItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%ld",kbpsBitrates[i]] action:nil keyEquivalent:@""];
		[newItem setRepresentedObject:[NSNumber numberWithUnsignedLong:kbpsBitrates[i]*1000]];
		[theMenu addItem:newItem];
	}
	[aacBitratePUB selectItemWithTitle:@"160"];
	*/
	
	unsigned long		hintBitDepths[] = {16,20,24,32};
	[_losslessBitDepthPUB removeAllItems];
	theMenu = [_losslessBitDepthPUB menu];
	for (int i=0; i<4; ++i)	{
		newItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%ld",hintBitDepths[i]] action:nil keyEquivalent:@""];
		[newItem setRepresentedObject:[NSNumber numberWithUnsignedLong:hintBitDepths[i]]];
		[theMenu addItem:newItem];
	}
	[_losslessBitDepthPUB selectItemAtIndex:0];
	
	
	//	the AAC encoder is the only encoder that ONLY works with a limited and explicit set of sample rates, so i'm going to use that as the list of values in the PUB
	[self populateMenu:[_audioResamplePUB menu] withItemsForAudioProperty:kAudioFormatProperty_AvailableEncodeSampleRates ofAudioFormat:kAudioFormatMPEG4AAC];
	[_audioResamplePUB selectItemAtIndex:7];	//	actuall selects 44.1 khz
	[self audioResamplePUBUsed:_audioResamplePUB];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}
//- (void) dealloc	{
//	//NSLog(@"%s",__func__);
//}


- (NSMutableDictionary *) createAVFSettingsDict	{
	NSMutableDictionary		*returnMe = [NSMutableDictionary dictionaryWithCapacity:0];
	//switch ([audioCategoryTabView selectedTabViewItemIndex])	{
	//	no transcoding
	//case 0:
	//	switch ([audioNoTranscodeMatrix selectedRow])	{
		//	strip audio
	//	case 0:
	//		[returnMe setObject:@YES forKey:kAVFExportStripMediaKey];
	//		break;
		//	copy video
	//	case 1:
	//		break;
	//	}
	//	break;
	//	transcoding
	//case 1:
	//	{
			//	audio format
			NSNumber		*formatIDNum = [[_audioCodecPUB selectedItem] representedObject];
			[returnMe setObject:formatIDNum forKey:AVFormatIDKey];
			switch ([formatIDNum intValue])	{
			case kAudioFormatLinearPCM:
				[returnMe setObject:[[_pcmBitsPUB selectedItem] representedObject] forKey:AVLinearPCMBitDepthKey];
				[returnMe setObject:[NSNumber numberWithBool:([_pcmLittleEndianButton intValue]==NSControlStateValueOn)?NO:YES] forKey:AVLinearPCMIsBigEndianKey];
				[returnMe setObject:[NSNumber numberWithBool:([_pcmFloatingPointButton intValue]==NSControlStateValueOn)?YES:NO] forKey:AVLinearPCMIsFloatKey];
				//[returnMe setObject:[NSNumber numberWithBool:([pcmInterleavedButton intValue]==NSControlStateValueOn)?YES:NO] forKey:AVLinearPCMIsNonInterleaved];
				[returnMe setObject:[NSNumber numberWithBool:NO] forKey:AVLinearPCMIsNonInterleaved];
				
				//	this key doesn't work with AAC, so i have to add it everywhere else...
				//[returnMe setObject:AVSampleRateConverterAlgorithm_Mastering forKey:AVSampleRateConverterAlgorithmKey];
				break;
			case kAudioFormatMPEG4AAC:
			//case kAudioFormatMPEGLayer3:
				[returnMe setObject:[[_aacBitrateStrategyPUB selectedItem] representedObject] forKey:AVEncoderBitRateStrategyKey];
				if ([_aacBitratePUB isEnabled] && [_aacBitratePUB selectedItem]!=nil)
					[returnMe setObject:[[_aacBitratePUB selectedItem] representedObject] forKey:AVEncoderBitRateKey];
				break;
			case kAudioFormatAppleLossless:
				
				//	bitrate key is ignored for variable bitrate
				//if ([_losslessBitDepthPUB isEnabled])
					[returnMe setObject:[[_losslessBitDepthPUB selectedItem] representedObject] forKey:AVEncoderBitDepthHintKey];
				
				
				//if ([_aacBitratePUB isEnabled])
				//	[returnMe setObject:[[_aacBitratePUB selectedItem] representedObject] forKey:AVEncoderBitRateKey];
				
				//	AVEncoderBitDepthHintKey must be included
				//[returnMe setObject:[NSNumber numberWithInt:32] forKey:AVEncoderBitDepthHintKey];
				
				//	this key doesn't work with AAC, so i have to add it everywhere else...
				//[returnMe setObject:AVSampleRateConverterAlgorithm_Mastering forKey:AVSampleRateConverterAlgorithmKey];
				break;
			}
			
			//[returnMe setObject:AVSampleRateConverterAlgorithm_Mastering forKey:AVSampleRateConverterAlgorithmKey];
			
			
			switch ([_audioResampleTabView selectedTabViewItemIndex])	{
			//	no resampling
			case 0:
				break;
			//	resampling
			case 1:
				[returnMe setObject:[NSNumber numberWithInteger:[_audioResampleField integerValue]] forKey:AVSampleRateKey];
				break;
			}
	//	}
	//	break;
	//}
	return returnMe;
}
- (void) populateUIWithAVFSettingsDict:(NSDictionary *)n	{
	//NSLog(@"%s",__func__);
	NSNumber		*formatNum = nil;
	NSString		*tmpString = nil;
	NSNumber		*tmpNum = nil;
	
	tmpNum = [n objectForKey:kAVFExportAudioSampleRateKey];
	if (tmpNum == nil)
		tmpNum = @( 48000 );
	displayAudioResampleRate = tmpNum.unsignedIntegerValue;
	
	formatNum = [n objectForKey:AVFormatIDKey];
	if (formatNum==nil)	{
		//[audioCategoryTabView selectTabViewItemAtIndex:0];
		//tmpNum = [n objectForKey:kAVFExportStripMediaKey];
		//if (tmpNum!=nil && [tmpNum boolValue])
		//	[audioNoTranscodeMatrix selectCellAtRow:0 column:0];
		//else
		//	[audioNoTranscodeMatrix selectCellAtRow:1 column:0];
	}
	else	{
		//[audioCategoryTabView selectTabViewItemAtIndex:1];
		[_audioCodecPUB selectItemWithRepresentedObject:formatNum];
		[self audioCodecPUBUsed:_audioCodecPUB];
		switch ([formatNum intValue])	{
		case kAudioFormatLinearPCM:
			tmpNum = [n objectForKey:AVLinearPCMBitDepthKey];
			if (tmpNum!=nil)	{
				[_pcmBitsPUB selectItemWithRepresentedObject:tmpNum];
				[self pcmBitsPUBUsed:_pcmBitsPUB];
			}
			tmpNum = [n objectForKey:AVLinearPCMIsBigEndianKey];
			if (tmpNum!=nil)
				[_pcmLittleEndianButton setIntValue:([tmpNum boolValue]) ? NSControlStateValueOff : NSControlStateValueOn];
			tmpNum = [n objectForKey:AVLinearPCMIsFloatKey];
			if (tmpNum!=nil)
				[_pcmFloatingPointButton setIntValue:([tmpNum boolValue]) ? NSControlStateValueOn : NSControlStateValueOff];
			break;
		case kAudioFormatMPEG4AAC:
			tmpString = [n objectForKey:AVEncoderBitRateStrategyKey];
			if (tmpString!=nil)	{
				[_aacBitrateStrategyPUB selectItemWithRepresentedObject:tmpString];
				[self aacBitrateStrategyPUBUsed:_aacBitrateStrategyPUB];
			}
			else	{
				[_aacBitrateStrategyPUB selectItemWithRepresentedObject:AVAudioBitRateStrategy_Variable];
				[self aacBitrateStrategyPUBUsed:_aacBitrateStrategyPUB];
			}
			
			tmpNum = [n objectForKey:AVEncoderBitRateKey];
			if (tmpNum!=nil)	{
				[_aacBitratePUB selectItemWithRepresentedObject:tmpNum];
			}
			else	{
				NSMenuItem		*tmpItem = [_aacBitrateStrategyPUB selectedItem];
				NSString		*tmpStrategy = (tmpItem==nil) ? AVAudioBitRateStrategy_Variable : [tmpItem representedObject];
				if (tmpStrategy == AVAudioBitRateStrategy_Variable)	{
					//	intentionally blank, variable bitrate doesn't use the bitrate PUB picker...
				}
				else	{
					[_aacBitratePUB selectItemAtIndex:[_aacBitratePUB numberOfItems]-1];
				}
			}
			break;
		case kAudioFormatAppleLossless:
			tmpNum = [n objectForKey:AVEncoderBitDepthHintKey];
			if (tmpNum!=nil)	{
				[_losslessBitDepthPUB selectItemWithRepresentedObject:tmpNum];
			}
			break;
		}
		
		tmpNum = [n objectForKey:AVSampleRateKey];
		if (tmpNum==nil)
			[self noResampleAudioClicked:nil];
		else	{
			[self resampleAudioClicked:nil];
			[_audioResampleField setStringValue:[NSString stringWithFormat:@"%ld",(long)[tmpNum integerValue]]];
		}
	}
}


- (NSString *) lengthyDescription	{
	NSString		*returnMe = nil;
	//switch ([audioCategoryTabView selectedTabViewItemIndex])	{
	//case 0:
	//	switch ([audioNoTranscodeMatrix selectedRow])	{
		//	strip
	//	case 0:
	//		returnMe = @"Audio tracks will be stripped.";
	//		break;
		//	copy
	//	case 1:
	//		returnMe = @"Audio tracks will be copied (but not processed).";
	//		break;
	//	}
	//	break;
	//case 1:
	//	{
			NSNumber		*formatIDNum = [[_audioCodecPUB selectedItem] representedObject];
			switch ([formatIDNum integerValue])	{
			case kAudioFormatLinearPCM:
				if ([_pcmLittleEndianButton intValue]==NSControlStateValueOn)
					returnMe = [NSString stringWithFormat:@"PCM %@ bit, little-endian",[_pcmBitsPUB titleOfSelectedItem]];
				else
					returnMe = [NSString stringWithFormat:@"PCM %@ bit, big-endian",[_pcmBitsPUB titleOfSelectedItem]];
				if ([_pcmFloatingPointButton intValue]==NSControlStateValueOn)
					returnMe = [NSString stringWithFormat:@"%@ float",returnMe];
				break;
			case kAudioFormatMPEG4AAC:
				returnMe = @"AAC";
				returnMe = [NSString stringWithFormat:@"%@, %@",returnMe,[_aacBitrateStrategyPUB titleOfSelectedItem]];
				if ([_aacBitratePUB isEnabled])
					returnMe = [NSString stringWithFormat:@"%@, %@ kbps.",returnMe,[_aacBitratePUB titleOfSelectedItem]];
				break;
			case kAudioFormatAppleLossless:
				returnMe = [NSString stringWithFormat:@"Apple Lossless, %@ bit",[_losslessBitDepthPUB titleOfSelectedItem]];
				break;
			}
	//		break;
	//	}
	//}
	
	switch ([_audioResampleTabView selectedTabViewItemIndex])	{
	//	no resampling
	case 0:
		break;
	//	resampling
	case 1:
		returnMe = [NSString stringWithFormat:@"%@, %ld Hz",returnMe,(long)[_audioResampleField integerValue]];
		break;
	}
	
	
	return returnMe;
}


#pragma mark - UI actions


- (IBAction) audioCodecPUBUsed:(id)sender	{
	NSMenuItem		*selectedItem = [_audioCodecPUB selectedItem];
	uint32_t		audioFormat = (uint32_t)[[selectedItem representedObject] integerValue];
	switch (audioFormat)	{
	case kAudioFormatLinearPCM:
		[_audioCodecTabView selectTabViewItemAtIndex:1];
		break;
	case kAudioFormatMPEG4AAC:
		{
			[_audioCodecTabView selectTabViewItemAtIndex:2];
			
			[_aacBitrateStrategyPUB selectItemWithRepresentedObject:AVAudioBitRateStrategy_Variable];
			[self aacBitrateStrategyPUBUsed:_aacBitrateStrategyPUB];
			
			//	AAC only works with a limited set of sample rates, so when i switch to it i need to run through the pop-up button and make sure that one of its options are selected
			//	get the value of the _audioResampleField as a string-converted-to-an-integer
			NSString		*audioResampleFieldString = [_audioResampleField stringValue];
			NSUInteger		audioResampleFieldInt = (audioResampleFieldString==nil) ? 48000 : [audioResampleFieldString integerValue];
			//	run through items in the _audioResamplePUB- if the item's repObj value is >= the text field's integer value, select that item from the _audioResamplePUB
			BOOL			foundItem = NO;
			for (NSMenuItem *itemPtr in [[_audioResamplePUB menu] itemArray])	{
				NSNumber		*tmpNum = [itemPtr representedObject];
				if (tmpNum!=nil && [tmpNum integerValue]>=audioResampleFieldInt)	{
					[_audioResamplePUB selectItem:itemPtr];
					foundItem = YES;
					break;
				}
			}
			if (!foundItem)	{
				[_audioResamplePUB selectItemAtIndex:[[[_audioResamplePUB menu] itemArray] count]-1];
			}
			else	{
				//	intentionally blank
			}
			[self audioResamplePUBUsed:_audioResamplePUB];
		}
		break;
	case kAudioFormatAppleLossless:
		[_audioCodecTabView selectTabViewItemAtIndex:3];
		break;
	}
}
- (IBAction) pcmBitsPUBUsed:(id)sender	{
	NSUInteger		newBitdepth = [[_pcmBitsPUB titleOfSelectedItem] integerValue];
	switch (newBitdepth)	{
	case 8:
		[_pcmFloatingPointButton setIntValue:NSControlStateValueOff];
		[_pcmFloatingPointButton setEnabled:NO];
		break;
	case 16:
		[_pcmFloatingPointButton setIntValue:NSControlStateValueOff];
		[_pcmFloatingPointButton setEnabled:NO];
		break;
	case 24:
		[_pcmFloatingPointButton setIntValue:NSControlStateValueOff];
		[_pcmFloatingPointButton setEnabled:NO];
		break;
	case 32:
		[_pcmFloatingPointButton setEnabled:YES];
		break;
	}
}
- (IBAction) aacBitrateStrategyPUBUsed:(id)sender	{
	/*
	[_aacBitratePUB setEnabled:([[_aacBitrateStrategyPUB selectedItem] representedObject]!=AVAudioBitRateStrategy_Variable) ? YES : NO];
	*/
	
	
	
	NSMenuItem		*brStratItem = [_aacBitrateStrategyPUB selectedItem];
	NSString		*brStrat = (brStratItem==nil) ? AVAudioBitRateStrategy_Variable : [brStratItem representedObject];
	
	[_aacBitratePUB removeAllItems];
	
	AudioStreamBasicDescription		tmpASBD;
	tmpASBD.mFormatID = kAudioFormatMPEG4AAC;
	tmpASBD.mSampleRate = displayAudioResampleRate;
	tmpASBD.mChannelsPerFrame = 1;
	tmpASBD.mBitsPerChannel = 0;
	tmpASBD.mBytesPerPacket = 0;
	tmpASBD.mBytesPerFrame = 0;
	tmpASBD.mFramesPerPacket = 1024;
	tmpASBD.mFormatFlags = 0;
	
	NSArray			*bitrateVals = nil;
	if (brStrat == AVAudioBitRateStrategy_Constant)	{
		bitrateVals = [VVAudioFormatUtilities bitratesForDescription:tmpASBD bitRateMode:kAudioCodecBitRateFormat_CBR];
	}
	else if (brStrat == AVAudioBitRateStrategy_LongTermAverage)	{
		bitrateVals = [VVAudioFormatUtilities bitratesForDescription:tmpASBD bitRateMode:kAudioCodecBitRateFormat_ABR];
	}
	else if (brStrat == AVAudioBitRateStrategy_VariableConstrained)	{
		bitrateVals = [VVAudioFormatUtilities bitratesForDescription:tmpASBD bitRateMode:kAudioCodecBitRateFormat_VBR];
	}
	else if (brStrat == AVAudioBitRateStrategy_Variable)	{
		//	intentionally blank, no bitrate vals
	}
	
	NSMenu			*tmpMenu = [_aacBitratePUB menu];
	
	if (bitrateVals != nil)	{
		[_aacBitratePUB setEnabled:YES];
		for (NSNumber *bitrateVal in bitrateVals)	{
			NSMenuItem		*tmpItem = [[NSMenuItem alloc]
				initWithTitle:[NSString stringWithFormat:@"%ld",[bitrateVal longValue]/1000]
				action:nil
				keyEquivalent:@""];
			[tmpItem setRepresentedObject:bitrateVal];
			[tmpMenu addItem:tmpItem];
		}
		
		[_aacBitratePUB selectItemWithRepresentedObject:[NSNumber numberWithDouble:160000.0]];
		if ([_aacBitratePUB selectedItem]==nil && [_aacBitratePUB numberOfItems]>0)	{
			[_aacBitratePUB selectItemAtIndex:[_aacBitratePUB numberOfItems]-1];
		}
	}
	else	{
		[_aacBitratePUB setEnabled:NO];
	}
	
}
- (IBAction) resampleAudioClicked:(id)sender	{
	[_audioResampleTabView selectTabViewItemAtIndex:1];
}
- (IBAction) noResampleAudioClicked:(id)sender	{
	[_audioResampleTabView selectTabViewItemAtIndex:0];
}
- (IBAction) audioResamplePUBUsed:(id)sender	{
	NSNumber		*tmpNum = [[_audioResamplePUB selectedItem] representedObject];
	NSUInteger		newSampleRate = (tmpNum==nil) ? 0.0 : [tmpNum unsignedLongValue];
	if (newSampleRate!=0)	{
		[_audioResampleField setStringValue:[NSString stringWithFormat:@"%ld",(unsigned long)newSampleRate]];
	}
	
}
- (IBAction) resampleAudioTextFieldUsed:(id)sender	{
	NSString		*audioResampleFieldString = [_audioResampleField stringValue];
	NSUInteger		audioResampleFieldInt = (audioResampleFieldString==nil) ? 0.0 : [audioResampleFieldString integerValue];
	//	if the audio format is AAC then i can only work with a specific and limited set of sample rates, so i need to verify the value in this field
	if ([[[_audioCodecPUB selectedItem] representedObject] integerValue]==kAudioFormatMPEG4AAC)	{
		//	run through the items in the _audioResamplePUB- if the item's repObj value is >= the text field's integer value, select that item from the _audioResamplePUB
		BOOL			foundItem = NO;
		for (NSMenuItem *itemPtr in [[_audioResamplePUB menu] itemArray])	{
			NSNumber		*tmpNum = [itemPtr representedObject];
			if (tmpNum!=nil && [tmpNum integerValue]>=audioResampleFieldInt)	{
				[_audioResamplePUB selectItem:itemPtr];
				foundItem = YES;
				break;
			}
		}
		if (!foundItem)	{
			[_audioResamplePUB selectItemAtIndex:[[[_audioResamplePUB menu] itemArray] count]-1];
		}
		else	{
			//	intentionally blank
		}
		[self audioResamplePUBUsed:_audioResamplePUB];
	}
	//	else the audio format is either PCM or apple lossless- i just need to make sure the new val is between 8 and 192
	else	{
		if (audioResampleFieldInt<8000)
			audioResampleFieldInt = 8000;
		else if (audioResampleFieldInt>192000)
			audioResampleFieldInt = 192000;
		[_audioResampleField setStringValue:[NSString stringWithFormat:@"%ld",(unsigned long)audioResampleFieldInt]];
		//if (audioResampleFieldInt<8 || audioResampleFieldInt>192)
		//	[self audioResamplePUBUsed:_audioResamplePUB];
	}
	
}


#pragma mark - backend methods


- (void) populateMenu:(NSMenu *)popMenu withItemsForAudioProperty:(uint32_t)popQueryProperty ofAudioFormat:(uint32_t)popAudioFormat	{
	if (popMenu!=nil)	{
		[popMenu removeAllItems];
		
		OSStatus		osErr = noErr;
		uint32_t		replySize;
		osErr = AudioFormatGetPropertyInfo(popQueryProperty, sizeof(popAudioFormat), &popAudioFormat, (UInt32 *)&replySize);
		if (osErr!=noErr)	{
			NSLog(@"\t\terr %d at AudioFormatGetProperty() in %s",(int)osErr,__func__);
			NSLog(@"\t\terr: property is %c%c%c%c", (int)((popQueryProperty>>24)&0xFF), (int)((popQueryProperty>>16)&0xFF), (int)((popQueryProperty>>8)&0xFF), (int)((popQueryProperty>>0)&0xFF));
			NSLog(@"\t\terr: format is %c%c%c%c", (int)((popAudioFormat>>24)&0xFF), (int)((popAudioFormat>>16)&0xFF), (int)((popAudioFormat>>8)&0xFF), (int)((popAudioFormat>>0)&0xFF));
		}
		else	{
			void			*replyData = malloc(replySize);
			osErr = AudioFormatGetProperty(popQueryProperty, sizeof(popAudioFormat), &popAudioFormat, (UInt32 *)&replySize, replyData);
			if (osErr!=noErr)	{
				NSLog(@"\t\terr %d at AudioFormatGetProperty() in %s",(int)osErr,__func__);
				NSLog(@"\t\terr: property is %c%c%c%c", (int)((popQueryProperty>>24)&0xFF), (int)((popQueryProperty>>16)&0xFF), (int)((popQueryProperty>>8)&0xFF), (int)((popQueryProperty>>0)&0xFF));
				NSLog(@"\t\terr: format is %c%c%c%c", (int)((popAudioFormat>>24)&0xFF), (int)((popAudioFormat>>16)&0xFF), (int)((popAudioFormat>>8)&0xFF), (int)((popAudioFormat>>0)&0xFF));
			}
			else	{
				//NSLog(@"\t\treplySize is %u, sizeof(AudioValueRange) is %ld",replySize,sizeof(AudioValueRange));
				//NSLog(@"\t\ttheoretically, there are %ld strcuts",replySize/sizeof(AudioValueRange));
				int					rangeCount = replySize/sizeof(AudioValueRange);
				AudioValueRange		*rangePtr = replyData;
				for (int i=0; i<rangeCount; ++i)	{
					//NSLog(@"\t\trange %d is %f / %f",i,rangePtr->mMinimum,rangePtr->mMaximum);
					NSUInteger			tmpInt = rangePtr->mMaximum;
					NSMenuItem			*tmpItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%ld",(unsigned long)tmpInt] action:nil keyEquivalent:@""];
					[tmpItem setRepresentedObject:[NSNumber numberWithInteger:tmpInt]];
					[popMenu addItem:tmpItem];
					++rangePtr;
				}
			}
			free(replyData);
		}
	}
}


@end
