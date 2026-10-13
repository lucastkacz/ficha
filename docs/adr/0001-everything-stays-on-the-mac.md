# Everything stays on the Mac, and Claude refines cards only through the CLI

Ficha holds what Lucas is learning, and he wants it private and under his control. The app makes no network calls and has no accounts or telemetry; cards live in one SQLite file in `~/Library/Application Support/Ficha/`, never in the repo. There's no AI inside the app: Claude improves cards only in a session Lucas starts, through the `ficha` command-line tool. Claude drafts each card following the content guide, Lucas approves it, and only then is it saved.

## Considered options

- An assistant inside the app that drafts cards on its own: it needs the network, and it would change cards without Lucas looking.

## Consequences

- Lucas captures on the Mac only, from the menu bar or the CLI: nothing reaches Ficha from his phone.
- The app and the CLI must agree on the database, so both use the same storage code and migrations.
