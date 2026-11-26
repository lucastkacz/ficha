---
name: recorrida
description: Recorre el proyecto como una obra antes de retomarla: qué se hizo y por qué, dónde estás y qué sigue. No cambia nada.
disable-model-invocation: true
---

# Recorrida

The user typed `/recorrida`, alone or with a date, to pick the project up again: what was done since they last looked, and why; where it stands; and what comes next. It only reads: it changes no issue, PR or file of the project, writes only its own page, with its sources and its link, and names what it finds out of place with the command that fixes it. Read [`../../method/method.md`](../../method/method.md) and [`../../method/artifacts.md`](../../method/artifacts.md) first, then the pliego. With no pliego, tell the user `/preparar` comes first, and stop.

## 1. Since when

The date the user gave; else the date the last recorrida ran, from the file step 5 keeps; else seven days ago.

Done when you have the date.

## 2. What was done, and why

Since that date, with each time in the user's time zone:

- **Each PR merged**: what it built, its area, the day it merged and the issues it closed; how it went, from its checks and what went sideways in its body; and what it left the user, from its notes: a choice made without asking, for them to confirm; something to look at when they try it; a step before an upload; a check by hand. Of what it left, only what no later PR, decision or comment settled.
- **Why**: each issue's `El problema`, and the decision records the PR wrote or follows, with the decision's artifact.
- **What it left**: what `/entregar` wrote on the PR and its issues, and the issues it opened, such as a retro's Tasks.
- **Without a PR**: the issues opened since the date, and those closed without a PR, with why.

Done when each PR has its what, its why, how it went and what it left, and each issue without a PR its line, all in the user's language.

## 3. Where it stands

- **The order of the work**, where the pliego's How we work says it lives: each step done, next or waiting, and on what.
- **The open issues**, listed as the project's instructions say, by area and node: ready for `/construir`, Ideas for `/debate`, with no type for `/idea`, and assigned to the user.
- **The artifacts in flight**: each open issue's debate or decision, linked from its body, and whether its round or its approval waits for the user's answer, has it, or closed with nothing left to ask.
- **The open PRs**: a node being built, one waiting for the user's merge, and their checks.
- **The pliego's open items**, and whether the pliego still matches the project.

Done when every open issue and PR sits in its node, each step of the order has its state, and each artifact in flight and each open item of the pliego is listed.

## 4. What comes next

The next step is the first of these that holds, with its command and why:

1. **What waits for the user** and holds other work back, with what they do: a merge only they make, with its command; a round or an approval waiting for their answer, with its artifact's link; a change order; a check by hand.
2. **What's half done**: a PR merged since the date that closed issues and has no `Delivered:` comment from `/entregar`: `/entregar`. One merged before the repo's first such comment counts as delivered when its decision's artifact marks it built, or it has no decision. A round the user answered: `/debate`. A debate with nothing left to ask, an approval given with no decision record yet, or a probe merged whose waiting piece has no issues yet: `/decision`. A node's PR still open: the session that builds it, with what it waits on.
3. **The next node**: a bug that blocks everything, alone; else the next node in the order of the work whose issues are ready: `/construir` with it.
4. **What waits to be sorted or shaped**: `/idea` for the issues with no type; `/debate` for an Idea, or `/decision` for one small enough to need none; `/preparar` when the pliego no longer matches the project.

Under it, the rest that waits, in the same order, and the nodes that can go in parallel; and everything the PRs left the user, from step 2, each with its PR.

Done when the next step has its command, or what the user does, and its why.

## 5. Show it

The page, as [`../../method/artifacts.md`](../../method/artifacts.md) shows a recorrida, with the date it ran. Its sources go in a folder named `recorrida`, with a file that holds its link and the date it ran, so the next recorrida updates the same page and starts from that date. Then a line to the user, linking the page: what changed since the date, and the next step with its command.

Done when the page passes the checks of [`../../method/artifacts.md`](../../method/artifacts.md), the file holds its link and its date, and the user has the line.
