# Ficha is for a few small things: Anki inside, Ficha outside

Since ADR 0024 and ADR 0025, Ficha had turned toward Anki, so that someone switching from it found what they know, and in #450 Lucas proposed selling it as Anki's frictionless complement, not its replacement. Ten issues asked for Anki's features one by one, from its Custom Study to its statistics. On 2026-11-13 and 2026-11-14, talking it over, he named what Ficha is for: small things, such as new words, the types of clouds or the twenty highest mountains, and never thousands of cards a day, which is what Anki is for; his mistake, he said, had been to copy Anki. The market research (#450) found that 8 of 11 launches like Ficha's were asked "why not Anki?", and read "complement" as no headline, but as a line of honesty. In two rounds of debate on 2026-11-24, in the artifact "Hacia dónde va Ficha", he settled what follows, and approved it as a decision. It replaces no record: it is the why that ADRs 0033 to 0036 rest on.

- **Ficha is its own app, for a few small things** the user wants to remember, which come to them while they work. For volume, Anki: Ficha says so once, honestly, on its App Store page.
- **Anki inside.** Ficha keeps Anki's model: decks and tags (ADR 0024), FSRS from Anki's own library (ADR 0025, ADR 0026), the four ratings each review stores, and Anki's packages, imported with their progress and exported with it (#457).
- **Ficha outside.** What the user sees is Ficha's own, simpler than Anki's: the card alone with two buttons (ADR 0033), a pace with its finish date (ADR 0034), a few small decks inside (ADR 0035), in English alone (ADR 0036). Anki's settings stay, in Settings' Advanced tab.
- **Never a flood.** What Ficha asks of the user a day doesn't grow as they add decks: the pace sees to it (ADR 0034).
- **The price stays**: $4.99 once, after seven free days (ADR 0029).

## Considered options

- Anki's frictionless complement, as #450 had it: "complement" means nothing to someone who doesn't know Anki, and nobody who stays in Anki asked for it.
- Parity with Anki, one feature at a time: it makes Ficha a smaller Anki, competing at Anki's own game.

## Consequences

- Ten issues that copied Anki, or measured against it, close as not planned, each with a comment that names this record, and can reopen: reviewing a deck freely (#392), formatting (#394), typing the answer (#395), several sounds on a side (#397), Image Occlusion (#455), several images on a side (#456), statistics like Anki's (#465), control from outside as with AnkiConnect (#466), counts and a streak (#461), and the rest of the market research (#464).
- Four are rewritten in this direction: the App Store page (#450), the launch plan (#462), the roadmap (#160), and Anki's import, which now must lose nothing in silence rather than take every note type whole (#454).
- `PLIEGO.md`'s What it is says it, and its open item on the new direction closes.
- The iPhone takes the same direction when it starts (ADR 0019, #97).
- A web page where people share decks, which Lucas would like later, stays an idea for `/idea`: `.out-of-scope/card-sharing-website.md` says Ficha keeps no such site.
- Standard practice: a store page that names the bigger tool honestly. Our own: Anki's model inside, Ficha's own face outside.
