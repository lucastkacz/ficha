#!/bin/bash
# Fails while a String Catalog lacks a translation: `make check` runs it on
# every catalog at once (ADR 0027). Each text is translated into every one of
# Ficha's languages, which scripts/languages.txt lists with their plural
# categories, besides the catalog's source, English, and a catalog has no
# texts in a language the list lacks. It reads the catalogs alone, without
# building anything: Apple ships no command that checks a catalog's
# translations, so this check is our own.
#
# Usage: check-translations.sh <languages file> <catalog>...

set -u
list=$1
shift

# shellcheck source=scripts/languages.sh
source "$(dirname "$0")/languages.sh"
lines=$(read_languages "$list" "run make check again") || exit 1
# Ficha's languages, as a JSON array of {code, categories, name}.
listed=$(jq -R -s -c '[split("\n")[] | select(length > 0) | split(" ")
  | {code: .[0], categories: (.[3] | split(",")), name: (.[4:] | join(" "))}]' <<<"$lines")

# The catalogs jq can read, and the languages each has a text in, besides its
# source, as {catalog, code}, one a line, for the languages the list lacks.
found=0
catalogs=()
present=""
for catalog in "$@"; do
  if ! codes=$(jq -c --arg catalog "$catalog" '.sourceLanguage as $source
    | [.strings[] | .localizations // {} | keys[]] | unique[] | select(. != $source) | {catalog: $catalog, code: .}' \
    "$catalog"); then
    echo "$catalog isn't a String Catalog this check can read, as jq says above: write it back as Xcode writes it, with make strings, and run make check again." >&2
    found=1
    continue
  fi
  # Without its source, the check can't tell English from a translation.
  if ! jq -e '.sourceLanguage | type == "string"' "$catalog" >/dev/null; then
    echo "$catalog doesn't say its source language: write it back as Xcode writes it, with make strings, and run make check again." >&2
    found=1
    continue
  fi
  catalogs+=("$catalog")
  present+="$codes"$'\n'
done

# A language a catalog has that isn't one of Ficha's fails.
read -r -d '' unknown_language <<'EOF'
select(.code | IN($listed[].code) | not)
| "\(.catalog) has texts in \(.code), which isn't one of Ficha's languages in \($list): add the language's line there, or delete the texts, and run make check again."
EOF
unknown=$(jq -r --argjson listed "$listed" --arg list "$list" "$unknown_language" <<<"$present")
if [[ -n $unknown ]]; then
  echo "$unknown" >&2
  found=1
fi

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

.sourceLanguage as $source
| .strings | to_entries[] | .key as $key | .value as $entry
| if $entry.extractionState == "stale" then
    "\($catalog): “\($key)” is stale, since the code no longer has it: delete it, after moving its translations to the text that replaced it, if one did, and run make check again."
  elif $entry.shouldTranslate == false then empty
  else
    ($entry.localizations[$source] // {}) as $english
    | ($listed[] | select(.code != $source)) as $language
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

for catalog in ${catalogs[@]+"${catalogs[@]}"}; do
  if ! messages=$(jq -r --arg catalog "$catalog" --arg list "$list" --argjson listed "$listed" "$failures" "$catalog"); then
    echo "The check stopped reading $catalog, as jq says above: write it back as Xcode writes it, with make strings, or fix scripts/check-translations.sh, and run make check again." >&2
    found=1
  fi
  if [[ -n $messages ]]; then
    echo "$messages" >&2
    found=1
  fi
done
exit $found
