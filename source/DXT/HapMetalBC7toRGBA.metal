//
//  BC7toRGBA.metal
//  AppleTextureEncoderTestApp
//
//  Created by testadmin on 2/16/24.
//

#include <metal_stdlib>

using namespace metal;


/*	this shader runs once for each block of 2x2 pixels- each execution, run a texture gather and copy the vals to the output texture
	because of this, the gid's always going to be half of the pixel values the shader's working with...
*/


kernel void HapMetalBC7toRGBA(
	texture2d<float,access::sample> srcTexture [[ texture(0) ]],
	device uchar4 * dstBuffer [[ buffer(0) ]],
	constant uint32_t & dstBufferBytesPerRow [[ buffer(1) ]],
	constant uint2 & dstBufferRes [[ buffer(2) ]],
	constant bool & bgraFlag [[ buffer(3) ]],
	uint2 gid [[ thread_position_in_grid ]])
{
	if (2*gid.x >= srcTexture.get_width() || 2*gid.y >= srcTexture.get_height())	{
		return;
	}
	
	constexpr sampler sampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge, coord::pixel);
	
	float2		samplerCoord = float2( (gid.x*2)+0.45, (gid.y*2)+0.45 );
	float4		samples[4];
	
	samples[0] = srcTexture.gather( sampler, samplerCoord, int2(0), component::x );
	samples[1] = srcTexture.gather( sampler, samplerCoord, int2(0), component::y );
	samples[2] = srcTexture.gather( sampler, samplerCoord, int2(0), component::z );
	samples[3] = srcTexture.gather( sampler, samplerCoord, int2(0), component::w );
	
	//#define TESTCOLORS
	#ifdef TESTCOLORS
	uchar4		tmpIntColors[4] = {
		uchar4(255, 0, 0, 255),
		uchar4(0, 255, 0, 255),
		uchar4(0, 0, 255, 255),
		uchar4(255, 255, 255, 255)
	};
	#else
	uchar4		tmpIntColors[4] = {
		uchar4( round(samples[0].x*255.), round(samples[1].x*255.), round(samples[2].x*255.), round(samples[3].x*255.) ),
		uchar4( round(samples[0].y*255.), round(samples[1].y*255.), round(samples[2].y*255.), round(samples[3].y*255.) ),
		uchar4( round(samples[0].z*255.), round(samples[1].z*255.), round(samples[2].z*255.), round(samples[3].z*255.) ),
		uchar4( round(samples[0].w*255.), round(samples[1].w*255.), round(samples[2].w*255.), round(samples[3].w*255.) )
	};
	#endif
	
	if (bgraFlag)	{
		tmpIntColors[0] = tmpIntColors[0].bgra;
		tmpIntColors[1] = tmpIntColors[1].bgra;
		tmpIntColors[2] = tmpIntColors[2].bgra;
		tmpIntColors[3] = tmpIntColors[3].bgra;
	}
	
	//	start in the bottom left corner, run counter-clockwise ( (- +), (+ +), (+ -), (- -) )
	const uint2		pixelLoc[4] = {
		uint2(2*gid.x, 2*gid.y+1),		//	(- +)
		uint2(2*gid.x+1, 2*gid.y+1),	//	(+ +)
		uint2(2*gid.x+1, 2*gid.y),		//	(+ -)
		uint2(2*gid.x, 2*gid.y)			//	(- -)
	};
	device uint8_t		*basePtr = (device uint8_t*)dstBuffer;	//	do ptr ops on a byte ptr to support padding in the dst buffer of a non-even multiple
	
	device uchar4		*recastWPtr;
	if (pixelLoc[0].x < dstBufferRes.x && pixelLoc[0].y < dstBufferRes.y)	{
		recastWPtr = (device uchar4*)(basePtr + (pixelLoc[0].x * 4) + (dstBufferBytesPerRow * pixelLoc[0].y));
		*recastWPtr = tmpIntColors[0];
	}
	
	if (pixelLoc[1].x < dstBufferRes.x && pixelLoc[1].y < dstBufferRes.y)	{
		recastWPtr = (device uchar4*)(basePtr + (pixelLoc[1].x * 4) + (dstBufferBytesPerRow * pixelLoc[1].y));
		*recastWPtr = tmpIntColors[1];
	}
	
	if (pixelLoc[2].x < dstBufferRes.x && pixelLoc[2].y < dstBufferRes.y)	{
		recastWPtr = (device uchar4*)(basePtr + (pixelLoc[2].x * 4) + (dstBufferBytesPerRow * pixelLoc[2].y));
		*recastWPtr = tmpIntColors[2];
	}
	
	if (pixelLoc[3].x < dstBufferRes.x && pixelLoc[3].y < dstBufferRes.y)	{
		recastWPtr = (device uchar4*)(basePtr + (pixelLoc[3].x * 4) + (dstBufferBytesPerRow * pixelLoc[3].y));
		*recastWPtr = tmpIntColors[3];
	}
}
