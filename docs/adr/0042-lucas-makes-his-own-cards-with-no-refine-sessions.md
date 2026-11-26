# Lucas makes his own cards, with no refine sessions

ADR 0041 took Capture and the inbox out of Ficha and kept one door for Lucas's own cards: `ficha add`, so that Claude kept making them in a refine session, the `/refine` skill's (provisional). It also asked for two refine sessions before the builds that hide tags and the inbox: one to turn Lucas's tags into decks, one to empty his inbox. On 2026-11-26, reading the issues ADR 0041 made, Lucas said refining was something much more complex, thought for Anki, that he no longer needs it and makes his own cards apart from it, and asked to delete it. It changes ADR 0041 in part, whose `ficha add` and refine sessions kept Claude making Lucas's cards; ADR 0001 in part, whose Claude refines cards through the CLI; ADR 0007 in part, whose `/refine` skill was ours; and ADR 0012 in part, whose refining with Claude stayed Lucas's own way of making cards.

- **No refine sessions.** The `/refine` skill goes, with the content guide it followed. Lucas makes his cards as anyone does, in the Cards window, apart from the sessions that build Ficha.
- **No `ficha add`.** It was there for refine sessions alone. The CLI's capture, inbox, approve, approve-expansion and discard commands still go with Capture (ADR 0041).
- **The `ficha` CLI stays.** Agents drive Ficha Dev with it on a scratch folder, and Claude reads or writes Lucas's cards with it only in a session where he asks, writing only what he approved (`CLAUDE.md`'s Rules).
- **Lucas's tags and captures stay in the database, unseen, as anyone's do** (provisional). No session turns his tags into decks or empties his inbox before the builds that hide them. If he wants his tags as decks first, a session he asks for runs `ficha tag convert-to-decks`.
- **A flagged card is fixed in the Cards window**, with its note in sight, in its deck (ADR 0041).

## Considered options

- `/refine` kept to fix flagged cards and tidy the decks: the Cards window does both, and Lucas no longer uses it.
- `ficha add` kept, with no skill behind it: nothing but a refine session called it.

## Consequences

- #534, `ficha add`, and #535, the refine skill without captures, close as not planned, each with a comment that names this record. #540, Capture's removal, no longer waits for them, and #538 and #540 lose their hand checks on Lucas's tags and inbox.
- `CLAUDE.md`'s table of the method loses its `/refine` row. `README.md` loses its Refine paragraph, and `docs/development.md` its Refining section. `GLOSSARY.md` loses Refine and Content guide, and Approve, Fix and Bury no longer name a refine session. `PLIEGO.md`'s plano loses the content guide and the `/refine` skill, and its Hands-free line on the CLI no longer names `ficha add`.
- What the app's texts, its code and the CLI's help say of refining goes with what it's about, mostly in #540's node, which also takes the last two lines that name the content guide: a comment in FichaData's `SampleCards.swift` and a fixture in `scripts/test-hooks.sh`. Once the CLI's capture and approve go there, it makes no card: #540's replanteo checks what agents' scratch runs and `docs/development.md` use in their place.
- Older records that name refining, such as ADRs 0018 and 0022, and `docs/research/`, keep their words and are read with this one.
- Standard practice: a flashcard app whose user makes their own cards in it. Our own: nothing new; this takes one of our own skills out.
