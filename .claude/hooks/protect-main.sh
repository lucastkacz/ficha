#!/bin/bash
# Keeps main clean (PreToolUse on Bash). Every change reaches main through a
# pull request (CLAUDE.md), so a command that would commit or merge while the
# main branch is checked out is blocked. Pulling with --ff-only, other commands
# and other branches pass. GitHub's ruleset is the lock on the remote; this hook
# stops the mistake before it's made locally.

input=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
dir=$(jq -r '.cwd // "."' <<<"$input")

# git commit|merge|cherry-pick|revert|am|rebase, also as `git -C <dir> ...`.
pattern='(^|[^[:alnum:]_./-])git[[:space:]]+(-C[[:space:]]+([^[:space:]]+)[[:space:]]+)?(commit|merge|cherry-pick|revert|am|rebase)([[:space:]]|$)'
[[ $cmd =~ $pattern ]] || exit 0
if [[ -n ${BASH_REMATCH[3]} ]]; then
  target=${BASH_REMATCH[3]//[\"\']/}
  [[ $target == "~"* ]] && target=$HOME${target:1}
  if [[ $target == /* ]]; then dir=$target; else dir="$dir/$target"; fi
fi

branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
[[ $branch == main ]] || exit 0

echo "On main nothing is committed or merged: create a branch <issue>-<short-name> and open a pull request (CLAUDE.md)." >&2
exit 2
