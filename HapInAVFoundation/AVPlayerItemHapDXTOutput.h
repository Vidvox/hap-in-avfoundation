#import <Foundation/Foundation.h>
#import "HapDecoderFrame.h"
#import <AVFoundation/AVFoundation.h>




/**
This defines a block that returns an instance of HapDecoderFrame that has been allocated and populated (the returned frame should have a buffer into which the decompressed DXT data can be written).  Providing the buffer into which DXT data is decompressed allows devs to minimize the number of copies performed with this data (DMA to GL textures being the best-case scenario).  Use of this block is optional- but if you use it, you *must* populate the HapDecoderFrame's dxtData and dxtDataSize properties.		*/
typedef HapDecoderFrame* (^HapDecoderFrameAllocBlock)(CMSampleBufferRef decompressMe);
/**
This defines a block that gets called immediately after a frame has finished uncompressing a hap frame into DXT data.  Frame decoding is done via GCD- this block is executed on a thread spawned and controlled by GCD, so this would be a good place to take the opportunity to upload the decompressed DXT data to a GL texture.		*/
typedef void (^AVFHapDXTPostDecodeBlock)(HapDecoderFrame *decodedFrame);




/**
This class is the main interface for decoding hap video from AVFoundation.  You create an instance of this class and add it to an AVPlayerItem as you would with any other AVPlayerItemOutput subclass.  You retrieve frame data from this output by calling allocFrameClosestToTime:, which will either return nil (if a frame isn't available yet) or an instance of HapDecoderFrame into which the hap frame has been decompressed into DXT data ready for upload to a GL texture.  At this time, there's no built-in CPU-based method for decoding a hap frame into a BGRA/RGBA pixel buffer, but this can certainly be added if requested.		*/
@interface AVPlayerItemHapDXTOutput : AVPlayerItemOutput	{
	OSSpinLock					propertyLock;	//	used to lock access to everything
	
	dispatch_queue_t			decodeQueue;	//	decoding is performed on this queue (if you use them, the allocFrameBlock and postDecodeBlock are also executed on this queue)
	AVAssetTrack				*track;	//	RETAINED
	AVSampleBufferGenerator		*gen;	//	RETAINED
	CMTime						lastGeneratedSampleTime;	//	used to prevent requesting the same buffer twice from the sample generator
	NSMutableArray				*decompressedFrames;	//	contains HapDecoderFrame instances that have been decompressed and are ready to be used elsewhere
	
	HapDecoderFrameAllocBlock		allocFrameBlock;	//	retained, nil by default.  this block is optional, but it must be threadsafe- it will be called (on a thread spawned by GCD) to create HapDecoderFrame instances.  if you want to provide your own memory into which the hap frames will be decoded into DXT, this is a good place to do it.
	AVFHapDXTPostDecodeBlock		postDecodeBlock;	//	retained, nil by default.  this block is optional, but it must be threadsafe- it's executed on GCD-spawned threads immediately after decompression if decompression was successful.  if you want to upload your DXT data to a GL texture, this is a good place to do it.
}

/**
This method returns a retained frame as close to the passed time as possible.  May return nil if no frame is immediately available.
@return This method is synchronous- it returns immediately, so if a frame isn't available right now it'll return nil.  If it doesn't return nil, it returns a retained (caller must release the returned object) instance of HapDecoderFrame which has been decoded (the raw DXT data is available).
@param n The time at which you would like to retrieve a frame.
*/
- (HapDecoderFrame *) allocFrameClosestToTime:(CMTime)n;

/**
Use this if you want to provide a custom block that allocates and configures a HapDecoderFrame instance- if you want to pool resources or manually provide the memory into which the decoded data will be written, you need to provide a custom alloc block.
@param n This HapDecoderFrameAllocBlock must be threadsafe, and should avoid retaining the instance of this class that "owns" the block to prevent a retain loop.
*/
- (void) setAllocFrameBlock:(HapDecoderFrameAllocBlock)n;
/**
The post decode block is executed immediately after the hap frame has been decoded into DXT data.  if you want to upload your DXT data to a GL texture on a GCD-spawned thread, this is a good place to implement it.
@param n This AVFHapDXTPostDecodeBlock must be threadsafe, and should avoid retaining the instance of this class that "owns" the block to prevent a retain loop.
*/
- (void) setPostDecodeBlock:(AVFHapDXTPostDecodeBlock)n;

@end




//	we need to register the DXT pixel formats with CoreVideo- until we do this, they won't be recognized and we won't be able to work with them.  this BOOL is used to ensure that we only register them once.
extern BOOL				_AVFinHapCVInit;
