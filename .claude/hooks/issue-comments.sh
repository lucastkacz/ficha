#!/bin/bash
# Keeps issues read with their comments (PreToolUse on Bash and on the terminal
# panel). Other issues leave an issue work in its comments
# (docs/agents/issue-tracker.md), but `gh issue view` with no terminal, as
# agents run it, prints how many comments there are and not what they say. So
# a command that would print issues' bodies without their comments is blocked:
# - `gh issue view` without `--comments`, `--web` or `--json`;
# - `gh issue view` or `gh issue list` whose `--json` list has `body` and not
#   `comments`.
# A plain `gh issue list` prints no bodies, and `gh api` and `gh pr view` are
# out of scope. Text in quotes, here-documents and shell comments is never read
# as a command, so a body that mentions `gh issue view` passes. Unlike
# merge-gate.sh, this hook is a reminder and not a lock: when in doubt, it lets
# the command run.

cmd=$(jq -r '.tool_input.command // ""')

# Only a command that mentions `gh` and `issue view` or `issue list` is read.
mentions_gh='(^|[^[:alnum:]_.-])gh[[:space:]]'
mentions_issues='issue[[:space:]]+(view|list)'
[[ $cmd =~ $mentions_gh && $cmd =~ $mentions_issues ]] || exit 0

# check <word>...: blocks one command whose `gh issue view` or `gh issue list`
# would print issues' bodies without their comments.
check() {
  local -a args=("$@")
  local i j subcommand json fields
  for ((i = 0; i + 2 < ${#args[@]}; i++)); do
    [[ ${args[i]} == gh && ${args[i + 1]} == issue ]] || continue
    subcommand=${args[i + 2]}
    [[ $subcommand == view || $subcommand == list ]] || continue
    json=0 fields=""
    for ((j = i + 3; j < ${#args[@]}; j++)); do
      case ${args[j]} in
        # The comments alone, the browser or the help: no body without its comments.
        -c | --comments | -w | --web | -h | --help) continue 2 ;;
        --json) json=1 fields=${args[j + 1]-} ;;
        --json=*) json=1 fields=${args[j]#--json=} ;;
      esac
    done
    if ((json)); then
      [[ ,$fields, == *,body,* && ,$fields, != *,comments,* ]] || continue
    else
      [[ $subcommand == view ]] || continue
    fi
    echo "This command would print issues' bodies without their comments, where other issues leave them work: read them with a \`--json\` list that has \`comments\`, as in \`gh issue view <number> --json number,title,body,labels,comments\` (docs/agents/issue-tracker.md, Read an issue). With no terminal, \`--comments\` alone prints the comments without the body." >&2
    exit 2
  done
}

# The command is read as the shell splits it: into commands at ; & | ( ) and
# newlines, and each command into words, without their quotes. It's read a line
# at a time, and text in quotes up to the next character that matters at once:
# a character at a time, a long body takes seconds.
words=()  # the words of the command being read
word=""   # the word being read
started=0 # 1 once the word has begun, so "" is a word too
quote=""  # ' or " inside quotes
# The delimiters of the here-documents whose bodies come next, as -EOF for
# <<-EOF.
heredocs=()
here_string='^<<<'
heredoc='^<<(-?)[[:space:]]*([^[:space:];&|()<>]+)'

end_word() {
  if ((started)); then words+=("$word"); fi
  word="" started=0
}
end_command() {
  end_word
  check "${words[@]}"
  words=()
}
# redirection: at a `<` on $i, takes a here-string's <<< into the word, or a
# here-document's operator, noting its delimiter. Fails for any other `<`.
redirection() {
  if [[ ${line:i} =~ $here_string ]]; then
    word+='<<<' i=$((i + 2))
  elif [[ ${line:i} =~ $heredoc ]]; then
    heredocs+=("${BASH_REMATCH[1]}${BASH_REMATCH[2]//[\"\'\\]/}")
    i=$((i + ${#BASH_REMATCH[0]} - 1))
  else
    return 1
  fi
}

while IFS= read -r line; do
  # A here-document's body is text, up to the line with its delimiter alone,
  # which <<- allows after tabs.
  if ((${#heredocs[@]} > 0)); then
    if [[ ${heredocs[0]} == -* ]]; then
      while [[ $line == $'\t'* ]]; do line=${line#$'\t'}; done
    fi
    if [[ $line == "${heredocs[0]#-}" ]]; then heredocs=("${heredocs[@]:1}"); fi
    continue
  fi
  joined=0 # 1 when a backslash ends the line, joining it to the next
  for ((i = 0; i < ${#line}; i++)); do
    c=${line:i:1}
    if [[ $quote == "'" ]]; then
      rest=${line:i}
      text=${rest%%\'*}
      word+=$text i=$((i + ${#text}))
      if ((i < ${#line})); then quote=""; fi
    elif [[ $quote == '"' ]]; then
      case $c in
        '"') quote="" ;;
        \\)
          if ((i + 1 < ${#line})); then word+=${line:i+1:1}; else joined=1; fi
          i=$((i + 1))
          ;;
        # A here-document inside quotes, as in "$(cat <<'EOF' … EOF)", which
        # opens a `$(` first.
        '<')
          if [[ $word == *"\$("* ]] && redirection; then :; else word+=$c; fi
          ;;
        *)
          rest=${line:i}
          text=${rest%%[\"\\<]*}
          word+=$text i=$((i + ${#text} - 1))
          ;;
      esac
    else
      case $c in
        "'" | '"') quote=$c started=1 ;;
        \\)
          if ((i + 1 < ${#line})); then word+=${line:i+1:1} started=1; else joined=1; fi
          i=$((i + 1))
          ;;
        # A `#` that starts a word starts a comment, up to the end of the line.
        '#')
          if ((started)); then word+=$c; else break; fi
          ;;
        '<')
          redirection || word+=$c
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
