# Focus prototype tools (#10), throwaway

What an agent used to check, on Lucas's Mac, where the keyboard goes when the focus prototype's panel (`App/FocusPrototype.swift`) shows up and closes. They live on this never-merged branch, with the prototype. The findings are in `docs/prototypes/review-panel-focus.md` on `main`.

They show windows on Lucas's screen, move the pointer and take the keyboard for a few seconds, so ask him to keep off the Mac first. `drive` posts clicks and keys with `CGEvent`, which needs Accessibility; Claude's shell had it. Before each click or key, it checks that the panel is the topmost window under the point and that the given app is frontmost, so nothing lands in another app.

- `Probe/`: an app with one window and a text field, standing for the app Lucas types in. It logs to a file when its window becomes or stops being key, and every key it gets.
- `drive.swift`: waits for the panel, clicks "Dar vuelta" (`button`, or `button-stay` to leave the pointer there) or the text under the card (`readout`), then presses keys: `1`, `2`, `3`, `space`, `esc`, `return`, `x` or `f19`, which types nothing.
- `text-of.swift`: prints the text of TextEdit's focused text area.
- `capture.swift`: captures only the panel's window to a PNG.

## Build

```bash
TOOLS=<a scratch folder>
mkdir -p "$TOOLS/Probe.app/Contents/MacOS"
cp prototypes/focus/Probe/Info.plist "$TOOLS/Probe.app/Contents/"
swiftc -O -swift-version 5 prototypes/focus/Probe/main.swift -o "$TOOLS/Probe.app/Contents/MacOS/Probe"
for tool in drive text-of capture; do swiftc -O -swift-version 5 "prototypes/focus/$tool.swift" -o "$TOOLS/$tool"; done
xcodegen generate --quiet
xcodebuild -project Ficha.xcodeproj -scheme Ficha -destination 'platform=macOS,arch=arm64' -derivedDataPath "$TOOLS/DerivedData" -quiet -configuration Debug build
```

The scratch DerivedData leaves the Ficha Dev that Lucas runs as it is.

## Run a trial

```bash
APP="$TOOLS/DerivedData/Build/Products/Debug/Ficha Dev.app"
/usr/bin/log stream --level info --style compact --timeout 13 \
  --predicate 'subsystem == "com.lucastkacz.ficha" AND category == "focus-prototype"' > "$TOOLS/ficha.log" &
open -n "$TOOLS/Probe.app" --args "$TOOLS/probe.log" 13
open -n --env CFFIXED_USER_HOME="$TOOLS/home" "$APP" --args -FocusPrototype never -FocusPrototypeReturn nothing
"$TOOLS/drive" "$TOOLS/DerivedData" com.lucastkacz.ficha.focus-probe readout f19 esc f19
wait
```

- `-FocusPrototype <never|afterIdle|always>` runs one trial 2 seconds after launch, closes the panel 3 seconds after it shows, and quits 4 seconds after that.
- `-FocusPrototypeReturn <nothing|activateFront|hide>` picks how the panel gives the keyboard back.
- `CFFIXED_USER_HOME` keeps the run out of Ficha Dev's data and preferences.
- Read `probe.log` and `ficha.log` side by side, by time: the probe's window should become key as the panel closes, and the last F19 should reach the probe.
- For TextEdit instead, open a scratch text file with `open -a TextEdit <file>`, pass `com.apple.TextEdit` to `drive` with `x` among the keys, and check where the x's went with `text-of`.
