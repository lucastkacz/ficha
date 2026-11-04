#!/bin/bash
# Fails on what reads the clock or makes a review log's ID outside its source,
# naming each file and line, for `make time-and-ids-check`. Tests control both
# through those sources: the fuzz of FSRS's intervals is seeded by a review log
# entry's ID, so an ID made at random changes a test's intervals from run to
# run. It reads the working tree of the checkout it runs in, new files too,
# skipping comments. The reviewer judges what it can't see, such as
# `Date(timeIntervalSinceNow:)` or a `UUID()` in FichaData, as CODING_STANDARDS.md's
# Time and IDs says. Finding the calls with git grep is our own.

set -u

# The lines of the Swift files in the pathspecs that match a pattern, exiting 2
# when it can't read them: code_lines <pattern> <pathspec>...
code_lines() {
  local lines status
  lines=$(git grep --untracked -nE "$1" -- "${@:2}")
  status=$?
  if ((status > 1)); then
    echo "git grep couldn't read this checkout, as it says above, so nothing was checked: run this from a git checkout of Ficha." >&2
    exit 2
  fi
  grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' <<<"$lines"
}

failed=0

clock=$(code_lines '(^|[^[:alnum:]_])Date(\(\)|\.now([^[:alnum:]_]|$))' '*.swift' \
  ':(exclude)scripts/*' ':(exclude)Packages/FichaKit/Tests/*' \
  ':(exclude)Packages/FichaKit/Sources/FichaCore/TimeSource.swift')
(($? < 2)) || exit 1
if [[ -n $clock ]]; then
  echo "$clock" >&2
  echo "The lines above read the clock with Date() or Date.now: ask a TimeSource for now instead, so tests control the time, as CODING_STANDARDS.md's Time and IDs says." >&2
  failed=1
fi

ids=$(code_lines '(^|[^[:alnum:]_])UUID\(\)' 'Packages/FichaKit/Sources/FichaCore/*.swift' \
  ':(exclude)Packages/FichaKit/Sources/FichaCore/IDSource.swift')
(($? < 2)) || exit 1
if [[ -n $ids ]]; then
  echo "$ids" >&2
  echo "The lines above make an ID with UUID() in FichaCore: ask the engine's IDSource for one instead, so tests get the same IDs and the same intervals on every run, as CODING_STANDARDS.md's Time and IDs says." >&2
  failed=1
fi

exit $failed
