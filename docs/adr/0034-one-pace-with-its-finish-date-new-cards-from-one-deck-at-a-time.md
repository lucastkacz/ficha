# One pace with its finish date: new cards come from one deck at a time, at 85%

> Changed in part by [ADR 0041](0041-ficha-is-small-decks-shown-as-cards-without-ankis-packages-tags-or-capture.md), whose priority decks go, so the queue's Put it first alone puts a deck first (2026-11-26).

The user meets 5 new cards a day, from every deck together, at a desired retention of 90% (ADR 0025), and Ficha shows no forecast (ADR 0023, kept by ADR 0025). Lucas asked for a screen as a deck comes in that says, in his words, your deck has so many cards, at so many a day you're done in so long; and for FSRS at 85%. In the Ficha Lab, a deck of 120 cards brought 13.0 appearances and 3.2 minutes each weekday over its first four weeks with today's settings, and 6.7 appearances and 1.2 minutes at 2 new cards a day and 85%. With two decks added the same day, 30 cards and 120, at 2 a day: a queue had the user meet all of the small one by day 18 and the big one by day 89, with 6.6 appearances a weekday in the second week; a pace for each deck, by days 18 and 73, with 11.3; one pace split between them, by days 36 and 90, with 7.5. In the debate of 2026-11-24 Lucas chose one pace and a queue, and approved it as a decision (ADR 0032). It replaces ADR 0023, whose last rule, no forecast, gives way to the pace's finish date; it changes ADR 0024 in part, since a deck now has a place in the queue, and ADR 0025 in part, since the desired retention starts at 85%, and its rule that Ficha shows no other statistics gives way to the finish date too.

- **The pace.** Chill, Steady or Faster, 1, 2 or 4 new cards a day, Steady to start (the numbers are provisional: the pace's issue measures them again in the Ficha Lab). It sets the new cards a day, one of the settings that decide progress, by name. Ficha asks "How fast?" as a deck comes in, and Settings' Pace tab changes it.
- **The queue.** New cards come from one deck at a time, the first in the queue, until the user has met all of its cards; then from the next. Cards already met keep coming from every deck. A deck that comes in goes last, or first if the user asks. A deck set aside leaves the queue, and a priority deck goes first (provisional).
- **The finish date.** How fast? and each deck's row in the Cards window say when the user will have met all of a deck's cards, as a range, such as "on track for mid-December". FichaCore works it out from the pace and the decks ahead in the queue, and it moves later when days go by without appearances, with no reproach. "You've met them all" marks the end, and the next deck in the queue starts.
- **85% to start.** The desired retention starts at 85% on a new install; a Mac with settings already stored keeps its own (provisional). Advanced changes it.
- **Cards per appearance and how long the panel stays.** 5 and 10 minutes, as today, until the pace's issue measures them in the Ficha Lab (provisional).

## Considered options

- A pace for each deck: in the first weeks almost twice the appearances, growing with each deck added, and a setting of each deck's own, which syncs.
- One pace split between the decks under way: it costs what the queue costs, but both decks finish late, and a deck's date moves each time another comes in.
- An exact finish date: a few days away from the Mac would break it.
- No forecast, as ADR 0023 had it: the user can't tell how long a deck takes before they start it.

## Consequences

- ADR 0023 is replaced: Ficha still shows no other statistic, as ADR 0023 and ADR 0025 had it, but the pace's finish date, so a statistics page (#465) and a streak (#461) close.
- ADR 0024's "a deck has no settings of its own" keeps, but for a deck's place in the queue, which syncs with the deck (ADR 0017): a new field in iCloud's schema, deployed before the next `make upload`.
- The `ficha` CLI sets the pace and a deck's place in the queue, and prints each deck's finish date, so agents drive and see it.
- `GLOSSARY.md` gains Pace, Queue and Finish date, and its Desired retention says 85%.
- Coming back after a break (#460) keeps a debate of its own.
- The iPhone does the same when it starts (ADR 0019).
- Standard practice: Anki's new cards a day and desired retention, and a forecast as a range. Our own: three named paces, a queue of decks for new cards, and the finish date as the one forecast.
