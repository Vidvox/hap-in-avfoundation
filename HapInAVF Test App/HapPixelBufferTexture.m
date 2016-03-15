/*
 HapPixelBufferTexture.m
 Hap QuickTime Playback
 
 Copyright (c) 2012-2013, Tom Butterworth and Vidvox LLC. All rights reserved.
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "HapPixelBufferTexture.h"
#import <OpenGL/CGLMacro.h>
//#import "HapSupport.h"
#import <HapInAVFoundation/HapInAVFoundation.h>

#define FourCCLog(n,f) NSLog(@"%@, %c%c%c%c",n,(int)((f>>24)&0xFF),(int)((f>>16)&0xFF),(int)((f>>8)&0xFF),(int)((f>>0)&0xFF))


@interface HapPixelBufferTexture (Shader)
- (GLhandleARB)loadShaderOfType:(GLenum)type named:(NSString *)name;
@end




@implementation HapPixelBufferTexture
- (id)initWithContext:(CGLContextObj)context
{
	self = [super init];
	if (self)
	{
		textureCount = 0;
		for (int i=0; i<2; ++i)	{
			textures[i] = 0;
			backingHeights[i] = 0;
			backingWidths[i] = 0;
			internalFormats[i] = 0;
		}
		decodedFrame = nil;
		width = 0;
		height = 0;
		valid = NO;
		shader = 0;
		alphaShader = 0;
		cgl_ctx = CGLRetainContext(context);
	}
	return self;
}

- (void)dealloc
{
	for (int texIndex=0; texIndex<textureCount; ++texIndex)	{
		if (textures[texIndex] != 0)
			glDeleteTextures(1,&(textures[texIndex]));
	}
	if (shader != NULL) glDeleteObjectARB(shader);
	if (alphaShader != NULL) glDeleteObjectARB(alphaShader);
	if (decodedFrame!=nil)	{
		[decodedFrame release];
		decodedFrame = nil;
	}
	CGLReleaseContext(cgl_ctx);
	[super dealloc];
}
- (void) setDecodedFrame:(HapDecoderFrame *)newFrame	{
	[newFrame retain];
	
	[decodedFrame release];
	decodedFrame = newFrame;
	
	valid = NO;
	
	if (decodedFrame == NULL)
	{
		NSLog(@"\t\terr: decodedFrame nil, bailing. %s",__func__);
		return;
	}
	
	NSSize			tmpSize = [decodedFrame imgSize];
	width = tmpSize.width;
	height = tmpSize.height;
	
	tmpSize = [decodedFrame dxtImgSize];
	GLuint			roundedWidth = tmpSize.width;
	GLuint			roundedHeight = tmpSize.height;
	if (roundedWidth % 4 != 0 || roundedHeight % 4 != 0)	{
		NSLog(@"\t\terr: width isn't a multiple of 4, bailing. %s",__func__);
		return;
	}
	
	textureCount = [decodedFrame dxtPlaneCount];
	OSType			*dxtPixelFormats = [decodedFrame dxtPixelFormats];
	GLenum			newInternalFormat;
	size_t			*dxtDataSizes = [decodedFrame dxtDataSizes];
	void			**dxtBaseAddresses = [decodedFrame dxtDatas];
	for (int texIndex=0; texIndex<textureCount; ++texIndex)	{
		unsigned int	bitsPerPixel = 0;
		switch (dxtPixelFormats[texIndex]) {
			case kHapCVPixelFormat_RGB_DXT1:
				newInternalFormat = HapTextureFormat_RGB_DXT1;
				bitsPerPixel = 4;
				break;
			case kHapCVPixelFormat_RGBA_DXT5:
			case kHapCVPixelFormat_YCoCg_DXT5:
				newInternalFormat = HapTextureFormat_RGBA_DXT5;
				bitsPerPixel = 8;
				break;
			case kHapCVPixelFormat_CoCgXY:
				if (texIndex==0)	{
					newInternalFormat = HapTextureFormat_RGBA_DXT5;
					bitsPerPixel = 8;
				}
				else	{
					newInternalFormat = HapTextureFormat_A_RGTC1;
					bitsPerPixel = 4;
				}
				
				//newInternalFormat = HapTextureFormat_RGBA_DXT5;
				//bitsPerPixel = 8;
				break;
			case kHapCVPixelFormat_YCoCg_DXT5_A_RGTC1:
				if (texIndex==0)	{
					newInternalFormat = HapTextureFormat_RGBA_DXT5;
					bitsPerPixel = 8;
				}
				else	{
					newInternalFormat = HapTextureFormat_A_RGTC1;
					bitsPerPixel = 4;
				}
				break;
			case kHapCVPixelFormat_A_RGTC1:
				newInternalFormat = HapTextureFormat_A_RGTC1;
				bitsPerPixel = 4;
				break;
			default:
				// we don't support non-DXT pixel buffers
				NSLog(@"\t\terr: unrecognized pixel format (%X) at index %d in %s",dxtPixelFormats[texIndex],texIndex,__func__);
				FourCCLog(@"\t\tpixel format fourcc is",dxtPixelFormats[texIndex]);
				valid = NO;
				return;
				break;
		}
		size_t			bytesPerRow = (roundedWidth * bitsPerPixel) / 8;
		GLsizei			newDataLength = (int)(bytesPerRow * roundedHeight);
		size_t			actualBufferSize = dxtDataSizes[texIndex];
		
		//	make sure the buffer's at least as big as necessary
		if (newDataLength > actualBufferSize)	{
			NSLog(@"\t\terr: new data length incorrect, %d vs %ld in %s",newDataLength,actualBufferSize,__func__);
			valid = NO;
			return;
		}
		
		//	if we got this far we're good to go
		
		valid = YES;
		
		glPushAttrib(GL_ENABLE_BIT | GL_TEXTURE_BIT);
		glPushClientAttrib(GL_CLIENT_PIXEL_STORE_BIT);
		glEnable(GL_TEXTURE_2D);
			
		GLvoid		*baseAddress = dxtBaseAddresses[texIndex];
	
		// Create a new texture if our current one isn't adequate
	
		if (textures[texIndex] == 0	||
		roundedWidth > backingWidths[texIndex] ||
		roundedHeight > backingHeights[texIndex] ||
		newInternalFormat != internalFormats[texIndex])
		{
			if (textures[texIndex] != 0)
			{
				glDeleteTextures(1, &(textures[texIndex]));
			}
		
			glGenTextures(1, &(textures[texIndex]));
		
			glBindTexture(GL_TEXTURE_2D, textures[texIndex]);
		
			// On NVIDIA hardware there is a massive slowdown if DXT textures aren't POT-dimensioned, so we use POT-dimensioned backing
			//	NOTE: NEEDS TESTING. this used to be the case- but this API is only available on 10.10+, so this may have been fixed.
			backingWidths[texIndex] = 1;
			while (backingWidths[texIndex] < roundedWidth) backingWidths[texIndex] <<= 1;
		
			backingHeights[texIndex] = 1;
			while (backingHeights[texIndex] < roundedHeight) backingHeights[texIndex] <<= 1;
		
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_STORAGE_HINT_APPLE , GL_STORAGE_SHARED_APPLE);
		
			// We allocate the texture with no pixel data, then use CompressedTexSubImage to update the content region
		
			glTexImage2D(GL_TEXTURE_2D, 0, newInternalFormat, backingWidths[texIndex], backingHeights[texIndex], 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, NULL);		  
		
			internalFormats[texIndex] = newInternalFormat;
		}
		else
		{
			glBindTexture(GL_TEXTURE_2D, textures[texIndex]);
		}
	
		glTextureRangeAPPLE(GL_TEXTURE_2D, newDataLength, baseAddress);
		glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE);
	
		glCompressedTexSubImage2D(GL_TEXTURE_2D,
								  0,
								  0,
								  0,
								  roundedWidth,
								  roundedHeight,
								  newInternalFormat,
								  newDataLength,
								  baseAddress);
	
		glPopClientAttrib();
		glPopAttrib();
	
		glFlush();
	}
}
- (HapDecoderFrame *) decodedFrame	{
	return decodedFrame;
}

- (int) textureCount
{
	return textureCount;
}
- (GLuint *)textureNames
{
	if (!valid) return 0;
	return textures;
}

- (GLuint)width
{
	if (valid) return width;
	else return 0;
}

- (GLuint)height
{
	if (valid) return height;
	else return 0;
}

- (GLuint*)textureWidths
{
	if (!valid) return 0;
	return backingWidths;
}

- (GLuint*)textureHeights
{
	if (!valid) return 0;
	return backingHeights;
}

- (GLhandleARB)shaderProgramObject
{
	if (valid && decodedFrame!=nil)	{
		OSType		codecSubType = [decodedFrame codecSubType];
		if (codecSubType==kHapYCoCgCodecSubType)	{
			if (shader == NULL)
			{
				GLhandleARB vert = [self loadShaderOfType:GL_VERTEX_SHADER_ARB named:@"ScaledCoCgYToRGBA"];
				GLhandleARB frag = [self loadShaderOfType:GL_FRAGMENT_SHADER_ARB named:@"ScaledCoCgYToRGBA"];
				GLint programLinked = 0;
				if (frag && vert)
				{
					shader = glCreateProgramObjectARB();
					glAttachObjectARB(shader, vert);
					glAttachObjectARB(shader, frag);
					glLinkProgramARB(shader);
					glGetObjectParameterivARB(shader,
											  GL_OBJECT_LINK_STATUS_ARB,
											  &programLinked);
					if(programLinked == 0 )
					{
						glDeleteObjectARB(shader);
						shader = NULL;
					}
					else	{
						glUseProgram(shader);
						GLint			samplerLoc = -1;
						samplerLoc = glGetUniformLocation(shader, "cocgsy_src");
						if (samplerLoc >= 0)
							glUniform1i(samplerLoc,0);
						glUseProgram(0);
					}
				}
				if (frag) glDeleteObjectARB(frag);
				if (vert) glDeleteObjectARB(vert);
			}
			return shader;
		}
		else if (codecSubType == kHapYCoCgACodecSubType)	{
			if (alphaShader == NULL)
			{
				GLhandleARB vert = [self loadShaderOfType:GL_VERTEX_SHADER_ARB named:@"ScaledCoCgYToRGBA"];
				GLhandleARB frag = [self loadShaderOfType:GL_FRAGMENT_SHADER_ARB named:@"ScaledCoCgYPlusAToRGBA"];
				GLint programLinked = 0;
				if (frag && vert)
				{
					alphaShader = glCreateProgramObjectARB();
					glAttachObjectARB(alphaShader, vert);
					glAttachObjectARB(alphaShader, frag);
					glLinkProgramARB(alphaShader);
					glGetObjectParameterivARB(alphaShader,
											  GL_OBJECT_LINK_STATUS_ARB,
											  &programLinked);
					if(programLinked == 0 )
					{
						glDeleteObjectARB(alphaShader);
						alphaShader = NULL;
					}
					else	{
						glUseProgram(alphaShader);
						GLint			samplerLoc = -1;
						samplerLoc = glGetUniformLocation(alphaShader, "cocgsy_src");
						if (samplerLoc >= 0)
							glUniform1i(samplerLoc,0);
						samplerLoc = -1;
						samplerLoc = glGetUniformLocation(alphaShader, "alpha_src");
						if (samplerLoc >= 0)
							glUniform1i(samplerLoc,1);
						glUseProgram(0);
					}
				}
				if (frag) glDeleteObjectARB(frag);
				if (vert) glDeleteObjectARB(vert);
			}
			return alphaShader;
		}
	}
	return NULL;
}

- (GLhandleARB)loadShaderOfType:(GLenum)type named:(NSString *)name
{
	NSString *extension = (type == GL_VERTEX_SHADER_ARB ? @"vert" : @"frag");
	NSString  *path = [[NSBundle bundleForClass:[self class]] pathForResource:name
																	   ofType:extension];
	NSString *source = nil;
	if (path) source = [NSString stringWithContentsOfFile:path usedEncoding:nil error:nil];
	
	GLint		shaderCompiled = 0;
	GLhandleARB shaderObject = NULL;
	
	if(source != nil)
	{
		const GLcharARB *glSource = [source cStringUsingEncoding:NSASCIIStringEncoding];
		
		shaderObject = glCreateShaderObjectARB(type);
		glShaderSourceARB(shaderObject, 1, &glSource, NULL);
		glCompileShaderARB(shaderObject);
		glGetObjectParameterivARB(shaderObject,
								  GL_OBJECT_COMPILE_STATUS_ARB,
								  &shaderCompiled);
		
		if(shaderCompiled == 0 )
		{
			glDeleteObjectARB(shaderObject);
			shaderObject = NULL;
		}
	}
	return shaderObject;
}
@end
