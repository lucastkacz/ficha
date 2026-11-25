---
name: recorrida
description: Recorre el proyecto como una obra antes de retomarla: qué se hizo y por qué, dónde estás y qué sigue. No cambia nada.
disable-model-invocation: true
---

# Recorrida

The user typed `/recorrida`, alone or with a date, to pick the project up again: what was done since they last looked, and why; where it stands; and what comes next. It only reads: it changes no issue, PR or file, only its own page, and it names what it finds out of place with the command that fixes it. Read [`../../method/method.md`](../../method/method.md) and [`../../method/artifacts.md`](../../method/artifacts.md) first, then the pliego. With no pliego, tell the user `/preparar` comes first, and stop.

## 1. Since when

The date the user gave; else the date the last recorrida's page shows, found by the link step 5 keeps; else seven days ago.

Done when you have the date.

## 2. What was done, and why

Since that date, with each time in the user's time zone:

- **Each PR merged**: what it built, its area, the issues it closed, and what went sideways, from its body.
- **Why**: each issue's `El problema`, and the decision records the PR wrote or follows, with the decision's artifact.
- **What it left**: what `/entregar` wrote on the PR and its issues, the issues opened since, such as a retro's Tasks, and those closed without a PR, with why.

Done when each PR has its what and its why, a line each, in the user's words.

## 3. Where it stands

- **The order of the work**, where the pliego's How we work says it lives: each step done, next or waiting, and on what.
- **The open issues**, listed as the project's instructions say, by area and node: ready for `/construir`, Ideas for `/debate`, with no type for `/idea`, and assigned to the user.
- **The artifacts waiting for the user**: each open issue's debate or decision, linked from its body, whose round or approval has no answer in its database.
- **The open PRs**: a node being built, one waiting for the user's merge, and their checks.
- **The pliego's open items**.

Done when every open issue and PR sits in its node, and each step of the order has its state.

## 4. What comes next

The next step is the first of these that holds, with its command and why:

1. **What waits for the user** and holds other work back: a merge only they make, a round or a decision waiting for their answer, a change order, a check by hand.
2. **What's half done**: a merged PR with no comment from `/entregar` on it, or a node's PR still open.
3. **The next node** in the order of the work whose issues are ready: `/construir` with it.
4. **What waits to be sorted or shaped**: `/idea`, `/debate`.

Under it, the rest that waits, in the same order, and the nodes that can go in parallel.

Done when the next step has its command and its why.

## 5. Show it

The page, as [`../../method/artifacts.md`](../../method/artifacts.md) shows a recorrida, published again to the same link each time, with the date it ran. Its sources go where the pliego keeps artifacts' sources, with a file beside them that holds its link, so the next recorrida finds it. Then two lines to the user: what changed since the date, and the next step with its command, linking the page.

Done when the page passes the checks of [`../../method/artifacts.md`](../../method/artifacts.md), its link is kept beside its sources, and the user has the two lines.
