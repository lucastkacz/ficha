# Detecting meetings, videos and full-screen apps: prototype findings

What #12's prototype found about telling, on macOS 26, that Lucas is in a meeting (the camera or the microphone is in use), watching a video or using an app in full screen, for the suppressions ticket (#13). Measured on macOS 26.3.1 on 2026-10-17, by an agent, on Lucas's MacBook Pro with only its built-in, notched screen. Lucas's own trial is still to come; until then, some readings are verified and some aren't, and each section says which.

The prototype's code is on the branch [`12-detection-prototype`](https://github.com/lucastkacz/ficha/tree/12-detection-prototype), which is never merged, in `prototypes/detection/`.

## The prototype

A small standalone app, `DetectionProbe.app`, built with `swiftc` from one file and an `Info.plist`, outside `App/` and the package. Launched with `open`, it shows a floating window, on every Space and over full-screen apps, with the four signals and what each is based on, read about once a second. Each change goes to `~/Library/Logs/FichaDetectionProbe.log` as one JSON line, so a trial can be read afterwards. For agents, `--once` prints the current readings as JSON and `--watch <seconds>` prints each change, neither with a window. Its README says how to build and run it.

Its `Info.plist` has no camera or microphone usage description: if anything in it touched a device, macOS would stop the probe instead of asking. Nothing it calls asks for a permission.

## What works, and how

**Camera: CoreMediaIO.** Every video device CoreMediaIO lists (`kCMIOHardwarePropertyDevices` on the system object) has `kCMIODevicePropertyDeviceIsRunningSomewhere`, "1 means that the CMIODevice is running in at least one process on the system" (`CoreMediaIO/CMIOHardwareDevice.h`). The camera is in use when any device runs somewhere. On Lucas's Mac it lists the built-in camera and its Desk View camera, and an iPhone's camera and Desk View camera through Continuity. All four read idle while no app used a camera. **Not verified:** a device reading "running", since nothing used a camera during the agent's tests and the agent may not open one.

The probe also shows AVFoundation's `AVCaptureDevice.isInUseByAnotherApplication` for the same devices, which is documented in more words (`AVFoundation/AVCaptureDevice.h`: "whether the device represented by the receiver is in use by another application", observable with KVO). For the microphone it was wrong (see below), so CoreMediaIO stays the candidate until the trial compares them.

**Microphone: CoreAudio's devices.** Every device with input streams (`kAudioDevicePropertyStreams` in the input scope is non-empty) has `kAudioDevicePropertyDeviceIsRunningSomewhere`, "1 means that the AudioDevice is running in at least one process on the system" (`CoreAudio/AudioHardware.h`). The microphone is in use when any input device that isn't an aggregate runs somewhere. Aggregates (`kAudioDevicePropertyTransportType` is `kAudioDeviceTransportTypeAggregate`, `'grup'`, or the old `kAudioDeviceTransportTypeAutoAggregate`, `'fgrp'`) are left out because they're made of other devices, which are read on their own. None was in the list on Lucas's Mac. Output-only devices, like the speakers, have no input streams, so they're never in the list. Lucas's Mac lists the built-in microphone (`bltn`) and an iPhone's (`ccwd`, Continuity). **Verified:** while the Claude app used the microphone for voice input, the built-in microphone read running, and it went back to idle when the Claude app stopped.

To say who uses it, CoreAudio's process objects help: `kAudioHardwarePropertyProcessObjectList`, then for each one `kAudioProcessPropertyPID`, `kAudioProcessPropertyIsRunningInput` and `kAudioProcessPropertyDevices` in the input scope (`CoreAudio/AudioHardware.h`). They named "Claude Helper" (`com.anthropic.claudefordesktop.helper`) on the MacBook Pro Microphone. They can't be the signal on their own, though: a system daemon runs input whenever any sound plays (see "Gotchas").

**Video: power assertions that keep the display on.** Our own reading: there's no public API for what other apps play, so a video is taken to be whatever keeps the display awake. `IOPMCopyAssertionsByProcess` (`IOKit/pwr_mgt/IOPMLib.h`) returns every process's power assertions. A video is playing when a process other than Ficha holds one whose type (`kIOPMAssertionTypeKey`) is `PreventUserIdleDisplaySleep` or its old name, `NoDisplaySleepAssertion`, at a level other than off. The header's own words for that type: it "prevents the display from dimming automatically", which is what a player needs and a music app doesn't. **Verified:** `caffeinate -d -t 4` created one, named "caffeinate command-line tool" and held by `caffeinate`; the probe saw it within the second, and saw it go within a second of its end.

Audio-only playback creates a different type, `PreventUserIdleSystemSleep`, which keeps the Mac awake but lets the display sleep. **Verified:** `afplay` playing a system sound got one from `coreaudiod` for `afplay`, with the resources "audio-out BuiltInSpeakerDevice", and no display assertion, so the video signal stayed off. The Claude app, which is built on Chromium like Chrome, held one more of its own while it played sound, named "Playing audio", and no display assertion. **Not verified:** what Safari, Chrome, YouTube and music apps create; that's the trial's main question for this signal.

**Full screen: the window list.** `CGWindowListCopyWindowInfo` with `kCGWindowListOptionOnScreenOnly` (`CoreGraphics/CGWindow.h`) lists every window on screen, front to back, with its layer (`kCGWindowLayer`), bounds (`kCGWindowBounds`, in points, with the origin at the top-left of the main screen) and owner (`kCGWindowOwnerPID`, `kCGWindowOwnerName`). The probe reads no window names (`kCGWindowName`), which need Screen Recording. For each screen (`NSScreen.screens`, matched to `CGDisplayBounds` through `NSScreenNumber`), it finds:

- the frontmost window on the normal layer (0), owned by a regular app (`NSRunningApplication.activationPolicy == .regular`), that spans the screen's whole width down to its bottom, and how far below the screen's top it starts (the "top gap");
- whether the menu bar's window is on screen there: a window at `CGWindowLevelForKey(.mainMenuWindow)` (24) at the screen's top;
- the camera housing's height, from `NSScreen.safeAreaInsets.top`.

Our own rule, from the geometry: a screen shows a full-screen window when that window starts at the very top, or when it starts within the camera housing's height (with a point of slack) while no menu bar is on screen there. An app is in full screen when such a window belongs to the frontmost app (`NSWorkspace.frontmostApplication`). The probe also notes it for any app, for a second screen.

**Verified:** only the case that isn't full screen. On Lucas's built-in screen (1512 × 982 points, camera housing 32 points), zoomed windows with the Dock hidden span 1512 × 949 from 33 points down, right under the 33-point menu bar window, and the probe says no. **Not verified:** a real full-screen app. Whether macOS puts it at the very top or under the camera housing, and whether the menu bar's window really leaves the list, is the trial's main question for this signal. The rule above covers both.

## Permissions

| Signal | API | Permission |
|---|---|---|
| Camera | CoreMediaIO, `kCMIODevicePropertyDeviceIsRunningSomewhere` | None to read it idle. Verified. A running camera wasn't seen. |
| Microphone | CoreAudio, `kAudioDevicePropertyDeviceIsRunningSomewhere` and the process objects | None. Verified. |
| Video | IOKit, `IOPMCopyAssertionsByProcess` | None: the same call `pmset -g assertions` makes, and it isn't covered by any privacy setting. Verified. |
| Full screen | CoreGraphics, `CGWindowListCopyWindowInfo`; AppKit, `NSScreen` and `NSWorkspace` | Layers, bounds and owners: none expected, since macOS 10.15 hides only other apps' window names without Screen Recording (WWDC 2019, "Advances in macOS Security"). Names aren't read. Not verified from a clean process. |

How far that's checked: a process started from a shell gets the permissions of the app that runs the shell. On 2026-10-17, Claude's shell had Accessibility, Input Monitoring and Screen Recording, but camera and microphone were both "not determined". So the probe, run from that shell, read the cameras' and the microphones' state, and saw the microphone in use, with neither permission, which settles those two. It can't settle whether the window list needs Screen Recording: only the probe launched with `open`, which should have no permission at all, can. Its "Permissions" section shows which it has, and the trial's log keeps it.

## What we measured, and how

The agent ran the probe from the shell only, with `--once` and `--watch`, never with `open`, and never showed a window or took the keyboard.

- `--watch 16` while `caffeinate -d -t 4` ran, then four `afplay -v 0.03 /System/Library/Sounds/Submarine.aiff`: video on for the 4 seconds of `caffeinate`, then off throughout `afplay`; each `afplay` showed up as a process playing sound and in `coreaudiod`'s assertion for it.
- `--watch 240` while Lucas used the Mac: the Claude app's voice input turned the microphone on and off; its sound playback, and the power chime, showed up as sound only.
- `--once` several times, to read the devices, the screens and the windows.

`--once` takes about half a second, most of it starting up AVFoundation.

## What's still open for Lucas's trial

The trial runs the probe launched with `open`, with no permissions, through the steps in the probe's README ("The trial"), and its log answers these:

- **Permissions**: does the window list still give layers, bounds and owners without Screen Recording, and does every reading work with the "Permissions" section all false or "not determined"?
- **Camera**: does CoreMediaIO's reading turn on and off with a real call's camera, and does AVFoundation agree? And is a lingering camera power assertion (see "Gotchas") stale, or did CoreMediaIO miss a capture?
- **Microphone**: does a call turn it on, and muting in the call app turn it off or not? Does dictation turn it on, as the agent saw with the Claude app?
- **Video**: what do Safari and Chrome hold while a YouTube video plays, pauses, plays muted, plays in a background tab, and plays in full screen? What do music apps hold? Does anything hold a display assertion all day?
- **Full screen**: where does a full-screen window sit on the notched screen, does the menu bar's window leave the list, and what happens while the menu bar is shown by hovering at the top? With two screens: a full-screen app on one while Lucas works on the other.

## Gotchas

- **A system daemon runs input whenever sound plays.** `/usr/libexec/historicalaudiod` (launchd label `com.apple.audio.isolated.historicalaudiod`) starts audio input on a hidden device, "AOP Audio", through a private aggregate, as soon as anything plays sound, even a system sound, and stops when it ends. Its process object has an empty bundle ID and devices CoreAudio doesn't name (`kAudioObjectUnknown`). A process-level reading would call every song a meeting. The device-level reading doesn't see it: the built-in microphone stayed idle. What the daemon does isn't documented.
- **AVFoundation's `isInUseByAnotherApplication` said no while the microphone was in use**, twice, once from a fresh discovery session. Don't use it for the microphone.
- **A camera power assertion can outlast the camera.** A messaging app held a `PreventUserIdleSystemSleep` named "cameracaptured-idleSleepPreventionForBWFigCaptureDevice" for over 30 minutes while CoreMediaIO said no camera was running. Either the assertion was stale, or CoreMediaIO missed a capture; the trial compares them. Either way, power assertions aren't a camera signal.
- **Dictation uses the microphone.** Lucas dictates a lot, so a microphone-only suppression would hold appearances back while he dictates, and for 2 minutes after.
- **Anything that keeps the display awake counts as a video**: `caffeinate -d` (measured), and likely apps that keep the Mac awake on purpose, presentations and call apps (not measured).
- **The Dock can put a screen-sized window on the normal layer.** Once, while Lucas was switching apps, a window owned by the Dock covered the whole screen from its very top, on layer 0, and was gone when the agent looked again. Counting only regular apps' windows leaves it out.
- **On a notched screen, a zoomed window starts 33 points down**, under the menu bar, which is 1 point taller than the camera housing (32). Bounds alone can't tell it from a window placed under the camera housing; the menu bar's window can.
- **If the menu bar hides itself always** (System Settings, Control Center, "Automatically hide and show the menu bar"), a zoomed window may fill the screen and pass for full screen. Lucas's menu bar didn't hide on 2026-10-17.
- **Some assertion keys aren't in the public header.** `AssertType`, `AssertName` and `AssertLevel` are (`kIOPMAssertionTypeKey`, `kIOPMAssertionNameKey`, `kIOPMAssertionLevelKey`), and the owning process is the dictionary's key. `AssertionOnBehalfOfPID` (the process `coreaudiod` holds an assertion for) and `ResourcesUsed` aren't, so the probe only shows them.
- **Window names need Screen Recording.** Never rely on a window's name, and read only layers, bounds and owners.

## Better documented approaches, and why not

- **Camera**: AVFoundation's `isInUseByAnotherApplication` is the documented, higher-level way, but it was wrong for the microphone here; the trial compares it with CoreMediaIO for the camera.
- **Video**: there's no public API for what other apps play. `MediaRemote`, which Control Center's "Now Playing" uses, is private.
- **Full screen**: the Accessibility API's `AXFullScreen` attribute says it directly, but needs Accessibility. Spaces' types are private (`CGSCopyManagedDisplaySpaces`). `NSApplication.PresentationOptions` only covers Ficha's own app.

## For the suppressions ticket (#13)

- **Camera**: any CoreMediaIO device running somewhere, or AVFoundation's `isInUseByAnotherApplication` if the trial shows it agrees. Not seen running yet.
- **Microphone**: any CoreAudio input device other than an aggregate (`'grup'` or `'fgrp'`) running somewhere. Use the process objects only to name who, in Diagnostics, never to decide. Decide whether dictation should count.
- **Video**: any `PreventUserIdleDisplaySleep` or `NoDisplaySleepAssertion` assertion held by a process other than Ficha. The trial says whether browsers and players create it reliably and music apps don't.
- **Full screen**: the frontmost regular app's normal-layer window spanning a screen, starting at its very top, or under the camera housing while no menu bar is on screen there. The trial settles the notch and two screens.
- None is expected to need a permission, and the camera's and the microphone's readings are verified to need none. Whether the window list does without Screen Recording is the trial's to confirm; if it doesn't, full screen needs a decision in #13: Screen Recording for the window list, or Accessibility for `AXFullScreen`, or no full-screen suppression.
- A reading that fails says it doesn't know, not that nothing is in use (`CODING_STANDARDS.md`: never guess a default). The probe reads a failed call as idle, which is fine for a prototype only. Ficha never uses the camera or the microphone, so the device readings need no exclusion; the video and full-screen readings leave Ficha's processes out.
- They enter through a protocol the app implements (`CODING_STANDARDS.md`, "Layers"), as the appearances' idle time does, so the engine is tested with a fake.
- Our own suggestion: read the four signals when an appearance would show, and while one is held back, every few seconds, to see when the suppression ends. CoreAudio and CoreMediaIO have property listeners (`AudioObjectAddPropertyListenerBlock`, `CMIOObjectAddPropertyListenerBlock`), but with a 2-minute wait after a suppression ends, polling is enough and simpler.
- Diagnostics can show what the probe shows: which device runs, who holds the display assertion, and which window covers which screen.
