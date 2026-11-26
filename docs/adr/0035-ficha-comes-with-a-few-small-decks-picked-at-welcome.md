# Ficha comes with a few small decks, picked at the Welcome page

> Changed in part by [ADR 0040](0040-ficha-comes-with-three-decks-of-its-own-in-spanish-for-now.md), which brings three decks, Palabras lindas, Arte argentino and Flores de Buenos Aires, in Spanish for now, with the picture on a card's front (2026-11-26).

ADR 0029 has Ficha come with no decks, not even for the beta: a newcomer who doesn't come from Anki opens it empty, and on 2026-11-06 Lucas said the app is only the app. On 2026-11-13 and 2026-11-14 the examples he gave of what Ficha is for were decks: new words, the types of clouds, the twenty highest mountains, famous paintings (ADR 0032). The seven free days count from the first card (ADR 0029), and Ficha makes no network connection of its own (ADR 0017), so a deck it offers has to come inside the app. In the debate of 2026-11-24 Lucas chose to bring a few inside, for now, and approved it as a decision; later he'd like a web page where people share decks. It changes ADR 0029 in part.

- **Four to six small decks of Ficha's own.** 14 to 50 cards each, in English, inside the app.
- **The Welcome page offers them.** Beside them, an Anki file and starting from scratch; then it asks How fast? (ADR 0034), then, as today, whether Ficha opens at login.
- **The next deck.** From the Cards window, or when "You've met them all" offers one (provisional).
- **Which decks.** The types of clouds, the fourteen eight-thousanders, famous paintings and beautiful words are examples; Lucas approves each deck and each of its cards before it ships (provisional).
- **Each image has its license.** It's in the public domain or under a Creative Commons license, with its credit on its card.
- **A deck the user added is theirs.** An update of the app touches neither it nor its progress (provisional).
- **Each of Ficha's decks is a file in the app's resources.** It's in a format Ficha imports, such as its own zip (provisional), and comes in through the same import as any file.

## Considered options

- A web page with decks to download, a double click away: the user leaves the app, it needs a double click on a package (#470) and a site, which `.out-of-scope/card-sharing-website.md` rules out for now, and the Welcome page could only link to it.
- No decks, as ADR 0029 has it: a stranger without Anki writes cards before they see one, and the free days start later.

## Consequences

- ADR 0029's consequence that Ficha comes with no decks, not even for the beta, goes; its price and its trial stay. The friends' beta (#359) picks one of Ficha's decks instead of a file of Lucas's, so it tests the Welcome page as a stranger meets it.
- The app's download grows by the decks' images.
- `GLOSSARY.md` gains Ficha's decks, and its Welcome page offers them.
- The plano names Ficha's decks, which #458 brings.
- A web page where people share decks stays an idea for `/idea`.
- Standard practice: starter content inside an app, and Creative Commons attribution. Our own: the decks, and their choice at the Welcome page before the pace.
