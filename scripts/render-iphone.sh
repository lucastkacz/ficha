#!/bin/bash
# Takes the iPhone app's pictures, light and dark, on the screen it opens on:
# `make render-iphone`, which builds Ficha Dev for the simulator first and
# passes its path. The pictures come from an iPhone simulator of its own, of
# the newest iOS the Mac has and the first iPhone it offers, which it boots
# without the Simulator app and deletes after them, so the simulators that
# other sessions and the Simulator app use stay as they were. The commands are
# simctl's, which `xcrun simctl help` documents. Our own are a simulator for
# each run, the line the app says on its standard output once its screen is up
# (iPhone/Rendering.swift), and the wait for a still screen after it.
#
# With `--language <code>`, the app opens in one of Ficha's languages, with
# its region's formats, through the launch arguments Xcode's scheme options
# pass: `-AppleLanguages` and `-AppleLocale`, and for Arabic those of its
# right-to-left pseudolanguage too, which mirror the screen even before the
# app has Arabic.

set -euo pipefail

# English and the eleven languages Ficha comes in, each as `<locale> <name>`:
# the language's code in the String Catalogs and its region, as the render
# tool for the Mac has them (renderLanguages, in
# scripts/render/Sources/Render/main.swift), and its name in English.
languages=(
  "en_US English" "zh-Hans_CN Simplified Chinese" "ja_JP Japanese" "de_DE German" "es_AR Spanish" "fr_FR French"
  "ko_KR Korean" "pt_BR Portuguese" "zh-Hant_TW Traditional Chinese" "it_IT Italian" "ru_RU Russian" "ar_EG Arabic"
)
language_list=""
for entry in "${languages[@]}"; do
  language_list+="${language_list:+, }${entry%%_*} (${entry#* })"
done

usage="Usage: make render-iphone ARGS=\"[--language <code>] [--out <path>]\", which saves <path>-light.png and <path>-dark.png, or .build/render/iphone-light.png and iphone-dark.png without --out, iphone-<code>-light.png and iphone-<code>-dark.png in a language. Without --language, the app opens in English, with the simulator's formats. The languages: $language_list."
(($# > 0)) || {
  echo "There's no app to take pictures of: run the tool through make render-iphone, which builds Ficha Dev and passes its path. $usage" >&2
  exit 1
}
app=$1
shift
out=""
language=""
language_name=""
locale=""
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
    --language)
      language=${2:-}
      locale=""
      for entry in "${languages[@]}"; do
        if [[ ${entry%% *} == "$language"_* ]]; then
          locale=${entry%% *}
          language_name=${entry#* }
        fi
      done
      [[ -n $locale ]] || {
        echo "${language:+Ficha has no language $language: }--language takes one of the languages below, by its code." >&2
        echo "$usage" >&2
        exit 1
      }
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
out=${out:-.build/render/iphone${language:+-$language}}

# What the app reads and says when the tool opens it, as iPhone/Rendering.swift
# writes them.
launch_arguments=(-FichaRendering)
screen_is_up="The screen is up"

bundle=$(plutil -extract CFBundleIdentifier raw "$app/Info.plist" 2>/dev/null) || {
  echo "There's no app at $app: build it with make build-iphone." >&2
  exit 1
}

# The language the app opens in: English without --language, with the
# simulator's own formats, as before the tool took a language.
if [[ -z $locale ]]; then
  launch_arguments+=(-AppleLanguages "(en)")
else
  launch_arguments+=(-AppleLanguages "($language)" -AppleLocale "$locale")
  # Arabic, the one of Ficha's languages read right to left.
  if [[ $language == ar ]]; then
    launch_arguments+=(-AppleTextDirection YES -NSForceRightToLeftWritingDirection YES)
  fi
  # The app's bundle is flat on iOS: its compiled String Catalog is a folder
  # for each language beside its Info.plist. English is the language the code
  # writes the texts in, which needs none.
  if [[ $language != en && ! -d $app/$language.lproj ]]; then
    echo "iPhone/Localizable.xcstrings has no $language_name ($language) yet, so the app's texts are English, as Ficha shows them on an iPhone in $language_name, with its formats."
  fi
fi

# The newest iOS the Mac has, and the first iPhone it offers: simctl lists them
# by generation, newest first.
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

# Stops the tool after a simctl command that failed, whose message comes
# first, saying what the tool couldn't do, $1, and what to do, $2, by default
# trying again.
couldnt() {
  echo "Couldn't $1, as simctl says above, so there are no pictures: ${2:-run make render-iphone again.}" >&2
  exit 1
}

# Saves the simulator's screen as the PNG $1. simctl says what it did on
# standard error, as it says what went wrong, so that's shown only then.
screenshot() {
  local message
  message=$(xcrun simctl io "$device" screenshot "$1" 2>&1) || {
    echo "$message" >&2
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
  local app_output=$scratch/$1-output.txt shot=$scratch/shot.png last=$scratch/last.png still_since deadline
  xcrun simctl launch --terminate-running-process --stdout="$app_output" "$device" "$bundle" \
    "${launch_arguments[@]}" >/dev/null || give_up "$1" "Ficha Dev didn't open, as simctl says above"
  deadline=$((SECONDS + 60))
  until grep -qxF "$screen_is_up" "$app_output" 2>/dev/null; do
    ((SECONDS < deadline)) || give_up "$1" "Ficha Dev didn't say its screen was up within a minute"
    sleep 0.1
  done
  rm -f "$last"
  still_since=$SECONDS
  deadline=$((SECONDS + 60))
  until [[ -f $last ]] && ((SECONDS - still_since >= 8)); do
    ((SECONDS < deadline)) || give_up "$1" "The screen kept changing for a minute after Ficha Dev said it was up"
    sleep 0.25
    screenshot "$shot" || couldnt "take a screenshot of the simulator"
    if [[ ! -f $last ]] || ! cmp -s "$shot" "$last"; then
      still_since=$SECONDS
    fi
    mv "$shot" "$last"
  done
  mv "$last" "$out-$1.png"
  echo "$out-$1.png"
}

echo "Taking the pictures in a simulator of its own, an $iphone_name on iOS $version"
device=$(xcrun simctl create "Ficha render" "$iphone" "$runtime") || couldnt "make a simulator"
xcrun simctl bootstatus "$device" -b >/dev/null || couldnt "boot the simulator"
# The time and the battery the pictures show, as in Apple's: the same in every
# picture, and a minute going by doesn't change the screen.
xcrun simctl status_bar "$device" override --time 9:41 --batteryState discharging --batteryLevel 100 ||
  couldnt "set the simulator's status bar"
xcrun simctl install "$device" "$app" || couldnt "install Ficha Dev in the simulator" "build it again with make build-iphone."
mkdir -p "$(dirname "$out")"
for appearance in light dark; do
  xcrun simctl ui "$device" appearance "$appearance" || couldnt "switch the simulator to $appearance"
  take_picture "$appearance"
done
