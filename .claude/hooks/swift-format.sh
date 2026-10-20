#!/bin/bash
# Formats each Swift file Claude edits in the project (PostToolUse on Edit,
# Write and MultiEdit) with the repo's .swift-format, so `make lint` never
# fails on formatting. A file that doesn't parse yet is left as it is, and so
# is a file outside the project, like a scratch script, which the repo's style
# doesn't cover.

file=$(jq -r '.tool_input.file_path // ""')
[[ -n ${CLAUDE_PROJECT_DIR:-} && $file == "$CLAUDE_PROJECT_DIR"/* ]] || exit 0
[[ $file == *.swift && -f $file ]] || exit 0
swift format --in-place "$file" >/dev/null 2>&1
exit 0
