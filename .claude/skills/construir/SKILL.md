---
name: construir
description: Construye un nodo: sus issues listos en una rama corta, cada uno con su test primero, revisados, en un solo PR.
disable-model-invocation: true
---

# Construir

The user typed `/construir` with a node, such as `Mac › UI › Settings`, or an issue, whose node it builds. Build the node's ready issues on one branch, each test first, check them, and open the node's PR. Read [`../../method/method.md`](../../method/method.md) first, then the pliego, its plano and the project's standards. With no pliego, tell the user `/preparar` comes first, and stop.

## 1. The node's issues

The open issues of type Feature, Bug or Task whose area is the node or below it, leaving out those assigned to the user, which wait for them. Read each with every comment. A bug named alone, because it blocks everything, is a node of its own.

Done when you have the list. With nothing ready, tell the user what the node holds, such as Ideas waiting for `/debate`, and stop.

## 2. Replanteo

Set each issue against today's code: the files and tests it touches, and anything it assumes that changed since it was decided, such as a part renamed, a rule moved or a decision replaced.

- **Something changed**: stop, and ask the user in one message, with how it was and how it is.
- **The plano must change**: a change order, as [`../../method/artifacts.md`](../../method/artifacts.md) shows one: the plano before and after, and the node's issues it touches, with Aprobar. Stop until the user approves it; a big one goes back to `/debate`.

Done when each issue has its files and tests, and nothing it assumes has changed.

## 3. Build

Open the node's branch from the default branch, as [`../../method/method.md`](../../method/method.md) names it, or as the project's instructions say. Then each issue in turn, each building on the last:

1. **The test first**: one that fails for the issue's reason, the bug reproduced or an acceptance criterion unmet. Run it, and see it fail.
2. **The code**, until it passes with the project's tests.
3. **One commit**, whose message names the issue. A change order the user approved updates the plano in it.

A fix that would change a decision goes back to `/debate`: stop, and tell the user.

Done when every issue has its commit and its passing test.

## 4. The three checks

1. **Tests and CI**: every command the pliego names, passing.
2. **What each issue asked for**: a fresh reviewer gets the issues, with their comments, and the diff, and reports for each issue whether `Qué buscamos` and every acceptance criterion hold, citing file and line.
3. **The plano and the standards**: a fresh reviewer gets the plano, the standards and the diff, and reports each rule broken, citing the rule, the file and the line.

A change the user sees gets its pictures, as the pliego says. Fix every finding, then run the check it came from again.

Done when all three pass with no finding left.

## 5. The PR

One PR from the node's branch, in English: a title that names the node and what it does, then each issue it closes (`Closes #<n>`), what was built, the three checks' results, and the pictures.

- **It changes a path the pliego lists under what waits for the user's OK**: the project's label for it, and the user's merge command, last in the message.
- **Otherwise**: it merges itself once CI passes, as the project's instructions turn that on.

Tell the user in one line: the PR, linked, and whether it merges itself or waits for them. After the merge, `/entregar`.
