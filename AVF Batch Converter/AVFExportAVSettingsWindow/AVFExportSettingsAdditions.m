//
//  AVFExportSettingsAdditions.m
//  VVAVFExport-TestApp
//
//  Created by testadmin on 5/4/22.
//

#import "AVFExportSettingsAdditions.h"


@implementation NSTabView (AVFExportSettingsAdditions_TabView)
- (NSInteger) selectedTabViewItemIndex	{
	NSInteger		returnMe = -1;
	NSTabViewItem	*selectedItem = [self selectedTabViewItem];
	if (selectedItem!=nil)	{
		returnMe = [self indexOfTabViewItem:selectedItem];
	}
	return returnMe;
}
@end


@implementation NSPopUpButton (AVFExportSettingsAdditions_PUB)
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


