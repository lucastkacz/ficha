#!/bin/bash
# Builds the detection probe (#12) into prototypes/detection/.build/DetectionProbe.app,
# or into the folder given as the first argument. Only swiftc: no Xcode project.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="${1:-$here/.build}"
app="$out/DetectionProbe.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$here/Probe/Info.plist" "$app/Contents/"
swiftc -O -swift-version 6 -target arm64-apple-macos26.0 \
  "$here/Probe/main.swift" -o "$app/Contents/MacOS/DetectionProbe"
# An ad hoc signature that seals the Info.plist, so macOS sees one app with its bundle ID.
codesign --force --sign - "$app" 2>/dev/null

echo "$app"
