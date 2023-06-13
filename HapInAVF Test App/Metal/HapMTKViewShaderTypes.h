//
//  HapMTKViewShaderTypes.h
//  HapInAVFoundation
//
//  Created by testadmin on 6/8/23.
//  Copyright © 2023 Vidvox. All rights reserved.
//

#ifndef MetalImageViewShaderTypes_h
#define MetalImageViewShaderTypes_h




//	vertex data is passed to the shader formatted as this struct
typedef struct HapMTKViewVertex	{
	vector_float2		geometry;	//	(x,y) location of the vertex.  coords are expected to be orthogonal.
	vector_float2		texCoord;	//	sampler is pixel-based (NOT normalized)- these are the coords of the pixel to sample that corresponds to this geometry
} HapMTKViewVertex;




//	Some Hap codecs produce texture data which needs to be processed in some fashion to produce RGB texture data usable by other shaders.  This enum describes all of these states.
typedef enum HapMTKViewImageType	{
	HapMTKViewImageType_Sampleable = 0,	//	if the texture can just be sampled and its colors don't require either conversion or assembly
	HapMTKViewImageType_YCoCg,	//	the texture data is YCoCg and needs to be converted to RGB
	HapMTKViewImageType_YCoCgA	//	the texture data is provided as two textures- one YCoCg, and another single-channel for alpha
} HapMTKViewImageType;

//	this struct describes an image- we pass this description to the frag shader so it knows how to sample the attached textures
typedef struct HapMTKViewImageDescription	{
	HapMTKViewImageType		imageType;
} HapMTKViewImageDescription;




//	this enum describes the indexes at which various attachments are located in the view's vertex shader
typedef enum HapMTKViewVSIndex	{
	HapMTKViewVSIndex_VertexData = 0,	//	geometry data formatted as 'HapMTKViewVertex'
	HapMTKViewVSIndex_MVPMatrix,		//	a 4x4 matrix describing the (concatenated) model/view/projection matrix for an orthogonal display
} HapMTKViewVSIndex;




//	this enum describes the indexes at which various attachments are located in the view's fragment shader
typedef enum HapMTKViewFSIndex	{
	HapMTKViewFSIndex_ImageDescription = 0,	//	'HapMTKViewImageDescription' struct describing the image we're meant to be displaying
	HapMTKViewFSIndex_TextureA,
	HapMTKViewFSIndex_TextureB
} HapMTKViewFSIndex;




#endif /* MetalImageViewShaderTypes_h */
