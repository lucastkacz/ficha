#!/bin/bash
# Unregisters every copy of an app from LaunchServices but one, so that what
# opens the app by its bundle ID, such as a widget's click, a Shortcut, a Focus
# filter or a link, opens that one:
#
#   scripts/unregister-other-copies.sh <the app's file name> <the path to keep>
#
# LaunchServices keeps every copy it ever saw, each worktree's build among them,
# even in folders long deleted, and picks one. In #308 it picked the newest
# build, an unsigned agent's copy, and `lsregister -f` on the right one didn't
# win. A copy comes back when it's built or opened again, so `make run` does
# this each time, not once. The iPhone simulator's copies stay: they never open
# on the Mac. Apple documents lsregister only in its -help, so reading its -dump
# is our own.

set -u

if (($# != 2)); then
  echo "This script takes the app's file name and the path of the copy to keep, and got $# arguments: run scripts/unregister-other-copies.sh \"Ficha Dev.app\" <the path to keep>." >&2
  exit 2
fi
name=$1
keep=$2
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

dump=$("$lsregister" -dump) || {
  echo "lsregister couldn't list the copies of $name that LaunchServices has registered, as it says above, so what opens the app by its bundle ID may open another copy: check that macOS still has $lsregister, and try again." >&2
  exit 1
}

unregistered=0
while IFS= read -r path; do
  case $path in
    "" | "$keep" | */Debug-iphonesimulator/* | */CoreSimulator/*) continue ;;
  esac
  "$lsregister" -u "$path" || {
    echo "lsregister couldn't unregister $path, as it says above, so what opens the app by its bundle ID may open that copy: check that macOS still has $lsregister, and try again." >&2
    exit 1
  }
  unregistered=$((unregistered + 1))
done < <(grep -F "/$name (0x" <<<"$dump" | sed -nE 's/^path: +(.*) \(0x[0-9a-f]+\)$/\1/p' | sort -u)

if ((unregistered > 0)); then
  echo "Other copies of $name unregistered from LaunchServices: $unregistered."
fi
