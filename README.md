# Ficha

A macOS menu-bar app that shows you a tiny flashcard every so often (a word, a concept, a quote or a question) and spaces each card by how well you know it. Answering takes seconds, and everything stays on your Mac.

Status: early development.

## Run it

Requires macOS 26 and Xcode 26.

```bash
make bootstrap   # installs XcodeGen
make run         # builds and opens Ficha Dev, the development app
make install     # installs Ficha in /Applications
```

Ficha Dev is a separate app, with its own menu-bar icon, data and preferences, so it runs next to Ficha without touching your cards.

## How it's built

Ficha is built by AI agents (Claude Code) with [Matt Pocock's skills](https://github.com/mattpocock/skills). Lucas brings the ideas and the decisions; the agents turn them into specs, tickets, code and pull requests. [`CLAUDE.md`](CLAUDE.md) holds the rules they follow, and [`CODING_STANDARDS.md`](CODING_STANDARDS.md) how the code is written.
