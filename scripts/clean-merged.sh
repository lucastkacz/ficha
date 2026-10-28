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

fail() {
  echo "$1" >&2
  exit 1
}

root=$(git rev-parse --show-toplevel 2>/dev/null) ||
  fail "This isn't a git repository: run make clean-merged from Ficha's main folder."
cd "$root" || exit 1
git_dirs=$(git rev-parse --path-format=absolute --git-dir --git-common-dir) || exit 1
[[ ${git_dirs%%$'\n'*} == "${git_dirs##*$'\n'}" ]] ||
  fail "$root is a worktree: run make clean-merged from the main folder, which holds the worktrees."
[[ $(git symbolic-ref --short -q HEAD) == main ]] ||
  fail "The main folder isn't on main: switch it back to main, then run make clean-merged again."

# The pull requests, one per line: the merged ones' number and head commit,
# and the open ones' number and branch.
merged=$(gh pr list --state merged --limit 200 --json number,headRefOid --jq '.[] | "\(.number) \(.headRefOid)"') ||
  fail "Couldn't list the merged pull requests, so no worktree was removed: check that gh reaches GitHub (gh auth status), then run make clean-merged again."
open=$(gh pr list --state open --limit 200 --json number,headRefName --jq '.[] | "\(.number) \(.headRefName)"') ||
  fail "Couldn't list the open pull requests, so no worktree was removed: check that gh reaches GitHub (gh auth status), then run make clean-merged again."

# The merged pull request whose head is commit $1, or holds it, by number.
merged_pr() {
  local number oid
  while read -r number oid; do
    [[ $oid == "$1" ]] && echo "$number" && return 0
  done <<<"$merged"
  while read -r number oid; do
    [[ -n $oid ]] && git merge-base --is-ancestor "$1" "$oid" 2>/dev/null && echo "$number" && return 0
  done <<<"$merged"
  return 1
}

# The open pull request from branch $1, by number.
open_pr() {
  local number branch
  while read -r number branch; do
    [[ $branch == "$1" ]] && echo "$number" && return 0
  done <<<"$open"
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
claude_lock='^claude .*\(pid ([0-9]+)'

keep() { echo "Kept $name: $1"; }

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
  if pr=$(open_pr "$branch"); then
    keep "its pull request, #$pr, is still open."
    continue
  fi
  head=$(git -C "$dir" rev-parse HEAD)
  if on_main "$head"; then
    keep "its branch, $branch, has no commits of its own: its session may have only just started."
    continue
  fi
  if ! pr=$(merged_pr "$head"); then
    keep "no merged pull request holds its branch's last commit, ${head:0:7}: its work isn't merged."
    continue
  fi
  lock="$(git -C "$dir" rev-parse --absolute-git-dir)/locked"
  if [[ -f $lock ]]; then
    reason=$(<"$lock")
    if ! [[ $reason =~ $claude_lock ]]; then
      keep "it's locked ($reason): once nothing uses it, unlock it with git worktree unlock and run make clean-merged again."
      continue
    fi
    if ps -p "${BASH_REMATCH[1]}" >/dev/null; then
      keep "pull request #$pr merged its work, but a running process, pid ${BASH_REMATCH[1]}, holds it, most likely its session: archive the session, then run make clean-merged again."
      continue
    fi
    git worktree unlock "$dir"
  fi
  if ! error=$(git worktree remove "$dir" 2>&1); then
    keep "git couldn't remove it: $error"
    continue
  fi
  if error=$(git branch -D "$branch" 2>&1); then
    echo "Removed $name and its branch, $branch: pull request #$pr merged its work."
  else
    echo "Removed $name, but git couldn't delete its branch, $branch: $error"
  fi
done

error=$(git pull --ff-only --quiet 2>&1) ||
  fail "git pull --ff-only couldn't bring main up to date: $error"
