---
name: decision
description: Arma la decisión para que la apruebes, con su antes y su después; aprobada, la escribe y la parte en issues listos para construir.
disable-model-invocation: true
---

# Decision

The user typed `/decision` after a debate, or for an idea small enough to need none, or after approving, or once a probe a piece waited on merged. Build the decision for the user to approve; once approved, write it down and split it into issues `/construir` can build. Read [`../../method/method.md`](../../method/method.md) and [`../../method/artifacts.md`](../../method/artifacts.md) first, then the pliego. With no pliego, tell the user `/preparar` comes first, and stop.

When the decision's artifact already exists and the user says they approved, start at **3**. When a probe a piece waited on has merged, start at **3**'s step 2, for that piece alone, with what its PR found; an answer the piece didn't plan for sends it back to `/debate`.

## 1. The pieces

From the debate's answers, read from its artifact's database, or from the idea's issue: the decision in pieces, each a change the user sees on its own. Each piece has:

- its before and after, shown;
- what gets built, as items, each decided, provisional or open; an open item a probe can settle, with what the piece does with each of its answers;
- why, in a line;
- the plano before and after, when it changes it;
- the agent's part, folded, in English: the decision records it follows, replaces or changes in part, and its acceptance criteria.

Done when every answer of the debate is in a piece, and every item of what gets built is decided, provisional or open.

## 2. Show it

The decision's artifact, as [`../../method/artifacts.md`](../../method/artifacts.md) says, linked from the idea's issue. Tell the user in one line, with the link, and end the turn.

Done when the artifact passes the checks of [`../../method/artifacts.md`](../../method/artifacts.md), the idea's issue links it, and the user has its link.

## 3. Approved

Read the approval and the notes from the artifact's database. A note that changes a piece: change it, show it again, and end the turn. Approved as it is:

1. **The record**: a decision record in the project's format, in English, saying which records it replaces or changes in part.
2. **The pliego**: the open items it decided, and the plano's changes; and the glossary's new words.
3. **A PR** with those, through the three checks and the merge rule of [`../../method/method.md`](../../method/method.md).
4. **The issues**: one for each part of the work `/construir` can build and check on its own, a Feature, a Bug or a Task, in its area, written as [`../../method/method.md`](../../method/method.md) says and linking the artifact. A piece with an open item that changes what gets built gets, first, a probe, a Task that names the piece it holds back, when the piece says what it does with each answer, or else goes back to `/debate`: its Feature, Bug or Task is written once the probe or the debate settles the item, so `/construir` never finds it open. The Idea it came from becomes the first of them, its type and body updated, or, when it became several, closes with a comment that links them.
5. **The artifact** marks the decision approved, and links its record and its issues.

Done when every piece is in the record, in an issue, or waiting on its probe or its debate, and the user has the issues by node, titles linked, with the next step: `/construir` with the node to build first, or with the probe, or `/debate` on a piece that went back.
