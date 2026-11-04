#!/bin/bash
# Tests scripts/last-crash.sh; `make check` runs it. It reads a crash report
# written by hand, last-crash-fixture.ips, shaped as Apple's are, with no user's
# paths in it, as a report a path names and as the newest in a scratch home.

set -u
root=$(cd "$(dirname "$0")/.." && pwd)
script="$root/scripts/last-crash.sh"
fixture="$root/scripts/last-crash-fixture.ips"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

check() {
  if [[ $1 == *"$2"* ]]; then
    echo "ok    $3"
  else
    echo "FAIL  $3 (got: $1)"
    failures=$((failures + 1))
  fi
}

check_not() {
  if [[ $1 != *"$2"* ]]; then
    echo "ok    $3"
  else
    echo "FAIL  $3 (got: $1)"
    failures=$((failures + 1))
  fi
}

output=$("$script" "$fixture" 2>&1)
check "$output" "last-crash-fixture.ips" "it names the report's file"
check "$output" "Ficha Dev [4242]" "it names the process and its ID"
check "$output" "2026-10-27 22:10:01.1000 -0300" "it says when the process started"
check "$output" "2026-10-27 22:12:33.5000 -0300" "it says when the process crashed"
check "$output" "EXC_BREAKPOINT (SIGTRAP)" "it says the exception's type and signal"
check "$output" "CloudKit: Don't call cancelOperations from inside handleEvent" "it says the application-specific information, with its image"
check "$output" "0  CloudKit  -[CKSyncEngine cancelOperations]" "it starts with the triggered thread's top frame, by image and symbol"
check "$output" "19  Ficha Dev  frame19" "it lists the triggered thread's twentieth frame"
check_not "$output" "frame20" "it stops at twenty frames"
check_not "$output" "OtherThreadSymbol" "it leaves the other threads out"

home="$tmp/home"
reports="$home/Library/Logs/DiagnosticReports"
mkdir -p "$reports/Retired"
output=$(HOME=$home "$script" 2>&1)
status=$?
check "$output" "No crash report of Ficha Dev" "it says so when there's no report"
if ((status == 1)); then
  echo "ok    it fails when there's no report"
else
  echo "FAIL  it fails when there's no report (exit $status)"
  failures=$((failures + 1))
fi

cp "$fixture" "$reports/Ficha Dev-2026-10-27-221233.ips"
cp "$fixture" "$reports/Retired/Ficha Dev-2026-10-28-090000.ips"
cp "$fixture" "$reports/Retired/Render-2026-10-29-090000.ips"
output=$(HOME=$home "$script" 2>&1)
check "$output" "Ficha Dev-2026-10-28-090000.ips" "it reads the newest of Ficha Dev's reports, in Retired too"

named="$tmp/Ficha Dev-2026-10-27-221233.ips"
cp "$fixture" "$named"
output=$(make -C "$root" --no-print-directory last-crash ARGS="$named" 2>&1)
check "$output" "Ficha Dev [4242]" "make last-crash reads a report whose name holds a space, as every report's does"

printf 'not a report\n' >"$tmp/Broken.ips"
output=$("$script" "$tmp/Broken.ips" 2>&1)
check "$output" "isn't a crash report in Apple's format" "it says so when a file isn't a crash report"

if ((failures > 0)); then
  echo "$failures last-crash test(s) failed"
  exit 1
fi
echo "All last-crash tests passed"
