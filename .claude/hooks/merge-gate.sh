#!/bin/bash
# Keeps risk:high pull requests for Lucas (PreToolUse on Bash). Claude merges a
# PR only when it isn't risk:high (CLAUDE.md). Claude works with Lucas's GitHub
# account, so GitHub can't tell them apart: this hook is the lock.
#
# A command that runs `gh pr merge` is blocked when the PR has the risk:high
# label or changes a file in a risk:high area. If the PR can't be checked, the
# merge is blocked too.

input=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
dir=$(jq -r '.cwd // "."' <<<"$input")

[[ $cmd =~ (^|[^[:alnum:]_./-])gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$) ]] || exit 0

# The PR is the first argument after `gh pr merge` that isn't a flag or a
# flag's value. None means the current branch's PR. A wrong guess fails the
# check below, which blocks: it never lets a merge through.
pr=""
read -ra words <<<"$cmd"
for ((i = 0; i + 2 < ${#words[@]}; i++)); do
  [[ ${words[i]} == gh && ${words[i + 1]} == pr && ${words[i + 2]} == merge ]] || continue
  for ((j = i + 3; j < ${#words[@]}; j++)); do
    case ${words[j]} in
      '&&' | '||' | ';' | '|') break ;;
      -t | --subject | -b | --body | -F | --body-file | -A | --author-email | --match-head-commit) ((j++)) ;;
      -*) ;;
      *) pr=${words[j]}; break ;;
    esac
  done
  break
done

block() {
  echo "$1 Lucas reviews and merges risk:high pull requests (CLAUDE.md): tell him it's ready." >&2
  exit 2
}

info=$(cd "$dir" 2>/dev/null && gh pr view ${pr:+"$pr"} --json number,labels,files 2>/dev/null) ||
  block "Couldn't check the pull request's labels and files."
number=$(jq -r '.number' <<<"$info")

if jq -e '.labels | any(.name == "risk:high")' <<<"$info" >/dev/null; then
  block "Pull request #$number is labeled risk:high."
fi

risky=$(jq -r '.files[].path' <<<"$info" |
  grep -E '^(CLAUDE\.md|CODING_STANDARDS\.md|\.claude/|docs/agents/|\.github/workflows/|project\.yml$|Packages/FichaKit/Package\.(swift|resolved)$)')
if [[ -n $risky ]]; then
  block "Pull request #$number changes risk:high files: $(tr '\n' ' ' <<<"$risky")"
fi
exit 0
