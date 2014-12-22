HapInAVFoundation Framework
==========

Hap is a video codec for fast decompression on modern graphics hardware. This is the home of the HapInAVFoundation framework. For general information about Hap, see [the Hap project][1].

The HapInAVFoundation framework supports encoding and decoding Hap video. Unlike the QuickTime codec, the HapInAVFoundation framework will only decode to S3TC/DXT frames suitable for upload to graphics hardware at this time.  If requested, decoding to RGB(A) pixel formats can be added.  Encoding RGB(A) frames is supported.  For the most part, this is a port of the hap quicktime codec.

Sample code for a test application ("HapInAVF Test App") that demonstrates the use of this framework for accelerated playback is included.

Download
====

A compiled version of the framework can be downloaded from the [Releases](https://github.com/Vidvox/hap-in-avfoundation/releases/latest) page.

Requires at minimum MacOS 10.10 Yosemite.

Using the HapInAVFoundation.framework
====

The general idea is to either download or compile the framework, add the framework to your XCode project so you may link against it, and then set up a build phase to copy the framework into your application bundle.  This is fairly important: most of the time when you link against a framework, the framework is expected to be installed on your OS.  HapInAVFoundation is different: your application will include a compiled copy of the framework.  Here's the exact procedure:

If you downloaded a compiled framework
--------------------------------------

  1.  Unzip the framework, add it to your source tree, and then drag the framework into your xcode project file's workspace.
  2.  Locate the "Build Phases" section for your project/application's target.
  3.  Add the HapInAVFoundation framework to the "Link Binary with Libraries" section.
  4.  Create a new "Copy Files" build phase, set its destination to the "Frameworks" folder, and add the HapInAVFoundation framework to this build phase- the goal is to copy the framework you need into the "Frameworks" folder inside your app package.
  5.  Switch to the "Build Settings" section of your project's target, locate the "Runpath Search Paths" settings, and make sure that the following paths exist: "@loader_path/../Frameworks" and "@executable_path/../Frameworks".

If you're compiling from source
-------------------------------  

  1.  In XCode, close the HapInAVFoundation project (if it is open), and then open your project.
  2.  In the Finder, drag "HapInAVFoundation.xcodeproj" into your project's workspace.
  3.  Switch back to XCode, and locate the "Build Phases" section for your project/application's target.
  4.  Add a dependency for the "HapInAVFoundation" framework.  This will ensure that the framework gets compiled before your project, so there won't be any missing dependencies.
  5.  Add the HapInAVFoundation framework to the "Link Binary with Libraries" section.
  6.  Create a new "Copy Files" build phase, set its destination to the "Frameworks" folder, and add the HapInAVFoundation framework to this build phase- the goal is to copy the framework you need into the "Frameworks" folder inside your app package.
  7.  Switch to the "Build Settings" section of your project's target, locate the "Runpath Search Paths" settings, and make sure that the following paths exist: "@loader_path/../Frameworks" and "@executable_path/../Frameworks".
  8.  That's it- you're done now.  You can import/include objects from the framework in your source just as you normally would.

Documentation
===

[Documentation for this framework can be found here.](http://vidvox.net/rays_oddsnends/HapInAVFoundation_doc/html/index.html)  The header files are also commented extensively, and the included sample application demonstrates the use of the framework to play back Hap video to GL textures.

Open-Source
====

The Hap codec project is open-source, licensed under a [FreeBSD License][2], meaning you can use it in your commercial or non-commercial applications free of charge.  The hap project was originally written by [Tom Butterworth][3] and commissioned by [VIDVOX][4], 2012.

[1]: http://github.com/vidvox/hap
[2]: http://github.com/vidvox/hap-in-avfoundation/blob/master/LICENSE
[3]: http://kriss.cx/tom
[4]: http://www.vidvox.net
