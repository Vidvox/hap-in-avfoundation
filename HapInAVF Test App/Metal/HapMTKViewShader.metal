//
//  MetalImageViewShader.metal
//  HapInAVF Test App
//
//  Created by testadmin on 6/8/23.
//  Copyright © 2023 Vidvox. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

#include "HapMTKViewShaderTypes.h"




typedef struct	{
	float4			geometry [[ position ]];
	float2			texCoord [[ sample_perspective ]];
} HapMTKViewRasterizerData;




vertex HapMTKViewRasterizerData HapMTKViewVertShader(
	uint inVertexID [[ vertex_id ]],
	constant HapMTKViewVertex * inVerts [[ buffer(HapMTKViewVSIndex_VertexData) ]],
	constant float4x4 * inMVP [[ buffer(HapMTKViewVSIndex_MVPMatrix) ]])
{
	HapMTKViewRasterizerData		returnMe;
	returnMe.geometry = (*inMVP) * float4(inVerts[inVertexID].geometry, 0., 1.);
	returnMe.texCoord = inVerts[inVertexID].texCoord;
	return returnMe;
}




fragment float4 HapMTKViewFragShader(
	HapMTKViewRasterizerData inRasterData [[ stage_in ]],
	constant HapMTKViewImageDescription * imageDescription [[ buffer(HapMTKViewFSIndex_ImageDescription) ]],
	texture2d<float,access::sample> textureA [[ texture(HapMTKViewFSIndex_TextureA) ]],
	texture2d<float,access::sample> textureB [[ texture(HapMTKViewFSIndex_TextureB) ]])
{
	constexpr sampler		sampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge, coord::pixel);
	const float4			offsets = float4(-0.50196078431373, -0.50196078431373, 0.0, 0.0);
	
	switch (imageDescription->imageType)	{
		case HapMTKViewImageType_Sampleable:
			{
				return textureA.sample(sampler, inRasterData.texCoord);
			}
			break;
		case HapMTKViewImageType_YCoCg:
			{
				float4		CoCgSY = textureA.sample(sampler, inRasterData.texCoord);
				CoCgSY += offsets;
				float		scale = ( CoCgSY.z * (255./8.)) + 1.;
				
				float		Co = CoCgSY.x / scale;
				float		Cg = CoCgSY.y / scale;
				float		Y = CoCgSY.w;
				
				return float4(Y + Co - Cg, Y + Cg, Y - Co - Cg, 1.0);
			}
			break;
		case HapMTKViewImageType_YCoCgA:
			{
				float4		CoCgSY = textureA.sample(sampler, inRasterData.texCoord);
				float4		alpha = textureB.sample(sampler, inRasterData.texCoord);
				CoCgSY += offsets;
				float		scale = ( CoCgSY.z * (255./8.)) + 1.;
				
				float		Co = CoCgSY.x / scale;
				float		Cg = CoCgSY.y / scale;
				float		Y = CoCgSY.w;
				
				return float4(Y + Co - Cg, Y + Cg, Y - Co - Cg, alpha.x);
			}
			break;
	}
}

