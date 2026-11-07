#!/bin/bash
# Tests scripts/watch-for-hang.sh and scripts/where-threads-wait.sh; `make check`
# runs it. It compiles a small program that hangs, burns CPU or waits, as the
# watched process, runs the watchdog on it with limits of a few seconds, and
# reads a report of macOS's own `sample`, so a change to that format fails here.

set -u
root=$(cd "$(dirname "$0")/.." && pwd)
script="$root/scripts/watch-for-hang.sh"
summary="$root/scripts/where-threads-wait.sh"
tmp=$(mktemp -d)
others=()
cleanup() {
  ((${#others[@]} == 0)) || kill -KILL "${others[@]}" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT
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

check_status() {
  if (($1 == $2)); then
    echo "ok    $3"
  else
    echo "FAIL  $3 (exit $1)"
    failures=$((failures + 1))
  fi
}

cat >"$tmp/fake-tests.c" <<'C'
#include <dispatch/dispatch.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static void wait_forever(void) {
    dispatch_semaphore_wait(dispatch_semaphore_create(0), DISPATCH_TIME_FOREVER);
}

int main(int argc, char **argv) {
    if (strcmp(argv[1], "hang") == 0) {
        dispatch_async(dispatch_queue_create("com.example.waits", DISPATCH_QUEUE_SERIAL), ^{ wait_forever(); });
        for (int i = 0; i < 3; i++) {
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ wait_forever(); });
        }
        wait_forever();
    } else if (strcmp(argv[1], "burn") == 0) {
        time_t end = time(NULL) + atoi(argv[2]);
        while (time(NULL) < end) {}
    } else if (strcmp(argv[1], "wait") == 0) {
        sleep(atoi(argv[2]));
    } else if (strcmp(argv[1], "exit") == 0) {
        return atoi(argv[2]);
    }
    return 0;
}
C
cc -o "$tmp/fake-tests" "$tmp/fake-tests.c" || {
  echo "The test's small program didn't compile, as it says above: check that Xcode's command line tools are selected, which make xcode-check checks, and run it again." >&2
  exit 1
}
cd "$tmp" || exit 1

watch() {
  "$script" --after 2 --process fake-tests --advice "Advice for this run." -- "$@" 2>&1
}

mkdir "$tmp/fake-tools"
printf '#!/bin/bash\nexit 1\n' >"$tmp/fake-tools/sample"
chmod +x "$tmp/fake-tools/sample"
watch_where_sample_fails() {
  PATH="$tmp/fake-tools:$PATH" watch "$@"
}

# Starts a run beside the others, since most of each is waiting out its limit,
# in a folder of its own, as .build/hangs goes under the folder it runs from.
run() {
  local name=$1
  shift
  mkdir "$name"
  (cd "$name" && "$@" >output 2>&1; echo $? >status) &
}

# Sets output and status to what the run $1 left.
results_of() {
  output=$(<"$1/output")
  status=$(<"$1/status")
}

# Another session's tests, which share the process's name.
"$tmp/fake-tests" hang &
others+=($!)
disown

run hang watch "$tmp/fake-tests" hang
run descendant watch bash -c "'$tmp/fake-tests' hang; exit 3"
run burn watch "$tmp/fake-tests" burn 4
run command-status watch "$tmp/fake-tests" exit 7
# A build that waits for another's lock on .build uses no CPU either.
run another-name "$script" --after 2 --process another-name --advice "Advice." -- "$tmp/fake-tests" wait 4
run another-session watch sleep 4
run failing-sample watch_where_sample_fails "$tmp/fake-tests" hang
wait

results_of hang
check_status "$status" 1 "a process that uses no CPU fails the run"
check "$output" "The run hung: fake-tests used no CPU for 2 seconds" "it says which process hung, and for how long"
check "$output" "Advice for this run." "it says what to do"
check "$output" "com.apple.root.default-qos (concurrent): 3 threads" "it groups the waiting threads by queue, with a real sample"
check "$output" "com.example.waits (serial): 1 thread" "it lists each queue apart"
check "$output" "semaphore_wait_trap (libsystem_kernel.dylib)" "it says where the threads wait"
check "$output" "(fake-tests)" "it reaches the frames of the program itself"
samples=$(cd hang && find .build/hangs -name 'fake-tests-*.txt')
check "$output" "$samples" "it names the file the sample stays in"
hung=${samples##*-}
if [[ -n $hung ]] && ! kill -0 "${hung%.txt}" 2>/dev/null; then
  echo "ok    it kills the process"
else
  echo "FAIL  it kills the process"
  failures=$((failures + 1))
fi

results_of descendant
check_status "$status" 1 "it finds the process among the command's descendants, as swift test starts the tests' helper"
check "$output" "The run hung" "it says so for a descendant too"

results_of burn
check_status "$status" 0 "a process that keeps using CPU past the limit passes"
check_not "$output" "hung" "it says nothing of a hang then"

results_of command-status
check_status "$status" 7 "it ends with the command's own status"

results_of another-name
check_status "$status" 0 "it leaves alone a process of another name that uses no CPU"

results_of another-session
check_status "$status" 0 "it leaves alone a process of that name it didn't start"
if kill -0 "${others[0]}" 2>/dev/null; then
  echo "ok    that process stays alive"
else
  echo "FAIL  that process stays alive"
  failures=$((failures + 1))
fi

output=$("$script" --after soon --process fake-tests --advice "Advice." -- true 2>&1)
status=$?
check_status "$status" 2 "it refuses a limit that isn't whole seconds"
check "$output" "Usage:" "it says how to run it"

# A limit whose polls take 10 seconds: the watcher's sleep mustn't hold a pipe
# open after the command ends, as make test | tee would wait for it.
started=$SECONDS
"$script" --after 200 --process fake-tests --advice "Advice." -- sleep 1 2>&1 | cat
if ((SECONDS - started < 5)); then
  echo "ok    it holds no pipe open after the command ends"
else
  echo "FAIL  it holds no pipe open after the command ends ($((SECONDS - started)) seconds)"
  failures=$((failures + 1))
fi

results_of failing-sample
check_status "$status" 1 "a process that sample can't read still fails the run"
check "$output" "macOS's sample couldn't read process" "it says the sample failed"
check "$output" "run this again" "it says what to do then"

# A report by hand, for what a real one of a hung process rarely shows.
cat >"$tmp/report.txt" <<'REPORT'
Call graph:
    100 Thread_1   DispatchQueue_1: com.apple.main-thread  (serial)
    + 100 start  (in dyld) + 8  [0x1]
    +   100 main  (in Tool) + 8  [0x2]  main.swift:7
    +     60 heaviest  (in libsystem_kernel.dylib) + 8  [0x3]
    +     ! 60 deeper  (in libsystem_kernel.dylib) + 8  [0x4]
    +     40 lighter  (in libsystem_kernel.dylib) + 8  [0x5]
    100 Thread_2
    + 100 start_wqthread  (in libsystem_pthread.dylib) + 8  [0x6]
    +   100 _pthread_wqthread  (in libsystem_pthread.dylib) + 8  [0x7]
    +     100 __workq_kernreturn  (in libsystem_kernel.dylib) + 8  [0x8]
    100 Thread_3: a worker
    + 100 thread_start  (in libsystem_pthread.dylib) + 8  [0x9]
    +   100 ourFunction  (in Tool) + 8  [0xa]  Tool.swift:12
    +     100 aFunctionWithAVeryLongName(ofItsFirstArgument: SomeVeryLongTypeName<AnotherVeryLongTypeName>, andItsSecondArgument: YetAnotherVeryLongTypeName<AndOneMoreLongTypeName>)  (in Tool) + 8  [0x11]  Tool.swift:20
    +       100 f6  (in libsystem_c.dylib) + 8  [0xb]
    +         100 f5  (in libsystem_c.dylib) + 8  [0xc]
    +           100 f4  (in libsystem_c.dylib) + 8  [0xd]
    +             100 f3  (in libsystem_c.dylib) + 8  [0xe]
    +               100 f2  (in libsystem_c.dylib) + 8  [0xf]
    +                 100 f1  (in libsystem_c.dylib) + 8  [0x10]

Total number in stack (recursive counted multiple times):

Binary Images:
       0x100000000 -        0x100000fff +Tool (0) <UUID> /tmp/Tool
       0x200000000 -        0x200000fff  libsystem_c.dylib (1) <UUID> /usr/lib/libsystem_c.dylib
REPORT
output=$("$summary" "$tmp/report.txt" 2>&1)
check "$output" "main (Tool) main.swift:7" "it keeps a frame's image and its line"
check "$output" "deeper (libsystem_kernel.dylib)" "it follows the heaviest stack"
check_not "$output" "lighter" "it leaves out the lighter branch"
check "$output" "And 1 thread waiting for work." "it counts the threads that wait for work apart"
check "$output" "a worker: 1 thread" "it names a thread without a queue by its name"
check "$output" "f4 (libsystem_c.dylib)" "it keeps the innermost frames"
check_not "$output" "f5 (" "it cuts the frames in the middle"
check "$output" "ourFunction (Tool) Tool.swift:12" "it keeps the frames of a binary that isn't Apple's"
check "$output" "aFunctionWithAVeryLongName" "it keeps such a frame when its name runs long, as a Swift signature's does"
check "$output" "…" "it marks where it cut"

output=$("$summary" "$tmp/no-such-report.txt" 2>&1)
status=$?
check_status "$status" 1 "it fails on a report it can't read"
check "$output" "can't be read" "it says so"

if ((failures > 0)); then
  echo "$failures of the watchdog's tests failed, as the lines above say: fix scripts/watch-for-hang.sh, scripts/where-threads-wait.sh or the tests, and run make check again." >&2
  exit 1
fi
echo "All watch-for-hang tests passed"
