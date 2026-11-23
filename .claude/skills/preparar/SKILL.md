---
name: preparar
description: Arma con vos el pliego y el plano del proyecto, y dónde corre cada trabajo, para dejar libre tu computadora; una vez por proyecto, o los repasa cuando ya no coinciden con él.
disable-model-invocation: true
---

# Preparar

The user typed `/preparar`: write the project's pliego with them, light, with its plano and where its work runs, or review the one it has against the project as it is now. Read [`../../method/method.md`](../../method/method.md) first; its words are used below. The pliego's sections are [`pliego-template.md`](pliego-template.md).

## 1. Read the project

Read what the project already says about itself: its README, `CLAUDE.md` and what it points at, the docs, the build files, CI's workflows, the hooks and permissions, the decision records, and the code's layout down to its packages or modules. With a pliego already there, read it first, then everything it points at, looking for where it no longer matches.

Then measure the machines the work could use, cloud first, trying rather than assuming:

- **The session in the cloud**: whether the user starts sessions there, and, when this one runs there, its system, its tools and what its network lets in. Run the project's build and tests in it, and keep what fails and why.
- **Rented machines**: where the repo lives and whether it's public, the runners its CI host offers by system, and what they cost on the plan of the account that owns the repo, from the host's current pricing page, linked; and how long the project's recent CI runs took.
- **The user's computer**: whether a session can reach it, and what only it has: the user's hands, signed-in accounts, a device, a tool or a license.

What trying can't tell, such as another machine the user has, is a question for the user in the artifact.

Done when each section of the template has its facts, each with the file, page or run it comes from, or is named as unknown.

## 2. Draft it

Fill the template. Each item is decided when the project's files or the user already chose it, provisional when it's your proposal, and open when nobody knows yet: an open item is decided in the debate that needs it, so write it down and move on.

- **Hands-free**: for driving, seeing and testing the product, name the project's tool, or the gap. Each gap is an open item, and, once the user agrees, the first issues to build.
- **Where it runs**: each kind of work on the first machine that can do it, in cloud first's order: the session in the cloud, a rented machine, the user's computer. Each with what it costs, how long it takes, and the page or run that says so; one that costs money is the user's choice, as a question. The checks the method needs before the PR is ready, such as the tests, need a way to run on their machine before then, such as a CI workflow on a push or on demand. A step left on the user's computer for a missing tool, or a check with no way to run before the PR is ready, is a gap: an open item, and, once the user agrees, an issue.
- **What waits for the user's OK**: the paths of CI, as its workflows and the file that lists the checks they run, the hooks, the permissions, the subagent types and the app's sandbox, as the guard that enforces them (a merge-gate hook, a branch rule) lists them. Where the guard and the pliego disagree, the guard is what holds: say so.
- **The plano**: the parts as the build files declare them, what each does, which uses which, and the rules the code keeps, with the rule every plano holds: everything is driven and seen without hands.
- **The areas**: a tree two or three levels deep, from the plano's parts and the work that isn't code.

Keep it light: a line per item, and a pointer where a file already holds the details. A fact lives in one place: the pliego points at the file that holds it, or takes it in and the file points back.

Done when every section is filled, and each item is decided, provisional or open.

## 3. Show it

An artifact, as [`../../method/artifacts.md`](../../method/artifacts.md) says: the home with the pliego's items by status, the plano as a diagram, hands-free as three columns (drives, sees, tests), where it runs as three lanes (the session, rented machines, the user's computer) with each kind of work in its lane and its cost, the areas as a tree with a color per top area, a question for each provisional item that changes how the agents work, with your recommendation, the open items, and Aprobar. The question on where it runs says the fact it rests on, in the user's terms, such as: the repo is public, so its CI's standard runners cost nothing, and the tests can run there while your computer stays free.

Tell the user in one line, with the link, and end the turn.

Done when the artifact passes the checks of [`../../method/artifacts.md`](../../method/artifacts.md), and the user has its link.

## 4. Write it

Once the user approved, on the artifact's button or in their words, and with their notes read:

1. Write the pliego as approved, and name it in `CLAUDE.md`. Move what it takes in, so each fact lives once.
2. Create a label for each node of the areas' tree, named with its path and colored as its top area, leaving the labels the repo already has.
3. Check the account's issue types: Idea, Feature, Bug and Task. For one that's missing, give the user GitHub's steps to create it, in their account's settings; nothing else waits on it.
4. Open an issue for each gap, hands-free or of where it runs, the user chose to build first, written as [`../../method/method.md`](../../method/method.md) says.
5. Open a PR with the files, through the three checks and the merge rule of [`../../method/method.md`](../../method/method.md).

Done when the PR is open and the user has the next step: `/idea` for what they want first, or `/construir` for a gap.
