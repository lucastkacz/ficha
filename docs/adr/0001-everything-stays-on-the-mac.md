# Everything stays on the Mac, and Claude refines cards only through the CLI

Ficha holds what Lucas is learning, and he wants it private and under his control. The app makes no network calls and has no accounts or telemetry, and cards live in one SQLite file in Application Support, never in the repo. There's no AI inside the app: Claude improves cards only in a session Lucas starts, through the `ficha` command-line tool, and saves only what Lucas approves.

## Considered options

- An assistant inside the app that drafts cards on its own: it needs the network, and it would change cards without Lucas looking.

## Consequences

- Lucas captures on the Mac only, from the menu bar or the CLI: nothing reaches Ficha from his phone.
- The app and the CLI must agree on the database, so both use the same storage code and migrations.
- Since ADR 0012, Ficha is for anyone: other people bring their cards in by hand or from a file, and refining with Claude stays Lucas's own way of making cards.
