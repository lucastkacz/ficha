#!/bin/bash
# Removes each worktree in .claude/worktrees whose work is all in a merged
# pull request, with its branch and its build folders, lists the others with
# the reason each stays, and then updates main. `make clean-merged` runs it
# from the main folder, on main; CLAUDE.md says who runs it and when, and
# docs/development.md what it checks.
#
# Nothing is lost when a worktree has no uncommitted changes and its branch's
# head is a merged pull request's head, or inside one, as an implementer's
# branch joined into a spec's branch is: that check stands in for the prompt
# `git branch -D` asks when typed by hand. Reading Claude Code's locks is our
# own.

set -u
shopt -s nullglob

die() {
  echo "$1" >&2
  exit 1
}

root=$(git rev-parse --show-toplevel 2>/dev/null) ||
  die "This isn't a git repository: run make clean-merged from Ficha's main folder."
cd "$root" || die "Couldn't enter $root: run make clean-merged from Ficha's main folder."
git_dirs=$(git rev-parse --path-format=absolute --git-dir --git-common-dir) ||
  die "Couldn't tell whether $root is the main folder: git 2.31 or later reads --path-format, so update git, then run make clean-merged again."
[[ ${git_dirs%%$'\n'*} == "${git_dirs##*$'\n'}" ]] ||
  die "$root is a worktree: run make clean-merged from the main folder, which holds the worktrees."
[[ $(git symbolic-ref --short -q HEAD) == main ]] ||
  die "The main folder isn't on main: switch it back to main, then run make clean-merged again."

# The pull requests in state $1, one per line: number and head commit.
pull_requests() {
  gh pr list --state "$1" --limit 200 --json number,headRefOid --jq '.[] | "\(.number) \(.headRefOid)"' ||
    die "Couldn't list the $1 pull requests, so no worktree was removed: check that gh reaches GitHub (gh auth status), then run make clean-merged again."
}
merged=$(pull_requests merged) || exit 1
open=$(pull_requests open) || exit 1

# The pull request among the lines $1 whose head is commit $2, or holds it,
# by number.
holding() {
  local number oid
  while read -r number oid; do
    [[ $oid == "$2" ]] && echo "$number" && return 0
  done <<<"$1"
  while read -r number oid; do
    [[ -n $oid ]] && git merge-base --is-ancestor "$2" "$oid" 2>/dev/null && echo "$number" && return 0
  done <<<"$1"
  return 1
}

# Whether commit $1 is on main, here or on origin: a branch with no commits
# of its own, as a session's that just started.
on_main() {
  git merge-base --is-ancestor "$1" main 2>/dev/null ||
    git merge-base --is-ancestor "$1" refs/remotes/origin/main 2>/dev/null
}

# Claude Code locks a session's worktree while the session runs, as
# "claude session <name> (pid <n> start <time>)", and leaves the lock when it
# ends.
claude_lock_pattern='^claude .*\(pid ([0-9]+)'

# keep <reason>: lists the worktree the loop is on, $name, as staying.
keep() { echo "Kept $name: $1"; }

# The worktrees that go, with their branches and the pull requests that merged
# their work, all decided before any goes: a spec's branch holds the commits
# of the implementers' branches joined into it.
going=()
branches=()
pull_request_numbers=()
for dir in "$root"/.claude/worktrees/*/; do
  dir=${dir%/}
  name=${dir##*/}
  if [[ $(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) != "$dir" ]]; then
    keep "it isn't a worktree of this repo: check what it holds, and delete it by hand."
    continue
  fi
  if ! branch=$(git -C "$dir" symbolic-ref --short -q HEAD); then
    keep "it isn't on a branch, so no pull request holds its work: check it by hand."
    continue
  fi
  if ! changes=$(git -C "$dir" status --porcelain 2>&1) || [[ -n $changes ]]; then
    keep "it has uncommitted changes, which its session or Lucas looks at."
    continue
  fi
  head=$(git -C "$dir" rev-parse HEAD)
  if on_main "$head"; then
    keep "its branch, $branch, has no commits of its own: its session may have only just started."
    continue
  fi
  if ! number=$(holding "$merged" "$head"); then
    if number=$(holding "$open" "$head"); then
      keep "its work is in pull request #$number, which is still open."
    else
      keep "no pull request holds its branch's last commit, ${head:0:7}: its work isn't merged."
    fi
    continue
  fi
  lock="$(git -C "$dir" rev-parse --absolute-git-dir)/locked"
  if [[ -f $lock ]]; then
    reason=$(<"$lock")
    if ! [[ $reason =~ $claude_lock_pattern ]]; then
      keep "it's locked ($reason): once nothing uses it, unlock it with git worktree unlock and run make clean-merged again."
      continue
    fi
    if ps -p "${BASH_REMATCH[1]}" >/dev/null; then
      keep "pull request #$number merged its work, but a running process, pid ${BASH_REMATCH[1]}, holds it, most likely its session: archive the session, then run make clean-merged again."
      continue
    fi
    git worktree unlock "$dir"
  fi
  going+=("$dir")
  branches+=("$branch")
  pull_request_numbers+=("$number")
done

for ((i = 0; i < ${#going[@]}; i++)); do
  name=${going[i]##*/}
  branch=${branches[i]}
  if ! error=$(git worktree remove "${going[i]}" 2>&1); then
    keep "git couldn't remove it: $error. Once that's fixed, run make clean-merged again."
  elif error=$(git branch -D "$branch" 2>&1); then
    echo "Removed $name and its branch, $branch: pull request #${pull_request_numbers[i]} merged its work."
  else
    echo "Removed $name, but git couldn't delete its branch, $branch: $error. Delete it with git branch -D $branch."
  fi
done

error=$(git pull --ff-only --quiet 2>&1) ||
  die "The worktrees above are done, but git pull --ff-only couldn't bring main up to date: $error. Fix that, then run git pull --ff-only on main."
