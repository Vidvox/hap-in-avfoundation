#include <metal_stdlib>
using namespace metal;

#include "MetalShaderTypes.h"

// Vertex shader outputs and fragmentShader inputs.
typedef struct
{
    // The [[position]] attribute qualifier of this member indicates this value is the clip space
    //   position of the vertex when this structure is returned from the vertex function
    float4 clipSpacePosition [[position]];
    
    // Since this member does not have a special attribute qualifier, the rasterizer will
    //   interpolate its value with values of other vertices making up the triangle and
    //   pass that interpolated value to the fragment shader for each fragment in that triangle
    float4 color;
    
    // Since this member does not have a special attribute qualifier, the rasterizer will
    //   interpolate its value with values of other vertices making up the triangle and
    //   pass that interpolated value to the fragment shader for each fragment in that triangle;
    float2 textureCoordinate;
    
} RasterizerData;



#pragma mark basic Vertex
vertex RasterizerData
textureToScreenVertexShader(uint vertexID [[ vertex_id ]],
                            constant AAPLTextureVertex *vertexArray [[ buffer(AAPLVertexInputIndexVertices) ]],
                            constant vector_uint2 *viewportSizePointer [[ buffer(AAPLVertexInputIndexViewportSize) ]])
{
    
    RasterizerData out;
    
    // Index into our array of positions to get the current vertex
    //   Our positions are specified in pixel dimensions (i.e. a value of 100 is 100 pixels from
    //   the origin)
    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    
    // Get the size of the drawable so that we can convert to normalized device coordinates,
    float2 viewportSize = float2(*viewportSizePointer);
    
    // The output position of every vertex shader is in clip space (also known as normalized device
    //   coordinate space, or NDC). A value of (-1.0, -1.0) in clip-space represents the
    //   lower-left corner of the viewport whereas (1.0, 1.0) represents the upper-right corner of
    //   the viewport.
    
    // In order to convert from positions in pixel space to positions in clip space we divide the
    //   pixel coordinates by half the size of the viewport.
    out.clipSpacePosition.xy = pixelSpacePosition / (viewportSize / 2.0);
    
    // Set the z component of our clip space position 0 (since we're only rendering in
    //   2-Dimensions for this sample)
    out.clipSpacePosition.z = 0.0;
    
    // Set the w component to 1.0 since we don't need a perspective divide, which is also not
    //   necessary when rendering in 2-Dimensions
    out.clipSpacePosition.w = 1.0;
    
    // Pass our input textureCoordinate straight to our output RasterizerData. This value will be
    //   interpolated with the other textureCoordinate values in the vertices that make up the
    //   triangle.
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate;
    
    return out;
}

#pragma mark basic Fragment
fragment float4
textureToScreenSamplingShader(RasterizerData in [[stage_in]],
                              texture2d<half> colorTexture [[ texture(AAPLTextureIndexZero) ]])
{
    constexpr sampler textureSampler (mag_filter::linear, min_filter::linear);
    // Sample the texture to obtain a color
    const half4 colorSample = colorTexture.sample(textureSampler, in.textureCoordinate);
    // We return the color of the texture
    return float4(colorSample);
}

#pragma mark HAP color conversion
float3 CoCgSYToRgb(const float4 CoCgSY)
{
    const float4 offsets = float4(-0.50196078431373, -0.50196078431373, 0.0, 0.0);
    const float4 CoCgSYOffseted = CoCgSY + offsets;
    const float scale = ( CoCgSYOffseted.z * ( 255.0 / 8.0 ) ) + 1.0;
    const float Co = CoCgSYOffseted.x / scale;
    const float Cg = CoCgSYOffseted.y / scale;
    const float Y = CoCgSYOffseted.w;
    const float3 rgb = float3(Y + Co - Cg, Y + Cg, Y - Co - Cg);
    return rgb;
}

fragment float4
textureToScreenSamplingShader_ScaledCoCgYToRGBA(RasterizerData in [[stage_in]],
                                                texture2d<float> colorTexture [[ texture(AAPLTextureIndexZero) ]])
{
    constexpr sampler textureSampler (mag_filter::linear, min_filter::linear);
    const float4 colorSample = colorTexture.sample(textureSampler, in.textureCoordinate);
    const float3 rgb = CoCgSYToRgb(colorSample);
    return float4(rgb, 1.);
}

fragment float4
textureToScreenSamplingShader_ScaledCoCgYPlusAToRGBA(RasterizerData in [[stage_in]],
                                                     texture2d<float> colorTexture [[ texture(AAPLTextureIndexZero) ]],
                                                     texture2d<float> maskTexture [[ texture(AAPLTextureIndexOne) ]])
{
    constexpr sampler textureSampler (mag_filter::linear, min_filter::linear);
    const float4 colorSample = colorTexture.sample(textureSampler, in.textureCoordinate);
    const float4 maskSample = maskTexture.sample(textureSampler, in.textureCoordinate);
    const float3 rgb = CoCgSYToRgb(colorSample);
    return float4(rgb, maskSample.x);
}
