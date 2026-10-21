#!/bin/bash
# Takes the iPhone app's pictures, light and dark, on the screen it opens on:
# `make render-iphone`, which builds Ficha Dev for the simulator first and
# passes its path. The pictures come from an iPhone simulator of its own, the
# newest iPhone of the newest iOS the Mac has, which it boots without the
# Simulator app and deletes after them, so the simulators that other sessions
# and the Simulator app use stay as they were. The commands are simctl's,
# which `xcrun simctl help` documents; a simulator of its own for each run is
# our own.

set -euo pipefail

usage='Usage: make render-iphone ARGS="--out <path>", which saves <path>-light.png and <path>-dark.png, or .build/render/iphone-light.png and iphone-dark.png without it.'
app=$1
shift
out=.build/render/iphone
while (($# > 0)); do
  case $1 in
    --out)
      (($# > 1)) || {
        echo "--out needs a path. $usage" >&2
        exit 1
      }
      out=$2
      shift 2
      ;;
    *)
      echo "There's no option $1. $usage" >&2
      exit 1
      ;;
  esac
done
if [[ $out == *.png ]]; then
  echo "--out takes a path without .png: the tool adds -light.png and -dark.png to it. $usage" >&2
  exit 1
fi

# What the app reads and says when the tool opens it, as iPhone/Rendering.swift
# writes them.
launch_argument=-FichaRendering
screen_is_up="The screen is up"

bundle=$(plutil -extract CFBundleIdentifier raw "$app/Info.plist" 2>/dev/null) || {
  echo "There's no app at $app: build it with make build-iphone." >&2
  exit 1
}

# The newest iOS the Mac has, and the first iPhone it lists, its newest.
newest=$(xcrun simctl list runtimes available --json | jq -r '
  [.runtimes[] | select(.platform == "iOS")]
  | max_by(.version | split(".") | map(tonumber))
  | select(. != null)
  | (first(.supportedDeviceTypes[] | select(.productFamily == "iPhone")) // {}) as $iphone
  | [.identifier, .version, $iphone.identifier, $iphone.name]
  | @tsv')
IFS=$'\t' read -r runtime version iphone iphone_name <<<"$newest" || true
if [[ -z ${iphone:-} ]]; then
  echo "This Mac has no iOS simulator for an iPhone: install the iOS platform of Xcode in Xcode › Settings › Components." >&2
  exit 1
fi

# The tool's own files, the app's standard output among them. They go under the
# repository's .build, since the simulator has /tmp and /var/folders of its
# own: simctl would write the app's output there.
mkdir -p .build/render
scratch=$(mktemp -d "$PWD/.build/render/iphone.XXXXXX")
device=""
cleanup() {
  if [[ -n $device ]]; then
    xcrun simctl shutdown "$device" 2>/dev/null || true
    xcrun simctl delete "$device" ||
      echo "Couldn't delete the simulator make render-iphone made: delete it with xcrun simctl delete $device." >&2
  fi
  rm -rf "$scratch"
}
trap cleanup EXIT

# Saves the simulator's screen as the PNG $1. simctl says what it did on
# standard error, as it says what went wrong, so that's shown only then.
screenshot() {
  local said
  said=$(xcrun simctl io "$device" screenshot "$1" 2>&1) || {
    echo "$said" >&2
    return 1
  }
}

# Stops without the $1 picture, for the reason $2, and keeps what the screen
# showed and what the app logged, since the simulator goes with the tool.
give_up() {
  screenshot "$out-$1-failed.png" || true
  xcrun simctl spawn "$device" log show --last 5m --info --predicate "process == \"$(basename "$app" .app)\"" \
    >"$out-$1-failed.log" 2>&1 || true
  echo "$2, so there's no $1 picture: $out-$1-failed.png shows the screen then, and $out-$1-failed.log what the app logged." >&2
  exit 1
}

# Opens the app and takes the $1 picture once the app says its screen is up,
# and the screen then stays the same for more than seven seconds: before that,
# a picture catches the launch screen, the animation that opens the app, the
# home indicator, which hides a moment later, or a notification's banner, which
# stays about six seconds. A new simulator shows one, "Ready for Apple
# Intelligence", at some point in its first half minute. SECONDS counts whole
# seconds, so 8 of them are more than seven.
take_picture() {
  local said=$scratch/$1.txt shot=$scratch/shot.png last=$scratch/last.png still_since deadline
  xcrun simctl launch --terminate-running-process --stdout="$said" "$device" "$bundle" "$launch_argument" >/dev/null
  deadline=$((SECONDS + 60))
  until grep -qxF "$screen_is_up" "$said" 2>/dev/null; do
    ((SECONDS < deadline)) || give_up "$1" "Ficha Dev didn't say its screen was up within a minute"
    sleep 0.1
  done
  rm -f "$last"
  still_since=$SECONDS
  deadline=$((SECONDS + 60))
  until [[ -f $last ]] && ((SECONDS - still_since >= 8)); do
    ((SECONDS < deadline)) || give_up "$1" "The screen kept changing for a minute after Ficha Dev said it was up"
    sleep 0.25
    screenshot "$shot"
    if [[ ! -f $last ]] || ! cmp -s "$shot" "$last"; then
      still_since=$SECONDS
    fi
    mv "$shot" "$last"
  done
  mv "$last" "$out-$1.png"
  echo "$out-$1.png"
}

echo "Taking the pictures in a simulator of its own, an $iphone_name on iOS $version"
device=$(xcrun simctl create "Ficha render" "$iphone" "$runtime")
xcrun simctl bootstatus "$device" -b >/dev/null
# The time and the battery the pictures show, as in Apple's: the same in every
# picture, and a minute going by doesn't change the screen.
xcrun simctl status_bar "$device" override --time 9:41 --batteryState discharging --batteryLevel 100
xcrun simctl install "$device" "$app"
mkdir -p "$(dirname "$out")"
for appearance in light dark; do
  xcrun simctl ui "$device" appearance "$appearance"
  take_picture "$appearance"
done
