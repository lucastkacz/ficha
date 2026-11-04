#!/bin/bash
# Runs xcodebuild for the Makefile's builds, with the arguments it's given.
#
# One build at a time on this Mac, since each is heavy. The build holds a lock
# through /usr/bin/lockf, macOS's standard tool, on a file outside every
# checkout, so the main folder and each worktree share it. While another build
# holds it, this says so once and waits. -k keeps the file, as lockf's manual
# recommends for processes that take turns.
#
# It cuts each line xcodebuild prints to 500 characters. Even with -quiet, a
# file that fails to compile prints the whole swift-frontend command, on one
# line of about 10,000 characters, into every session that reads the build's
# output. The errors themselves, `<file>:<line>:<column>: error:`, are short,
# and stay whole.
#
# The exit status stays xcodebuild's, so a failed build still fails make, and
# CI. This wrapper, the lock's place and the cut are our own.

set -o pipefail

lock=/tmp/ficha-xcodebuild.lock

/usr/bin/lockf -k -s -t 0 "$lock" true ||
  echo "Waiting for another Xcode build on this Mac to finish…" >&2

/usr/bin/lockf -k "$lock" xcodebuild "$@" 2>&1 | LC_ALL=C cut -c 1-500
