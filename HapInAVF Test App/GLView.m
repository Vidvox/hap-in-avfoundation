/*
 GLView.m
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

#import "GLView.h"
#import <OpenGL/CGLMacro.h>

@implementation GLView

- (void) drawRect:(NSRect)r
{
    [self drawTexture:0 sized:NSMakeSize(0, 0) flipped:NO];
}

- (void) drawTexture:(GLuint)t sized:(NSSize)s flipped:(BOOL)f
{
    [self drawTexture:t target:GL_TEXTURE_RECTANGLE_ARB imageSize:s textureSize:s flipped:f usingShader:NULL];
}

- (void)reshape
{
    needsReshape = YES;
}

- (void)update
{
    CGLLockContext([[self openGLContext] CGLContextObj]);
    [super update];
    CGLUnlockContext([[self openGLContext] CGLContextObj]);
}

- (void) drawTexture:(GLuint)texture target:(GLenum)target imageSize:(NSSize)imageSize textureSize:(NSSize)textureSize flipped:(BOOL)isFlipped usingShader:(GLhandleARB)shader
{
    CGLContextObj cgl_ctx = [[self openGLContext] CGLContextObj];
    
    CGLLockContext(cgl_ctx);
    
    NSRect bounds = self.bounds;
    
    if (needsReshape)
    {
        glEnableClientState(GL_VERTEX_ARRAY);
        glEnableClientState(GL_TEXTURE_COORD_ARRAY);
        glDisable(GL_DEPTH_TEST);
        glDisable(GL_BLEND);
        glHint(GL_CLIP_VOLUME_CLIPPING_HINT_EXT, GL_FASTEST);

        glMatrixMode(GL_TEXTURE);
        glLoadIdentity();
        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();
        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        glViewport(0, 0, (GLsizei) bounds.size.width, (GLsizei) bounds.size.height);
        glOrtho(bounds.origin.x, bounds.origin.x+bounds.size.width, bounds.origin.y, bounds.origin.y+bounds.size.height, -1.0, 1.0);
        
        glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);
        
        needsReshape = NO;
    }
    if (!NSEqualSizes(imageSize, bounds.size))
    {
        // clear the view if the texture won't fill it
        glClearColor(0.0,0.0,0.0,0.0);
        glClear(GL_COLOR_BUFFER_BIT);
    }
    if (texture != 0 && !NSEqualSizes(imageSize, NSZeroSize) && !NSEqualSizes(textureSize, NSZeroSize))
    {
        glEnable(target);
        
        NSRect destRect = NSMakeRect(0,0,0,0);
        double bAspect = bounds.size.width/bounds.size.height;
        double aAspect = imageSize.width/imageSize.height;
        
        // if the rect i'm trying to fit stuff *into* is wider than the rect i'm resizing
        if (bAspect > aAspect)
        {
            destRect.size.height = bounds.size.height;
            destRect.size.width = destRect.size.height * aAspect;
        }
        // else if the rect i'm resizing is wider than the rect it's going into
        else if (bAspect < aAspect)
        {
            destRect.size.width = bounds.size.width;
            destRect.size.height = destRect.size.width / aAspect;
        }
        else
        {
            destRect.size.width = bounds.size.width;
            destRect.size.height = bounds.size.height;
        }
        destRect.origin.x = (bounds.size.width-destRect.size.width)/2.0+bounds.origin.x;
        destRect.origin.y = (bounds.size.height-destRect.size.height)/2.0+bounds.origin.y;
        
        GLfloat vertices[] =
        {
            destRect.origin.x,                          destRect.origin.y,
            destRect.origin.x+destRect.size.width,      destRect.origin.y,
            destRect.origin.x + destRect.size.width,    destRect.origin.y + destRect.size.height,
            destRect.origin.x,                          destRect.origin.y + destRect.size.height,
        };
        
        GLfloat texCoords[] =
        {
            0.0,        (isFlipped ? imageSize.height : 0.0),
            imageSize.width,   (isFlipped ? imageSize.height : 0.0),
            imageSize.width,   (isFlipped ? 0.0 : imageSize.height),
            0.0,        (isFlipped ? 0.0 : imageSize.height)
        };
        
        if (target == GL_TEXTURE_2D)
        {
            texCoords[1] /= (float)textureSize.height;
            texCoords[3] /= (float)textureSize.height;
            texCoords[5] /= (float)textureSize.height;
            texCoords[7] /= (float)textureSize.height;
            texCoords[2] /= (float)textureSize.width;
            texCoords[4] /= (float)textureSize.width;
        }
        
        glBindTexture(target,texture);
        
        glVertexPointer(2,GL_FLOAT,0,vertices);
        glTexCoordPointer(2,GL_FLOAT,0,texCoords);
        
        if (shader != NULL)
        {
            glUseProgramObjectARB(shader);
        }
        glDrawArrays(GL_QUADS,0,4);
        
        if (shader != NULL)
        {
            glUseProgramObjectARB(NULL);
        }
        glBindTexture(target,0);
        
        glDisable(target);
    }
    glFlush();
    
    CGLUnlockContext(cgl_ctx);
}

@end
