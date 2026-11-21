#!/bin/bash
# Tests scripts/data-changes.sh, which `make upload` runs; `make check` runs
# this. Each case is a commit of a scratch repo, tagged as an upload tags it,
# so nothing reaches GitHub.

set -u
script="$(cd "$(dirname "$0")" && pwd)/data-changes.sh"
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
  GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com \
  GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
failures=0

pass() { echo "ok    $1"; }
fail() {
  echo "FAIL  $1"
  failures=$((failures + 1))
}

repo="$tmp/repo"
git init -q -b main "$repo"
# commit <file> <subject>: changes a file of the scratch repo, and commits it
# with that subject.
commit() {
  mkdir -p "$repo/$(dirname "$1")"
  echo "$2" >>"$repo/$1"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "$2"
}
# expect_output <description> <pattern> [<commit>]: runs the script on the
# scratch repo, and checks its output matches the pattern.
expect_output() {
  local output
  output=$(cd "$repo" && "$script" ${3:+"$3"} 2>&1)
  # shellcheck disable=SC2053 # The pattern is a glob on purpose.
  if [[ $output == $2 ]]; then pass "$1"; else fail "$1 (got: $output)"; fi
}

kit=Packages/FichaKit
commit App/MenuContent.swift "The menu's first line"
expect_output "with no upload tagged yet, it says there's nothing to compare" "*nothing to compare yet*"

git -C "$repo" tag -a build-1 -m "Build 1"
commit App/MenuContent.swift "The menu's second line"
expect_output "a change outside the cards' data isn't listed" "Since build-1, nothing changed*"

subjects=()
# data <file> <what it holds>: commits a change to one of the cards' data.
data() {
  commit "$kit/$1" "$2"
  subjects+=("$2")
}
data Sources/FichaData/Schema.swift "the schema"
data Sources/FichaData/SchemaLadderCarryOver.swift "a migration"
data Sources/FichaData/CardsInReviews.swift "the way in to the cards in the reviews"
data Sources/FichaCore/Scheduler/CardStanding.swift "where a card stands"
data Sources/FichaCore/TagsInsideTags.swift "which decks a deck sits inside"
data Sources/FichaCore/ReviewNow.swift "which cards review now brings"
data Sources/FichaCore/AppearancePlanner.swift "when the review panel shows up"
data Sources/FichaCore/ReviewSettings.swift "the settings' defaults"
data Sources/FichaCore/Trigger.swift "the trigger's names"
data Rust/Cargo.lock "the version of fsrs-rs"
data Sources/FichaFSRS/FSRS.swift "the Swift that wraps fsrs-rs"
commit $kit/Sources/FichaData/FlaggingAndBurying.swift "how a card is flagged, outside the list"
for subject in "${subjects[@]}"; do
  expect_output "a change to $subject is listed" "Since build-1, these changed*$subject*"
done
output=$(cd "$repo" && "$script" 2>&1)
if [[ $output != *"outside the list"* && $output != *"The menu's"* ]]; then
  pass "a change outside the cards' data isn't listed among them"
else
  fail "a change outside the cards' data isn't listed among them (got: $output)"
fi

git -C "$repo" tag -a build-15 -m "Build 15"
commit App/MenuContent.swift "The menu's third line"
expect_output "it compares with the last upload's tag" "Since build-15, nothing changed*"
expect_output "a commit given is compared with instead" "Since build-1, these changed*the schema*" build-1

if ((failures > 0)); then
  echo "$failures test(s) of the list of changes to the cards' data failed"
  exit 1
fi
echo "All the tests of the list of changes to the cards' data passed"
