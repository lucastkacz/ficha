#!/bin/bash
# Tests the Claude Code hooks in .claude/hooks; `make check` runs it.
# Each case feeds a hook the JSON Claude Code sends and checks its exit code or
# output. A fake `gh` answers from files, so nothing reaches GitHub.

set -u
root=$(cd "$(dirname "$0")/.." && pwd)
hooks="$root/.claude/hooks"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

pass() { echo "ok    $1"; }
fail() {
  echo "FAIL  $1"
  failures=$((failures + 1))
}

# expect <exit code> <description> <hook> <input json>
expect() {
  local got
  "$hooks/$3" <<<"$4" >/dev/null 2>&1
  got=$?
  if [[ $got == "$1" ]]; then pass "$2"; else fail "$2 (exit $got, expected $1)"; fi
}

bash_input() { jq -n --arg command "$1" --arg cwd "$2" '{tool_input: {command: $command}, cwd: $cwd}'; }

# A repo with main checked out, and a worktree on a branch.
git init -q -b main "$tmp/repo"
git -C "$tmp/repo" -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m init
git -C "$tmp/repo" worktree add -q -b 7-feature "$tmp/branch"

# The fake gh: `pr view [<pr>]` answers $FAKE_GH/pr-<pr>.json (pr-current.json without a PR),
# `issue list` and `pr list` answer issues.json and prs.json. A missing file is a failure.
mkdir -p "$tmp/bin" "$tmp/gh"
cat >"$tmp/bin/gh" <<'EOF'
#!/bin/bash
case "$1 $2" in
  "pr view") pr=current; [[ -n ${3:-} && $3 != -* ]] && pr=$3; cat "$FAKE_GH/pr-$pr.json" 2>/dev/null ;;
  "issue list") cat "$FAKE_GH/issues.json" 2>/dev/null ;;
  "pr list") cat "$FAKE_GH/prs.json" 2>/dev/null ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" FAKE_GH="$tmp/gh"

echo "protect-main"
expect 2 "a commit on main is blocked" protect-main.sh "$(bash_input 'git commit -m change' "$tmp/repo")"
expect 2 "a commit on main through git -C is blocked" protect-main.sh "$(bash_input "git -C $tmp/repo commit -m change" "$tmp")"
expect 2 "a merge on main is blocked" protect-main.sh "$(bash_input 'git merge 7-feature' "$tmp/repo")"
expect 0 "a commit on a branch passes" protect-main.sh "$(bash_input 'git commit -m change' "$tmp/branch")"
expect 0 "pulling main with --ff-only passes" protect-main.sh "$(bash_input 'git pull --ff-only' "$tmp/repo")"
expect 0 "git status on main passes" protect-main.sh "$(bash_input 'git status' "$tmp/repo")"

echo "merge-gate"
echo '{"number":12,"labels":[],"files":[{"path":"Packages/FichaKit/Sources/FichaCore/Ladder.swift"}]}' >"$tmp/gh/pr-12.json"
echo '{"number":13,"labels":[{"name":"risk:high"}],"files":[{"path":"App/FichaApp.swift"}]}' >"$tmp/gh/pr-13.json"
echo '{"number":14,"labels":[],"files":[{"path":"CLAUDE.md"}]}' >"$tmp/gh/pr-14.json"
echo '{"number":15,"labels":[],"files":[{"path":"App/FichaApp.swift"}]}' >"$tmp/gh/pr-current.json"
expect 0 "a normal PR can be merged" merge-gate.sh "$(bash_input 'gh pr merge 12 --auto --squash' "$tmp/branch")"
expect 0 "the current branch's normal PR can be merged" merge-gate.sh "$(bash_input 'gh pr merge --auto --squash' "$tmp/branch")"
expect 2 "a PR labeled risk:high is blocked" merge-gate.sh "$(bash_input 'gh pr merge 13 --auto --squash' "$tmp/branch")"
expect 2 "a PR that changes CLAUDE.md is blocked" merge-gate.sh "$(bash_input 'gh pr merge --squash 14' "$tmp/branch")"
expect 2 "a PR that can't be checked is blocked" merge-gate.sh "$(bash_input 'gh pr merge 99 --squash' "$tmp/branch")"
expect 0 "other gh commands pass" merge-gate.sh "$(bash_input 'gh pr view 13' "$tmp/branch")"

echo "swift-format"
printf 'let  x=1\n' >"$tmp/Sample.swift"
jq -n --arg file "$tmp/Sample.swift" '{tool_input: {file_path: $file}}' | "$hooks/swift-format.sh"
if [[ $(cat "$tmp/Sample.swift") == "let x = 1" ]]; then
  pass "an edited Swift file is formatted"
else
  fail "an edited Swift file is formatted (got: $(cat "$tmp/Sample.swift"))"
fi

echo "session-start"
echo 'This map matches mattpocock-skills 1.2.3; when the version changes, update it.' >"$tmp/repo/CLAUDE.md"
installed_plugin() {
  jq -n --arg version "$1" \
    '{plugins: {"mattpocock-skills@claude-plugins-official": [{version: $version, projectPath: "/elsewhere"}]}}' \
    >"$tmp/plugins.json"
}
export FICHA_PLUGINS_FILE="$tmp/plugins.json"
session_context() { CLAUDE_PROJECT_DIR="$tmp/repo" "$hooks/session-start.sh" | jq -r '.hookSpecificOutput.additionalContext'; }

installed_plugin 1.2.3
echo '[{"number":21,"title":"Cards climb the ladder","labels":[{"name":"ready-for-agent"}]}]' >"$tmp/gh/issues.json"
echo '[{"number":22,"title":"Menu bar skeleton","isDraft":true}]' >"$tmp/gh/prs.json"
context=$(session_context)
if [[ $context == *"#21 Cards climb the ladder"* && $context == *"#22 Menu bar skeleton (draft)"* && $context != *"skill map"* ]]; then
  pass "open work is listed at session start"
else
  fail "open work is listed at session start (got: $context)"
fi

installed_plugin 1.3.1
context=$(session_context)
if [[ $context == *"mattpocock-skills is now 1.3.1"*"is for 1.2.3"* ]]; then
  pass "a plugin update that outdates the skill map is flagged"
else
  fail "a plugin update that outdates the skill map is flagged (got: $context)"
fi

installed_plugin 1.2.3
rm "$tmp/gh/issues.json"
output=$(CLAUDE_PROJECT_DIR="$tmp/repo" "$hooks/session-start.sh")
status=$?
if [[ $status == 0 && -z $output ]]; then
  pass "nothing is said when GitHub can't be reached and the map is current"
else
  fail "nothing is said when GitHub can't be reached and the map is current (exit $status, output: $output)"
fi

if ((failures > 0)); then
  echo "$failures hook test(s) failed"
  exit 1
fi
echo "All hook tests passed"
