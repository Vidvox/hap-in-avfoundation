#import "AVPlayerItemAdditions.h"




@implementation AVPlayerItem (HapInAVFAVPlayerItemAdditions)


- (AVAssetTrack *) hapTrack	{
	AVAsset					*itemAsset = (self==nil) ? nil : [self asset];
	NSArray					*vidTracks = [itemAsset tracksWithMediaType:AVMediaTypeVideo];
	AVAssetTrack			*hapTrack = nil;
	for (AVAssetTrack *trackPtr in vidTracks)	{
		NSArray					*trackFormatDescs = [trackPtr formatDescriptions];
		CMFormatDescriptionRef	desc = (trackFormatDescs==nil || [trackFormatDescs count]<1) ? nil : (CMFormatDescriptionRef)[trackFormatDescs objectAtIndex:0];
		if (desc != nil)	{
			switch (CMFormatDescriptionGetMediaSubType(desc))	{
			case 'Hap1':
			case 'Hap5':
			case 'HapY':
			case 'HapM':
			case 'HapA':
				hapTrack = trackPtr;
				break;
			default:
				break;
			}
			if (hapTrack != nil)
				break;
		}
	}
	return hapTrack;
}


@end
