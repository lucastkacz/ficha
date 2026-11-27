#!/bin/bash
# Checks that an app holds English alone, the one language Ficha comes in
# (ADR 0036). `make upload` runs it on the archive's app before the export
# uploads it, and stops when it fails:
#
#   scripts/english-alone.sh <the app>
#
# A language is a folder named after it, `<language>.lproj`, anywhere in the
# app's bundle: its widget's, its CLI's and its XPC service's included. A Mac
# set to that language shows the texts in it, and TestFlight lists it. Only
# English's, `en.lproj`, and Base's, `Base.lproj`, Xcode's base
# localization, may stay. Such a folder can come from a String Catalog that
# holds the language, a resource localized in it, a package that brings it,
# or derived data an earlier build left it in (#518). This check is our own.

set -uo pipefail

if (($# != 1)); then
  echo "This script takes the app to check, and got $# arguments: run scripts/english-alone.sh <the app>." >&2
  exit 2
fi
app=$1

if [[ ! -d $app ]]; then
  echo "There's no app at $app to check: archive it first, as make upload does, and run this on the app inside the archive." >&2
  exit 1
fi

others=$(find "$app" -name '*.lproj' ! -name en.lproj ! -name Base.lproj | LC_ALL=C sort) || {
  echo "find couldn't list the language folders in $app, as it says above, so nothing shows it holds English alone: check that the app can be read, and try again." >&2
  exit 1
}

if [[ -n $others ]]; then
  {
    echo "$app holds folders of languages other than English, which a Mac set to one of them shows, and TestFlight lists:"
    while IFS= read -r folder; do
      echo "  ${folder#"$app"/}"
    done <<<"$others"
    echo "Ficha comes in English alone (ADR 0036), so make upload stops before it uploads: take each language out of what brings its folder, such as a String Catalog or a package, and run make upload again."
  } >&2
  exit 1
fi
echo "$app holds English alone."
