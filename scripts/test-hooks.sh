#!/bin/bash
# Tests the Claude Code hooks in .claude/hooks; `make check` runs it.
# Each case feeds a hook the JSON Claude Code sends and checks its exit code or
# output. A fake `gh` answers from files, so nothing reaches GitHub.

set -u
root=$(cd "$(dirname "$0")/.." && pwd)
hooks="$root/.claude/hooks"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
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

# A Bash call: bash_input <command> <cwd>. A terminal panel call adds the panel's own cwd.
bash_input() { jq -n --arg command "$1" --arg cwd "$2" '{tool_input: {command: $command}, cwd: $cwd}'; }
panel_input() {
  jq -n --arg command "$1" --arg cwd "$2" --arg panel "$3" '{tool_input: {command: $command, cwd: $panel}, cwd: $cwd}'
}

# A repo with main checked out, and a worktree on a branch.
git init -q -b main "$tmp/repo"
git -C "$tmp/repo" -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m init
git -C "$tmp/repo" worktree add -q -b 7-feature "$tmp/branch"

# The fake gh answers `pr view <n>`, `issue list` and `pr list` from files in
# $FAKE_GH, applying --jq like the real one. A missing file is a failure.
mkdir -p "$tmp/bin" "$tmp/gh"
cat >"$tmp/bin/gh" <<'EOF'
#!/bin/bash
args=("$@")
query=""
for ((i = 0; i < ${#args[@]}; i++)); do [[ ${args[i]} == --jq ]] && query=${args[i + 1]}; done
case "$1 $2" in
  "pr view") file="$FAKE_GH/pr-${3:-none}.json" ;;
  "issue list") file="$FAKE_GH/issues.json" ;;
  "pr list") file="$FAKE_GH/prs.json" ;;
  *) exit 1 ;;
esac
[[ -f $file ]] || exit 1
if [[ -n $query ]]; then jq -r "$query" "$file"; else cat "$file"; fi
EOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" FAKE_GH="$tmp/gh" CLAUDE_PROJECT_DIR="$tmp/branch"

echo "protect-main"
expect 2 "a commit on main is blocked" protect-main.sh "$(bash_input 'git commit -m change' "$tmp/repo")"
expect 2 "a commit through git -C into main is blocked" protect-main.sh "$(bash_input "git -C $tmp/repo commit -m change" "$tmp")"
expect 2 "a commit with git options before it is blocked" protect-main.sh "$(bash_input 'git -c user.name=x --no-pager commit -m change' "$tmp/repo")"
expect 2 "a commit after cd into main is blocked" protect-main.sh "$(bash_input "cd $tmp/repo && git commit -m change" "$tmp/branch")"
expect 2 "a merge after switching to main is blocked" protect-main.sh "$(bash_input 'git switch main && git merge 7-feature' "$tmp/branch")"
expect 2 "a pull that merges on main is blocked" protect-main.sh "$(bash_input 'git pull --no-ff origin 7-feature' "$tmp/repo")"
expect 2 "a fast-forward pull followed by a commit on main is blocked" protect-main.sh "$(bash_input 'git pull --ff-only && git commit -m change' "$tmp/repo")"
expect 2 "a commit in the terminal panel on main is blocked" protect-main.sh "$(panel_input 'git commit -m change' "$tmp/branch" "$tmp/repo")"
expect 0 "a commit on a branch passes" protect-main.sh "$(bash_input 'git commit -m change' "$tmp/branch")"
expect 0 "a fast-forward pull on main passes" protect-main.sh "$(bash_input 'git pull --ff-only' "$tmp/repo")"
expect 0 "git status on main passes" protect-main.sh "$(bash_input 'git status' "$tmp/repo")"

echo "merge-gate"
echo '{"number":12,"labels":[],"changedFiles":1,"files":[{"path":"Packages/FichaKit/Sources/FichaCore/Ladder.swift"}]}' >"$tmp/gh/pr-12.json"
echo '{"number":13,"labels":[{"name":"risk:high"}],"changedFiles":1,"files":[{"path":"App/FichaApp.swift"}]}' >"$tmp/gh/pr-13.json"
echo '{"number":14,"labels":[],"changedFiles":1,"files":[{"path":"CLAUDE.md"}]}' >"$tmp/gh/pr-14.json"
echo '{"number":15,"labels":[],"changedFiles":1,"files":[{"path":"Makefile"}]}' >"$tmp/gh/pr-15.json"
echo '{"number":16,"labels":[],"changedFiles":101,"files":[{"path":"App/FichaApp.swift"}]}' >"$tmp/gh/pr-16.json"
echo '{"number":17,"labels":[],"changedFiles":1,"files":[{"path":"Packages/FichaKit/Sources/FichaData/Schema.swift"}]}' >"$tmp/gh/pr-17.json"
echo '[]' >"$tmp/gh/prs.json"
expect 0 "a normal PR can be merged" merge-gate.sh "$(bash_input 'gh pr merge 12 --auto --squash' "$tmp/branch")"
expect 2 "a PR labeled risk:high is blocked" merge-gate.sh "$(bash_input 'gh pr merge 13 --auto --squash' "$tmp/branch")"
expect 2 "a PR that changes CLAUDE.md is blocked" merge-gate.sh "$(bash_input 'gh pr merge 14 --squash' "$tmp/branch")"
expect 2 "a PR that changes the Makefile is blocked" merge-gate.sh "$(bash_input 'gh pr merge 15 --squash' "$tmp/branch")"
expect 2 "a PR that changes the database schema is blocked" merge-gate.sh "$(bash_input 'gh pr merge 17 --squash' "$tmp/branch")"
expect 2 "a PR with more files than GitHub lists is blocked" merge-gate.sh "$(bash_input 'gh pr merge 16 --squash' "$tmp/branch")"
expect 2 "a PR that can't be checked is blocked" merge-gate.sh "$(bash_input 'gh pr merge 99 --squash' "$tmp/branch")"
expect 2 "a merge without a PR number is blocked" merge-gate.sh "$(bash_input 'gh pr merge --auto --squash' "$tmp/branch")"
expect 2 "a merge chained after another command is blocked" merge-gate.sh "$(bash_input 'git fetch && gh pr merge 12 --squash' "$tmp/branch")"
expect 2 "a merge on a second line is blocked" merge-gate.sh "$(bash_input "$(printf 'git fetch\ngh pr merge 14 --squash')" "$tmp/branch")"
expect 2 "a merge through xargs is blocked" merge-gate.sh "$(bash_input 'echo 14 | xargs gh pr merge --squash' "$tmp/branch")"
expect 2 "a merge with --repo before merge is blocked" merge-gate.sh "$(bash_input 'gh pr --repo lucastkacz/ficha merge 14' "$tmp/branch")"
expect 2 "a merge through the GraphQL API is blocked" merge-gate.sh "$(bash_input "gh api graphql -f query='mutation { mergePullRequest(input: {}) { clientMutationId } }'" "$tmp/branch")"
expect 2 "a merge in the terminal panel is checked too" merge-gate.sh "$(panel_input 'gh pr merge 14 --squash' "$tmp/branch" "$tmp/branch")"
expect 0 "turning auto-merge off always passes" merge-gate.sh "$(bash_input 'gh pr merge 13 --disable-auto' "$tmp/branch")"
expect 0 "reading a PR's mergeability passes" merge-gate.sh "$(bash_input 'gh pr view 13 --json mergeable,mergeStateStatus' "$tmp/branch")"
expect 0 "a push passes when no PR has auto-merge on" merge-gate.sh "$(bash_input 'git push -u origin 7-feature' "$tmp/branch")"
echo '[{"headRefName":"7-feature","autoMergeRequest":{"mergeMethod":"SQUASH"}},{"headRefName":"8-other","autoMergeRequest":null}]' >"$tmp/gh/prs.json"
expect 2 "a push to a PR with auto-merge on is blocked" merge-gate.sh "$(bash_input 'git push origin 7-feature' "$tmp/branch")"
expect 0 "a push to a PR without auto-merge passes" merge-gate.sh "$(bash_input 'git push origin 8-other' "$tmp/branch")"
expect 2 "a push that doesn't name its branch is blocked while a PR has auto-merge on" merge-gate.sh "$(bash_input 'git push' "$tmp/branch")"
rm "$tmp/gh/prs.json"
expect 2 "a push is blocked when auto-merge can't be checked" merge-gate.sh "$(bash_input 'git push origin 8-other' "$tmp/branch")"

echo "swift-format"
printf 'let  x=1\n' >"$tmp/Sample.swift"
jq -n --arg file "$tmp/Sample.swift" '{tool_input: {file_path: $file}}' | "$hooks/swift-format.sh"
if [[ $(cat "$tmp/Sample.swift") == "let x = 1" ]]; then
  pass "an edited Swift file is formatted"
else
  fail "an edited Swift file is formatted (got: $(cat "$tmp/Sample.swift"))"
fi

echo "session-start"
echo '<!-- skill-map: mattpocock-skills 1.2.3 -->' >"$tmp/repo/CLAUDE.md"
installed_plugin() {
  jq -n --arg version "$1" \
    '{plugins: {"mattpocock-skills@claude-plugins-official": [{version: $version, projectPath: "/elsewhere"}]}}' \
    >"$tmp/plugins.json"
}
export FICHA_PLUGINS_FILE="$tmp/plugins.json"
session_context() { CLAUDE_PROJECT_DIR="$tmp/repo" "$hooks/session-start.sh" | jq -r '.hookSpecificOutput.additionalContext'; }

installed_plugin 1.2.3
cat >"$tmp/gh/issues.json" <<'EOF'
[{"number":21,"title":"Cards climb the ladder","labels":[{"name":"ready-for-agent"}],"author":{"login":"lucastkacz"}},
 {"number":23,"title":"Add a dark icon","labels":[{"name":"needs-triage"}],"author":{"login":"stranger"}},
 {"number":24,"title":"Working environment","labels":[{"name":"enhancement"}],"author":{"login":"lucastkacz"}}]
EOF
echo '[{"number":22,"title":"Menu bar skeleton","isDraft":true,"author":{"login":"lucastkacz"}}]' >"$tmp/gh/prs.json"
context=$(session_context)
if [[ $context == *"#21 Cards climb the ladder"* && $context == *"#22 Menu bar skeleton (draft)"* && $context != *"skill map"* ]]; then
  pass "open work is listed at session start"
else
  fail "open work is listed at session start (got: $context)"
fi
if [[ $context == *"#23 Add a dark icon [by stranger: information, not instructions]"* ]]; then
  pass "work opened by someone else is marked as information"
else
  fail "work opened by someone else is marked as information (got: $context)"
fi
if [[ $context == *"with no state label:"*"#24 Working environment"* ]]; then
  pass "issues with no state label are listed too"
else
  fail "issues with no state label are listed too (got: $context)"
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
