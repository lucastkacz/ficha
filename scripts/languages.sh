# shellcheck shell=bash
# Reads scripts/languages.txt, Ficha's languages, for the scripts that need
# them: check-translations.sh and render-iphone.sh source this file.
# scripts/Languages.swift reads the list by the same rules for the Swift.
#
# read_languages <list> <what to run again>: prints the list's languages, one a
# line, as "<code> <region> <ltr|rtl> <plural categories> <name>", skipping
# blank lines and comments. It fails, saying what's wrong and what to do, ending
# with "and <what to run again>.", when the list is missing, has a line of
# another shape or lists no language.
read_languages() {
  local list=$1 again=$2 line number=0 found=0 code region direction categories name
  local category="(zero|one|two|few|many|other)"
  [[ -r $list ]] || {
    echo "There's no $list, Ficha's languages: restore it with git restore $list, and $again." >&2
    return 1
  }
  while IFS= read -r line || [[ -n $line ]]; do
    number=$((number + 1))
    [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
    read -r code region direction categories name <<<"$line"
    if [[ -z $name || ! $direction =~ ^(ltr|rtl)$ || ! $categories =~ ^$category(,$category)*$ ||
      ! ,$categories, =~ ,other, ]]; then
      echo "$list:$number isn't a language's code, region, direction, plural categories and name, as in 'es AR ltr one,many,other Spanish': write it so, with ltr or rtl for the direction it reads in and the categories Unicode's CLDR gives it, other among them, and $again." >&2
      return 1
    fi
    echo "$code $region $direction $categories $name"
    found=1
  done <"$list"
  ((found)) || {
    echo "$list lists no language: write a line for each of Ficha's languages, as in 'es AR ltr one,many,other Spanish', and $again." >&2
    return 1
  }
}
