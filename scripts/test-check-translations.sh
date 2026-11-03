#!/bin/bash
# Tests scripts/check-translations.sh, which `make check` runs on the String
# Catalogs; `make check` runs this too. Each case is a small catalog of its
# own, or a few checked at once, against a list of Ficha's languages of its
# own: English, the catalogs' source, Spanish and Japanese.

set -u
script="$(cd "$(dirname "$0")" && pwd)/check-translations.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

pass() { echo "ok    $1"; }
fail() {
  echo "FAIL  $1"
  failures=$((failures + 1))
}

list="$tmp/languages.txt"
cat >"$list" <<'EOF'
# The languages of these tests.
en US ltr one,other English
es AR ltr one,many,other Spanish

  # An indented comment.
ja JP ltr other Japanese
EOF

# catalog <name> <strings>: a catalog named <name>.xcstrings, holding the JSON
# object <strings> as its strings.
catalog() {
  printf '{\n  "sourceLanguage" : "en",\n  "strings" : %s,\n  "version" : "1.0"\n}' "$2" >"$tmp/$1.xcstrings"
}
# unit <language> <value> [state]: a localization with one translated value.
unit() {
  printf '"%s" : { "stringUnit" : { "state" : "%s", "value" : "%s" } }' "$1" "${3:-translated}" "$2"
}
# plural <language> <category>...: a localization with those plural variations.
plural() {
  local language=$1 variations="" category
  shift
  for category in "$@"; do
    variations+="${variations:+, }\"$category\" : { \"stringUnit\" : { \"state\" : \"translated\", \"value\" : \"%lld\" } }"
  done
  printf '"%s" : { "variations" : { "plural" : { %s } } }' "$language" "$variations"
}

# check <names>: runs the script on the catalogs <names>, one or more names
# separated by spaces, against the languages file $languages_file, keeping
# what it prints in $output and its exit code in $status.
languages_file=languages.txt
check() {
  local names=() name catalogs=()
  read -r -a names <<<"$1"
  for name in "${names[@]}"; do
    catalogs+=("$name.xcstrings")
  done
  output=$(cd "$tmp" && "$script" "$languages_file" "${catalogs[@]}" 2>&1)
  status=$?
}
# expect_pass <description> <names>
expect_pass() {
  check "$2"
  if [[ $status == 0 && -z $output ]]; then pass "$1"; else fail "$1 (exit $status: $output)"; fi
}
# expect_failure <description> <names> <part of what it prints>...
expect_failure() {
  local description=$1 part
  check "$2"
  shift 2
  if [[ $status == 0 ]]; then
    fail "$description (it passed)"
    return
  fi
  for part in "$@"; do
    if [[ $output != *"$part"* ]]; then
      fail "$description (it doesn't say \"$part\": $output)"
      return
    fi
  done
  pass "$description"
}

echo "check-translations"

catalog complete "{
  \"Review now\" : { \"comment\" : \"A button.\", \"localizations\" : { $(unit es 'Repasar ahora'), $(unit ja '今すぐ復習') } }
}"
expect_pass "a catalog translated into every language passes" complete

catalog spanish-only "{
  \"Cancel\" : { \"localizations\" : { $(unit es 'Cancelar') } },
  \"Review now\" : { \"localizations\" : { $(unit es 'Repasar ahora') } }
}"
expect_failure "a key missing a language of the list fails, though no catalog has that language yet" spanish-only \
  'spanish-only.xcstrings: “Cancel” has no Japanese (ja) translation' \
  'spanish-only.xcstrings: “Review now” has no Japanese (ja) translation'

catalog missing "{
  \"Cancel\" : { \"localizations\" : { $(unit es 'Cancelar'), $(unit ja 'キャンセル') } },
  \"Review now\" : { \"localizations\" : { $(unit es 'Repasar ahora') } }
}"
expect_failure "a missing translation's failure names the catalog, the key and the language" \
  missing 'missing.xcstrings: “Review now” has no Japanese (ja) translation'

catalog dutch "{
  \"Review now\" : { \"localizations\" : { $(unit es 'Repasar ahora'), $(unit ja '今すぐ復習'), $(unit nl 'Nu herhalen') } }
}"
expect_failure "a language that isn't in the list fails, saying how to fix it" dutch \
  "dutch.xcstrings has texts in nl, which isn't one of Ficha's languages in languages.txt: add the language's line there, or delete the texts"

catalog english "{
  \"Review now\" : { \"localizations\" : { $(unit en 'Review now'), $(unit es 'Repasar ahora'), $(unit ja '今すぐ復習') } },
  \"Cancel\" : { \"localizations\" : { $(unit es 'Cancelar'), $(unit ja 'キャンセル') } }
}"
expect_pass "English, the catalogs' source, isn't required" english

catalog plurals "{
  \"%lld cards\" : { \"localizations\" : { $(plural en one other), $(plural es one many other), $(plural ja other) } }
}"
expect_pass "plural variations in each language's categories pass" plurals

catalog plural-missing "{
  \"%lld cards\" : { \"localizations\" : { $(plural en one other), $(plural es one other), $(plural ja other) } }
}"
expect_failure "a plural variation missing in one language fails, naming it" plural-missing \
  'plural-missing.xcstrings: “%lld cards” has no Spanish (es) translation for its “many” plural variation'

catalog plain-for-plural "{
  \"%lld cards\" : { \"localizations\" : { $(plural en one other), $(unit es '%lld tarjetas'), $(plural ja other) } }
}"
expect_failure "a plain translation of a text with plural variations fails" plain-for-plural \
  '“%lld cards” has no Spanish (es) translation for its “one” plural variation'

catalog zero-missing "{
  \"%lld cards\" : { \"localizations\" : { $(plural en zero one other), $(plural es zero one many other), $(plural ja other) } }
}"
expect_failure "a zero variation the English has, missing in one language, fails" zero-missing \
  '“%lld cards” has no Japanese (ja) translation for its “zero” plural variation'

# substitution <language> <category>...: a localization of "%lld cards · %lld
# new" with a substitution for each count, "cards" in those plural categories.
substitution() {
  local language=$1 variations="" category
  shift
  for category in "$@"; do
    variations+="${variations:+, }\"$category\" : { \"stringUnit\" : { \"state\" : \"translated\", \"value\" : \"%arg\" } }"
  done
  printf '"%s" : { "stringUnit" : { "state" : "translated", "value" : "%%#@cards@ · %%#@new@" },
    "substitutions" : {
      "cards" : { "argNum" : 1, "formatSpecifier" : "lld", "variations" : { "plural" : { %s } } },
      "new" : { "argNum" : 2, "formatSpecifier" : "lld", "variations" : { "plural" : {
        "other" : { "stringUnit" : { "state" : "translated", "value" : "%%arg" } } } } } } }' \
    "$language" "$variations"
}
catalog substitutions "{
  \"%lld cards · %lld new\" : { \"localizations\" : {
    $(substitution en one other), $(substitution es one many other), $(substitution ja other) } }
}"
expect_failure "a substitution's plural variation missing in one language fails, naming the substitution" \
  substitutions '“%lld cards · %lld new” has no Spanish (es) translation for the “one” plural variation of its “new” substitution'

catalog review "{
  \"Review now\" : { \"localizations\" : { $(unit es 'Repasar ahora' needs_review), $(unit ja '今すぐ復習') } }
}"
expect_failure "a translation marked for review fails" review \
  'review.xcstrings: “Review now” has its Spanish (es) translation marked for review'

catalog plural-review "{
  \"%lld cards\" : { \"localizations\" : { $(plural en one other), $(plural ja other),
    \"es\" : { \"variations\" : { \"plural\" : {
      \"one\" : { \"stringUnit\" : { \"state\" : \"translated\", \"value\" : \"%lld tarjeta\" } },
      \"many\" : { \"stringUnit\" : { \"state\" : \"needs_review\", \"value\" : \"%lld de tarjetas\" } },
      \"other\" : { \"stringUnit\" : { \"state\" : \"translated\", \"value\" : \"%lld tarjetas\" } } } } } } }
}"
expect_failure "a plural variation marked for review fails, naming it" plural-review \
  '“%lld cards” has its Spanish (es) translation marked for review in its “many” plural variation'

catalog untranslated "{
  \"Review now\" : { \"localizations\" : { $(unit es 'Repasar ahora' new), $(unit ja '') } }
}"
expect_failure "a translation in another state than translated fails" untranslated \
  '“Review now” has its Spanish (es) translation marked “new”, not translated'
expect_failure "an empty translation fails" untranslated '“Review now” has no Japanese (ja) translation'

catalog stale "{
  \"Review later\" : { \"extractionState\" : \"stale\", \"localizations\" : { $(unit es 'Repasar más tarde'), $(unit ja '後で復習') } }
}"
expect_failure "a stale key fails" stale 'stale.xcstrings: “Review later” is stale'

catalog dont-translate "{
  \"%@ · %@\" : { \"shouldTranslate\" : false },
  \"Review now\" : { \"localizations\" : { $(unit es 'Repasar ahora'), $(unit ja '今すぐ復習') } }
}"
expect_pass "a key marked Don't translate passes without translations" dont-translate

expect_failure "the message says what to do" missing \
  "translate it into every language in languages.txt, with the words in docs/terms.md, and run make check again."
expect_failure "the message for a translation to check says what to do" review \
  "check it against the English, with the words in docs/terms.md, mark it translated, and run make check again."

# phrases <language> <phrase>: an App Shortcut's phrases in a language, a set.
phrases() {
  printf '"%s" : { "stringSet" : { "state" : "translated", "values" : [ "%s" ] } }' "$1" "$2"
}
# The app's name token, which every phrase has.
name="\${applicationName}"
catalog shortcuts "{
  \"Review now in $name\" : { \"localizations\" : {
    $(phrases en "Review now in $name"), $(phrases es "Repasar ahora en $name") } }
}"
expect_failure "an App Shortcut's phrases missing a language of the list fail" shortcuts \
  'shortcuts.xcstrings: “Review now in '"$name"'” has no Japanese (ja) translation'
catalog shortcuts "{
  \"Review now in $name\" : { \"localizations\" : {
    $(phrases es "Repasar ahora en $name"), $(phrases ja "${name}で今すぐ復習") } }
}"
expect_pass "an App Shortcut's phrases in every language pass" shortcuts

printf '{\n  "strings" : { "Review now" : { "localizations" : { %s } } },\n  "version" : "1.0"\n}' \
  "$(unit es 'Repasar ahora')" >"$tmp/sourceless.xcstrings"
expect_failure "a catalog without its source language fails, saying how to fix it" sourceless \
  "sourceless.xcstrings doesn't say its source language: write it back as Xcode writes it, with make strings, and run make check again."

echo "garbled" >"$tmp/garbled.xcstrings"
expect_failure "a catalog that isn't JSON fails, naming it" garbled "garbled.xcstrings isn't a String Catalog"
expect_failure "a catalog that isn't JSON fails beside the others, which the check still reads" \
  "garbled missing" "garbled.xcstrings isn't a String Catalog" \
  'missing.xcstrings: “Review now” has no Japanese (ja) translation'

catalog spanish-missing "{
  \"Cancel\" : { \"localizations\" : { $(unit es 'Cancelar'), $(unit ja 'キャンセル') } },
  \"Review now\" : { \"localizations\" : { $(unit ja '今すぐ復習') } }
}"
expect_failure "a key missing Spanish fails, naming it" spanish-missing \
  'spanish-missing.xcstrings: “Review now” has no Spanish (es) translation'

# The languages file's own failures, each with a file of its own, which
# `check` reads in place of languages.txt.
languages_file=missing.txt
expect_failure "a missing languages file fails, saying how to fix it" complete \
  "There's no missing.txt, Ficha's languages: restore it with git restore missing.txt, and run make check again."

languages_file=empty.txt
printf '# Only a comment.\n\n   # And an indented one.\n' >"$tmp/$languages_file"
expect_failure "a languages file with no language fails, saying how to fix it" complete \
  "empty.txt lists no language: write a line for each of Ficha's languages"

languages_file=bad-direction.txt
echo "ar EG down zero,one,two,few,many,other Arabic" >"$tmp/$languages_file"
expect_failure "a line of the languages file with another direction than ltr or rtl fails" complete \
  "bad-direction.txt:1 isn't a language's code, region, direction, plural categories and name"

languages_file=without-other.txt
echo "es AR ltr one,many Spanish" >"$tmp/$languages_file"
expect_failure "a line of the languages file whose categories lack other fails" complete \
  "without-other.txt:1 isn't a language's code, region, direction, plural categories and name"

languages_file=languages.txt
echo "es Spanish" >>"$list"
expect_failure "a line of the languages file without its region, direction and categories fails, saying how to fix it" \
  complete "languages.txt:7 isn't a language's code, region, direction, plural categories and name, as in 'es AR ltr one,many,other Spanish': write it so"

if ((failures > 0)); then
  echo "$failures of the check's tests failed, as the lines above say: fix scripts/check-translations.sh or the tests, and run make check again." >&2
  exit 1
fi
