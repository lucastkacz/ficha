# Ficha comes only in English

ADR 0027 has Ficha in eleven languages besides English, which Claude translates in every PR that adds or changes a text, and each PR that changes what Lucas sees shows its windows in English, German and Arabic. Today the three String Catalogs hold 836 texts, each in the eleven languages, and `make check` fails while one lacks a translation. On 2026-11-14 Lucas said he wants everything in English, and that's all; in the debate of 2026-11-24 that stood, and he approved it as a decision (ADR 0032). It replaces ADR 0027, makes ADR 0028 obsolete, and changes ADR 0009 in part.

- **The Mac app, its widget, the iPhone app and the `ficha` CLI are in English alone**, whatever the device's language.
- **The eleven translations go** from the String Catalogs, with `make check`'s translations check, `scripts/languages.txt` and what reads it, and `docs/terms.md`.
- **The code keeps writing its texts through String Catalogs**, in English (provisional): Apple's standard way, so no text in the code changes.
- **A PR's pictures are in English alone.**
- **Settings' Language row goes**: with one language there's nothing to choose.
- Dates, numbers and durations still follow the device's region, through Apple's formats.

## Considered options

- Keeping the eleven: each PR keeps translating every text eleven times and drawing three pictures of each window, for a product whose first users read English.
- Keeping the translations without requiring them: the app would mix languages as its texts change.

## Consequences

- ADR 0009 keeps its English base and its CLI in English; its "other languages come later, starting with Rioplatense Spanish" goes.
- ADR 0028 is obsolete: the Language row it kept goes, and nothing replaces it.
- `CODING_STANDARDS.md`'s rule that every text is translated goes back to every text through a String Catalog; `CLAUDE.md`, `docs/development.md` and `PLIEGO.md` say a PR's pictures are in English. The names Ficha comes with, Default and the four card types, are in English.
- The change takes a step out of the `Makefile`, so its PR is `risk:high`, and Lucas merges it.
- Lucas's cards, the sample cards and the content guide stay in Spanish: cards are the user's.
- Standard practice: an app in one language, through String Catalogs. Our own: none.
