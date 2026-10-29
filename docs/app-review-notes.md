# Notes for App Review

What Ficha tells Apple's App Review about the entitlements it claims and the command-line tool it ships, in App Store Connect's App Review Information, under Notes. The text under each heading below goes there as it is, in English, pasted by Lucas when he submits a version for review: `make upload` sends builds to TestFlight's internal testers alone, which App Review doesn't see (#310).

## The camera entitlement

Ficha is a menu-bar flashcard app: every so often, it shows a small panel with a few cards to review. It holds that panel back while the user is in a meeting or a video call, so that it never interrupts one.

To tell whether a meeting is on, Ficha reads, every few seconds, whether any app on the Mac is running a camera: Core Media I/O's `kCMIODevicePropertyDeviceIsRunningSomewhere` property of each video device. In the App Sandbox, that property says no camera is running unless the app holds `com.apple.security.device.camera`, so Ficha claims that entitlement for this reading alone.

Ficha never captures video or photos, never opens or starts a camera, and never asks for camera access: it has no camera usage description, and no permission prompt ever appears. It reads whether a microphone is running the same way, through Core Audio's `kAudioDevicePropertyDeviceIsRunningSomewhere`, which needs no entitlement in the sandbox, so Ficha doesn't claim `com.apple.security.device.audio-input`.

The user sees what these readings say in Ficha's Diagnostics window, from its menu-bar menu.

## The command-line tool

Ficha ships a command-line tool, `ficha`, inside the app, at `Contents/Helpers/ficha`, always the same version as the app. From Terminal, the user captures ideas to turn into cards later, lists their cards, and turns their captures into cards, by hand or with an assistant they run in their own terminal. The user starts every run: the tool never runs on its own, and the app never launches it.

A terminal can't start a tool in its app's sandbox, so `ficha` runs in an App Sandbox of its own, with a bundle identifier of its own, `com.lucastkacz.ficha.cli`, in an Info.plist embedded in its binary. It holds two entitlements besides the sandbox: the app's App Group, whose folder holds the cards the tool and the app share, and `com.apple.security.files.downloads.read-only`, to read the images and sounds the user puts on cards from their Downloads folder alone. It holds no network entitlement, and it never asks for a permission.
