#!/bin/bash
# Tests scripts/english-alone.sh, which `make upload` runs on the archive's app
# before the export uploads it, and that `make upload` runs it there; `make
# check` runs this. Each case of the script is an app made by hand, of folders
# alone, laid out as the archive's, in a scratch folder.

set -u
script="$(cd "$(dirname "$0")" && pwd)/english-alone.sh"
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
failures=0

pass() { echo "ok    $1"; }
fail() {
  echo "FAIL  $1"
  failures=$((failures + 1))
}

# app: makes a new app in English alone, at $made, as the archive holds the
# real Ficha: English's and Base's folders in its resources, English's in its
# widget's, and its CLI and XPC service. Its folder's name has a space, as a
# path to the main folder may.
cases=0
app() {
  cases=$((cases + 1))
  made="$tmp/case $cases/Ficha.app"
  mkdir -p "$made/Contents/Resources/en.lproj" "$made/Contents/Resources/Base.lproj" \
    "$made/Contents/PlugIns/FichaWidget.appex/Contents/Resources/en.lproj" \
    "$made/Contents/XPCServices/SVGDrawer.xpc/Contents/Resources" "$made/Contents/Helpers"
  touch "$made/Contents/Helpers/ficha"
}
# expect <description> <passes|stops> <pattern> <app>: runs the script on the
# app, and checks that it passes or stops, as said, and that what it prints
# matches the pattern.
expect() {
  local output status matches=no
  output=$("$script" "$4" 2>&1)
  status=$?
  # shellcheck disable=SC2053 # The pattern is a glob on purpose.
  if [[ $output == $3 ]]; then matches=yes; fi
  if [[ $2 == passes && $status != 0 ]]; then
    fail "$1 (it stopped, with status $status: $output)"
  elif [[ $2 == stops && $status == 0 ]]; then
    fail "$1 (it passed: $output)"
  elif [[ $matches == no ]]; then
    fail "$1 (got: $output)"
  else
    pass "$1"
  fi
}

app
expect "an app with English's and Base's folders alone passes" passes "*holds English alone*" "$made"

app
mkdir -p "$made/Contents/Resources/de.lproj"
expect "a language's folder in the app's resources stops it, named, and it says what to do" stops \
  "*Contents/Resources/de.lproj*take each language out*run make upload again*" "$made"

app
mkdir -p "$made/Contents/PlugIns/FichaWidget.appex/Contents/Resources/fr.lproj"
expect "a language's folder in the widget stops it too" stops \
  "*Contents/PlugIns/FichaWidget.appex/Contents/Resources/fr.lproj*" "$made"

app
mkdir -p "$made/Contents/Resources/de.lproj" "$made/Contents/Resources/ar.lproj" \
  "$made/Contents/XPCServices/SVGDrawer.xpc/Contents/Resources/es.lproj"
expect "each language's folder is named" stops \
  "*Contents/Resources/ar.lproj*Contents/Resources/de.lproj*SVGDrawer.xpc/Contents/Resources/es.lproj*" "$made"
output=$("$script" "$made" 2>&1)
if [[ $output != *"/en.lproj"* && $output != *"/Base.lproj"* ]]; then
  pass "English's and Base's folders aren't named among them"
else
  fail "English's and Base's folders aren't named among them (got: $output)"
fi

expect "with no app at the path, it stops and says so" stops "*There's no app at*" "$tmp/nowhere/Ficha.app"

# make upload's recipe, as `make -n` prints it without running it, with none of
# the make that runs this test's flags.
recipe=$(MAKEFLAGS='' make --no-print-directory -C "$(dirname "$script")/.." -n upload 2>&1)
# line_of <text>: the number of the recipe's first line that holds the text, or
# 0 when none does.
line_of() {
  local number
  number=$(grep -n -F -e "$1" <<<"$recipe" | head -n 1 | cut -d : -f 1)
  echo "${number:-0}"
}
deleted=$(line_of "rm -rf .build/upload")
archived=$(line_of "-derivedDataPath .build/upload/DerivedData")
unregistered=$(line_of "scripts/unregister-other-copies.sh Ficha.app")
checked=$(line_of "scripts/english-alone.sh .build/upload/Ficha.xcarchive/Products/Applications/Ficha.app")
exported=$(line_of "-exportArchive")
if ((deleted > 0 && deleted < archived && archived < unregistered && unregistered < checked && checked < exported)); then
  pass "make upload deletes .build/upload, archives in the derived data there, unregisters the other copies, and checks its app before the export"
else
  fail "make upload deletes .build/upload, archives in the derived data there, unregisters the other copies, and checks its app before the export (got: $recipe)"
fi

if ((failures > 0)); then
  echo "$failures test(s) of the check that an upload's app holds English alone failed"
  exit 1
fi
echo "All the tests of the check that an upload's app holds English alone passed"
