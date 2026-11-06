#!/bin/bash
# Runs the import-preview tool, scripts/import-preview, on files of cards, for
# `make preview-import`: "An import's numbers" in docs/development.md explains
# it. It builds the tool for release, and runs it once per file, so each file's
# peak memory footprint is its own, under scripts/watch-for-hang.sh.
#
#   scripts/preview-import.sh [--at <commit>] [--dump <output>] <file>...
#
# --at builds the tool against FichaKit as it is at that commit: `git archive`
# unpacks FichaKit in a scratch folder under .build, beside a copy of the tool,
# which stays for the next run at that commit. All of this is our own.

set -uo pipefail

usage='Usage: make preview-import ARGS="[--at <commit>] [--dump <output>] <file>...": --dump takes one file, and a path with a space goes in quotes inside ARGS.'
tool=scripts/import-preview
scratch=.build/import-preview-at
fsrs=Packages/FichaKit/Frameworks
crate=Packages/FichaKit/Rust
hang_advice="Run it again: if it hangs in the same place, the frames above say where the import waits, and CODING_STANDARDS.md's rule on code that blocks a thread says what usually causes it. A run that truly has nothing to do for that long would need a higher limit in scripts/preview-import.sh."

at=""
dump=""
files=()
while (($# > 0)); do
  case $1 in
  --at | --dump)
    (($# >= 2)) || {
      echo "$1 needs a value. $usage" >&2
      exit 2
    }
    if [[ $1 == --at ]]; then at=$2; else dump=$2; fi
    shift 2
    ;;
  --*)
    echo "$1 isn't an option of this tool. $usage" >&2
    exit 2
    ;;
  *)
    files+=("$1")
    shift
    ;;
  esac
done
((${#files[@]} > 0)) || {
  echo "No file to read. $usage" >&2
  exit 2
}
[[ -z $dump || ${#files[@]} == 1 ]] || {
  echo "--dump writes one file's cards, and this run names ${#files[@]} files. $usage" >&2
  exit 2
}

# Unpacks FichaKit as it is at the commit $1 in a new folder, with its
# XCFramework, which git ignores, and prints the folder, or says what failed.
# The XCFramework is copied when the commit's crate is this checkout's, and
# built otherwise.
unpack_commit() {
  local commit=$1 work
  if ! {
    mkdir -p "$scratch" &&
      work=$(mktemp -d "$scratch/.unpacking.XXXXXX") &&
      git archive "$commit" Packages/FichaKit scripts/build-fsrs.sh | tar -x -C "$work"
  }; then
    echo "FichaKit at $commit couldn't be unpacked into $scratch, as it says above. A commit older than e8eaed8, which brought the Rust crate, can't be compared: try a later one. Otherwise check that the disk has room, delete $scratch, and try again." >&2
    return 1
  fi
  if git diff --quiet "$commit" -- "$crate"; then
    cp -R "$fsrs" "$work/Packages/FichaKit/" || {
      echo "The XCFramework couldn't be copied into $work, as it says above: run make fsrs, check that the disk has room, delete $scratch, and try again." >&2
      return 1
    }
  elif ! (cd "$work" && scripts/build-fsrs.sh "$crate" "$fsrs/CFichaFSRS.xcframework") >&2; then
    echo "fsrs-rs at $commit didn't build, as it says above: run this through make preview-import, which finds Rust's tools, and if it still fails, try a later commit." >&2
    return 1
  fi
  echo "$work"
}

package=$tool
if [[ -n $at ]]; then
  commit=$(git rev-parse --verify --quiet "$at^{commit}") || {
    echo "$at names no commit in this repository: pass a branch, a tag or a commit, such as main, and fetch it first if it's only on GitHub." >&2
    exit 1
  }
  if [[ ! -d $scratch/$commit ]]; then
    work=$(unpack_commit "$commit") || exit 1
    mv "$work" "$scratch/$commit" || {
      echo "$work couldn't become $scratch/$commit, as it says above: delete $scratch, and try again." >&2
      exit 1
    }
  fi
  package=$scratch/$commit/$tool
  if ! { mkdir -p "$package" && cp -Rp "$tool/Package.swift" "$tool/Sources" "$package/"; }; then
    echo "The tool couldn't be copied into $package, as it says above: delete $scratch/$commit, and try again." >&2
    exit 1
  fi
fi

swift build -c release --quiet --package-path "$package" || {
  echo "The import-preview tool didn't build, as it says above. With --at, it may not compile against that commit's FichaKit: try a later commit. If the lines above name a FichaKit file that's missing, which a merge can leave in SwiftPM's cached plan (#293), run swift package --package-path $package clean, and try again." >&2
  exit 1
}

status=0
for file in "${files[@]}"; do
  arguments=("$file")
  [[ -z $dump ]] || arguments=(--dump "$dump" "$file")
  "$(dirname "$0")/watch-for-hang.sh" --after 60 --process ImportPreview --advice "$hang_advice" -- \
    "$package/.build/release/ImportPreview" "${arguments[@]}" || status=1
done
exit "$status"
