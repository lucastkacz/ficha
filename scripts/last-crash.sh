#!/bin/bash
# Says where Ficha Dev crashed, for `make last-crash`, since a crash writes
# nothing to the app's log. It reads the newest `Ficha Dev-<date>-<time>.ips` in
# ~/Library/Logs/DiagnosticReports or its Retired folder, the Mac app's and the
# simulator's alike, or the report a path names:
#
#   scripts/last-crash.sh [<report>]
#
# The report's format is Apple's, a line of JSON and then the report as JSON, as
# "Interpreting the JSON format of a crash report" describes. What it picks from
# it is our own.

set -u

reports="$HOME/Library/Logs/DiagnosticReports"

if (($# > 0)); then
  report=$1
else
  # The names sort by date, whichever folder holds them.
  report=$(find "$reports" "$reports/Retired" -maxdepth 1 -name 'Ficha Dev-*.ips' 2>/dev/null |
    awk -F/ '{ print $NF "\t" $0 }' | sort | tail -n 1 | cut -f 2)
  [[ -n $report ]] || {
    echo "No crash report of Ficha Dev in $reports or its Retired folder: if it quit on its own, look there for a report with another process's name, or pass a report's path." >&2
    exit 1
  }
fi

body=$(tail -n +2 "$report" 2>/dev/null)
jq -e '.threads and .exception' <<<"$body" >/dev/null 2>&1 || {
  echo "$report isn't a crash report in Apple's format, a line of JSON and then the report as JSON: pass the path of a .ips file." >&2
  exit 1
}

basename "$report"
jq -r '
  "Process: \(.procName) [\(.pid)]",
  "Started: \(.procLaunch)",
  "Crashed: \(.captureTime)",
  "Exception: \(.exception.type) (\(.exception.signal // "no signal"))",
  (if (.asi // {}) == {} then
    "Application-specific information: none"
  else
    "Application-specific information:",
    (.asi | to_entries[] | .key as $image | .value[] | "  \($image): \(.)")
  end),
  (.usedImages as $images
    | ([.threads[] | select(.triggered)][0].frames // []) as $frames
    | "Frames of the triggered thread, the first \([$frames | length, 20] | min) of \($frames | length):",
      ($frames[:20] | to_entries[]
        | "  \(.key)  \($images[.value.imageIndex].name // "unknown image")  \(.value.symbol // "at offset \(.value.imageOffset)")"))
' <<<"$body"
