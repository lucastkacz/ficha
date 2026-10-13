#!/bin/bash
# Formats each Swift file Claude edits (PostToolUse on Edit, Write and
# MultiEdit) with the repo's .swift-format, so `make lint` never fails on
# formatting. A file that doesn't parse yet is left as it is.

file=$(jq -r '.tool_input.file_path // ""')
[[ $file == *.swift && -f $file ]] || exit 0
swift format --in-place "$file" >/dev/null 2>&1
exit 0
