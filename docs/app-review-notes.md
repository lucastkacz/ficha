# Notes for App Review

What Ficha tells Apple's App Review about the entitlements it claims, in App Store Connect's App Review Information, under Notes, when a version is submitted. The text under each heading below goes there as it is, in English. How it gets there is #310's to decide, with `make upload`.

## The camera entitlement

Ficha is a menu-bar flashcard app: every so often, it shows a small panel with a few cards to review. It holds that panel back while the user is in a meeting or a video call, so that it never interrupts one.

To tell whether a meeting is on, Ficha reads, every few seconds, whether any app on the Mac is running a camera: Core Media I/O's `kCMIODevicePropertyDeviceIsRunningSomewhere` property of each video device. In the App Sandbox, that property says no camera is running unless the app holds `com.apple.security.device.camera`, so Ficha claims that entitlement for this reading alone.

Ficha never captures video or photos, never opens or starts a camera, and never asks for camera access: it has no camera usage description, and no permission prompt ever appears. It reads whether a microphone is running the same way, through Core Audio's `kAudioDevicePropertyDeviceIsRunningSomewhere`, which needs no entitlement in the sandbox, so Ficha doesn't claim `com.apple.security.device.audio-input`.

The user sees what these readings say in Ficha's Diagnostics window, from its menu-bar menu.
