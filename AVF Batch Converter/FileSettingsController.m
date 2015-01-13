#import "FileSettingsController.h"
#import "ExportController.h"




@implementation FileSettingsController


- (id) init	{
	self = [super init];
	if (self!=nil)	{
		transcoderSettings = [[VVAVFExportBasicSettingsCtrlr alloc] init];
	}
	return self;
}
- (void) awakeFromNib	{
	//	put the transcoder settings view in the settings view holder
	NSView			*settingsView = [transcoderSettings settingsView];
	[settingsView setFrameOrigin:NSMakePoint(0,0)];
	[settingsViewHolder addSubview:settingsView];
	//	load the saved settings from the user defaults (populates the pop-up button)
	[self loadSavedSettingsFromDefaults];
	//	load the last audio/video settings
	NSUserDefaults		*def = [NSUserDefaults standardUserDefaults];
	NSDictionary		*tmpDict = nil;
	BOOL				lastAudioAndVideoNil = YES;
	
	tmpDict = [def objectForKey:@"lastAudioSettings"];
	if (tmpDict==nil)
		tmpDict = [NSDictionary dictionary];
	else
		lastAudioAndVideoNil = NO;
	[transcoderSettings populateUIWithAudioSettingsDict:tmpDict];
	[audioDescriptionField setStringValue:[transcoderSettings lengthyAudioDescription]];
	[exportController setAudioSettingsDict:tmpDict];
	
	tmpDict = [def objectForKey:@"lastVideoSettings"];
	if (tmpDict==nil)
		tmpDict = [NSDictionary dictionary];
	else
		lastAudioAndVideoNil = NO;
	[transcoderSettings populateUIWithVideoSettingsDict:tmpDict];
	[videoDescriptionField setStringValue:[transcoderSettings lengthyVideoDescription]];
	[exportController setVideoSettingsDict:tmpDict];
	
	if (lastAudioAndVideoNil)	{
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
					AVVideoCodecKey: AVVideoCodecH264,
					VVAVVideoMultiPassEncodeKey: @1,
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
			@"PJPEG": @{
				@"audio":@{},
				@"video":@{
					AVVideoCodecKey: AVVideoCodecJPEG,
					AVVideoCompressionPropertiesKey: @{
						AVVideoQualityKey: @0.76
					}
				}
			},
			@"ProRes 422": @{
				@"audio":@{},
				@"video":@{
					AVVideoCodecKey: AVVideoCodecAppleProRes422,
				}
			},
			@"ProRes 4444": @{
				@"audio":@{},
				@"video":@{
					AVVideoCodecKey: AVVideoCodecAppleProRes4444,
				}
			}
		};
		[def setObject:savedSettings forKey:@"savedExportSettings"];
		[def synchronize];
		savedSettings = [def objectForKey:@"savedExportSettings"];
	}
	
	//	run through and populate the pop-up button with the saved settings
	if (savedSettings!=nil && [savedSettings count]>0)	{
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
				[newItem release];
			}
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
	[mainWindow beginCriticalSheet:settingsWindow completionHandler:^(NSModalResponse returnCode)	{
		[self pushSettingsToExportController];
	}];
}
- (IBAction) closeSettingsButtonClicked:(id)sender	{
	//NSLog(@"%s",__func__);
	[mainWindow endSheet:settingsWindow returnCode:NSModalResponseContinue];
	[loadSavedExportSettingsPUB selectItem:nil];
}
- (void) pushSettingsToExportController	{
	//NSLog(@"%s",__func__);
	
	NSUserDefaults			*def = [NSUserDefaults standardUserDefaults];
	NSMutableDictionary		*tmpDict = nil;
	
	tmpDict = [transcoderSettings createAudioOutputSettingsDict];
	[exportController setAudioSettingsDict:tmpDict];
	[def setObject:tmpDict forKey:@"lastAudioSettings"];
	
	tmpDict = [transcoderSettings createVideoOutputSettingsDict];
	[exportController setVideoSettingsDict:tmpDict];
	[def setObject:tmpDict forKey:@"lastVideoSettings"];
	
	[def synchronize];
	
	[videoDescriptionField setStringValue:[transcoderSettings lengthyVideoDescription]];
	[audioDescriptionField setStringValue:[transcoderSettings lengthyAudioDescription]];
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
	[transcoderSettings populateUIWithAudioSettingsDict:audio];
	NSDictionary		*video = [settingsDict objectForKey:@"video"];
	[transcoderSettings populateUIWithVideoSettingsDict:video];
	//NSLog(@"\t\taudio is %@",audio);
	//NSLog(@"\t\tvideo is %@",video);
	[self pushSettingsToExportController];
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
				
				[mutSavedSettings release];
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
		NSMutableDictionary		*tmpDict = nil;
		tmpDict = [transcoderSettings createVideoOutputSettingsDict];
		if (tmpDict!=nil)
			[newSettingsDict setObject:tmpDict forKey:@"video"];
		tmpDict = [transcoderSettings createAudioOutputSettingsDict];
		if (tmpDict!=nil)
			[newSettingsDict setObject:tmpDict forKey:@"audio"];
		
		//	save stuff in the default
		NSUserDefaults		*def = [NSUserDefaults standardUserDefaults];
		NSDictionary		*settings = [def objectForKey:@"savedExportSettings"];
		NSMutableDictionary	*tmpMutDict = (settings==nil) ? [NSMutableDictionary dictionaryWithCapacity:0] : [[settings mutableCopy] autorelease];
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
