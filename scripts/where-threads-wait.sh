#!/bin/bash
# Says where a hung process's threads wait, cut short, from a report of macOS's
# `sample`, whose whole call graph runs to thousands of lines:
#
#   scripts/where-threads-wait.sh <sample report>
#
# It groups the threads by their queue, or their name, and by where they stand:
# each thread's heaviest stack, as `sample` lists it first, as its innermost
# frames, and then the innermost frames of the binaries that aren't Apple's,
# which `sample` marks with a +, such as the tests' or the tool's. It leaves out
# the threads that wait for work. The report's format is Apple's, undocumented,
# so scripts/test-watch-for-hang.sh reads a real one. Picking these lines is our
# own.

set -u

(($# == 1)) || {
  echo "Usage: scripts/where-threads-wait.sh <sample report>: pass the file macOS's sample wrote with -file." >&2
  exit 2
}
[[ -r $1 ]] || {
  echo "$1 can't be read: pass the file macOS's sample wrote with -file." >&2
  exit 1
}

awk '
  # A frame of the call graph, "semaphore_wait_trap  (in libsystem_kernel.dylib)
  # + 8  [0x185bfcbb0]  File.swift:12", as "semaphore_wait_trap
  # (libsystem_kernel.dylib) File.swift:12".
  function frame(text, place) {
    place = ""
    if (match(text, /\[0x[0-9a-f]+\] +[^ ].*$/)) {
      place = substr(text, RSTART, RLENGTH)
      sub(/^\[0x[0-9a-f]+\] +/, "", place)
    }
    sub(/ *(\+ [0-9]+ +)?\[0x[0-9a-f]+\].*$/, "", text)
    sub(/ +\(in /, " (", text)
    return place != "" ? text " " place : text
  }

  # The image a whole frame names, between its last parentheses.
  function image_of(text, opening) {
    opening = 0
    while (match(substr(text, opening + 1), /\(/)) opening += RSTART
    return opening ? substr(text, opening + 1, index(substr(text, opening + 1), ")") - 1) : ""
  }

  /^Call graph:/ { in_graph = 1; next }
  in_graph && /^ *$/ { in_graph = 0; next }
  in_graph && /^    [0-9]+ Thread_[0-9]+/ {
    threads++
    last_depth[threads] = 0
    following[threads] = 1
    line = $0
    if (match(line, /DispatchQueue_[0-9]+: /)) {
      queue[threads] = substr(line, RSTART + RLENGTH)
    } else if (match(line, /Thread_[0-9]+: /)) {
      queue[threads] = substr(line, RSTART + RLENGTH)
    } else {
      queue[threads] = "no queue"
    }
    gsub(/  +/, " ", queue[threads])
    next
  }
  in_graph && threads && following[threads] {
    # The tree marks hold no digits: the count starts the frame, and how far
    # in it starts says its depth. The first frame that isn t deeper than the
    # last ends the heaviest stack.
    if (!match($0, /[0-9]+ /)) next
    depth = RSTART
    if (depth <= last_depth[threads]) { following[threads] = 0; next }
    last_depth[threads] = depth
    whole = frame(substr($0, RSTART + RLENGTH))
    frame_count[threads]++
    images[threads, frame_count[threads]] = image_of(whole)
    frames[threads, frame_count[threads]] = length(whole) > 150 ? substr(whole, 1, 150) "…" : whole
    next
  }

  /^Binary Images:/ { in_images = 1; next }
  in_images && match($0, / \+[^ ]+/) { ours[substr($0, RSTART + 2, RLENGTH - 2)] = 1 }

  END {
    for (thread = 1; thread <= threads; thread++) {
      count = frame_count[thread]
      leaf = frames[thread, count]
      # A worker thread with nothing to do.
      if (leaf ~ /^(__workq_kernreturn|kevent_id|__kevent_qos|kevent_qos)/ && count <= 5) { idle++; continue }
      stack = ""
      for (i = count; i > count - 4 && i >= 1; i--) stack = stack "    " frames[thread, i] "\n"
      shown = 0
      gap = 0
      for (i = count - 4; i >= 1 && shown < 4; i--) {
        if (images[thread, i] in ours) {
          stack = stack "    " (gap ? "…\n    " : "") frames[thread, i] "\n"
          shown++
          gap = 0
        } else {
          gap = 1
        }
      }
      key = queue[thread] SUBSEP stack
      if (!(key in seen)) { order[++groups] = key; name[groups] = queue[thread]; text[groups] = stack }
      seen[key]++
    }
    limit = 12
    for (group = 1; group <= groups && group <= limit; group++) {
      many = seen[order[group]]
      printf "%s: %d thread%s\n%s", name[group], many, (many == 1 ? "" : "s"), text[group]
    }
    if (groups > limit) printf "And %d more places, in the whole sample.\n", groups - limit
    if (idle) printf "And %d thread%s waiting for work.\n", idle, (idle == 1 ? "" : "s")
    if (!threads) print "The sample lists no threads."
  }
' "$1"
