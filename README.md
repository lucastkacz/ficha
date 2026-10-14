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

Ficha Dev's menu also has "Depuración", to try a change in minutes: it loads sample cards, written by hand, and moves Ficha Dev's time forward. Its time keeps running from there, and stays ahead when Ficha Dev restarts. The real Ficha has no such menu and always runs on the system's time.

## The `ficha` command

Ficha ships with a command-line tool inside the app. Claude uses it to turn your captures into cards, and you can capture from a terminal with it:

```bash
/Applications/Ficha.app/Contents/Helpers/ficha capture "serendipia" --source "Un ensayo de Borges"
```

`ficha --help` lists its commands; each one prints JSON. To type just `ficha`, add an alias to `~/.zshrc`:

```bash
alias ficha="/Applications/Ficha.app/Contents/Helpers/ficha"
```

The `ficha` inside Ficha Dev, which `make build` puts in `.build/DerivedData/Build/Products/Debug/Ficha Dev.app/Contents/Helpers/`, works on Ficha Dev's cards.

## How it's built

Ficha is built by AI agents (Claude Code) with [Matt Pocock's skills](https://github.com/mattpocock/skills). Lucas brings the ideas and the decisions; the agents turn them into specs, tickets, code and pull requests. [`CLAUDE.md`](CLAUDE.md) holds the rules they follow, and [`CODING_STANDARDS.md`](CODING_STANDARDS.md) how the code is written.
