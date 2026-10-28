#!/bin/bash
# Tests scripts/clean-merged.sh, which `make clean-merged` runs; `make check`
# runs this. Each case is a worktree of a scratch repo, which has a scratch
# origin, and a fake `gh` answers which pull requests merged and which are
# open from files, so nothing reaches GitHub.

set -u
script="$(cd "$(dirname "$0")" && pwd)/clean-merged.sh"
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

# The fake gh answers `pr list --state <state>` from $FAKE_GH/prs-<state>.json,
# applying --jq like the real one. A missing file is a failure.
mkdir -p "$tmp/bin" "$tmp/gh"
cat >"$tmp/bin/gh" <<'EOF'
#!/bin/bash
args=("$@")
state=""
query=""
for ((i = 0; i < ${#args[@]}; i++)); do
  case ${args[i]} in
    --state) state=${args[i + 1]} ;;
    --jq) query=${args[i + 1]} ;;
  esac
done
[[ "$1 $2" == "pr list" ]] || exit 1
file="$FAKE_GH/prs-$state.json"
[[ -f $file ]] || exit 1
if [[ -n $query ]]; then jq -r "$query" "$file"; else cat "$file"; fi
EOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" FAKE_GH="$tmp/gh"

# The main folder, on main, with an origin, ignoring what Ficha's ignores.
main="$tmp/main"
worktrees="$main/.claude/worktrees"
git init -q --bare -b main "$tmp/origin.git"
git init -q -b main "$main"
printf '.build/\n.claude/worktrees/\n' >"$main/.gitignore"
git -C "$main" add .gitignore
git -C "$main" commit -q -m init
git -C "$main" remote add origin "$tmp/origin.git"
git -C "$main" push -q -u origin main

# commit <dir> <text>: a commit of its own in a worktree, to a file named after
# it, so joined branches don't conflict.
commit() {
  echo "$2" >>"$1/${1##*/}.txt"
  git -C "$1" add "${1##*/}.txt"
  git -C "$1" commit -q -m "$2"
}
# worktree <name> <branch>: a worktree on a new branch from main, with a commit of its own.
worktree() {
  git -C "$main" worktree add -q -b "$2" "$worktrees/$1" main
  commit "$worktrees/$1" "$1"
}
tip() { git -C "$1" rev-parse HEAD; }

worktree 10-merged 10-merged
mkdir -p "$worktrees/10-merged/.build"
echo build >"$worktrees/10-merged/.build/product"
worktree 11-dirty 11-dirty
worktree 12-ahead 12-ahead
merged_12=$(tip "$worktrees/12-ahead")
commit "$worktrees/12-ahead" "after the merge"
worktree 13-open 13-open
# An implementer's branch, joined into its spec's branch, which then goes on.
worktree agent-a1 worktree-agent-a1
worktree 14-spec 14-spec
git -C "$worktrees/14-spec" merge -q --no-edit worktree-agent-a1
commit "$worktrees/14-spec" "after the implementer"
git -C "$main" worktree add -q -b 15-fresh "$worktrees/15-fresh" main
# Claude Code locks a session's worktree with its process's pid: this test's
# own, which runs, and one that ended.
worktree 16-live 16-live
git -C "$main" worktree lock --reason "claude session 16-live (pid $$ start Wed Oct 28 00:54:27 2026)" "$worktrees/16-live"
worktree 17-ended 17-ended
sleep 0 &
ended=$!
wait "$ended"
git -C "$main" worktree lock --reason "claude session 17-ended (pid $ended start Wed Oct 28 00:54:27 2026)" "$worktrees/17-ended"

cat >"$tmp/gh/prs-merged.json" <<EOF
[{"number":10,"headRefOid":"$(tip "$worktrees/10-merged")"},
 {"number":11,"headRefOid":"$(tip "$worktrees/11-dirty")"},
 {"number":12,"headRefOid":"$merged_12"},
 {"number":14,"headRefOid":"$(tip "$worktrees/14-spec")"},
 {"number":16,"headRefOid":"$(tip "$worktrees/16-live")"},
 {"number":17,"headRefOid":"$(tip "$worktrees/17-ended")"}]
EOF
echo '[{"number":13,"headRefName":"13-open"}]' >"$tmp/gh/prs-open.json"
echo "uncommitted" >>"$worktrees/11-dirty/11-dirty.txt"

# Another clone moves origin's main forward, as a squash merge does.
git clone -q "$tmp/origin.git" "$tmp/other"
commit "$tmp/other" "squashed"
git -C "$tmp/other" push -q origin main

# expect_kept <description> <worktree> <branch> <part of the reason listed>
expect_kept() {
  if ! [[ -d $worktrees/$2 ]] || ! git -C "$main" rev-parse -q --verify "refs/heads/$3" >/dev/null; then
    fail "$1 (the worktree or its branch is gone)"
  elif [[ $output != *"Kept $2: "*"$4"* ]]; then
    fail "$1 (it isn't listed with \"$4\": $output)"
  else
    pass "$1"
  fi
}
# expect_gone <description> <worktree> <branch>

expect_gone() {
  if [[ ! -e $worktrees/$2 ]] && ! git -C "$main" rev-parse -q --verify "refs/heads/$3" >/dev/null; then
    pass "$1"
  else
    fail "$1 (the worktree or its branch stays)"
  fi
}
expect_nothing_removed() {
  local count
  count=$(find "$worktrees" -mindepth 1 -maxdepth 1 -type d | wc -l)
  if [[ $1 != 0 && $count -eq 9 ]]; then pass "$2"; else fail "$2 (exit $1, $count of 9 worktrees left)"; fi
}

echo "clean-merged"
mv "$tmp/gh/prs-merged.json" "$tmp/gh/unreachable.json"
(cd "$main" && "$script") >/dev/null 2>&1
expect_nothing_removed $? "nothing is removed when GitHub can't be reached"
mv "$tmp/gh/unreachable.json" "$tmp/gh/prs-merged.json"
(cd "$worktrees/13-open" && "$script") >/dev/null 2>&1
expect_nothing_removed $? "nothing is removed when it runs outside the main folder"

output=$(cd "$main" && "$script" 2>&1)
status=$?
if [[ $status == 0 ]]; then pass "it succeeds in the main folder on main"; else fail "it succeeds in the main folder on main (exit $status: $output)"; fi
expect_gone "a merged, clean worktree goes with its branch and its build folders" 10-merged 10-merged
expect_kept "a worktree with uncommitted changes stays" 11-dirty 11-dirty "uncommitted changes"
expect_kept "a worktree whose head isn't the merged pull request's stays" 12-ahead 12-ahead "isn't merged"
expect_kept "a worktree whose pull request is open stays" 13-open 13-open "#13, is still open"
expect_gone "an implementer's branch inside a merged spec's branch goes" agent-a1 worktree-agent-a1
expect_gone "the merged spec's branch goes" 14-spec 14-spec
expect_kept "a worktree with no commits of its own stays" 15-fresh 15-fresh "no commits of its own"
expect_kept "a worktree a running session holds stays" 16-live 16-live "a running process"
expect_gone "a worktree a session that ended held goes" 17-ended 17-ended
if [[ $(git -C "$main" rev-parse main) == $(git -C "$tmp/other" rev-parse main) ]]; then
  pass "main is brought up to date with origin"
else
  fail "main is brought up to date with origin"
fi

if ((failures > 0)); then
  echo "$failures clean-merged test(s) failed"
  exit 1
fi
echo "All clean-merged tests passed"
