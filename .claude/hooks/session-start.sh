#!/bin/bash
# Tells Claude what's waiting when a session starts (SessionStart): the open
# work on GitHub, so it can suggest the next step without being asked, and a
# note when the installed mattpocock-skills version no longer matches the skill
# map in CLAUDE.md. If there's nothing to say, it says nothing.

project=${CLAUDE_PROJECT_DIR:-.}
cd "$project" 2>/dev/null || exit 0
notes=()

# The skill map in CLAUDE.md names the plugin version it was written for.
plugins=${FICHA_PLUGINS_FILE:-$HOME/.claude/plugins/installed_plugins.json}
installed=$(jq -r --arg dir "$project" '
  .plugins["mattpocock-skills@claude-plugins-official"] // []
  | (map(select(.projectPath == $dir)) + .)[0].version // empty' "$plugins" 2>/dev/null)
mapped=$(grep -oE 'matches mattpocock-skills [0-9][0-9.]*[0-9]' CLAUDE.md 2>/dev/null | awk '{print $3}')
if [[ -n $installed && -n $mapped && $installed != "$mapped" ]]; then
  notes+=("mattpocock-skills is now $installed, but the skill map in CLAUDE.md is for $mapped: update the map as CLAUDE.md says, in a risk:high pull request, and tell Lucas which skills are new.")
fi

# The open work, if GitHub answers.
if issues=$(gh issue list --state open --limit 200 --json number,title,labels 2>/dev/null) &&
  prs=$(gh pr list --state open --json number,title,isDraft 2>/dev/null); then
  section() {
    jq -r --arg label "$1" '
      [.[] | select(any(.labels[]; .name == $label)) | "  #\(.number) \(.title)"]
      | if length == 0 then "  none" else join("\n") end' <<<"$issues"
  }
  pulls=$(jq -r '
    [.[] | "  #\(.number) \(.title)\(if .isDraft then " (draft)" else "" end)"]
    | if length == 0 then "  none" else join("\n") end' <<<"$prs")
  notes+=("Open work in lucastkacz/ficha:
Ready for an agent (ready-for-agent):
$(section ready-for-agent)
Waiting for Lucas to do it (ready-for-human):
$(section ready-for-human)
Waiting for Lucas's answer (needs-info):
$(section needs-info)
Not triaged yet (needs-triage):
$(section needs-triage)
Open pull requests:
$pulls")
fi

((${#notes[@]} > 0)) || exit 0
context=$(printf '%s\n\n' "${notes[@]}")
jq -n --arg context "$context" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $context}}'
