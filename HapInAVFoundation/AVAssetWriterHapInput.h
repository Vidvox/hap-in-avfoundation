#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "CMBlockBufferPool.h"
#import "HapEncoderFrame.h"




//	this string constant is used to describe a video track using the Hap codec.  pass it in a settings dict when init'ing an AVAssetWriterHapInput.
extern NSString *const			AVVideoCodecHap;
//	same as "AVVideoCodecHap", except this defines a video using the Hap Alpha codec
extern NSString *const			AVVideoCodecHapAlpha;
//	same as "AVVideoCodecHap", except this defines a video using the HapQ codec
extern NSString *const			AVVideoCodecHapQ;




/**
This class is the main interface for using AVFoundation to encode and output video tracks that use the hap codec.  You create an instance of this class and add it to an AVAssetWriter just as you would any other instance of AVAssetWriterInput.  Any frames you want to encode must then be passed to this class as CVPixelBufferRefs containing pixel data formatted as either RGBA or BGRA (8 bits per channel).
*/
@interface AVAssetWriterHapInput : AVAssetWriterInput	{
	dispatch_queue_t	encodeQueue;	//	encoding is performed on this queue
	
	OSType			exportCodecType;	//	like kHapCodecSubType/'Hap1', etc.  declared in HapCodecSubTypes.h
	OSType			exportPixelFormat;	//	like kHapCVPixelFormat_RGB_DXT1/'DXt1', etc.  declared in PixelFormats.h.
	uint32_t		exportTextureType;	//	like HapTextureFormat_RGB_DXT1, etc.  declared in hap.h
	NSSize			exportImgSize;	//	the size of the exported image in pixels.  doesn't take any rounding/block sizes into account- just the image size.
	NSSize			exportDXTImgSize;	//	'exportImgSize' rounded up to a multiple of 4
	
	OSType			encoderInputPxlFmt;	//	the encoder wants pixels of a particular format.  this is the format they want.
	uint32_t		encoderInputPxlFmtBytesPerRow;	//	the number of bytes per row in the buffers created to convert to 'encoderInputPxlFmt'
	
	size_t			formatConvertPoolLength;	//	the size of the buffers that i need to create if i need to convert pixel formats
	size_t			dxtBufferPoolLength;	//	the size of the buffers that i need to create to hold dxt frames
	size_t			hapBufferPoolLength;	//	the size of the buffers i need to create to hold hap frames
	
	OSSpinLock			encoderLock;
	void				*dxtEncoder;	//	actually a 'HapCodecDXTEncoderRef'
	
	OSSpinLock			encoderProgressLock;	//	locks 'encoderProgressFrames' and 'encoderWaitingToRunOut'
	__block NSMutableArray		*encoderProgressFrames;	//	array of HapEncoderFrame instances.  the frames are made when you append a pixel buffer, and are flagged as encoded and appended (as an encoded sample buffer) in the GCD-driven block that did the encoding
	BOOL				encoderWaitingToRunOut;	//	set to YES when the user marks this input as finished (the frames that are "in flight" via GCD need to finish up)
	
	CMTime				lastEncodedDuration;
}

/**
Functionally similar to the same method in its superclass- initializes the returned AVAssetWriterInput based on the settings in the passed dictionary.
@param vidOutSettings An NSDictionary such as you would pass to any other instance of AVAssetWriterInput- the only difference is that this dict must specify a hap video codec using AVVideoCodecHap, AVVideoCodecHapAlpha, or AVVideoCodecHapQ (defined in this header file).  Like the JPEG codec, the hap codec recognizes the AVVideoQualityKey- if the corresponding value > 0.80, a slower, high-quality encoder is used.  if the value is <= 0.80 or isn't specified at all, a fast low-quality encoder is used (the default).
@return Returns nil if the passed dict doesn't describe a hap video track, otherwise it returns the initialized writer input.
*/
- (id) initWithOutputSettings:(NSDictionary *)vidOutSettings;

/**
Begins encoding the passed pixel buffer asynchronously and appends the encoded frame to this input when complete.  This method is equivalent to calling appendPixelBuffer:withPresentationTime:asynchronously: with an asynch value of YES, and is generally appropriate for realtime encoding of video data.
@param pb The passed pixel buffer must be either 8-bit BGRA or RGBA, and will be retained for as long as necessary
@param t The time at which this pixel buffer should appear as a frame
*/
- (BOOL) appendPixelBuffer:(CVPixelBufferRef)pb withPresentationTime:(CMTime)t;

/**
Begins encoding the passed pixel buffer and appends the encoded frame to this input when complete.
@param pb The passed pixel buffer must be either 8-bit BGRA or RGBA, and will be retained for as long as necessary
@param t The time at which this pixel buffer should appear as a frame
@param a If YES, the pixel buffer will be encoded and appended asynchronously (the method will return immediately, and encoding will happen on another thread).  If NO, the pixel buffer will be encoded and appended before this method returns.
*/
- (BOOL) appendPixelBuffer:(CVPixelBufferRef)pb withPresentationTime:(CMTime)t asynchronously:(BOOL)a;

/**
It's not necessary to check this- but for best results, you should mark the AVAssetWriterHapInput as finished, wait until "finishedEncoding" returns a YES, and then tell your AVAssetWriter to finish writing.  If you don't wait for this method to return YES, the last X pixel buffers may get dropped (depends how long it takes to wrap up, could be no dropped frames, could be a couple).
*/
- (BOOL) finishedEncoding;
- (void) finishEncoding;


@end
