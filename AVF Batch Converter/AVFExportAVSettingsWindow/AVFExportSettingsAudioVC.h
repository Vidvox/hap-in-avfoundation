//
//  AVFExportSettingsAudioVC.h
//  VVAVFExport-TestApp
//
//  Created by testadmin on 5/4/22.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN




@interface AVFExportSettingsAudioVC : NSViewController

+ (NSMutableDictionary *) defaultAVFSettingsDict;

- (NSMutableDictionary *) createAVFSettingsDict;
- (void) populateUIWithAVFSettingsDict:(NSDictionary *)n;

- (NSString *) lengthyDescription;

@end




NS_ASSUME_NONNULL_END
