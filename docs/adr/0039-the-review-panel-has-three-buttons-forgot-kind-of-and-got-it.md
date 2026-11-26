# The review panel has three buttons: Forgot, Kind of and Got it

> Changed in part by [ADR 0041](0041-ficha-is-small-decks-shown-as-cards-without-ankis-packages-tags-or-capture.md), whose Easy stays one of the four ratings a review stores, though Anki's packages no longer bring it, and whose import of Anki's progress and export go (2026-11-26).

Since ADR 0033 the review panel shows two buttons once a card is flipped, Forgot and Got it, with a small line under them, "Also 2 Hard and 4 Easy, as in Anki", since keys 2 and 4 still recorded hard and easy for whoever comes from Anki. On 2026-11-25 Lucas tried the panel #508 built, found that the line still copied Anki, and asked for three buttons instead: Forgot, a yellow Kind of in the middle, and Got it, simple, and less confusing than Anki's four. His idea, #517, needed no debate, and he approved the decision on 2026-11-26 in the artifact "Tres botones en el panel". It changes ADR 0033 in part: its two buttons, keys 2 and 4 kept without buttons and the line under them, a new card's names on its first flip, and the iPhone's two actions; ADR 0032 in part, whose Ficha outside shows the card with two buttons; and ADR 0025 in part, whose keys 1 to 4 rated a card, since 4 no longer does in the panel.

- **Three buttons, once the card is flipped.** Forgot records Again, on 1; Kind of, in the middle, records Hard, on 2; Got it records Good, on Space and 3, and stays the prominent one Space presses. No line under them.
- **Kind of is yellow**, and Forgot and Got it keep their look. The web mock sets its look first, as `PLIEGO.md`'s How it's drawn says of a proposal.
- **Key 4 rates nothing in the panel.** A key no one sees, next to 3, would record the answer that stretches a card the most. Easy stays one of the four ratings a review stores: Anki's packages bring it, and the review log keeps it.
- **A new card's first flip names the three New to me, Kind of and Knew it.** They record Again, Hard and Good, as on any other review: a card never seen can still ring a bell.
- **Kind of means remembered, with effort.** FSRS counts Hard as recalled, so Kind of still stretches a card, less than Got it: in the web mock's engine, at 85%, a card that waited 4 days and comes on time waits about three weeks after Kind of and about a month after Got it, and comes back in an hour after Forgot. A card the user forgot is Forgot: Anki's manual says FSRS adapts to the way a user rates, save the habit of pressing Hard after forgetting ([deck options](https://docs.ankiweb.net/deck-options.html)).
- **The iPhone takes the same three when it starts** (ADR 0019, #160): its card notifications and its Review tab show Forgot, Kind of and Got it, and New to me, Kind of and Knew it on a new card; its notifications take them in place of the two ADR 0033 gave them.

## Considered options

- Two buttons and the line, as ADR 0033 has them: the line names Anki's keys and buttons on every flip.
- Three buttons, with key 4 still recording Easy and no line: a key the panel never shows.
- A plainer middle, Barely, which ADR 0033 weighed: Lucas chose Kind of.
- Two buttons on a new card's first flip, New to me and Knew it: but a card never seen can be half known, and the same three buttons on every flip are one less thing to learn.

## Consequences

- ADR 0025's ratings stay Anki's four, stored as they are, so the review log, the import of Anki's progress and the export don't change. The panel takes keys 1, 2, 3 and Space.
- The forgotten-often offer still counts Forgot alone: Kind of records Hard, which is no lapse.
- `GLOSSARY.md`'s Rating says what the panel shows.
- The web mock shows the three buttons first, and the README and `docs/development.md`'s pictures follow the panel when it's built (#517).
- Standard practice: Anki's Hard, as Anki and FSRS define it, and three of Anki's four ratings on buttons, which FSRS supports. Our own: the names Forgot, Kind of and Got it, New to me and Knew it, the yellow middle, and key 4 left without a rating.
