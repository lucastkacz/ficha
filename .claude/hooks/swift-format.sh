#!/bin/bash
# Formats each Swift file Claude edits in the project (PostToolUse on Edit,
# Write and MultiEdit) with the repo's .swift-format, so `make lint` never
# fails on formatting, then lints it as `make lint` does. For what the formatter
# can't fix, it prints the findings and exits 2, which Claude Code shows to
# Claude, and the edit stays as it is. A file that doesn't parse yet is left as
# it is, with no message, and so is a file outside the project, like a scratch
# script, which the repo's style doesn't cover.

file=$(jq -r '.tool_input.file_path // ""')
[[ -n ${CLAUDE_PROJECT_DIR:-} && $file == "$CLAUDE_PROJECT_DIR"/* ]] || exit 0
[[ $file == *.swift && -f $file ]] || exit 0
swift format --in-place "$file" >/dev/null 2>&1 || exit 0
findings=$(swift format lint --strict "$file" 2>&1) && exit 0
echo "$findings" >&2
echo "The lint found what swift format can't fix, as the lines above say, and make lint would fail on it: fix each in $file. The edit stays as it is." >&2
exit 2
