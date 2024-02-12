//
//	ATEBC7Encoder.c
//	HapInAVFoundation
//
//	Created by testadmin on 2/13/24.
//	Copyright © 2024 Vidvox. All rights reserved.
//

#include "ATEBC7Encoder.h"

#include "AppleTextureEncoder.h"
#include "Utility.h"
//#include "PixelFormats.h"

#include <CoreVideo/CoreVideo.h>




struct HapCodecATEBC7Encoder	{
	struct HapCodecDXTEncoder base;
	at_encoder_t rgbaEncoder;
	at_encoder_t bgraEncoder;
	float errorThreshold;
#ifdef DEBUG
	char description[255];
#endif
};




static void HapCodecATEBC7Destroy(HapCodecDXTEncoderRef encoder)
{
	struct HapCodecATEBC7Encoder	*recast = (struct HapCodecATEBC7Encoder*)encoder;
	if (recast->rgbaEncoder != NULL)	{
		os_release( recast->rgbaEncoder );
		recast->rgbaEncoder = NULL;
	}
	if (recast->bgraEncoder != NULL)	{
		os_release( recast->bgraEncoder );
		recast->bgraEncoder = NULL;
	}
	free(encoder);
}

static OSType HapCodecATEBC7WantedPixelFormat(HapCodecDXTEncoderRef encoder, OSType format)
{
	#pragma unused(encoder)
	switch (format) {
		case kCVPixelFormatType_32BGRA:
		case kCVPixelFormatType_32RGBA:
			return format;
		default:
			return kCVPixelFormatType_32RGBA;
	}
}

static int HapCodecATEBC7Encode(
	HapCodecDXTEncoderRef encoder,
	const void *src,
	unsigned int src_bytes_per_row,
	OSType src_pixel_format,
	void *dst,
	unsigned int width,
	unsigned int height)
{
	if (encoder == NULL || encoder->encoder_type != HapDXTEncoderType_ATEBC7)
		return 1;
	
	struct HapCodecATEBC7Encoder	*recastEncoder = (struct HapCodecATEBC7Encoder*)encoder;
	
	uint32_t	roundedWidth = (uint32_t)roundUpToMultipleOf4(width);
	uint32_t	roundedHeight = (uint32_t)roundUpToMultipleOf4(height);
	uint32_t	blocks_wide = roundedWidth / 4;
	uint32_t	blocks_high = roundedHeight / 4;
	//uint32_t	num_blocks = blocks_wide * blocks_high;
	//size_t		dxtLength = num_blocks * 128 / 8;
	
	at_flags_t		debugFlags = 0;
	debugFlags += at_flags_default;
	//debugFlags += at_flags_skip_parameter_checking;
	//debugFlags += at_flags_print_debug_info;
	//debugFlags += at_flags_disable_multithreading;
	//debugFlags += at_flags_skip_error_calculation;
	//debugFlags += at_flags_flip_texel_region_vertically;
	//debugFlags += at_flags_srgb_linear_texels;
	//debugFlags += at_flags_weight_channels_equally;
	
	at_texel_region_t		srcRegionBC7;
	srcRegionBC7.texels = (void*)src;
	srcRegionBC7.validSize.x = width;
	srcRegionBC7.validSize.y = height;
	srcRegionBC7.validSize.z = 1;
	srcRegionBC7.rowBytes = src_bytes_per_row;
	srcRegionBC7.sliceBytes = src_bytes_per_row * roundedHeight * 32 / 8;
	
	at_block_buffer_t		destRegionBC7;
	destRegionBC7.blocks = dst;
	destRegionBC7.rowBytes = blocks_wide * 128 / 8;
	destRegionBC7.sliceBytes = destRegionBC7.rowBytes * blocks_high;
	
	float		msq_err = 0.;
	
	switch (src_pixel_format) {
		case kCVPixelFormatType_32BGRA:
			msq_err = at_encoder_compress_texels( recastEncoder->bgraEncoder, &srcRegionBC7, &destRegionBC7, recastEncoder->errorThreshold, debugFlags);
			break;
		case kCVPixelFormatType_32RGBA:
			msq_err = at_encoder_compress_texels( recastEncoder->rgbaEncoder, &srcRegionBC7, &destRegionBC7, recastEncoder->errorThreshold, debugFlags);
			break;
		default:
			return 2;
	}
	
	if (msq_err < 0.)	{
		return 3;
	}
	
	return 0;
}

#if defined(DEBUG)
static const char *HapCodecATEBC7Describe(HapCodecDXTEncoderRef encoder)
{
	return ((struct HapCodecATEBC7Encoder *)encoder)->description;
}
#endif

HapCodecDXTEncoderRef HapCodecATEBC7EncoderCreate(OSType pixelFormat, double encodeQuality)
{
	struct HapCodecATEBC7Encoder *encoder = malloc(sizeof(struct HapCodecATEBC7Encoder));
	if (encoder)
	{
		encoder->base.destroy_function = HapCodecATEBC7Destroy;
		encoder->base.pixelformat_function = HapCodecATEBC7WantedPixelFormat;
		encoder->base.encode_function = HapCodecATEBC7Encode;
		encoder->base.pad_source_buffers = true;
		encoder->base.can_slice = true;
		encoder->base.encoder_type = HapDXTEncoderType_ATEBC7;
		
		encoder->rgbaEncoder = at_encoder_create(
			at_texel_format_rgba8_unorm,
			at_alpha_not_premultiplied,
			at_block_format_bc7,
			at_alpha_not_premultiplied,
			NULL);
		encoder->bgraEncoder = at_encoder_create(
			at_texel_format_bgra8_unorm,
			at_alpha_not_premultiplied,
			at_block_format_bc7,
			at_alpha_not_premultiplied,
			NULL);
		encoder->errorThreshold = 1. - encodeQuality;
		
#if defined(DEBUG)
		char *format_str;
		switch (pixelFormat) {
			case kHapCVPixelFormat_RGBA_BC7:
				format_str = "RGBA BC7";
				break;
			default:
				format_str = "??? BC7";
				break;
		}
		snprintf(encoder->description, sizeof(encoder->description), "ATE BC7 %s Encoder", format_str);
		encoder->base.describe_function = HapCodecATEBC7Describe;
#endif
		
		if (encoder->rgbaEncoder == NULL || encoder->bgraEncoder == NULL)
		{
			HapCodecATEBC7Destroy((HapCodecDXTEncoderRef)encoder);
			encoder = NULL;
		}
	}
	
	return (HapCodecDXTEncoderRef)encoder;
}

