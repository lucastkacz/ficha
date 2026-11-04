#!/bin/bash
# Runs the `ficha` of the Ficha Dev this checkout's `make build` made, for an
# agent's tries, with these arguments and this standard input, on a scratch
# folder alone, so Ficha Dev's own cards stay as they were:
#
#   FICHA_DEV_SCRATCH=<name> scripts/ficha-dev.sh <command>
#
# With --delete-scratch-zones it runs Ficha Dev's own binary instead, which
# deletes that scratch run's zones from iCloud, and only theirs. Its path, like
# the CLI's, has a space, which Claude's Bash refuses in a worktree. The script
# is our own.

set -u

root=$(cd "$(dirname "$0")/.." && pwd)
app="$root/.build/DerivedData/Build/Products/Debug/Ficha Dev.app"

[[ -n ${FICHA_DEV_SCRATCH:-} ]] || {
  echo "FICHA_DEV_SCRATCH isn't set, and agents never run on Ficha Dev's own cards: name a scratch folder, as in FICHA_DEV_SCRATCH=<name> scripts/ficha-dev.sh <command>." >&2
  exit 1
}
export FICHA_DEV_SCRATCH

if [[ ${1:-} == --delete-scratch-zones ]]; then
  binary="$app/Contents/MacOS/Ficha Dev"
else
  binary="$app/Contents/Helpers/ficha"
fi

[[ -x $binary ]] || {
  echo "$binary isn't built: copy iPhone/Local.xcconfig into this checkout from the main folder, and run make build, as docs/development.md explains." >&2
  exit 1
}

exec "$binary" "$@"
