# Domain Docs

How agents read Ficha's domain documentation while they explore the code: one `GLOSSARY.md` and `docs/adr/`, both at the repo root.

## Before exploring, read these

- **`GLOSSARY.md`**: the words of Ficha's domain, as Lucas uses them.
- **`docs/adr/`**: the decisions that touch the area you're about to work in.

`/decision` adds a word to the glossary, and a decision to `docs/adr/`, once a debate settles it.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `GLOSSARY.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap, which the next `/debate` on it asks about.

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR 0003 (cards appear when due), but worth reopening because…_
