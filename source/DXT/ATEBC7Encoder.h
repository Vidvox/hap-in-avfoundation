//
//  ATEBC7Encoder.h
//  HapInAVFoundation
//
//  Created by testadmin on 2/13/24.
//  Copyright © 2024 Vidvox. All rights reserved.
//

#ifndef ATEBC7Encoder_h
#define ATEBC7Encoder_h

#include "DXTEncoder.h"

/*
	- 'pixelFormat' is the pixel format of the BC7 texture to encode (like kHapCVPixelFormat_RGBA_BC7)
	- 'decodeQuality' is a normalized value indicating the visual quality of the encode- 1 is "best quality", and will take longer and more closely resemble the input image than an encode of 0 quality.
*/
HapCodecDXTEncoderRef HapCodecATEBC7EncoderCreate(OSType pixelFormat, double encodeQuality);

#endif /* ATEBC7Encoder_h */
