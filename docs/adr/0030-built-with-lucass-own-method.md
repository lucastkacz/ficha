# Ficha is built with Lucas's own method: six commands, a pliego, and one branch per node

Since ADR 0007, agents built Ficha with the `mattpocock-skills` plugin and a map of its skills in `CLAUDE.md`, partly as an experiment. After a month Lucas found its 25 skills, ours among them, too many to remember and their text too long to read, specs split into tickets slow to review, and 45 of the last 100 pull requests (#200 to #469) waiting for his merge. In nine rounds of debate, on 2026-11-19 and 2026-11-20, he designed a method of his own, generic so that any of his projects can follow it, and approved it as a decision with its before and after. It replaces ADR 0007, and changes ADR 0006 in part.

- Six commands, which only Lucas types, take an idea or a bug from his words to the code and back. `/preparar` writes a project's pliego, its plano among it; `/idea` makes an idea or a bug an issue in its area; `/debate` asks, round by round, in an artifact; `/decision` shows the decision to approve, then writes its record and splits it into issues; `/construir` builds a node's ready issues on one branch, each test first, behind one PR; `/entregar` leaves everything as built, with a retro only when something went sideways. They live in `.claude/skills/`, with what they share in `.claude/method/`, and say nothing of Ficha: they read Ficha from its pliego.
- What Lucas decides, he sees in an artifact, and what he alone reads is in Spanish: the commands' descriptions, and an issue's body above its folded part for agents, an exception to the repo's English.
- An issue carries one of the account's types, Idea, Feature, Bug or Task, and one of the repo's area labels, named with its path, such as `Mac › UI › Settings`. The triage labels go.
- A node of the areas' tree is built on one short branch from `main`, named after its path, with a commit per issue and one PR, and the branch is deleted after the merge. Each build uploaded is a tag on `main`, and there's no develop branch.
- A PR merges itself once its three checks pass: `make check` and CI, a review against what each issue asks for, and one against the plano and `CODING_STANDARDS.md`. Only a change to what limits the agents or the app waits for Lucas's merge, as `risk:high`: CI and the `Makefile`, the hooks, the permissions, the subagents' types, and the apps' sandboxes, with `project.yml`, which turns each on. Of those 100 pull requests, 22 would have waited.
- The database and the scheduler leave the merge gate, since a change to them reaches Lucas's cards only through an upload: `make upload` lists those since the last upload's tag.

## Considered options

- Keeping the plugin and its map: the commands stay many, the map follows each version, and the plugin's text stays long.
- A permanent branch per area, merged into a `develop` branch, as Lucas first proposed to cut CI's runs: the branches are merged down forever, their conflicts surface late, and git can't hold `mac` and `mac/ui` at once. A node's issues on one short branch save the same runs. GitFlow suits explicitly versioned software, but TestFlight and the App Store read no branch: they take the builds `make upload` sends, so tags on `main` mark them as well.
- Keeping the database and the scheduler `risk:high`: 34 of the 100 would have waited, for changes that reach Lucas's cards only when he installs a build.
- The area as an issue field: on a personal account a field is the account's, shared by every repo, and labels are each repo's.

## Consequences

- The plugin is off in `.claude/settings.json`, and its map in `CLAUDE.md`, the marker of its version and the session-start check of it are gone, with `docs/agents/triage-labels.md`.
- Until `/preparar` writes Ficha's pliego, `CLAUDE.md` and `docs/development.md` hold what it will.
- Ficha's open issues move to the method's types and area labels, their texts as they are: `needs-info` becomes Idea; `ready-for-agent` becomes Feature, Bug or Task; `ready-for-human` becomes assigned to Lucas; `enhancement` goes; `mac`, `ios`, `marketing` and `environment` become area labels. `risk:high` stays, for pull requests.
- A new dependency no longer makes its PR `risk:high`: Lucas approves it as a decision, before it's built.
- The decisions' page on GitHub Pages, built from `docs/adr/`, comes in a PR of its own.
- The skills move to a repo of their own once another project follows them.
- Open, for Ficha's pliego: whether CI's run on `main` after each merge stays, and which hand checks become tests.
- Standard practice: short branches off `main` (GitHub flow), tags for releases, and issue types and labels. Our own: the six commands, the pliego and the plano, a branch per node of the areas' tree, and the list `make upload` leaves.
