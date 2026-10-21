#!/bin/bash
# Keeps issues read with their comments (PreToolUse on Bash and on the terminal
# panel). Other issues leave an issue work in its comments
# (docs/agents/issue-tracker.md), but `gh issue view` with no terminal, as
# agents run it, prints how many comments there are and not what they say. So
# a command that would print issues' bodies without their comments is blocked:
# - `gh issue view` without `--comments`, `--web`, `--help` or `--json`;
# - `gh issue view` or `gh issue list` whose `--json` list has `body` and not
#   `comments`.
# A plain `gh issue list` prints no bodies, and `gh api` and `gh pr view` are
# out of scope. How the hook splits a command is our own approximation of the
# shell's. Text in quotes, here-documents and shell comments is never a
# command, so a body that mentions `gh issue view` passes; commands in
# backticks or in a `$( )` inside quotes aren't read either, so they pass too.
# Unlike merge-gate.sh, this hook is a reminder and not a lock: when in doubt,
# it lets the command run.

cmd=$(jq -r '.tool_input.command // ""')

# Only a command that mentions `gh`, and `issue` before `view` or `list`, is read.
mentions_gh='(^|[^[:alnum:]_.-])gh[[:space:]]'
mentions_issues='issue[[:space:]].*(view|list)'
[[ $cmd =~ $mentions_gh && $cmd =~ $mentions_issues ]] || exit 0

block() {
  echo "This command would print issues' bodies without their comments, where other issues leave them work: read them with a \`--json\` list that has \`comments\`, as in \`gh issue view <number> --json number,title,body,labels,comments\` (docs/agents/issue-tracker.md, Read an issue). With no terminal, \`--comments\` alone prints the comments without the body." >&2
  exit 2
}

# drops_comments <word>...: whether one command's `gh issue view` or
# `gh issue list` would print issues' bodies without their comments.
drops_comments() {
  local -a args=("$@")
  local i j subcommand json fields
  for ((i = 0; i < ${#args[@]}; i++)); do
    [[ ${args[i]} == gh ]] || continue
    j=$i
    next_word
    [[ ${args[j]-} == issue ]] || continue
    next_word
    subcommand=${args[j]-}
    [[ $subcommand == view || $subcommand == list ]] || continue
    json=0 fields=""
    for ((j = j + 1; j < ${#args[@]}; j++)); do
      case ${args[j]} in
        # The comments alone, the browser or the help: no body without its comments.
        -c | --comments | -w | --web | -h | --help) continue 2 ;;
        --json) json=1 fields=${args[j + 1]-} ;;
        --json=*) json=1 fields=${args[j]#--json=} ;;
      esac
    done
    if ((json)); then
      [[ ,$fields, == *,body,* && ,$fields, != *,comments,* ]] && return 0
    elif [[ $subcommand == view ]]; then
      return 0
    fi
  done
  return 1
}
# next_word: moves $j to drops_comments' next word, past any -R or --repo and
# its repository.
next_word() {
  j=$((j + 1))
  while :; do
    case ${args[j]-} in
      -R | --repo) j=$((j + 2)) ;;
      --repo=*) j=$((j + 1)) ;;
      *) return ;;
    esac
  done
}

# The command is read a line at a time, into commands at ; & | ( ) and
# newlines, and each command into words, without their quotes. Text in quotes
# is taken up to the next character that matters at once: a character at a
# time, a long body takes seconds.
words=()  # the words of the command being read
word=""   # the word being read
started=0 # 1 once the word has begun, so "" is a word too
quote=""  # ' or " inside quotes
# The here-documents whose bodies come next, each as <dash>:<delimiter>, where
# <dash> is - for <<-, which allows tabs before the delimiter.
heredocs=()
here_string='^<<<'
heredoc='^<<(-?)[[:space:]]*([^[:space:];&|()<>]+)'

end_word() {
  if ((started)); then words+=("$word"); fi
  word="" started=0
}
end_command() {
  end_word
  if drops_comments "${words[@]}"; then block; fi
  words=()
}
# take_text <characters>: takes the text from $i up to the next of the
# characters into the word, leaving $i on the text's last character.
take_text() {
  local rest=${line:i} text
  text=${rest%%["$1"]*}
  word+=$text i=$((i + ${#text} - 1))
}
# escape: takes the character after the backslash at $i into the word, or
# joins the line to the next when the backslash ends it.
escape() {
  if ((i + 1 < ${#line})); then word+=${line:i+1:1} started=1; else joined=1; fi
  i=$((i + 1))
}
# here_operator: at a `<` on $i, takes a here-string's <<< into the word, or a
# here-document's operator, noting its delimiter. Fails for any other `<`.
here_operator() {
  if [[ ${line:i} =~ $here_string ]]; then
    word+='<<<' i=$((i + 2))
  elif [[ ${line:i} =~ $heredoc ]]; then
    heredocs+=("${BASH_REMATCH[1]}:${BASH_REMATCH[2]//[\"\'\\]/}")
    i=$((i + ${#BASH_REMATCH[0]} - 1))
  else
    return 1
  fi
}

while IFS= read -r line; do
  # A here-document's body is text, up to the line with its delimiter alone.
  if ((${#heredocs[@]} > 0)); then
    if [[ ${heredocs[0]%%:*} == - ]]; then
      while [[ $line == $'\t'* ]]; do line=${line#$'\t'}; done
    fi
    if [[ $line == "${heredocs[0]#*:}" ]]; then heredocs=("${heredocs[@]:1}"); fi
    continue
  fi
  joined=0 # 1 when a backslash ends the line, joining it to the next
  for ((i = 0; i < ${#line}; i++)); do
    c=${line:i:1}
    if [[ $quote == "'" ]]; then
      case $c in
        "'") quote="" ;;
        *) take_text "'" ;;
      esac
    elif [[ $quote == '"' ]]; then
      case $c in
        '"') quote="" ;;
        \\) escape ;;
        # A here-document inside quotes, as in "$(cat <<'EOF' … EOF)", which
        # opens a `$(` first.
        '<')
          if [[ $word == *"\$("* ]] && here_operator; then :; else word+=$c; fi
          ;;
        *) take_text '"\<' ;;
      esac
    else
      case $c in
        "'" | '"') quote=$c started=1 ;;
        \\) escape ;;
        # A `#` that starts a word starts a comment, up to the end of the line.
        '#')
          if ((started)); then word+=$c; else break; fi
          ;;
        '<')
          here_operator || word+=$c
          started=1
          ;;
        ';' | '&' | '|' | '(' | ')') end_command ;;
        [[:space:]]) end_word ;;
        *) word+=$c started=1 ;;
      esac
    fi
  done
  # The line's newline: nothing after a backslash, text in quotes, and
  # otherwise the end of a command.
  if ((joined)); then
    :
  elif [[ -n $quote ]]; then
    word+=$'\n'
  else
    end_command
  fi
done <<<"$cmd"
end_command
exit 0
