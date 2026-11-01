# Ficha comes in eleven languages besides English, translated in every PR

ADR 0009 made English the app's base language and left other languages for later. On 2026-11-01, grilling #390, Lucas decided Ficha comes in the most-used languages before his friends test it (#359), since not all of them speak English. The languages are chosen by how much each matters to a paid app on the Mac, from what its countries spend on the App Store, how many Macs they have and its weight on the web, not by how many people speak it: Simplified Chinese, Japanese, German, Spanish, French, Korean, Portuguese (Brazil), Traditional Chinese, Italian, Russian and Arabic. Claude translates them, with Anki's word for each term Anki has, in the same PR that adds or changes a text, so no screen mixes languages. This changes ADR 0009.

## Considered options

- The most-spoken languages, as Lucas first listed them, with Hindi and Urdu: most people in India and Pakistan use their computers in English, Anki has only about 20% of its Hindi and 6% of its Urdu translated, nobody can check them, and macOS doesn't offer Urdu as a system language. They can come later, on the Mac and the iPhone together.
- A translation service: it costs money and slows every change, and nobody on the team could check its work either.
- Translations in batches before each release, as Anki's volunteers translate after its English changes: each PR would cost a little less, but the app would show English among the other languages in between.
- A neutral Spanish with "tú" for every country: it reads natural everywhere, but Lucas prefers Argentine Spanish.
- A Rioplatense Spanish for Argentina beside a neutral one: each PR would write Spanish twice, and a Mac set to Spanish (Latin America) can get the general one anyway, even with its region set to Argentina.

## Consequences

- One Spanish, `es`, for every Mac set to Spanish, in Rioplatense Spanish with "vos", as ADR 0009 planned, though it reads unusual in Mexico or Spain. Both Chinese, since a Mac in Traditional Chinese doesn't fall back to Simplified.
- The words: Anki's translation wherever Anki has the term, such as deck, card, the four ratings and interval; Apple's for the Mac's own words, such as Settings and Quit; and for Ficha's own terms, such as capture and inbox, one word in each language, kept in a list in the repo so every PR uses the same.
- Every PR that adds or changes a text the app shows translates it into the eleven languages, and `make check` fails when a language lacks a text. Apple ships no command that checks a String Catalog for missing translations, so the check is our own.
- Claude translates. Friends who speak a language correct it during the beta through TestFlight's feedback, and Lucas reviews the Spanish. Nobody reviews a language none of them speaks.
- In Arabic the whole interface is mirrored, as in Apple's apps, and the keys keep their ratings: 1 is still again. A card's content follows the direction of its own text whatever the app's language.
- `make render` draws a window in any of the languages. A PR that changes what Lucas sees shows it in German, the longest, and in Arabic beside English, and a text that doesn't fit makes its view grow instead of being cut.
- The translations cover the Mac app, its widget with the engine's messages, and the iPhone app, which does the same (ADR 0019). The `ficha` CLI and Ficha Dev's debug tools stay in English (ADR 0009). The App Store page and the privacy policy in `site/` are translated when the store page is made, and TestFlight's description for the friends is written in #359, in their languages.
- The names Ficha comes with, the Default deck and the four card types, show in each device's language. A new deck can't take Default's name in English or in the device's language, so a deck named "Standard" on a Spanish iPhone shows on a German Mac beside Default, which German calls "Standard" too.
- Standard practice: String Catalogs, Apple's mirroring for right-to-left languages, and dates, numbers and durations in the Mac's region. Our own: languages chosen by their market; one Rioplatense Spanish for every country; every text translated in its own PR, with our own check; Anki's words in each language.
