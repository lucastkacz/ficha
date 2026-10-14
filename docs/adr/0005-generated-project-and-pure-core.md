# A generated Xcode project and a pure core

Agents build Ficha, and an Xcode project file is a large machine-written format that's easy to break and hard to merge, so `project.yml` is the source of truth: XcodeGen generates the project, which is never committed or edited by hand. The logic lives in the `FichaKit` Swift package instead of the app: `FichaCore` holds the rules (the ladder, which cards show and when, duplicates) with nothing beyond Foundation and the standard library, and time from an injected `TimeSource`, so `swift test` checks them in seconds without building the app. The app and the CLI stay thin, going through one engine in `FichaData` that stores the cards and applies those rules.

## Considered options

- Committing the Xcode project: every change would touch a file nobody reviews, and parallel branches would conflict in it.
