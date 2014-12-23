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




@interface HapPixelBufferTexture (Shader)
- (GLhandleARB)loadShaderOfType:(GLenum)type;
@end




@implementation HapPixelBufferTexture
- (id)initWithContext:(CGLContextObj)context
{
	self = [super init];
	if (self)
	{
		decodedFrame = nil;
		cgl_ctx = CGLRetainContext(context);
	}
	return self;
}

- (void)dealloc
{
	if (texture != 0) glDeleteTextures(1, &texture);
	if (shader != NULL) glDeleteObjectARB(shader);
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
	
	if (decodedFrame == NULL)
	{
		NSLog(@"\t\terr: decodedFrame nil, bailing. %s",__func__);
		valid = NO;
		return;
	}
	
	NSSize		tmpSize = [decodedFrame imgSize];
	width = tmpSize.width;
	height = tmpSize.height;
	
	tmpSize = [decodedFrame dxtImgSize];
	GLuint roundedWidth = tmpSize.width;
	GLuint roundedHeight = tmpSize.height;
	if (roundedWidth % 4 != 0 || roundedHeight % 4 != 0)
	{
		NSLog(@"\t\terr: width isn't a multiple of 4, bailing. %s",__func__);
		valid = NO;
		return;
	}
	
	OSType newPixelFormat = [decodedFrame dxtPixelFormat];
	
	GLenum newInternalFormat;
	unsigned int bitsPerPixel;
	
	switch (newPixelFormat) {
		case kHapCVPixelFormat_RGB_DXT1:
			newInternalFormat = GL_COMPRESSED_RGB_S3TC_DXT1_EXT;
			bitsPerPixel = 4;
			break;
		case kHapCVPixelFormat_RGBA_DXT5:
		case kHapCVPixelFormat_YCoCg_DXT5:
			newInternalFormat = GL_COMPRESSED_RGBA_S3TC_DXT5_EXT;
			bitsPerPixel = 8;
			break;
		default:
			// we don't support non-DXT pixel buffers
			NSLog(@"\t\terr: unrecognized pixel format in %s",__func__);
			valid = NO;
			return;
			break;
	}
	
	// Ignore the value for CVPixelBufferGetBytesPerRow()
	
	size_t bytesPerRow = (roundedWidth * bitsPerPixel) / 8;
	GLsizei newDataLength = bytesPerRow * roundedHeight; // usually not the full length of the buffer
	
	size_t actualBufferSize = [decodedFrame dxtDataSize];
	
	// Check the buffer is as large as we expect it to be
	
	if (newDataLength > actualBufferSize)
	{
		NSLog(@"\t\terr: new data length incorrect, %d vs %ld in %s",newDataLength,actualBufferSize,__func__);
		valid = NO;
		return;
	}
	
	// If we got this far we're good to go
	
	valid = YES;
	
	glPushAttrib(GL_ENABLE_BIT | GL_TEXTURE_BIT);
	glPushClientAttrib(GL_CLIENT_PIXEL_STORE_BIT);
	glEnable(GL_TEXTURE_2D);
			
	GLvoid *baseAddress = [decodedFrame dxtData];
	
	// Create a new texture if our current one isn't adequate
	
	if (texture == 0 || roundedWidth > backingWidth || roundedHeight > backingHeight || newInternalFormat != internalFormat)
	{
		if (texture != 0)
		{
			glDeleteTextures(1, &texture);
		}
		
		glGenTextures(1, &texture);
		
		glBindTexture(GL_TEXTURE_2D, texture);
		
		// On NVIDIA hardware there is a massive slowdown if DXT textures aren't POT-dimensioned, so we use POT-dimensioned backing
		//	NOTE: NEEDS TESTING. this used to be the case- but this API is only available on 10.10+, so this may have been fixed.
		backingWidth = 1;
		while (backingWidth < roundedWidth) backingWidth <<= 1;
		
		backingHeight = 1;
		while (backingHeight < roundedHeight) backingHeight <<= 1;
		
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_STORAGE_HINT_APPLE , GL_STORAGE_SHARED_APPLE);
		
		// We allocate the texture with no pixel data, then use CompressedTexSubImage to update the content region
		
		glTexImage2D(GL_TEXTURE_2D, 0, newInternalFormat, backingWidth, backingHeight, 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, NULL);		  
		
		internalFormat = newInternalFormat;
	}
	else
	{
		glBindTexture(GL_TEXTURE_2D, texture);
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
}
- (HapDecoderFrame *) decodedFrame	{
	return decodedFrame;
}

- (GLuint)textureName
{
	if (valid) return texture;
	else return 0;
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

- (GLuint)textureWidth
{
	if (valid) return backingWidth;
	else return 0;
}

- (GLuint)textureHeight
{
	if (valid) return backingHeight;
	else return 0;
}

- (GLhandleARB)shaderProgramObject
{
	if (valid && decodedFrame!=nil && [decodedFrame dxtPixelFormat] == kHapCVPixelFormat_YCoCg_DXT5)
	{
		if (shader == NULL)
		{
			GLhandleARB vert = [self loadShaderOfType:GL_VERTEX_SHADER_ARB];
			GLhandleARB frag = [self loadShaderOfType:GL_FRAGMENT_SHADER_ARB];
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
			}
			if (frag) glDeleteObjectARB(frag);
			if (vert) glDeleteObjectARB(vert);
		}
		return shader;
	}
	return NULL;
}

- (GLhandleARB)loadShaderOfType:(GLenum)type
{
	NSString *extension = (type == GL_VERTEX_SHADER_ARB ? @"vert" : @"frag");
	
	NSString  *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"ScaledCoCgYToRGBA"
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
