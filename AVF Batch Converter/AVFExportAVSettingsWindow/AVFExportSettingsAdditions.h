//
//  AVFExportSettingsAdditions.h
//  VVAVFExport-TestApp
//
//  Created by testadmin on 5/4/22.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN


@interface NSTabView (AVFExportSettingsAdditions_TabView)
- (NSInteger) selectedTabViewItemIndex;
@end


@interface NSPopUpButton (AVFExportSettingsAdditions_PUB)
- (BOOL) selectItemWithRepresentedObject:(id)n;
@end


NS_ASSUME_NONNULL_END
