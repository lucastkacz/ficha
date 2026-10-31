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
#   checked, so the only push allowed then is `git push [-u] origin <branch>`,
#   or `git -C <dir> push [-u] origin <branch>`, to a branch without
#   auto-merge.

shopt -s extglob
input=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
cmd=${cmd##+([[:space:]])}
cmd=${cmd%%+([[:space:]])}
repo=${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // "."' <<<"$input")}

# The risk:high paths, each an extended regular expression that a changed
# file's path matches from its start. One per line, so two branches that each
# add one change different lines: that layout is our own.
risky_paths=(
  # The process: what agents read, and what they may do.
  'CLAUDE\.md'
  'CODING_STANDARDS\.md'
  '\.claude/'
  'docs/agents/'
  # The content guide, which every card Claude drafts follows.
  'docs/content-guide\.md'
  # CI and the build, with their configuration files, such as the one both
  # apps sign with (Signing.xcconfig), and what their sandboxes let each app,
  # its CLI, its widget and its SVG drawer, the one on the network, reach:
  # their entitlements, and the CLI's Info.plist, which gives it a sandbox of
  # its own (ADR 0018). And how `make upload` sends the real Ficha to
  # TestFlight, and for whom (ExportOptions.plist).
  '\.github/workflows/'
  '\.github/dependabot\.yml'
  'Makefile'
  'scripts/'
  '\.swift-format'
  '\.xcode-version'
  'project\.yml'
  '.*\.xcconfig$'
  '.*\.entitlements$'
  'CLI/Info\.plist'
  'ExportOptions\.plist'
  # The package's manifest, and the versions it pins.
  'Packages/FichaKit/Package\.swift'
  'Packages/FichaKit/Package\.resolved'
  # The database schema and its migrations, which all live in FichaData/Schema*.
  'Packages/FichaKit/Sources/FichaData/Schema'
  # The one way in to the cards that show up, those in Lucas's reviews, and
  # which cards take an answer.
  'Packages/FichaKit/Sources/FichaData/CardsInReviews\.swift'
  # The scheduler, which moves cards on the ladder, says where a card stands:
  # in Lucas's reviews, waiting in the inbox, buried, or set aside by its deck
  # or a deck it sits inside, and keeps the cards in his reviews for the
  # planners to pick from.
  'Packages/FichaKit/Sources/FichaCore/Scheduler/'
  # Which decks a deck sits inside, named as tags inside tags are (ADR 0021,
  # ADR 0024), which the scheduler reads to say a card is set aside by a deck
  # its deck sits inside, and to tell which cards are in a priority deck or a
  # deck inside one.
  'Packages/FichaKit/Sources/FichaCore/TagsInsideTags\.swift'
  # Which cards review now brings, when the review panel shows up on its own
  # and with which cards, the settings' defaults, and the trigger's names,
  # which the review log stores.
  'Packages/FichaKit/Sources/FichaCore/ReviewNow\.swift'
  'Packages/FichaKit/Sources/FichaCore/AppearancePlanner\.swift'
  'Packages/FichaKit/Sources/FichaCore/ReviewSettings\.swift'
  'Packages/FichaKit/Sources/FichaCore/Trigger\.swift'
)

# `gh` with `merge` later in the same command, in any form or place.
merge_anywhere='(^|[^[:alnum:]_.-])gh[[:space:]]([^;&|]*[[:space:]])?merge([[:space:]]|$)'
merge_alone='^gh pr merge ([0-9]+)( --[a-z-]+)*$'
# `git push`, also with options before `push` (`git -C <dir> push`).
push_anywhere='(^|[^[:alnum:]_.-])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+push([[:space:]]|$)'
# A folder or a branch written out, with no quotes, spaces or expansions,
# which could hide a command, as `x;{git,push,origin,<branch>};cd` would.
plain='[[:alnum:]._/-]+'
# The push that names its branch, also from another folder (`git -C <dir>
# push`): `-C` changes the folder git runs in, not the branch a name pushes.
push_alone="^git (-C $plain )?push( -u)? origin ($plain)\$"

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
  risky=$(jq -r '.files[].path' <<<"$info" | grep -E -f <(printf '^(%s)\n' "${risky_paths[@]}"))
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
    block "Some pull requests have auto-merge on ($armed): push with \`git push origin <branch>\` on its own, or \`git -C <dir> push origin <branch>\` with <dir> written out, without quotes, spaces or variables, so this hook can check the branch."
  branch=${BASH_REMATCH[3]#refs/heads/}
  # `HEAD`, in whatever case, is whichever branch git finds checked out, which
  # the hook can't see: in a worktree, on macOS, `head` finds the main folder's.
  [[ $branch == [Hh][Ee][Aa][Dd] ]] &&
    block "Some pull requests have auto-merge on ($armed): name the branch instead of HEAD, as in \`git push origin <branch>\`, so this hook can check it."
  for armed_branch in $armed; do
    [[ $armed_branch == "$branch" ]] &&
      block "The pull request for $branch has auto-merge on, so a push could merge files nobody checked. Turn it off with \`gh pr merge <number> --disable-auto\`, push, and turn it on again with \`gh pr merge <number> --auto --squash\`, which checks the PR again (CLAUDE.md)."
  done
fi
exit 0
