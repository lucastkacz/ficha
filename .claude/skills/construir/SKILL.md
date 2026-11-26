---
name: construir
description: Construye un nodo: sus issues listos en una rama corta, con sus tests primero, revisados, en un solo PR.
disable-model-invocation: true
---

# Construir

The user typed `/construir` with a node, such as `Mac › UI › Settings`, or an issue, whose node it builds. Build the node's ready issues on one branch, their tests first, check them, and open the node's PR. Read [`../../method/method.md`](../../method/method.md) first, then the pliego, its plano and the project's standards. With no pliego, tell the user `/preparar` comes first, and stop.

## 1. The node's issues

The open issues of type Feature, Bug or Task whose area is the node or below it, leaving out those assigned to the user and those an open PR already closes, found as the project's instructions say: tell the user which PR holds each, and who opened it when someone other than the user did. Read each with every comment. A bug named alone, because it blocks everything, is a node of its own.

Done when you have the list. With nothing ready, tell the user what the node holds, such as Ideas waiting for `/debate` or issues an open PR holds, and stop.

## 2. Replanteo

Set each issue against today's code: the files and tests it touches, and anything it assumes that changed since it was decided, such as a part renamed, a rule moved or a decision replaced. An acceptance criterion that doesn't name its proof gets one, in the issue, as [`../../method/method.md`](../../method/method.md)'s Issues says.

A step of the node that needs the user or their machine, such as their OK to run something there, is asked for as soon as the replanteo shows it, all such steps in one message, and the build goes on while the answer comes.

- **Something changed**: stop, and ask the user in one message, with how it was and how it is.
- **The plano must change**: a change order, as [`../../method/artifacts.md`](../../method/artifacts.md) shows one: the plano before and after, and the node's issues it touches, with Aprobar. Stop until the user approves it; a big one goes back to `/debate`.

Done when each issue has its files and tests, every criterion its proof, nothing it assumes has changed, and each step that needs the user has been asked for.

## 3. Build

Open the node's branch from the default branch, as [`../../method/method.md`](../../method/method.md) names it, or as the project's instructions say. Each run of the tests goes where the pliego says; where that's CI on a draft PR, the first push opens the node's PR as a draft. Before the node's first push, look again as step 1 does: when an open PR now closes one of the node's issues, stop, and tell the user which PR holds which issue, as step 1 does. Then the node in two rounds:

1. **The tests first**: for each issue in turn, a test that fails for its reason, the bug reproduced or an `Accept (test)` criterion unmet, marked with its issue as the project's standards say, in a commit that names the issue. What a test needs that doesn't exist yet gets a stub that compiles and fails it, so one missing part doesn't hide the other tests. Run them all at once, and see each fail for its own issue's reason.
2. **The code**: for each issue in turn, each building on the last, in a commit that names the issue; a change order the user approved updates the plano in it. Then run the project's tests until all pass, each fix in a commit of its own that names its issue. Each commit of this round, a fix's too, also updates the lines elsewhere that describe what it changed: the project's standards say which changes those are and how to find the lines.

A fix that would change a decision goes back to `/debate`: stop, and tell the user.

Done when every issue has its commits and its passing test.

## 4. The three checks

1. **Tests and CI**: every command the pliego names, passing.
2. **What each issue asked for**: a fresh reviewer gets the issues, with their comments, and the diff, and reports for each issue whether `Qué buscamos` and every acceptance criterion hold, citing file and line.
3. **The plano and the standards**: a fresh reviewer gets the plano, the standards and the diff, and reports each rule broken, citing the rule, the file and the line. A diff too large for one careful read, such as files moved in from outside the repo, is split by groups of files, a fresh reviewer each, all in the same pass, and the check passes when every group does. The groups together are one pass over the whole diff: their findings are fixed together, and the check runs again as after any other pass.

A change the user sees gets its pictures, as the pliego says. Fix every finding, and before committing a fix, read it against the rule its finding cites and, for the text it writes, the project's standards for documents. Then run the check it came from again: once a pass has read the whole diff, a review run again reads the lines the fixes changed and what they could leave stale. Then a procedure the node writes for agents that its issues didn't ask for, such as steps to take on another machine, runs once as written, after its last change, on the machine it's for, before the PR is ready. When that machine can't be reached, the node gets that step done another way, such as the user taking it by hand, and the procedure goes to a Task of its own, in the area of the way of working, written as [`../../method/method.md`](../../method/method.md) says. A step the replanteo asked the user for, such as this one, runs at once when their answer has come, and waits for it only when it hasn't.

Done when all three pass with no finding left, and each such procedure ran as written, or its step got done another way and the procedure has its own Task.

## 5. The PR

With no draft yet, the node's first push comes now: look again first, as step 3 says. Then one PR from the node's branch, or the draft its rounds ran on, marked ready, in the repo's language: a title that names the node and what it does, then each issue it closes (`Closes #<n>`), what was built, the three checks' results, the pictures, for a probe what it found, how each procedure of step 4 ran, or how the node got its step done instead, with the procedure's Task, and what went sideways while building, as [`../../method/method.md`](../../method/method.md) says, or that nothing did.

- **It changes a path the pliego lists under what waits for the user's OK**: the project's label for it, and the user's merge command, last in the message.
- **Otherwise**: it merges itself once CI passes, as the project's instructions turn that on.

Tell the user in one line: the PR, linked, and whether it merges itself or waits for them. After the merge, `/entregar`.

Done when the PR is ready, merging itself or labeled for the user's merge, and the user has the line.
