#!/bin/bash
# Keeps email addresses out of what an agent sends off the Mac or writes into
# this repo, which is public (PreToolUse on Bash, the terminal panel, WebFetch
# and WebSearch, and on Write, Edit and MultiEdit of a file inside the repo).
# Claude Code gives every session the address of Lucas's Claude account, and
# #411's builder once sent it to crates.io, as the contact in a User-Agent.
#
# This hook is the lock, as merge-gate.sh is: the call doesn't run. It fails
# closed. It knows an address by its shape alone, since the repo is public, with
# its @ written or percent-encoded, and that shape is our own approximation of
# RFC 5322's. It allows only addresses that name no one:
#
# - those at example.com, example.org and example.net, which RFC 2606 reserves;
# - noreply@anthropic.com, in the commits' Co-Authored-By line;
# - those at users.noreply.github.com, git's own address on this Mac.
#
# An Edit is checked on the text it writes, so it can take an address out.

input=$(cat)

tool=$(jq -r '.tool_name // ""' <<<"$input" 2>/dev/null) || {
  echo "This hook couldn't read the call as JSON, so the call doesn't run, in case it holds an email address: check that jq runs on this Mac, as every hook here needs, and try again." >&2
  exit 2
}

case $tool in
  Write | Edit | MultiEdit)
    file=$(jq -r '.tool_input.file_path // ""' <<<"$input")
    # Only a path that plainly stays out of the repo skips the check.
    if [[ -n ${CLAUDE_PROJECT_DIR:-} && $file == /* && $file != *..* && $file != "$CLAUDE_PROJECT_DIR"/* ]]; then
      exit 0
    fi
    text=$(jq -r '.tool_input | [.content?, .new_string?, .edits[]?.new_string] | map(strings) | join("\n")' <<<"$input")
    ;;
  *)
    text=$(jq -r '[.tool_input | .. | strings] | join("\n")' <<<"$input")
    ;;
esac

refused=$(LC_ALL=en_US.UTF-8 grep -oE '[[:alnum:]._+-]+@[[:alnum:]-]+(\.[[:alnum:]-]+)*\.[[:alpha:]]{2,}' <<<"${text//%40/@}" |
  tr '[:upper:]' '[:lower:]' |
  grep -vE '@(example\.(com|org|net)|users\.noreply\.github\.com)$|^noreply@anthropic\.com$')

[[ -n $refused ]] || exit 0
# The message names the domain alone, so that the address goes no further.
first=${refused%%$'\n'*}
echo "This call holds an email address, at ${first#*@}, which would leave the Mac or reach this public repo, so it doesn't run. Leave the address out, or use one at example.com in a test or a doc. To read a crate's versions, run cargo info <crate> or cargo search <crate>, which name Cargo itself in their User-Agent." >&2
exit 2
