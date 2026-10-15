# The ficha CLI is built with swift-argument-parser

The `ficha` CLI reads subcommands, arguments and options, prints its help and says what's wrong with what it got. Apple's swift-argument-parser, the open-source package most Swift command-line tools use, does all of that from a few declarations, with the usual conventions (`--help`, subcommands, exit codes). We picked it over parsing the arguments by hand, which would save a dependency but leave us the help, the error messages and every command's parsing to write and keep up.

## Consequences

- swift-argument-parser is Ficha's second dependency, pinned to an exact version in `Package.swift`; this is the ADR that `CODING_STANDARDS.md` asks for.
- The commands live in FichaKit's `FichaCLI` target, so the pin stays in `Package.swift`. The executable is a target of the Xcode project, built with each app and shipped inside it, and it only picks whose cards the commands open: Ficha Dev's or the real Ficha's.
- The library's own messages, such as "Show help information.", are in English, and since ADR 0009 so are ours.
