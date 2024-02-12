//
//  AVFExportSettingsVideoVC.m
//  VVAVFExport-TestApp
//
//  Created by testadmin on 5/4/22.
//

#import "AVFExportSettingsVideoVC.h"
#import "AVFExportAVSettingsWindow.h"
#import "AVFExportSettingsAdditions.h"
#import <VideoToolbox/VideoToolbox.h>
#import "Availability.h"
#import "AvailabilityVersions.h"
#import <HapInAVFoundation/HapInAVFoundation.h>




@interface AVFExportSettingsVideoVC ()	{
	NSSize				displayVideoDims;
}

@property (weak) IBOutlet NSPopUpButton * vidCodecPUB;	//	pop-up button for selecting destination video codec
@property (weak) IBOutlet NSTabView * vidCodecTabView;	//	tab view, each tab has options for a different video codec
@property (weak) IBOutlet NSSlider * pjpegQualitySlider;	//	general-use quality slider in the pjpeg tab of 'vidCodecTabView'

@property (weak) IBOutlet NSPopUpButton * h264ProfilesPUB;	//	pop-up button with h.264 profiles in 'vidCodecTabView'
	@property (weak) IBOutlet NSButton * h264KeyframesMatrixAuto;
	@property (weak) IBOutlet NSButton * h264KeyframesMatrixOnceEvery;
@property (weak) IBOutlet NSTextField * h264KeyframesField;
	@property (weak) IBOutlet NSButton * h264BitrateMatrixAuto;
	@property (weak) IBOutlet NSButton * h264BitrateMatrixLimitTo;
@property (weak) IBOutlet NSTextField * h264BitrateField;
@property (weak) IBOutlet NSButton * h264MultiPassButton;

@property (weak) IBOutlet NSSlider * hapQualitySlider;
@property (weak) IBOutlet NSMatrix * hapChunkMatrix;
@property (weak) IBOutlet NSTextField * hapChunkField;
@property (weak) IBOutlet NSMatrix * hapQChunkMatrix;
@property (weak) IBOutlet NSTextField * hapQChunkField;
@property (weak) IBOutlet NSMatrix * hapHDRChunkMatrix;
@property (weak) IBOutlet NSTextField * hapHDRChunkField;
@property (weak) IBOutlet NSButton * hapHDRSignedToggle;

@property (weak) IBOutlet NSPopUpButton * hevcProfilesPUB;

@property (weak) IBOutlet NSTabView * vidDimsTabView;	//	tab view hosting a toggle for selecting whether or not video should be resized
@property (weak) IBOutlet NSTextField * vidWidthField;	//	text field in 'vidDimsTabView', destination width
@property (weak) IBOutlet NSTextField * vidHeightField;	//	text field in 'vidDimsTabView', destination height

- (IBAction) vidCodecPUBUsed:(id)sender;
- (IBAction) h264KeyframesMatrixUsed:(id)sender;
- (IBAction) h264KeyframesFieldUsed:(id)sender;
- (IBAction) h264BitrateMatrixUsed:(id)sender;
- (IBAction) h264BitrateFieldUsed:(id)sender;
- (IBAction) hapChunkMatrixUsed:(id)sender;
- (IBAction) hapChunkFieldUsed:(id)sender;
- (IBAction) hapQChunkMatrixUsed:(id)sender;
- (IBAction) hapQChunkFieldUsed:(id)sender;
- (IBAction) hapHDRChunkMatrixUsed:(id)sender;
- (IBAction) hapHDRChunkFieldUsed:(id)sender;
- (IBAction) resizeVideoClicked:(id)sender;
- (IBAction) noResizeVideoClicked:(id)sender;
- (IBAction) resizeVideoTextFieldUsed:(id)sender;

@end




@implementation AVFExportSettingsVideoVC


+ (NSMutableDictionary *) defaultAVFSettingsDict	{
	NSDictionary		*tmpDict = @{
		kAVFExportVideoResolutionKey: [NSValue valueWithSize:NSMakeSize(1920,1080)],
		//kAVFExportMultiPassEncodeKey: @( YES ),
		kAVFExportMultiPassEncodeKey: @( NO ),
		AVVideoCodecKey: AVVideoCodecTypeH264
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
	//	populate the codec pop-up button.  each item's representedObject should be the string of the codec type...
	[_vidCodecPUB removeAllItems];
	NSMenuItem				*newItem = nil;
	NSMenu					*theMenu = [_vidCodecPUB menu];
	newItem = [[NSMenuItem alloc] initWithTitle:@"PJPEG" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoCodecTypeJPEG];
	[theMenu addItem:newItem];
	newItem = [[NSMenuItem alloc] initWithTitle:@"H264" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoCodecTypeH264];
	[theMenu addItem:newItem];
	newItem = [[NSMenuItem alloc] initWithTitle:@"ProRes 422" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoCodecTypeAppleProRes422];
	[theMenu addItem:newItem];
	
	newItem = [[NSMenuItem alloc] initWithTitle:@"ProRes 422 HQ" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoCodecTypeAppleProRes422HQ];
	[theMenu addItem:newItem];
	newItem = [[NSMenuItem alloc] initWithTitle:@"ProRes 422 LT" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoCodecTypeAppleProRes422LT];
	[theMenu addItem:newItem];
	newItem = [[NSMenuItem alloc] initWithTitle:@"ProRes 422 Proxy" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoCodecTypeAppleProRes422Proxy];
	[theMenu addItem:newItem];
	
	newItem = [[NSMenuItem alloc] initWithTitle:@"ProRes 4444" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoCodecTypeAppleProRes4444];
	[theMenu addItem:newItem];
	
	newItem = [[NSMenuItem alloc] initWithTitle:@"Hap" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoCodecHap];
	[theMenu addItem:newItem];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Hap Alpha" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoCodecHapAlpha];
	[theMenu addItem:newItem];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Hap Q" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoCodecHapQ];
	[theMenu addItem:newItem];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Hap Q Alpha" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoCodecHapQAlpha];
	[theMenu addItem:newItem];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Hap 7A" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoCodecHap7Alpha];
	[theMenu addItem:newItem];
#if 0
	newItem = [[NSMenuItem alloc] initWithTitle:@"Hap HDR" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoCodecHapHDR];
	[theMenu addItem:newItem];
#endif
	
	newItem = [[NSMenuItem alloc] initWithTitle:@"HEVC" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoCodecTypeHEVC];
	[theMenu addItem:newItem];
	
	
	//	populate the h.264 video profiles pop-up button- again, the representedObject is the string of the property...
	[_h264ProfilesPUB removeAllItems];
	theMenu = [_h264ProfilesPUB menu];
	
	newItem = [[NSMenuItem alloc] initWithTitle:@"Baseline Profile 3.0" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoProfileLevelH264Baseline30];
	[theMenu addItem:newItem];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Baseline Profile 3.1" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoProfileLevelH264Baseline31];
	[theMenu addItem:newItem];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Baseline Profile 4.1" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoProfileLevelH264Baseline41];
	[theMenu addItem:newItem];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Baseline Profile Auto Level" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoProfileLevelH264BaselineAutoLevel];
	[theMenu addItem:newItem];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Main Profile 3.0" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoProfileLevelH264Main30];
	[theMenu addItem:newItem];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Main Profile 3.1" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoProfileLevelH264Main31];
	[theMenu addItem:newItem];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Main Profile 3.2" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoProfileLevelH264Main32];
	[theMenu addItem:newItem];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Main Profile 4.1" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoProfileLevelH264Main41];
	[theMenu addItem:newItem];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Main Profile Auto Level" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoProfileLevelH264MainAutoLevel];
	[theMenu addItem:newItem];
	newItem = [[NSMenuItem alloc] initWithTitle:@"High Profile 4.0" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoProfileLevelH264High40];
	[theMenu addItem:newItem];
	newItem = [[NSMenuItem alloc] initWithTitle:@"High Profile 4.1" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoProfileLevelH264High41];
	[theMenu addItem:newItem];
	newItem = [[NSMenuItem alloc] initWithTitle:@"High Profile Auto Level" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:AVVideoProfileLevelH264HighAutoLevel];
	[theMenu addItem:newItem];
	//	select a default h.264 profile
	[_h264ProfilesPUB selectItemAtIndex:[[[_h264ProfilesPUB menu] itemArray] count]-1];
	
	
	//	populate the hevc video profiles pop-up button- again, the representedObject is the string of the property...
	[_hevcProfilesPUB removeAllItems];
	theMenu = [_hevcProfilesPUB menu];
	
	newItem = [[NSMenuItem alloc] initWithTitle:@"Main" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:(NSString *)kVTProfileLevel_HEVC_Main_AutoLevel];
	[theMenu addItem:newItem];
	newItem = [[NSMenuItem alloc] initWithTitle:@"Main 10" action:nil keyEquivalent:@""];
	[newItem setRepresentedObject:(NSString *)kVTProfileLevel_HEVC_Main10_AutoLevel];
	[theMenu addItem:newItem];
#if defined(__MAC_12_3) && __MAC_OS_X_VERSION_MAX_ALLOWED >= __MAC_12_3
	if (@available(macOS 12.3, *))	{
		newItem = [[NSMenuItem alloc] initWithTitle:@"Main 422 10" action:nil keyEquivalent:@""];
		[newItem setRepresentedObject:(NSString *)kVTProfileLevel_HEVC_Main42210_AutoLevel];
		[theMenu addItem:newItem];
	}
#endif
	//	select a default hevc profile
	[_hevcProfilesPUB selectItemAtIndex:0];
	
	
	[_hapChunkField setStringValue:@"1"];
	[_hapChunkField setEnabled:NO];
	[_hapQChunkField setStringValue:@"1"];
	[_hapQChunkField setEnabled:NO];
	[_hapHDRChunkField setStringValue:@"1"];
	[_hapHDRChunkField setEnabled:NO];
	_hapHDRSignedToggle.intValue = NSControlStateValueOff;
	
	//	select a video codec (H264 by default), trigger a UI item method to set everything up with a default value
	[_vidCodecPUB selectItemWithRepresentedObject:AVVideoCodecTypeH264];
	[self vidCodecPUBUsed:_vidCodecPUB];
	
	
	[_vidWidthField setStringValue:@"40"];
	[_vidHeightField setStringValue:@"30"];
	
	[self h264KeyframesMatrixUsed:_h264KeyframesMatrixAuto];
	[self h264BitrateMatrixUsed:_h264BitrateMatrixAuto];
	
	//	now populate the UI by 
	[self populateUIWithAVFSettingsDict:[AVFExportSettingsVideoVC defaultAVFSettingsDict]];
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
	//	video codec
	NSString		*codecString = [[_vidCodecPUB selectedItem] representedObject];
	[returnMe setObject:codecString forKey:AVVideoCodecKey];
	//	pjpeg
	if ([codecString isEqualToString:AVVideoCodecTypeJPEG])	{
		NSMutableDictionary		*compProps = [NSMutableDictionary dictionaryWithCapacity:0];
		[returnMe setObject:compProps forKey:AVVideoCompressionPropertiesKey];
		[compProps setObject:[NSNumber numberWithDouble:[_pjpegQualitySlider doubleValue]] forKey:AVVideoQualityKey];
	}
	//	h264
	else if ([codecString isEqualToString:AVVideoCodecTypeH264])	{
		NSMutableDictionary		*compProps = [NSMutableDictionary dictionaryWithCapacity:0];
		[returnMe setObject:compProps forKey:AVVideoCompressionPropertiesKey];
		
		[compProps setObject:[[_h264ProfilesPUB selectedItem] representedObject] forKey:AVVideoProfileLevelKey];
		
		if (_h264KeyframesMatrixOnceEvery.state == NSControlStateValueOn)	{
			NSString		*tmpString = [_h264KeyframesField stringValue];
			NSUInteger		tmpVal = 24;
			if (tmpString!=nil)
				tmpVal = [tmpString integerValue];
			if (tmpVal<1)
				tmpVal = 1;
			[compProps setObject:[NSNumber numberWithInteger:tmpVal] forKey:AVVideoMaxKeyFrameIntervalKey];
		}
		
		if (_h264BitrateMatrixLimitTo.state == NSControlStateValueOn)	{
			NSString		*tmpString = [_h264BitrateField stringValue];
			double			tmpVal = (tmpString==nil) ? 0.0 : [tmpString doubleValue];
			if (tmpVal <=0.0)
				tmpVal = 4096.0;
			[_h264BitrateField setStringValue:[NSString stringWithFormat:@"%0.2f",tmpVal]];
			[compProps setObject:[NSNumber numberWithDouble:tmpVal*1024.0] forKey:AVVideoAverageBitRateKey];
		}
		
		if (![_h264MultiPassButton isHidden] && [_h264MultiPassButton intValue]==NSControlStateValueOn)
			[returnMe setObject:[NSNumber numberWithBool:YES] forKey:kAVFExportMultiPassEncodeKey];
	}
	//	prores 422
	else if ([codecString isEqualToString:AVVideoCodecTypeAppleProRes422]
	|| [codecString isEqualToString:AVVideoCodecTypeAppleProRes422HQ]
	|| [codecString isEqualToString:AVVideoCodecTypeAppleProRes422LT]
	|| [codecString isEqualToString:AVVideoCodecTypeAppleProRes422Proxy])	{
	}
	//	prores 4444
	else if ([codecString isEqualToString:AVVideoCodecTypeAppleProRes4444])	{
	}
	//	hap
	else if ([codecString isEqualToString:AVVideoCodecHap])	{
		NSMutableDictionary		*compProps = [NSMutableDictionary dictionaryWithCapacity:0];
		[returnMe setObject:compProps forKey:AVVideoCompressionPropertiesKey];
		
		[compProps setObject:[NSNumber numberWithDouble:[_hapQualitySlider doubleValue]] forKey:AVVideoQualityKey];
		
		if ([_hapChunkMatrix selectedRow]==0)	{
			[returnMe setObject:[NSNumber numberWithInteger:1] forKey:AVHapVideoChunkCountKey];
		}
		else	{
			int			tmpInt = [[_hapChunkField stringValue] intValue];
			tmpInt = fmaxl(fminl(tmpInt, HAPQMAXCHUNKS), 1);
			[compProps setObject:[NSNumber numberWithInteger:tmpInt] forKey:AVHapVideoChunkCountKey];
		}
	}
	//	hap alpha
	else if ([codecString isEqualToString:AVVideoCodecHapAlpha])	{
		NSMutableDictionary		*compProps = [NSMutableDictionary dictionaryWithCapacity:0];
		[returnMe setObject:compProps forKey:AVVideoCompressionPropertiesKey];
		
		[compProps setObject:[NSNumber numberWithDouble:[_hapQualitySlider doubleValue]] forKey:AVVideoQualityKey];
		
		if ([_hapChunkMatrix selectedRow]==0)	{
			[returnMe setObject:[NSNumber numberWithInteger:1] forKey:AVHapVideoChunkCountKey];
		}
		else	{
			int			tmpInt = [[_hapChunkField stringValue] intValue];
			tmpInt = fmaxl(fminl(tmpInt, HAPQMAXCHUNKS), 1);
			[compProps setObject:[NSNumber numberWithInteger:tmpInt] forKey:AVHapVideoChunkCountKey];
		}
	}
	//	hap Q
	else if ([codecString isEqualToString:AVVideoCodecHapQ])	{
		NSMutableDictionary		*compProps = [NSMutableDictionary dictionaryWithCapacity:0];
		[returnMe setObject:compProps forKey:AVVideoCompressionPropertiesKey];
		
		if ([_hapQChunkMatrix selectedRow]==0)	{
			[returnMe setObject:[NSNumber numberWithInteger:1] forKey:AVHapVideoChunkCountKey];
		}
		else	{
			int			tmpInt = [[_hapQChunkField stringValue] intValue];
			tmpInt = fmaxl(fminl(tmpInt, HAPQMAXCHUNKS), 1);
			[compProps setObject:[NSNumber numberWithInteger:tmpInt] forKey:AVHapVideoChunkCountKey];
		}
	}
	//	hap q alpha
	else if ([codecString isEqualToString:AVVideoCodecHapQAlpha])	{
		NSMutableDictionary		*compProps = [NSMutableDictionary dictionaryWithCapacity:0];
		[returnMe setObject:compProps forKey:AVVideoCompressionPropertiesKey];
		
		if ([_hapQChunkMatrix selectedRow]==0)	{
			[returnMe setObject:[NSNumber numberWithInteger:1] forKey:AVHapVideoChunkCountKey];
		}
		else	{
			int			tmpInt = [[_hapQChunkField stringValue] intValue];
			tmpInt = fmaxl(fminl(tmpInt, HAPQMAXCHUNKS), 1);
			[compProps setObject:[NSNumber numberWithInteger:tmpInt] forKey:AVHapVideoChunkCountKey];
		}
	}
	//	hap r
	else if ([codecString isEqualToString:AVVideoCodecHap7Alpha])	{
		NSMutableDictionary		*compProps = [NSMutableDictionary dictionaryWithCapacity:0];
		[returnMe setObject:compProps forKey:AVVideoCompressionPropertiesKey];
		
		[compProps setObject:[NSNumber numberWithDouble:[_hapQualitySlider doubleValue]] forKey:AVVideoQualityKey];
		
		if ([_hapChunkMatrix selectedRow]==0)	{
			[returnMe setObject:[NSNumber numberWithInteger:1] forKey:AVHapVideoChunkCountKey];
		}
		else	{
			int			tmpInt = [[_hapChunkField stringValue] intValue];
			tmpInt = fmaxl(fminl(tmpInt, HAPQMAXCHUNKS), 1);
			[compProps setObject:[NSNumber numberWithInteger:tmpInt] forKey:AVHapVideoChunkCountKey];
		}
	}
	//	hap hdr
	else if ([codecString isEqualToString:AVVideoCodecHapHDR])	{
		NSMutableDictionary		*compProps = [NSMutableDictionary dictionaryWithCapacity:0];
		[returnMe setObject:compProps forKey:AVVideoCompressionPropertiesKey];
		
		if ([_hapHDRChunkMatrix selectedRow]==0)	{
			[returnMe setObject:[NSNumber numberWithInteger:1] forKey:AVHapVideoChunkCountKey];
		}
		else	{
			int			tmpInt = [[_hapHDRChunkField stringValue] intValue];
			tmpInt = fmaxl(fminl(tmpInt, HAPQMAXCHUNKS), 1);
			[compProps setObject:[NSNumber numberWithInteger:tmpInt] forKey:AVHapVideoChunkCountKey];
		}
		
		if (_hapHDRSignedToggle.intValue != NSControlStateValueOff)	{
			[compProps setObject:@(YES) forKey:AVHapVideoHDRSignedFloatKey];
		}
	}
	//	HEVC
	else if ([codecString isEqualToString:AVVideoCodecTypeHEVC])	{
		NSMutableDictionary		*compProps = [NSMutableDictionary dictionaryWithCapacity:0];
		[returnMe setObject:compProps forKey:AVVideoCompressionPropertiesKey];
		
		[compProps setObject:[[_hevcProfilesPUB selectedItem] representedObject] forKey:AVVideoProfileLevelKey];
	}
	
	switch ([_vidDimsTabView selectedTabViewItemIndex])	{
	//	no resizing
	case 0:
		break;
	//	resizing
	case 1:
		[returnMe setObject:[NSNumber numberWithInteger:[_vidWidthField integerValue]] forKey:AVVideoWidthKey];
		[returnMe setObject:[NSNumber numberWithInteger:[_vidHeightField integerValue]] forKey:AVVideoHeightKey];
		break;
	}
	return returnMe;
}
- (void) populateUIWithAVFSettingsDict:(NSDictionary *)n	{
	//NSLog(@"%s ... %@",__func__,n);
	NSString		*codecString = nil;
	NSString		*tmpString = nil;
	NSNumber		*tmpNum = nil;
	NSValue			*tmpVal = nil;
	
	tmpVal = [n objectForKey:kAVFExportVideoResolutionKey];
	if (tmpVal == nil)
		tmpVal = [NSValue valueWithSize:NSMakeSize(4,3)];
	displayVideoDims = tmpVal.sizeValue;
	
	codecString = [n objectForKey:AVVideoCodecKey];
	if (codecString==nil)	{
		//[vidCategoryTabView selectTabViewItemAtIndex:0];
		//tmpNum = [n objectForKey:kAVFExportStripMediaKey];
		//if (tmpNum!=nil && [tmpNum boolValue])
		//	[vidNoTranscodeMatrix selectCellAtRow:0 column:0];
		//else
		//	[vidNoTranscodeMatrix selectCellAtRow:1 column:0];
	}
	else if ([codecString isEqualToString:AVVideoCodecTypeJPEG])	{
		//[vidCategoryTabView selectTabViewItemAtIndex:1];
		[_vidCodecPUB selectItemWithRepresentedObject:codecString];
		[self vidCodecPUBUsed:_vidCodecPUB];
		NSDictionary	*props = [n objectForKey:AVVideoCompressionPropertiesKey];
		if (props!=nil)	{
			tmpNum = [props objectForKey:AVVideoQualityKey];
			if (tmpNum!=nil)
				[_pjpegQualitySlider setDoubleValue:[tmpNum doubleValue]];
		}
	}
	//	h264
	else if ([codecString isEqualToString:AVVideoCodecTypeH264])	{
		//[vidCategoryTabView selectTabViewItemAtIndex:1];
		[_vidCodecPUB selectItemWithRepresentedObject:codecString];
		[self vidCodecPUBUsed:_vidCodecPUB];
		NSDictionary	*props = [n objectForKey:AVVideoCompressionPropertiesKey];
		if (props!=nil)	{
			tmpString = [props objectForKey:AVVideoProfileLevelKey];
			if (tmpString!=nil)
				[_h264ProfilesPUB selectItemWithRepresentedObject:tmpString];
			
			tmpNum = [props objectForKey:AVVideoMaxKeyFrameIntervalKey];
			if (tmpNum == nil)	{
				[self h264KeyframesMatrixUsed:_h264KeyframesMatrixAuto];
			}
			else	{
				_h264KeyframesField.stringValue = [NSString stringWithFormat:@"%ld",(long)tmpNum.integerValue];
				[self h264KeyframesMatrixUsed:_h264KeyframesMatrixOnceEvery];
			}
			
			tmpNum = [props objectForKey:AVVideoAverageBitRateKey];
			if (tmpNum == nil)	{
				[self h264BitrateMatrixUsed:_h264BitrateMatrixAuto];
			}
			else	{
				_h264BitrateField.stringValue = [NSString stringWithFormat:@"%0.2f",[tmpNum doubleValue]/1024.0];
				[self h264BitrateMatrixUsed:_h264BitrateMatrixLimitTo];
			}
			
			if (![_h264MultiPassButton isHidden])	{
				tmpNum = [n objectForKey:kAVFExportMultiPassEncodeKey];
				[_h264MultiPassButton setIntValue:(tmpNum==nil || [tmpNum intValue]!=NSControlStateValueOn) ? NSControlStateValueOff : NSControlStateValueOn];
			}
		}
	}
	//	prores 422
	else if ([codecString isEqualToString:AVVideoCodecTypeAppleProRes422])	{
		//[vidCategoryTabView selectTabViewItemAtIndex:1];
		[_vidCodecPUB selectItemWithRepresentedObject:codecString];
		[self vidCodecPUBUsed:_vidCodecPUB];
	}
	else if ([codecString isEqualToString:AVVideoCodecTypeAppleProRes422HQ])	{
		//[vidCategoryTabView selectTabViewItemAtIndex:1];
		[_vidCodecPUB selectItemWithRepresentedObject:codecString];
		[self vidCodecPUBUsed:_vidCodecPUB];
	}
	else if ([codecString isEqualToString:AVVideoCodecTypeAppleProRes422LT])	{
		//[vidCategoryTabView selectTabViewItemAtIndex:1];
		[_vidCodecPUB selectItemWithRepresentedObject:codecString];
		[self vidCodecPUBUsed:_vidCodecPUB];
	}
	else if ([codecString isEqualToString:AVVideoCodecTypeAppleProRes422Proxy])	{
		//[vidCategoryTabView selectTabViewItemAtIndex:1];
		[_vidCodecPUB selectItemWithRepresentedObject:codecString];
		[self vidCodecPUBUsed:_vidCodecPUB];
	}
	//	prores 4444
	else if ([codecString isEqualToString:AVVideoCodecTypeAppleProRes4444])	{
		//[vidCategoryTabView selectTabViewItemAtIndex:1];
		[_vidCodecPUB selectItemWithRepresentedObject:codecString];
		[self vidCodecPUBUsed:_vidCodecPUB];
	}
	
	//	hap
	else if ([codecString isEqualToString:AVVideoCodecHap])	{
		//[vidCategoryTabView selectTabViewItemAtIndex:1];
		//[_vidCodecPUB selectItemWithTitle:@"Hap"];
		[_vidCodecPUB selectItemWithRepresentedObject:codecString];
		[self vidCodecPUBUsed:_vidCodecPUB];
		NSDictionary	*props = [n objectForKey:AVVideoCompressionPropertiesKey];
		if (props!=nil)	{
			tmpNum = [props objectForKey:AVVideoQualityKey];
			if (tmpNum!=nil)
				[_hapQualitySlider setDoubleValue:[tmpNum doubleValue]];
		}
	}
	//	hap alpha
	else if ([codecString isEqualToString:AVVideoCodecHapAlpha])	{
		//[vidCategoryTabView selectTabViewItemAtIndex:1];
		//[_vidCodecPUB selectItemWithTitle:@"Hap Alpha"];
		[_vidCodecPUB selectItemWithRepresentedObject:codecString];
		[self vidCodecPUBUsed:_vidCodecPUB];
	}
	//	hap Q
	else if ([codecString isEqualToString:AVVideoCodecHapQ])	{
		//[vidCategoryTabView selectTabViewItemAtIndex:1];
		//[_vidCodecPUB selectItemWithTitle:@"Hap Q"];
		[_vidCodecPUB selectItemWithRepresentedObject:codecString];
		[self vidCodecPUBUsed:_vidCodecPUB];
	}
	//	hap Q alpha
	else if ([codecString isEqualToString:AVVideoCodecHapQAlpha])	{
		//[vidCategoryTabView selectTabViewItemAtIndex:1];
		//[_vidCodecPUB selectItemWithTitle:@"Hap Q Alpha"];
		[_vidCodecPUB selectItemWithRepresentedObject:codecString];
		[self vidCodecPUBUsed:_vidCodecPUB];
	}
	//	hap r/hap 7 alpha
	else if ([codecString isEqualToString:AVVideoCodecHap7Alpha])	{
		//[vidCategoryTabView selectTabViewItemAtIndex:1];
		//[_vidCodecPUB selectItemWithTitle:@"Hap Q Alpha"];
		[_vidCodecPUB selectItemWithRepresentedObject:codecString];
		[self vidCodecPUBUsed:_vidCodecPUB];
		NSDictionary	*props = [n objectForKey:AVVideoCompressionPropertiesKey];
		if (props!=nil)	{
			tmpNum = [props objectForKey:AVVideoQualityKey];
			if (tmpNum!=nil)
				[_hapQualitySlider setDoubleValue:[tmpNum doubleValue]];
		}
	}
	//	hap hdr
	else if ([codecString isEqualToString:AVVideoCodecHapHDR])	{
		//[vidCategoryTabView selectTabViewItemAtIndex:1];
		//[_vidCodecPUB selectItemWithTitle:@"Hap Q Alpha"];
		[_vidCodecPUB selectItemWithRepresentedObject:codecString];
		[self vidCodecPUBUsed:_vidCodecPUB];
	}
	//	hevc
	else if ([codecString isEqualToString:AVVideoCodecTypeHEVC])	{
		[_vidCodecPUB selectItemWithRepresentedObject:codecString];
		[self vidCodecPUBUsed:_vidCodecPUB];
		NSDictionary		*props = [n objectForKey:AVVideoCompressionPropertiesKey];
		if (props != nil)	{
			tmpString = [props objectForKey:AVVideoProfileLevelKey];
			if (tmpString != nil)
				[_hevcProfilesPUB selectItemWithRepresentedObject:tmpString];
		}
	}
	
	
	//	this code needs to run if i'm using hap
	if ([codecString isEqualToString:AVVideoCodecHap] || [codecString isEqualToString:AVVideoCodecHapAlpha] || [codecString isEqualToString:AVVideoCodecHap7Alpha])	{
		NSDictionary	*props = [n objectForKey:AVVideoCompressionPropertiesKey];
		tmpNum = (props==nil) ? nil : [props objectForKey:AVHapVideoChunkCountKey];
		if (tmpNum == nil)	{
			[_hapChunkMatrix selectCellAtRow:0 column:0];
			[_hapChunkField setStringValue:@"1"];
			[_hapChunkField setEnabled:NO];
		}
		else	{
			if ([tmpNum intValue]==0 || [tmpNum intValue]==1)	{
				[_hapChunkMatrix selectCellAtRow:0 column:0];
				[_hapChunkField setStringValue:@"1"];
				[_hapChunkField setEnabled:NO];
			}
			else	{
				[_hapChunkMatrix selectCellAtRow:1 column:0];
				[_hapChunkField setStringValue:[NSString stringWithFormat:@"%d",[tmpNum intValue]]];
				[_hapChunkField setEnabled:YES];
			}
		}
		
		if ([codecString isEqualToString:AVVideoCodecHapAlpha] || [codecString isEqualToString:AVVideoCodecHap7Alpha])	{
			tmpNum = (props==nil) ? nil : [props objectForKey:AVVideoQualityKey];
			if (tmpNum == nil)
				tmpNum = @(0.5);
			[_hapQualitySlider setDoubleValue:[tmpNum doubleValue]];
		}
	}
	//	this code needs to run if i'm using hap Q or hap Q alpha or hap r/hap7 alpha
	else if ([codecString isEqualToString:AVVideoCodecHapQ] || [codecString isEqualToString:AVVideoCodecHapQAlpha])	{
		NSDictionary	*props = [n objectForKey:AVVideoCompressionPropertiesKey];
		tmpNum = (props==nil) ? nil : [props objectForKey:AVHapVideoChunkCountKey];
		if (tmpNum == nil)	{
			[_hapQChunkMatrix selectCellAtRow:0 column:0];
			[_hapQChunkField setStringValue:@"1"];
			[_hapQChunkField setEnabled:NO];
		}
		else	{
			if ([tmpNum intValue]==0 || [tmpNum intValue]==1)	{
				[_hapQChunkMatrix selectCellAtRow:0 column:0];
				[_hapQChunkField setStringValue:@"1"];
				[_hapQChunkField setEnabled:NO];
			}
			else	{
				[_hapQChunkMatrix selectCellAtRow:1 column:0];
				[_hapQChunkField setStringValue:[NSString stringWithFormat:@"%d",[tmpNum intValue]]];
				[_hapQChunkField setEnabled:YES];
			}
		}
	}
	//	this code needs to run if i'm using hap HDR
	else if ([codecString isEqualToString:AVVideoCodecHapHDR])	{
		NSDictionary	*props = [n objectForKey:AVVideoCompressionPropertiesKey];
		tmpNum = (props==nil) ? nil : [props objectForKey:AVHapVideoChunkCountKey];
		if (tmpNum == nil)	{
			[_hapHDRChunkMatrix selectCellAtRow:0 column:0];
			[_hapHDRChunkField setStringValue:@"1"];
			[_hapHDRChunkField setEnabled:NO];
		}
		else	{
			if ([tmpNum intValue]==0 || [tmpNum intValue]==1)	{
				[_hapHDRChunkMatrix selectCellAtRow:0 column:0];
				[_hapHDRChunkField setStringValue:@"1"];
				[_hapHDRChunkField setEnabled:NO];
			}
			else	{
				[_hapHDRChunkMatrix selectCellAtRow:1 column:0];
				[_hapHDRChunkField setStringValue:[NSString stringWithFormat:@"%d",[tmpNum intValue]]];
				[_hapHDRChunkField setEnabled:YES];
			}
		}
		
		tmpNum = (props==nil) ? nil : [props objectForKey:AVHapVideoHDRSignedFloatKey];
		if (tmpNum == nil)
			tmpNum = @(NO);
		_hapHDRSignedToggle.intValue = (tmpNum.boolValue) ? NSControlStateValueOn : NSControlStateValueOff;
	}
	
	
	tmpNum = [n objectForKey:AVVideoWidthKey];
	if (tmpNum==nil)
		[self noResizeVideoClicked:nil];
	else	{
		[self resizeVideoClicked:nil];
		[self resizeVideoTextFieldUsed:nil];
		[_vidWidthField setStringValue:[NSString stringWithFormat:@"%ld",(long)[tmpNum integerValue]]];
	}
	tmpNum = [n objectForKey:AVVideoHeightKey];
	if (tmpNum==nil)
		[self noResizeVideoClicked:nil];
	else	{
		[self resizeVideoClicked:nil];
		[self resizeVideoTextFieldUsed:nil];
		[_vidHeightField setStringValue:[NSString stringWithFormat:@"%ld",(long)[tmpNum integerValue]]];
	}
}


- (NSString *) lengthyDescription	{
	NSString		*returnMe = nil;
	//	video codec
	NSString		*codecString = [[_vidCodecPUB selectedItem] representedObject];
	//	pjpeg
	if ([codecString isEqualToString:AVVideoCodecTypeJPEG])	{
		returnMe = [NSString stringWithFormat:@"PJPEG, %ld%%.",(unsigned long)(100.0*[_pjpegQualitySlider doubleValue])];
	}
	//	h264
	else if ([codecString isEqualToString:AVVideoCodecTypeH264])	{
		returnMe = [NSString stringWithFormat:@"h264, %@.",[_h264ProfilesPUB titleOfSelectedItem]];
		
		if (_h264KeyframesMatrixOnceEvery.state == NSControlStateValueOn)	{
			NSString		*tmpString = [_h264KeyframesField stringValue];
			returnMe = [NSString stringWithFormat:@"%@ Keyframe every %@.",returnMe,tmpString];
		}
		
		if (_h264BitrateMatrixLimitTo.state == NSControlStateValueOn)	{
			NSString		*tmpString = [_h264BitrateField stringValue];
			returnMe = [NSString stringWithFormat:@"%@ %@ kbps.",returnMe,tmpString];
		}
		
		if (![_h264MultiPassButton isHidden] && [_h264MultiPassButton intValue]==NSControlStateValueOn)
			returnMe = [NSString stringWithFormat:@"%@ Multipass.",returnMe];
	}
	//	prores 422
	else if ([codecString isEqualToString:AVVideoCodecTypeAppleProRes422])	{
		returnMe = @"ProRes 422.";
	}
	else if ([codecString isEqualToString:AVVideoCodecTypeAppleProRes422HQ])	{
		returnMe = @"ProRes 422 HQ";
	}
	else if ([codecString isEqualToString:AVVideoCodecTypeAppleProRes422LT])	{
		returnMe = @"ProRes 422 LT";
	}
	else if ([codecString isEqualToString:AVVideoCodecTypeAppleProRes422Proxy])	{
		returnMe = @"ProRes 422 Proxy";
	}
	//	prores 4444
	else if ([codecString isEqualToString:AVVideoCodecTypeAppleProRes4444])	{
		returnMe = @"ProRes 4444.";
	}
	//	hap
	else if ([codecString isEqualToString:AVVideoCodecHap])	{
		int			chunkCount = 1;
		if ([_hapChunkMatrix selectedRow] > 0)
			chunkCount = [_hapChunkField intValue];
		if (chunkCount <= 1)
			returnMe = [NSString stringWithFormat:@"Hap, %ld%%.",(unsigned long)(100.0*[_hapQualitySlider doubleValue])];
		else
			returnMe = [NSString stringWithFormat:@"Hap, %ld%%, %d chunks",(unsigned long)(100.0*[_hapQualitySlider doubleValue]),chunkCount];
	}
	//	hap alpha
	else if ([codecString isEqualToString:AVVideoCodecHapAlpha])	{
		int			chunkCount = 1;
		if ([_hapChunkMatrix selectedRow] > 0)
			chunkCount = [_hapChunkField intValue];
		if (chunkCount <= 1)
			returnMe = [NSString stringWithFormat:@"Hap Alpha, %ld%%.",(unsigned long)(100.0*[_hapQualitySlider doubleValue])];
		else
			returnMe = [NSString stringWithFormat:@"Hap Alpha, %ld%%, %d chunks.",(unsigned long)(100.0*[_hapQualitySlider doubleValue]),chunkCount];
	}
	//	hap Q
	else if ([codecString isEqualToString:AVVideoCodecHapQ])	{
		int			chunkCount = 1;
		if ([_hapQChunkMatrix selectedRow] > 0)
			chunkCount = [_hapQChunkField intValue];
		if (chunkCount <= 1)
			returnMe = @"HapQ.";
		else
			returnMe = [NSString stringWithFormat:@"HapQ, %d chunks.",chunkCount];
	}
	//	hap Q alpha
	else if ([codecString isEqualToString:AVVideoCodecHapQAlpha])	{
		int			chunkCount = 1;
		if ([_hapQChunkMatrix selectedRow] > 0)
			chunkCount = [_hapQChunkField intValue];
		if (chunkCount <= 1)
			returnMe = @"HapQ Alpha.";
		else
			returnMe = [NSString stringWithFormat:@"HapQ Alpha, %d chunks.",chunkCount];
	}
	//	hap 7 alpha
	else if ([codecString isEqualToString:AVVideoCodecHap7Alpha])	{
		int			chunkCount = 1;
		if ([_hapChunkMatrix selectedRow] > 0)
			chunkCount = [_hapChunkField intValue];
		if (chunkCount <= 1)
			returnMe = @"Hap 7A.";
		else
			returnMe = [NSString stringWithFormat:@"Hap7A, %d chunks.",chunkCount];
	}
	//	hap HDR
	else if ([codecString isEqualToString:AVVideoCodecHapHDR])	{
		int			chunkCount = 1;
		if ([_hapHDRChunkMatrix selectedRow] > 0)
			chunkCount = [_hapHDRChunkField intValue];
		
		NSString		*signedness = (_hapHDRSignedToggle.intValue==NSControlStateValueOn) ? @"Signed" : @"Unsigned";
		if (chunkCount <= 1)
			returnMe = [NSString stringWithFormat:@"HapHDR (%@).",signedness];
		else
			returnMe = [NSString stringWithFormat:@"HapHDR (%@), %d chunks.",signedness,chunkCount];
	}
	//	hevc
	else if ([codecString isEqualToString:AVVideoCodecTypeHEVC])	{
		returnMe = [NSString stringWithFormat:@"HEVC, %@.",[_hevcProfilesPUB titleOfSelectedItem]];
	}
	
	switch ([_vidDimsTabView selectedTabViewItemIndex])	{
	//	no resizing
	case 0:
		break;
	//	resizing
	case 1:
		returnMe = [NSString stringWithFormat:@"%@ Sized to %ld x %ld.",returnMe,(long)[_vidWidthField integerValue],(long)[_vidHeightField integerValue]];
		break;
	}
	return returnMe;
}


- (void) setDisplayVideoDims:(NSSize)n	{
	displayVideoDims = n;
}


#pragma mark - UI actions


- (IBAction) vidCodecPUBUsed:(id)sender	{
	NSString		*selectedRepObj = [[sender selectedItem] representedObject];
	if ([selectedRepObj isEqualToString:AVVideoCodecTypeJPEG])	{
		[_vidCodecTabView selectTabViewItemAtIndex:1];
	}
	else if ([selectedRepObj isEqualToString:AVVideoCodecTypeH264])	{
		[_vidCodecTabView selectTabViewItemAtIndex:2];
	}
	else if ([selectedRepObj isEqualToString:AVVideoCodecTypeAppleProRes422]
	|| [selectedRepObj isEqualToString:AVVideoCodecTypeAppleProRes422HQ]
	|| [selectedRepObj isEqualToString:AVVideoCodecTypeAppleProRes422LT]
	|| [selectedRepObj isEqualToString:AVVideoCodecTypeAppleProRes422Proxy])	{
		[_vidCodecTabView selectTabViewItemAtIndex:0];
	}
	else if ([selectedRepObj isEqualToString:AVVideoCodecTypeAppleProRes4444])	{
		[_vidCodecTabView selectTabViewItemAtIndex:0];
	}
	else if ([selectedRepObj isEqualToString:AVVideoCodecHap])	{
		[_vidCodecTabView selectTabViewItemAtIndex:3];
	}
	else if ([selectedRepObj isEqualToString:AVVideoCodecHapAlpha])	{
		[_vidCodecTabView selectTabViewItemAtIndex:3];
	}
	else if ([selectedRepObj isEqualToString:AVVideoCodecHapQ])	{
		[_vidCodecTabView selectTabViewItemAtIndex:4];
	}
	else if ([selectedRepObj isEqualToString:AVVideoCodecHapQAlpha])	{
		[_vidCodecTabView selectTabViewItemAtIndex:4];
	}
	else if ([selectedRepObj isEqualToString:AVVideoCodecTypeHEVC])	{
		[_vidCodecTabView selectTabViewItemAtIndex:5];
	}
	else if ([selectedRepObj isEqualToString:AVVideoCodecHap7Alpha])	{
		[_vidCodecTabView selectTabViewItemAtIndex:3];	//	uses the same tab as hap!
	}
	else if ([selectedRepObj isEqualToString:AVVideoCodecHapHDR])	{
		[_vidCodecTabView selectTabViewItemAtIndex:7];
	}
}
- (IBAction) h264KeyframesMatrixUsed:(id)sender	{
	//NSLog(@"%s ... %@",__func__,sender);
	NSArray<NSButton*>		*buttons = @[
		_h264KeyframesMatrixAuto,
		_h264KeyframesMatrixOnceEvery
	];
	for (NSButton * button in buttons)	{
		button.state = (button==sender) ? NSControlStateValueOn : NSControlStateValueOff;
	}
	
	if (sender == _h264KeyframesMatrixAuto)	{
		[_h264KeyframesField setEnabled:NO];
	}
	else if (sender == _h264KeyframesMatrixOnceEvery)	{
		[_h264KeyframesField setEnabled:YES];
		NSString		*tmpString = [_h264KeyframesField stringValue];
		if (tmpString==nil || [tmpString integerValue]<1)
			[_h264KeyframesField setStringValue:@"24"];
	}
}
- (IBAction) h264KeyframesFieldUsed:(id)sender	{
	NSString		*tmpString = [_h264KeyframesField stringValue];
	if (tmpString==nil || [tmpString integerValue]<1)
		[_h264KeyframesField setStringValue:@"24"];
}
- (IBAction) h264BitrateMatrixUsed:(id)sender	{
	NSArray<NSButton*>		*buttons = @[
		_h264BitrateMatrixAuto,
		_h264BitrateMatrixLimitTo
	];
	for (NSButton * button in buttons)	{
		button.state = (button==sender) ? NSControlStateValueOn : NSControlStateValueOff;
	}
	
	if (sender == _h264BitrateMatrixAuto)	{
		[_h264BitrateField setEnabled:NO];
	}
	else if (sender == _h264BitrateMatrixLimitTo)	{
		[_h264BitrateField setEnabled:YES];
		NSString		*tmpString = [_h264BitrateField stringValue];
		if (tmpString==nil || [tmpString doubleValue]<=0.0)
			[_h264BitrateField setStringValue:@"4096.0"];
	}
}
- (IBAction) h264BitrateFieldUsed:(id)sender	{
	NSString		*tmpString = [_h264BitrateField stringValue];
	if (tmpString==nil || [tmpString doubleValue]<=0.0)
		[_h264BitrateField setStringValue:@"4096.0"];
}

- (IBAction) hapChunkMatrixUsed:(id)sender	{
	if ([_hapChunkMatrix selectedRow] <= 0)	{
		[_hapChunkField setStringValue:@"1"];
		[_hapChunkField setEnabled:NO];
	}
	else	{
		[_hapChunkField setEnabled:YES];
	}
}
- (IBAction) hapChunkFieldUsed:(id)sender	{
	BOOL			needsCorrection = YES;
	NSString		*tmpString = [_hapChunkField stringValue];
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
		[_hapChunkField setStringValue:[NSString stringWithFormat:@"%d",tmpInt]];
	}
}
- (IBAction) hapQChunkMatrixUsed:(id)sender	{
	if ([_hapQChunkMatrix selectedRow] <= 0)	{
		[_hapQChunkField setStringValue:@"1"];
		[_hapQChunkField setEnabled:NO];
	}
	else	{
		[_hapQChunkField setEnabled:YES];
	}
}
- (IBAction) hapQChunkFieldUsed:(id)sender	{
	BOOL			needsCorrection = YES;
	NSString		*tmpString = [_hapQChunkField stringValue];
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
		[_hapQChunkField setStringValue:[NSString stringWithFormat:@"%d",tmpInt]];
	}
}
- (IBAction) hapHDRChunkMatrixUsed:(id)sender	{
	if ([_hapHDRChunkMatrix selectedRow] <= 0)	{
		[_hapHDRChunkField setStringValue:@"1"];
		[_hapHDRChunkField setEnabled:NO];
	}
	else	{
		[_hapHDRChunkField setEnabled:YES];
	}
}
- (IBAction) hapHDRChunkFieldUsed:(id)sender	{
	BOOL			needsCorrection = YES;
	NSString		*tmpString = [_hapHDRChunkField stringValue];
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
		[_hapHDRChunkField setStringValue:[NSString stringWithFormat:@"%d",tmpInt]];
	}
}

- (IBAction) resizeVideoClicked:(id)sender	{
	[_vidDimsTabView selectTabViewItemAtIndex:1];
}
- (IBAction) noResizeVideoClicked:(id)sender	{
	[_vidDimsTabView selectTabViewItemAtIndex:0];
}
- (IBAction) resizeVideoTextFieldUsed:(id)sender	{
	NSString		*tmpString = nil;
	NSInteger		tmpVal;
	
	tmpString = [_vidWidthField stringValue];
	tmpVal = (tmpString==nil) ? -1 : [tmpString integerValue];
	if (tmpVal<=0)
		[_vidWidthField setStringValue:[NSString stringWithFormat:@"%ld",(unsigned long)displayVideoDims.width]];
	tmpString = [_vidHeightField stringValue];
	tmpVal = (tmpString==nil) ? -1 : [tmpString integerValue];
	if (tmpVal<=0)
		[_vidHeightField setStringValue:[NSString stringWithFormat:@"%ld",(unsigned long)displayVideoDims.height]];
	
}


@end
