#import "FileSettingsController.h"
#import "ExportController.h"




@implementation FileSettingsController


- (id) init	{
	self = [super init];
	if (self!=nil)	{
	}
	return self;
}
- (void) awakeFromNib	{
	//	load the saved settings from the user defaults (populates the pop-up button)
	[self loadSavedSettingsFromDefaults];
	//	load the last audio/video settings
	NSUserDefaults		*def = [NSUserDefaults standardUserDefaults];
	//NSDictionary		*tmpDict = nil;
	
	NSDictionary		*tmpAudioDict = [def objectForKey:@"lastAudioSettings"];
	if (tmpAudioDict==nil)
		tmpAudioDict = [NSDictionary dictionary];
	exportController.audioSettingsDict = tmpAudioDict;
	
	NSDictionary		*tmpVideoDict = [def objectForKey:@"lastVideoSettings"];
	if (tmpVideoDict==nil)
		tmpVideoDict = [NSDictionary dictionary];
	exportController.videoSettingsDict = tmpVideoDict;
	
	AVFExportAVSettingsWindow		*tmpWin = [AVFExportAVSettingsWindow createWithAudioSettings:tmpAudioDict videoSettings:tmpVideoDict];
	NSString		*audioDesc = tmpWin.audioVC.lengthyDescription;
	NSString		*videoDesc = tmpWin.videoVC.lengthyDescription;
	[audioDescriptionField setStringValue:audioDesc];
	[videoDescriptionField setStringValue:videoDesc];
	
	if (tmpAudioDict == nil && tmpVideoDict == nil)	{
		[loadSavedExportSettingsPUB selectItemWithTitle:@"h264"];
		[self loadSavedExportSettingsPUBUsed:loadSavedExportSettingsPUB];
	}
	else	{
		[loadSavedExportSettingsPUB selectItem:nil];
	}
}

- (void) loadSavedSettingsFromDefaults	{
	//	populate the saved settings pop-up button
	[loadSavedExportSettingsPUB removeAllItems];
	NSUserDefaults		*def = [NSUserDefaults standardUserDefaults];
	NSDictionary		*savedSettings = [def objectForKey:@"savedExportSettings"];
	//	if the saved settings are nil or empty, populate them with a few default settings
	if (savedSettings==nil || [savedSettings count]<1)	{
		savedSettings = @{
			@"h264": @{
				@"audio":@{
					AVFormatIDKey: @1633772320,
					AVEncoderBitRateStrategyKey: AVAudioBitRateStrategy_Variable
				},
				@"video":@{
					AVVideoCodecKey: AVVideoCodecTypeH264,
					kVVAVFTranscodeMultiPassEncodeKey: @1,
					AVVideoCompressionPropertiesKey: @{
						AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
					}
				}
			},
			@"Hap": @{
				@"audio":@{},
				@"video":@{
					AVVideoCodecKey: AVVideoCodecHap,
					AVVideoCompressionPropertiesKey: @{
						AVVideoQualityKey: @0.76
					}
				}
			},
			@"Hap Alpha": @{
				@"audio":@{},
				@"video":@{
					AVVideoCodecKey: AVVideoCodecHapAlpha,
					AVVideoCompressionPropertiesKey: @{
						AVVideoQualityKey: @0.76
					}
				}
			},
			@"Hap Q": @{
				@"audio":@{},
				@"video":@{
					AVVideoCodecKey: AVVideoCodecHapQ,
				}
			},
			
			@"Hap 7 Alpha": @{
				@"audio":@{},
				@"video":@{
					AVVideoCodecKey: AVVideoCodecHap7Alpha,
				}
			},
			/*
			@"Hap HDR": @{
				@"audio":@{},
				@"video":@{
					AVVideoCodecKey: AVVideoCodecHapHDR,
					AVVideoCompressionPropertiesKey: @{
						AVHapVideoHDRSignedFloatKey: @NO
					}
				}
			},
			*/
			@"PJPEG": @{
				@"audio":@{},
				@"video":@{
					AVVideoCodecKey: AVVideoCodecTypeJPEG,
					AVVideoCompressionPropertiesKey: @{
						AVVideoQualityKey: @0.76
					}
				}
			},
			@"ProRes 422": @{
				@"audio":@{},
				@"video":@{
					AVVideoCodecKey: AVVideoCodecTypeAppleProRes422,
				}
			},
			@"ProRes 4444": @{
				@"audio":@{},
				@"video":@{
					AVVideoCodecKey: AVVideoCodecTypeAppleProRes4444,
				}
			}
		};
		[def setObject:savedSettings forKey:@"savedExportSettings"];
		[def synchronize];
		savedSettings = [def objectForKey:@"savedExportSettings"];
	}
	
	//	run through and populate the pop-up button with the saved settings
	NSArray				*sortedSettingKeys = nil;
	sortedSettingKeys = [[savedSettings allKeys] sortedArrayUsingComparator:^(id obj1, id obj2)	{
		return [obj1 compare:obj2];
	}];
	NSMenu				*settingsMenu = [loadSavedExportSettingsPUB menu];
	for (NSString *tmpKey in sortedSettingKeys)	{
		NSDictionary		*settingsDict = [savedSettings objectForKey:tmpKey];
		if (settingsDict!=nil)	{
			//	each saved setting menu item contains the dict
			NSMenuItem		*newItem = [[NSMenuItem alloc] initWithTitle:tmpKey action:nil keyEquivalent:@""];
			[newItem setRepresentedObject:settingsDict];
			[settingsMenu addItem:newItem];
			newItem = nil;
		}
	}
	
	//	copy all the items in the load settings pop-up button to the delete settings pop-up button
	{
		NSMenu		*loadMenu = [loadSavedExportSettingsPUB menu];
		NSMenu		*deleteMenu = [deleteSavedExportSettingsPUB menu];
		[deleteMenu removeAllItems];
		for (NSMenuItem *itemPtr in [loadMenu itemArray])	{
			NSMenuItem		*itemCopy = [itemPtr copy];
			if (itemCopy!=nil)
				[deleteMenu addItem:itemCopy];
		}
		[deleteSavedExportSettingsPUB selectItem:nil];
	}
}

- (IBAction) settingsButtonClicked:(id)sender	{
	//NSLog(@"%s",__func__);
	NSUserDefaults		*tmpDef = [NSUserDefaults standardUserDefaults];
	
	AVFExportAVSettingsWindow		*win = [AVFExportAVSettingsWindow
		createWithAudioSettings:[tmpDef objectForKey:@"lastAudioSettings"]
		videoSettings:[tmpDef objectForKey:@"lastVideoSettings"]];
	
	if (win != nil)	{
		//	open the win!
		[mainWindow
			beginSheet:win.window
			completionHandler:^(NSModalResponse returnCode)	{
				NSDictionary		*audioDict = [win.audioVC createAVFSettingsDict];
				NSDictionary		*videoDict = [win.videoVC createAVFSettingsDict];
				
				[self->loadSavedExportSettingsPUB selectItem:nil];
				if (returnCode != NSModalResponseOK)	{
					return;
				}
				
				NSUserDefaults		*def = [NSUserDefaults standardUserDefaults];
				[def setObject:audioDict forKey:@"lastAudioSettings"];
				[def setObject:videoDict forKey:@"lastVideoSettings"];
				
				NSString			*videoDesc = win.videoVC.lengthyDescription;
				NSString			*audioDesc = win.audioVC.lengthyDescription;
				self->videoDescriptionField.stringValue = (videoDesc==nil) ? @"" : videoDesc;
				self->audioDescriptionField.stringValue = (audioDesc==nil) ? @"" : audioDesc;
				
				self->exportController.audioSettingsDict = audioDict;
				self->exportController.videoSettingsDict = videoDict;
			}];
	}
	
}
- (IBAction) loadSavedExportSettingsPUBUsed:(id)sender	{
	//NSLog(@"%s",__func__);
	NSMenuItem			*selItem = [sender selectedItem];
	if (selItem==nil)
		return;
	NSDictionary		*settingsDict = [selItem representedObject];
	if (settingsDict==nil)
		return;
	NSDictionary		*audio = [settingsDict objectForKey:@"audio"];
	//[transcoderSettings populateUIWithAudioSettingsDict:audio];
	NSDictionary		*video = [settingsDict objectForKey:@"video"];
	//[transcoderSettings populateUIWithVideoSettingsDict:video];
	//NSLog(@"\t\taudio is %@",audio);
	//NSLog(@"\t\tvideo is %@",video);
	
	NSUserDefaults	*def = [NSUserDefaults standardUserDefaults];
	if (audio != nil)
		[def setObject:audio forKey:@"lastAudioSettings"];
	if (video != nil)
		[def setObject:video forKey:@"lastVideoSettings"];
	
	exportController.audioSettingsDict = audio;
	exportController.videoSettingsDict = video;
	
	AVFExportAVSettingsWindow		*tmpWin = [AVFExportAVSettingsWindow createWithAudioSettings:audio videoSettings:video];
	NSString		*tmpAudioString = tmpWin.audioVC.lengthyDescription;
	if (tmpAudioString == nil)
		tmpAudioString = @"";
	NSString		*tmpVideoString = tmpWin.videoVC.lengthyDescription;
	if (tmpVideoString == nil)
		tmpVideoString = @"";
	[audioDescriptionField setStringValue:tmpAudioString];
	[videoDescriptionField setStringValue:tmpVideoString];
	tmpWin = nil;
}
- (IBAction) saveCurrentSettingsClicked:(id)sender	{
	//NSLog(@"%s",__func__);
	[mainWindow beginCriticalSheet:saveSettingsWindow completionHandler:^(NSModalResponse returnCode)	{
		//	if i didn't save a setting, i'm not returning a 'continue'
		if (returnCode==NSModalResponseContinue)	{
		}
	}];
}
- (IBAction) deleteSettingClicked:(id)sender	{
	NSString		*deleteTitle = [deleteSavedExportSettingsPUB titleOfSelectedItem];
	if (deleteTitle!=nil)	{
		NSUserDefaults		*def = [NSUserDefaults standardUserDefaults];
		NSDictionary		*savedSettings = [def objectForKey:@"savedExportSettings"];
		if (savedSettings!=nil)	{
			NSMutableDictionary		*mutSavedSettings = [savedSettings mutableCopy];
			if (mutSavedSettings!=nil)	{
				[mutSavedSettings removeObjectForKey:deleteTitle];
				[def setObject:mutSavedSettings forKey:@"savedExportSettings"];
				[def synchronize];
				
				//	reload the saved export settings
				[self loadSavedSettingsFromDefaults];
				
				mutSavedSettings = nil;
			}
		}
	}
}
- (IBAction) cancelSaveSettingsClicked:(id)sender	{
	[mainWindow endSheet:saveSettingsWindow returnCode:NSModalResponseAbort];
}
- (IBAction) proceedSaveSettingsClicked:(id)sender	{
	NSString		*presetName = [saveSettingsField stringValue];
	if (presetName!=nil && [presetName length]>0 && [loadSavedExportSettingsPUB itemWithTitle:presetName]==nil)	{
		//	assemble the dict that contains other dicts which describe the audio & video settings
		NSMutableDictionary		*newSettingsDict = [NSMutableDictionary dictionaryWithCapacity:0];
		NSDictionary		*tmpDict = nil;
		tmpDict = exportController.videoSettingsDict;
		if (tmpDict!=nil)
			[newSettingsDict setObject:tmpDict forKey:@"video"];
		tmpDict = exportController.audioSettingsDict;
		if (tmpDict!=nil)
			[newSettingsDict setObject:tmpDict forKey:@"audio"];
		
		//	save stuff in the default
		NSUserDefaults		*def = [NSUserDefaults standardUserDefaults];
		NSDictionary		*settings = [def objectForKey:@"savedExportSettings"];
		NSMutableDictionary	*tmpMutDict = (settings==nil) ? [NSMutableDictionary dictionaryWithCapacity:0] : [settings mutableCopy];
		[tmpMutDict setObject:newSettingsDict forKey:presetName];
		[def setObject:tmpMutDict forKey:@"savedExportSettings"];
		[def synchronize];
		//NSLog(@"\t\tsaving settings %@",newSettingsDict);
		
		//	reset/reload the various UI items
		[saveSettingsField setStringValue:@""];
		[mainWindow endSheet:saveSettingsWindow returnCode:NSModalResponseContinue];
		//	reload the saved settings pop-up button regardless
		dispatch_async(dispatch_get_main_queue(), ^{
			[self loadSavedSettingsFromDefaults];
		});
	}
}


@end
