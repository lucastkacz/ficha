# The review panel shows the card alone, with two buttons: Forgot and Got it

> Changed in part by [ADR 0039](0039-the-review-panel-has-three-buttons-forgot-kind-of-and-got-it.md), whose panel shows three buttons, Forgot, Kind of and Got it, with no line under them and no rating on key 4, names a new card's New to me, Kind of and Knew it, and gives the iPhone the same three (2026-11-26).

> Changed in part by [ADR 0041](0041-ficha-is-small-decks-shown-as-cards-without-ankis-packages-tags-or-capture.md): a card's detail in the Cards window says in words when it's back and how often it was seen, its numbers under Details (2026-11-26).

Since ADR 0025 the review panel shows Anki's four buttons, Again, Hard, Good and Easy, each with the interval it would set above it, and since ADR 0024 the card's deck and tags above the card, beside the icons that ask about it, flag it and bury it. Lucas said that in Anki he almost only presses the outer two, and asked what Hard means. Hard means remembered, with effort: FSRS counts it as recalled, and stretches the card's interval. Anki's manual says FSRS adapts to the way a user rates, save one habit, pressing Hard after forgetting ([deck options](https://docs.ankiweb.net/deck-options.html)); an answer in Anki's forum cites FSRS's FAQ that Again and Good alone can be as accurate. In the Ficha Lab, at a desired retention of 85%, a card with a 4-day interval that the user had half forgotten came back in 22 days, at 58% recall, rated Hard, and in an hour and then a day, at 88%, rated Again. Lucas first chose three buttons, Don't know, Sort of and Know it, and in the second round of the debate of 2026-11-24 chose two, and approved it as a decision (ADR 0032). It changes ADR 0025 in part, its four buttons with their intervals and its settings in plain view, and ADR 0024 in part, the deck and tags in the panel.

- **Two buttons, once the card is flipped.** Forgot records Again, and Got it records Good, with keys 1, and Space or 3, as before; keys 2 and 4 still record Hard and Easy, for whoever comes from Anki, and a small line under the buttons says so.
- **The card alone.** No interval, deck, tag or icon in view. Asking, flagging and burying keep their keys, A, M and E, and sit in a ⋯ menu in a corner (provisional).
- **A new card's first flip names the two buttons New to me and Knew it (provisional).** They record the same: Forgot means nothing for a card never seen.
- **What's stored doesn't change.** Anki's four ratings, so the review log, the import of Anki's progress and the export stay as ADR 0025 has them.
- **One face for everyone.** Anki's settings move to Settings' Advanced tab: the learning and relearning steps, the desired retention and the longest interval. Settings has five tabs, General, Pace, Interruptions, Sync and Advanced, and Pace holds How fast? and the queue of decks (ADR 0034). Every row of today's seven tabs, Backups' and About's included, goes into one of the five, but the Language row, which ADR 0036 takes out; where each goes is provisional, until the mock of its issue sets it.

## Considered options

- Three buttons, Don't know, Sort of and Know it, as Lucas first chose: Sort of records Hard, so a half-forgotten card stretches.
- Three, with a plainer middle, Forgot, Barely and Got it: harder to press by mistake, but still a third choice for a small card.
- Anki's four, without the intervals: four choices for every card.
- An Anki mode in Advanced that brings back the four buttons with their intervals, by hand or once a package is imported: two faces to mock, draw and test, and someone who imports a package out of curiosity keeps Anki's.

## Consequences

- ADR 0025's ratings stay Anki's four, keys 1 to 4 and Space for good; the panel shows two of them, and Anki's names and the intervals above the buttons go from it. A card's detail in the Cards window keeps its interval, stability, difficulty and retrievability.
- ADR 0024's consequence that the review panel shows a card's deck first, then its tags, goes.
- `GLOSSARY.md`'s Rating says what the panel shows.
- The iPhone's card notifications take the same two actions when it starts (ADR 0019), in place of ADR 0025's four.
- Standard practice: pass and fail grading, which FSRS supports, and Anki's keys. Our own: the names Forgot and Got it, New to me and Knew it, keys 2 and 4 kept without buttons, and the card alone in the panel.
