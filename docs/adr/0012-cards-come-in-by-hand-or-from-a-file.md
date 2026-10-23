# Anyone brings their cards in by hand or from a file, never through an AI in the app

Ficha was Lucas's app, and his cards come from captures he refines with Claude through the `ficha` CLI (ADR 0001). Once it sells on the App Store (#160), anyone needs a way in of their own, and the app still holds no AI. So anyone creates cards in the Cards window, from scratch or from a capture, or imports a file. The file is plain text with one card per line, like the one Anki imports and exports as "Notes in Plain Text": an AI writes it from instructions the app copies, a spreadsheet saves it, and Anki reads what Ficha exports. Refining with Claude stays Lucas's own way of making cards, outside the app.

## Considered options

- JSON, as `ficha cards` prints: easy for programs, but no spreadsheet opens it and Anki doesn't read it.
- An AI inside the app that drafts cards for people who have none of their own: ADR 0001 ruled it out for Lucas, and it would need the network and an account.

## Consequences

- This widens who ADR 0001 is about, not what it rules: the app makes no network calls and holds no AI, and Claude still changes Lucas's cards only through the CLI.
- An export holds what the cards say, never the user's progress: a person's own cards reach another Mac through a backup, and later through iCloud sync (#161).
- Images travel in a zip, with the text file and a column naming each side's image. Sound could follow the same way.
- A card's type is optional, since cards from files and from other people rarely have one.
