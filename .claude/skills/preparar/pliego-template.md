# Pliego of <project>

What the method's skills read about <project> (`.claude/method/method.md`). Each item is ✓ decided, ◐ provisional or ○ open. An item points at the file that already holds its details, and that file is where they change.

## What it is

One or two lines: what the product does, and for whom.

## Areas

The tree, two or three levels deep, from the product's parts and the work that isn't code, such as the way of working and publishing. Each top area with its color, which its labels share.

## How it's drawn

How an agent gets a picture of a screen without the device: a render command, a simulator, a web mock kit. What the PR's pictures show, and in which languages.

## Hands-free

- **Drives it**: the CLI or debug mode an agent uses, and what it can't reach yet.
- **Sees it**: logs, screenshots, crash reports, and the commands that read them.
- **Tests it**: the test commands, and what CI runs.

What stays by hand, each with why it can't be a test yet.

## Where it runs

Cloud first (`.claude/method/method.md`): the project's machines, each with what it can do and what it costs, linked to the page that says so.

- **The session in the cloud**: its system, its tools, what its network lets in, what of the project it builds and tests, and which of the paths the guards list it can push to.
- **Rented machines**: the CI's runners by system, what they cost the project, such as nothing for a public repo's standard runners, or a price per minute by system past a private repo's included amount, and how long a run takes.
- **The user's computer**: how a session reaches it.

Then each kind of work and its machine: writing issues, debates and decisions, the reviews, the recorridas, building, the tests while building, the tests and CI of the three checks, the pictures, running the product, publishing. What stays on the user's computer, each with why no other machine can do it yet.

## What waits for the user's OK

The paths that hold CI, as its workflows and the file that lists the checks they run, the hooks, the permissions, the subagent types and the app's sandbox, as the guard that enforces them lists them, and the label a PR that changes one carries.

## When publishing

The command that publishes, the tag it leaves, and what it lists since the last tag: the changes that reach the users' data.

## Plano

The parts, as the build files declare them, what each does, and which uses which: a small diagram and a line per part. Then the rules that don't break, first of all: everything is driven and seen without hands.

## Words

The glossary's file.

## How we work

The language of each reader, the default branch, the branch and worktree rules, the standards' file, how a PR merges, what happens after a merge, and where the order of the work lives, such as a roadmap issue.

## Open

Each open item, with the debate that will decide it.
