#!/bin/bash
# Fails while a String Catalog lacks a translation: `make check` runs it on
# every catalog, against the languages scripts/languages.txt lists (ADR 0027).
# It reads the catalogs alone, without building anything: Apple ships no
# command that checks a catalog's translations, so this check is our own.
#
# Usage: check-translations.sh <languages file> <catalog>...

set -u
list=$1
shift

[[ -r $list ]] || {
  echo "There's no $list, the languages every catalog is translated into: restore it with git restore, and run make check again." >&2
  exit 1
}

# The languages, as a JSON array of {code, categories, name}, from the list's
# lines that aren't blank or comments.
languages="[]"
number=0
while IFS= read -r line || [[ -n $line ]]; do
  number=$((number + 1))
  [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
  read -r code categories name <<<"$line"
  category="(zero|one|two|few|many|other)"
  if [[ -z $name || ! $categories =~ ^$category(,$category)*$ || ! $categories =~ other ]]; then
    echo "$list:$number isn't a language's code, its plural categories and its name, as in 'es one,many,other Spanish': write it so, with the categories Unicode's CLDR gives the language, other among them, and run make check again." >&2
    exit 1
  fi
  languages=$(jq -c --arg code "$code" --arg categories "$categories" --arg name "$name" \
    '. + [{code: $code, categories: ($categories | split(",")), name: $name}]' <<<"$languages")
done <"$list"
[[ $languages != "[]" ]] || {
  echo "$list lists no language: write a line for each language, as in 'es one,many,other Spanish', and run make check again." >&2
  exit 1
}

# Each failure of a catalog, as a line that names the catalog, the key and the
# language, and says what to do. A text with plural variations in English has
# them in every language, in the categories the list gives it, and zero too
# when the English has one: Apple uses a zero variation for 0 in any language,
# as the English ones show, though Unicode's CLDR gives English no zero.
read -r -d '' failures <<'EOF'
# The failure of one value, `.`, unless it's translated, as {state, part}: its
# state, "missing" when there's no value, and the part of the text it is, ""
# for the whole text. App Shortcuts' phrases are a set of values.
def failure($part):
  (.stringUnit // .stringSet // null) as $unit
  | if $unit == null or ($unit.value // $unit.values // "" | length) == 0 then {state: "missing", part: $part}
    elif $unit.state == "translated" then empty
    else {state: $unit.state, part: $part} end;
# The failures of one translated text, `.`, of a text whose English is $english:
# its value, or each of its plural variations, named between $before and $after.
def failures($english; $language; $before; $after):
  if (.variations.plural // $english.variations.plural // null) != null then
    ($language.categories + (if $english.variations.plural.zero? then ["zero"] else [] end) | unique) as $categories
    | (.variations.plural // {}) as $plural
    | $categories[] as $category | $plural[$category] // {}
    | failure("\($before) “\($category)” plural variation\($after)")
  else failure("") end;
def failures($english; $language):
  failures($english; $language; "its"; "")
  , (. as $translation | $english.substitutions // {} | keys[] as $name
    | ($translation.substitutions[$name] // {})
    | failures($english.substitutions[$name]; $language; "the"; " of its “\($name)” substitution"));

.strings | to_entries[] | .key as $key | .value as $entry
| if $entry.extractionState == "stale" then
    "\($catalog): “\($key)” is stale, since the code no longer has it: delete it, after moving its translations to the text that replaced it, if one did, and run make check again."
  elif $entry.shouldTranslate == false then empty
  else
    ($entry.localizations.en // {}) as $english
    | $languages[] as $language
    | "\($language.name) (\($language.code))" as $name
    | ($entry.localizations[$language.code] // null) as $translation
    | if $translation == null then {state: "missing", part: ""}
      else $translation | failures($english; $language) end
    | (if .part == "" then "" else " for \(.part)" end) as $for
    | (if .part == "" then "" else " in \(.part)" end) as $in
    | "\($catalog): “\($key)” "
      + if .state == "missing" then
          "has no \($name) translation\($for): translate it into every language in \($list), with the words in docs/terms.md, and run make check again."
        else
          "has its \($name) translation marked "
          + (if .state == "needs_review" then "for review" else "“\(.state)”, not translated" end)
          + "\($in): check it against the English, with the words in docs/terms.md, mark it translated, and run make check again."
        end
  end
EOF

found=0
for catalog in "$@"; do
  if ! messages=$(jq -r --arg catalog "$catalog" --arg list "$list" --argjson languages "$languages" \
    "$failures" "$catalog"); then
    echo "$catalog isn't a String Catalog this check can read, as jq says above: write it back as Xcode writes it, with make strings, and run make check again." >&2
    found=1
  elif [[ -n $messages ]]; then
    echo "$messages" >&2
    found=1
  fi
done
exit $found
