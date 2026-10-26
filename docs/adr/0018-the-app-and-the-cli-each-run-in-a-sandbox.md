# The app and the CLI each run in a sandbox, and share the cards in one folder

The Mac App Store takes only apps whose every executable runs in the App Sandbox, which lets a process reach only its own folders. Apple's documented way to ship a command-line tool in a sandboxed app has it inherit the app's sandbox, and it crashes when a terminal runs it, as Claude's does for `/refine`. So the `ficha` CLI gets a sandbox of its own, and the app and the CLI share the cards through an App Group: a folder, `~/Library/Group Containers/<TeamID>.com.lucastkacz.ficha/`, that apps signed by one Apple Developer team share without asking the user. Under the sandbox, WebKit draws SVG images only with the network entitlement, so the drawing moves to an XPC service, a small process inside the app that holds that entitlement alone, and the app holds none (decision 10 of #229). Ficha Dev runs sandboxed too, in a group of its own, so the sandbox's surprises show up every day rather than first in TestFlight.

## Considered options

- The CLI inheriting the app's sandbox, as Apple documents: it crashes when a terminal, which isn't sandboxed, runs it.
- App Intents run from the terminal with `shortcuts run`, instead of the CLI: one shortcut per command, only two exit codes, and a hang if anything asks for input. It's the fallback if App Review or macOS 27 refuses the sandboxed CLI.
- A CLI signed with Developer ID and sold apart from the store: a second channel, which the store's app may not install.
- The network entitlement on the whole app: simplest, but the sandbox would no longer keep the app off the network.
- An open-source SVG library in the app's own process: a dependency that parses downloaded files, untried on Anki's flags.
- Apple's migration of an app's files into its sandbox: it moves instead of copying, once, can't reach the group's folder, and reports no failure.

## Consequences

- A terminal tool has no open panel, and standard input already carries the cards' JSON, so the CLI reads the image and sound files it puts on cards from the Downloads folder alone, through Apple's standard read-only entitlement for it. `/refine` copies a file there first.
- The cards, images, sounds and backups move from Application Support, where ADR 0001 put them, to the group's folder. A last unsandboxed build, signed with Lucas's paid team, copies his data and settings there once and leaves the old folder as it was; if that fails, the sandboxed app asks him to pick the old folder.
- Two processes still write one SQLite file, as ADR 0004 says, now in the group's folder, and a widget reads it too, which needs the writers to keep SQLite's side files between connections (persistent WAL).
- Whether App Review takes a CLI with a sandbox of its own, and whether macOS 27 lets a terminal run it without asking, is unknown until it's built and submitted: the work starts by trying it.
- Every build of Ficha Dev, `make run`'s included, is signed with the paid team. Once the sandbox lands, everything that names the old folder names the new one: `CLAUDE.md`, `/refine`, the permissions that keep agents out of Lucas's cards, and the development docs.
- Standard practice: the App Sandbox, an App Group named with the team's ID as macOS expects, Apple's entitlement for the Downloads folder, and an XPC service to keep one entitlement apart. Our own: a command-line tool with a sandbox of its own, which Apple staff suggest on the developer forums but no document describes, and the copy by a last unsandboxed build.
