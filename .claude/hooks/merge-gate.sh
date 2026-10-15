#!/bin/bash
# Keeps risk:high pull requests for Lucas (PreToolUse on Bash and on the
# terminal panel). Claude merges a PR only when it isn't risk:high (CLAUDE.md),
# and Claude works with Lucas's GitHub account, so GitHub can't tell them
# apart: this hook is the lock. It fails closed: when in doubt, it blocks.
#
# - Merging: the only form allowed is a command on its own,
#   `gh pr merge <number> --flags`. The PR is blocked when it's labeled
#   risk:high, changes a risk:high path, or has more files than GitHub lists.
#   Turning auto-merge off (`--disable-auto`) always passes.
# - Pushing: while a PR has auto-merge on, a push could land files nobody
#   checked, so the only push allowed then is `git push [-u] origin <branch>`
#   to a branch without auto-merge.

shopt -s extglob
input=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
cmd=${cmd##+([[:space:]])}
cmd=${cmd%%+([[:space:]])}
repo=${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // "."' <<<"$input")}

# The risk:high paths. Among them, the database schema and its migrations, which
# all live in FichaData/Schema*, and the scheduler, which moves cards on the
# ladder, in FichaCore/Scheduler/. The PR that creates the content guide adds
# its path here (CLAUDE.md).
risky_paths='^(CLAUDE\.md|CODING_STANDARDS\.md|\.claude/|docs/agents/|\.github/workflows/|\.github/dependabot\.yml|Makefile|scripts/|\.swift-format|project\.yml|Packages/FichaKit/Package\.(swift|resolved)|Packages/FichaKit/Sources/FichaData/Schema|Packages/FichaKit/Sources/FichaCore/Scheduler/)'

# `gh` with `merge` later in the same command, in any form or place.
merge_anywhere='(^|[^[:alnum:]_.-])gh[[:space:]]([^;&|]*[[:space:]])?merge([[:space:]]|$)'
merge_alone='^gh pr merge ([0-9]+)( --[a-z-]+)*$'
# `git push`, also with options before `push` (`git -C <dir> push`).
push_anywhere='(^|[^[:alnum:]_.-])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+push([[:space:]]|$)'
push_alone='^git push( -u)? origin ([[:alnum:]._/-]+)$'

block() {
  echo "$1" >&2
  exit 2
}

# --- Merging ------------------------------------------------------------------
if [[ $cmd == *mergePullRequest* || $cmd == *enablePullRequestAutoMerge* ]]; then
  block "Merging through GitHub's API isn't allowed: use \`gh pr merge <number> --auto --squash\` (CLAUDE.md)."
fi

if [[ $cmd =~ $merge_anywhere ]]; then
  [[ $cmd =~ $merge_alone ]] ||
    block "Merge with one command on its own, \`gh pr merge <number> --auto --squash\`, so this hook can check the PR (CLAUDE.md)."
  pr=${BASH_REMATCH[1]}
  [[ $cmd == *" --disable-auto"* ]] && exit 0

  info=$(cd "$repo" 2>/dev/null && gh pr view "$pr" --json number,labels,files,changedFiles 2>/dev/null) ||
    block "Couldn't check pull request #$pr's labels and files, so it isn't merged. Tell Lucas."
  ready="Lucas reviews and merges it (CLAUDE.md): tell him it's ready."
  if jq -e '.labels | any(.name == "risk:high")' <<<"$info" >/dev/null; then
    block "Pull request #$pr is labeled risk:high. $ready"
  fi
  if ! jq -e '(.files | length) == .changedFiles' <<<"$info" >/dev/null; then
    block "Pull request #$pr changes more files than GitHub lists, so its risk can't be checked. $ready"
  fi
  risky=$(jq -r '.files[].path' <<<"$info" | grep -E "$risky_paths")
  [[ -z $risky ]] || block "Pull request #$pr changes risk:high files: $(tr '\n' ' ' <<<"$risky")$ready"
  exit 0
fi

# --- Pushing ------------------------------------------------------------------
if [[ $cmd =~ $push_anywhere ]]; then
  armed=$(cd "$repo" 2>/dev/null && gh pr list --state open --json headRefName,autoMergeRequest \
    --jq '[.[] | select(.autoMergeRequest != null) | .headRefName] | join(" ")' 2>/dev/null) ||
    block "Couldn't check which pull requests have auto-merge on, so nothing is pushed. Tell Lucas."
  [[ -z $armed ]] && exit 0
  [[ $cmd =~ $push_alone ]] ||
    block "Some pull requests have auto-merge on ($armed): push with \`git push origin <branch>\` on its own, so this hook can check the branch."
  branch=${BASH_REMATCH[2]}
  for armed_branch in $armed; do
    [[ $armed_branch == "$branch" ]] &&
      block "The pull request for $branch has auto-merge on, so a push could merge files nobody checked. Turn it off with \`gh pr merge <number> --disable-auto\`, push, and turn it on again with \`gh pr merge <number> --auto --squash\`, which checks the PR again (CLAUDE.md)."
  done
fi
exit 0
