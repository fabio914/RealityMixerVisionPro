<img src="Images/rounded.png" width="100" />

# Reality Mixer Pro <br/> *Mixed Reality Capture app for the Vision Pro*

Reality Mixer lets you use your iPhone or iPad to display and record Vision Pro apps in Mixed Reality.

In other words, you can use your iPhone or iPad as a spectator camera.

This app is similar to the [Reality Mixer app](http://github.com/fabio914/RealityMixer) (compatible with the Meta Quest 2/3/Pro) and the [Reality Mixer JS](http://github.com/fabio914/reality-mixer-js/) (compatible with Three.js and WebXR) apps.

Click on the images below to watch the video:

<a href="https://www.youtube.com/watch?v=KzSbWwRCRrg"><img src="Images/video2.jpg" width="400"/></a>

<a href="https://www.youtube.com/watch?v=tPH5eTK-bGM"><img src="Images/video.jpg" width="400"/></a>

Follow us on [Twitter](https://twitter.com/reality_mixer) for more updates!

## Attention

This is still a very early prototype. This repository contains two apps: a Vision Pro app that has the necessary code to generate and stream the Mixed Reality video and an iPhone app that's capable of receiving and displaying this video.

I'm planning to create a separate visionOS Framework with the Mixed Reality code so people can integrate this into their own visionOS apps that use RealityKit.

## How to use it?

Requirements: 
 - iPhone that supports Person Segmentation with Depth running iOS 18.
 - Vision Pro running visionOS 2.
 - Xcode 16.0.

1. Build and install the iOS and visionOS apps with Xcode 16 (or newer). 

2. First run the visionOS app, then launch the iOS app and type the local IP address of your Vision Pro (assuming that both the iPhone and the Vision Pro are connected to the same local network) and then tap on "Connect".

3. Look at the image displayed on the iPhone screen with the Vision Pro so the Vision Pro can detect the position and orientation of the camera. After that, tap on the "Calibration image" button to hide this image.

4. Interact with the demo app with the Vision Pro. The app on the iPhone should now display the Mixed Reality video.

## Credits

Developed by [Fabio Dela Antonio](http://github.com/fabio914).

This project uses [SwiftSocket](https://github.com/swiftsocket/SwiftSocket) to handle the TCP connection with the Vision Pro, Apple's VideoToolbox to encode and decode the video stream, and ARKit and RealktyKit. Its video decoder is based on [zerdzhong's SwiftH264Demo](https://github.com/zerdzhong/SwfitH264Demo).

Special thanks to [Yasuhito Nagatomo](https://twitter.com/AtarayoSD) for sharing the `RealityRenderer` example on Twitter.
