# The app and the CLI each run in a sandbox, and share the cards in one folder

The Mac App Store takes only apps whose every executable runs in the App Sandbox, which lets a process reach only its own folders. Apple's documented way to ship a command-line tool in a sandboxed app has it inherit the app's sandbox, and it crashes when a terminal runs it, as Claude's does for `/refine`. So the `ficha` CLI gets a sandbox of its own, and the app and the CLI share the cards through an App Group: a folder, `~/Library/Group Containers/<TeamID>.com.lucastkacz.ficha/`, that apps of one team share without asking the user. Under the sandbox, WebKit draws SVG images only with the network entitlement, so the drawing moves to an XPC service, a small process inside the app that holds that entitlement alone, and the app holds none (#229's decision 10). Ficha Dev runs sandboxed too, in a group of its own, so the sandbox's surprises show up every day rather than first in TestFlight.

## Considered options

- The CLI inheriting the app's sandbox, as Apple documents: it crashes when a terminal, which isn't sandboxed, runs it.
- App Intents run from the terminal with `shortcuts run`, instead of the CLI: one shortcut per command, only two exit codes, and a hang if anything asks for input. It's the fallback if App Review or macOS 27 refuses the sandboxed CLI.
- A CLI signed with Developer ID and sold apart from the store: a second channel, which the store's app may not install.
- The network entitlement on the whole app: simplest, but the sandbox would no longer keep the app off the network.
- An open-source SVG library in the app's own process: a dependency that parses downloaded files, untried on Anki's flags.
- Apple's container migration for Lucas's data: it moves instead of copying, once, can't reach a group's folder, and reports no failure.

## Consequences

- A terminal tool has no open panel, and standard input already carries the cards' JSON, so the CLI reads the image and sound files it puts on cards from the Downloads folder alone, through Apple's standard read-only entitlement for it. `/refine` copies a file there first.
- The cards, images, sounds and backups live in the group's folder, which a widget can read too. A last unsandboxed build, signed by the team, copies Lucas's data and settings there once, and leaves the old folder as it was.
- Two processes still share one SQLite file, as ADR 0004 says, now in the group's folder.
- Whether App Review takes a CLI with a sandbox of its own, and whether macOS 27 lets a terminal run it without asking, is unknown until it's built and submitted: the work starts by trying it.
- `make run` signs Ficha Dev with the paid team, and `CLAUDE.md` and `/refine` name the new folder once the sandbox lands.
