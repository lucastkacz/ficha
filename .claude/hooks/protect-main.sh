#!/bin/bash
# Keeps main clean (PreToolUse on Bash and on the terminal panel). Every change
# reaches main through a pull request (CLAUDE.md), so a git command that would
# commit, merge or rewrite history on main is blocked: in the command's
# directory, in any `cd <dir>` or `git -C <dir>` it names, or after it switches
# to main. `git pull --ff-only` passes: it's how main gets updated. GitHub's
# ruleset is the lock on the remote; this hook stops the mistake locally, and
# errs on the side of blocking.

input=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
base=$(jq -r '.cwd // "."' <<<"$input")
panel_dir=$(jq -r '.tool_input.cwd // ""' <<<"$input")

resolve() {
  local path=${1//[\"\']/}
  path=${path//\$\{CLAUDE_PROJECT_DIR\}/${CLAUDE_PROJECT_DIR:-}}
  path=${path//\$CLAUDE_PROJECT_DIR/${CLAUDE_PROJECT_DIR:-}}
  path=${path//\$HOME/$HOME}
  [[ $path == "~"* ]] && path=$HOME${path:1}
  [[ $path == /* ]] || path="$base/$path"
  echo "$path"
}

# git, its options, then a subcommand that changes a branch's history.
changes='(^|[^[:alnum:]_.-])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+(commit|merge|cherry-pick|revert|am|rebase|pull)([[:space:]]|$)'
switch_to_main='(^|[^[:alnum:]_.-])git[[:space:]]+(switch|checkout)[[:space:]]+main([;&|[:space:]]|$)'

subcommands=()
rest=$cmd
while [[ $rest =~ $changes ]]; do
  subcommands+=("${BASH_REMATCH[4]}")
  rest=${rest#*"${BASH_REMATCH[0]}"}
done
((${#subcommands[@]} > 0)) || exit 0

# Fast-forward pulls are how main is updated.
only_pulls=1
for subcommand in "${subcommands[@]}"; do [[ $subcommand == pull ]] || only_pulls=0; done
((only_pulls)) && [[ $cmd == *--ff-only* ]] && exit 0

block() {
  echo "On main nothing is committed or merged: create a branch <issue>-<short-name> and open a pull request (CLAUDE.md)." >&2
  exit 2
}

[[ $cmd =~ $switch_to_main ]] && block

dirs=("$base")
[[ -n $panel_dir ]] && dirs+=("$(resolve "$panel_dir")")
# The command's words, from all its lines: with -d '', read doesn't stop at the first newline.
read -r -d '' -a words <<<"$cmd"
for ((i = 0; i + 1 < ${#words[@]}; i++)); do
  case ${words[i]} in
    -C | cd) dirs+=("$(resolve "${words[i + 1]}")") ;;
  esac
done

for dir in "${dirs[@]}"; do
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null) || continue
  [[ $branch == main ]] && block
done
exit 0
