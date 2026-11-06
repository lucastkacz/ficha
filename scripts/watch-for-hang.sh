#!/bin/bash
# Runs a command, and fails it when a process of a name it starts hangs: when
# that process's CPU time stops growing for a number of seconds, this samples
# it, says where its threads wait, kills it, and fails. `make test` runs
# `swift test` under it, and `make preview-import` the import-preview tool.
#
#   scripts/watch-for-hang.sh --after <seconds> --process <name> --advice <text> -- <command> [<argument>...]
#
# It watches only that process, among the command's descendants: so a build
# that waits for another's lock, which uses no CPU either, and the same process
# of another session's run, stay out of it. Stopped growing means by less than
# 1% of a core, since a blocked process's few timers still use some. It counts
# the seconds its own polls sleep, which stop while the Mac sleeps, so a Mac
# waking up in the middle of a run isn't a hang. `sample` is Apple's; the rest
# is our own, as SwiftPM and Swift Testing have no time limit for a whole run:
# "A test that hangs" in docs/development.md says why.
#
# The sample stays in .build/hangs, under the folder this runs from.

set -u

usage="Usage: scripts/watch-for-hang.sh --after <seconds> --process <name> --advice <text> -- <command> [<argument>...]: the Makefile and scripts/preview-import.sh show it."
after=""
process=""
advice=""
while (($# >= 2)) && [[ $1 != -- ]]; do
  case $1 in
  --after) after=$2 ;;
  --process) process=$2 ;;
  --advice) advice=$2 ;;
  *)
    echo "$1 isn't an option of this script. $usage" >&2
    exit 2
    ;;
  esac
  shift 2
done
shift
if ! [[ $after =~ ^[1-9][0-9]*$ && -n $process && -n $advice ]] || (($# == 0)); then
  echo "This run lacks --after in whole seconds, --process, --advice or a command. $usage" >&2
  exit 2
fi

here=$(dirname "$0")
samples=.build/hangs
report=$(mktemp)
# Twenty polls in the time it waits, or one a second.
poll=$((after / 20 > 0 ? after / 20 : 1))
# 1% of a core for `after` seconds is `after` hundredths of a second, the unit
# `ps` counts CPU time in.
least_growth=$after

# The IDs of the watched processes among this script's descendants, on one line
# with spaces, then a tab, then their CPU time in hundredths of a second; no
# line when none is running. `ps` says the time as [hours:]minutes:seconds.
watched_processes() {
  ps -axo pid=,ppid=,time=,comm= | awk -v root="$$" -v name="$process" '
    function hundredths(time, parts, count, i, total) {
      count = split(time, parts, ":")
      for (i = 1; i <= count; i++) total = total * 60 + parts[i]
      return int(total * 100 + 0.5)
    }
    {
      parent[$1] = $2
      time[$1] = $3
      path = $0
      sub(/^ *[0-9]+ +[0-9]+ +[0-9:.]+ /, "", path)
      count = split(path, parts, "/")
      if (parts[count] == name) candidates[$1] = 1
    }
    END {
      for (pid in candidates) {
        for (ancestor = parent[pid]; ancestor > 1; ancestor = parent[ancestor]) {
          if (ancestor == root) {
            pids = pids (pids == "" ? "" : " ") pid
            total += hundredths(time[pid])
            break
          }
        }
      }
      if (pids != "") printf "%s\t%d\n", pids, total
    }'
}

# Samples each of the processes $1 names, writes the report, and kills them.
# The report comes first: the command ends as they die, and this script prints
# the report then.
report_hang() {
  local pid file text
  text="The run hung: $process used no CPU for $after seconds, so it was killed."$'\n'
  mkdir -p "$samples"
  for pid in $1; do
    file=$samples/$process-$pid.txt
    if sample "$pid" 1 -file "$file" >/dev/null 2>&1; then
      text+=$'\n'"Where the threads of process $pid wait, cut short, from $file:"$'\n'
      text+="$("$here/where-threads-wait.sh" "$file")"$'\n'
    else
      text+=$'\n'"macOS's sample couldn't read process $pid, so this can't say where it waits."$'\n'
    fi
  done
  printf '%s\n%s\n' "$text" "$advice" >"$report"
  # shellcheck disable=SC2086 # $1 holds one ID or more, separated by spaces.
  kill -KILL $1 2>/dev/null
}

# Until a hang, or until this script is gone.
watch() {
  local seen="" pids="" time=0 grown_from=0 quiet=0
  while kill -0 "$$" 2>/dev/null; do
    sleep "$poll"
    IFS=$'\t' read -r pids time < <(watched_processes) || pids=""
    if [[ -z $pids || $pids != "$seen" ]]; then
      seen=$pids
      grown_from=${time:-0}
      quiet=0
    elif ((time - grown_from >= least_growth)); then
      grown_from=$time
      quiet=0
    else
      quiet=$((quiet + poll))
      if ((quiet >= after)); then
        report_hang "$pids"
        return
      fi
    fi
  done
}

watch &
watcher=$!
trap 'kill "$watcher" 2>/dev/null; rm -f "$report"' EXIT

"$@"
status=$?
kill "$watcher" 2>/dev/null
wait "$watcher" 2>/dev/null

if [[ -s $report ]]; then
  cat "$report" >&2
  exit 1
fi
exit "$status"
