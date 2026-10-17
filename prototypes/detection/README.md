# Detection probe (#12), throwaway

A small app that shows, live, whether the camera is in use, the microphone is in use, a video is playing and an app is in full screen, and what each reading is based on. It lives on this never-merged branch. The findings are in `docs/prototypes/suppression-detection.md`.

It reads everything about once a second, with no permission: CoreMediaIO for the camera, CoreAudio for the microphone, IOKit's power assertions for video, and CoreGraphics' window list for full screen. Its `Info.plist` has no camera or microphone usage description, so if anything in it touched a device, macOS would stop it rather than ask.

## Build

```bash
prototypes/detection/build.sh
```

It builds `prototypes/detection/.build/DetectionProbe.app` with `swiftc` only (no Xcode project, no `xcodebuild`), and signs it ad hoc. Pass a folder to build somewhere else. To build it without leaving `main` in Lucas's folder, from a worktree of this branch:

```bash
git fetch origin
git worktree add --detach /tmp/ficha-12 origin/12-detection-prototype
/tmp/ficha-12/prototypes/detection/build.sh
```

Quit the probe before building it again: re-signing it under a running copy changes what macOS says about that copy's permissions.

## Run it (Lucas)

```bash
open prototypes/detection/.build/DetectionProbe.app
```

A small floating window shows up in the top-right corner, on every Space and over full-screen apps. It has no Dock icon; "Quit" or its close button quits it. Each signal shows a red dot when it's on, and under it what it's based on:

- **Camera**: each CoreMediaIO video device and whether it runs somewhere, and AVFoundation's view of the same devices, to compare.
- **Microphone**: each CoreAudio input device and whether it runs somewhere; which processes run input, from CoreAudio's process objects; and AVFoundation's view, to compare.
- **Video**: the assertions that keep the display awake, and who holds them. Under them, for comparison, the apps' and audio's assertions that only keep the Mac awake, and which processes play sound.
- **Full screen**: the frontmost app, and for each screen its size, its camera housing (the notch), whether its menu bar is on screen, and the frontmost normal window that spans it, with how far below the screen's top it starts.
- **Permissions**: who launched the probe, and whether it has Accessibility, Screen Recording, Input Monitoring, the camera and the microphone. Launched with `open`, the probe should have none.

Every change is appended to `~/Library/Logs/FichaDetectionProbe.log`, one JSON line each, with the time, what changed, a one-line summary and all the readings. Quitting and opening the probe again keeps adding to the same file. It holds app names, process IDs and window sizes, never window titles, and stays on the Mac.

## The trial

With the probe open, about 20 seconds per step, in this order, so the log's times tell the steps apart:

1. Check its "Permissions" section: launched by launchd, everything false or "not determined".
2. Join a call with the camera and the microphone on (Meet in Chrome, and FaceTime or Zoom if you can). Turn the camera off, then mute, then leave.
3. Dictate a sentence with Wispr Flow or the Claude app.
4. Play a YouTube video in Safari, pause it, play it again, then muted, then switch to another tab while it plays. The same in Chrome. Then press YouTube's full-screen button, and leave full screen.
5. Play music (Music, Spotify, or YouTube Music in a background tab).
6. Put an app in full screen with its green button, hover at the top of the screen to show the menu bar, then leave full screen. Then zoom a window (double-click its title bar) without going full screen.
7. With a second screen: an app in full screen on one screen while you work on the other, both ways.
8. Quit the probe, and ask Claude to read `~/Library/Logs/FichaDetectionProbe.log`.

## For agents

Never `open` the probe while Lucas is using the Mac: launching an app activates it and takes his keyboard. These two show no window:

```bash
APP=prototypes/detection/.build/DetectionProbe.app/Contents/MacOS/DetectionProbe
"$APP" --once            # the current readings as JSON, then exits
"$APP" --watch 30        # each change as a JSON line on standard output, for 30 seconds
```

A probe started from a shell gets the shell's app's permissions (Claude's shell had Accessibility, Input Monitoring and Screen Recording on 2026-10-17), so only a probe launched with `open` tells which permissions the readings need.

To read the log after a trial, one line per change:

```bash
jq -r '"\(.at[11:19]) \(.changed | join(",")): \(.summary)"' ~/Library/Logs/FichaDetectionProbe.log
```
