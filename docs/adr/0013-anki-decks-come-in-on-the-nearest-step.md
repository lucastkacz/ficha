# Anki decks come in with their progress, on the nearest ladder step

Someone leaving Anki has years of reviews, and starting over at a few new cards a day would keep them in Anki. So Ficha reads Anki's `.apkg` packages, the file Anki exports by default, and brings each card's progress along. Anki gives each card an interval of its own while Ficha has a fixed ladder (ADR 0002), so a card Anki was reviewing lands on the step nearest its interval and falls due on the day Anki would have shown it; a new card stays new, and one Anki was still learning lands on the first step. Anki's review history stays behind: its four buttons don't map onto Ficha's three ratings, and Ficha works out a card's step by replaying its log, so the old reviews would put the card on another step. Instead, the card's log starts with one entry that places it on its step.

## Considered options

- Reading only Anki's plain-text export, which needs nothing new but carries no progress.
- Importing the review history, with Easy as "Know it", and working out the step without it: more work, for a record the user barely sees.

## Consequences

- This changes ADR 0002's consequence that a card always starts on the first step: a card imported with its progress starts on the step the import placed it on, without a first view.
- Current Anki compresses its packages with zstd, which Apple's Compression framework lacks, so reading them adds a dependency, with an ADR of its own in the pull request that adds it. Ficha reads every package version Anki writes.
- Each Anki card becomes one Ficha card, with what Anki showed on each side as plain text, so a cloze card comes in with "[...]" on its front and the whole sentence on its back. Suspended cards come in buried. Image Occlusion cards, and cards left with an empty side, such as a side whose only sound Ficha can't read, stay out. Before #232 brought each side's first sound in, every side with only a sound was empty.
- The import brings progress unless the user unticks it, since shared decks rarely carry any, while a person leaving Anki brings their own.
- Statistics per ladder step (#168) count an imported card's reviews from its import on.
