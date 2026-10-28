# Issue tracker: GitHub

Issues and specs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies. A ticket written for a spec, or a spec, opens with **Where this sits** below.
- **Create a detour**: an issue that comes up while building another, such as a retro's environment changes or a tool a ticket needs, is a detour. Its body starts with the issue it came up in and the spec being built at the time, if any, so GitHub lists it in the spec's timeline: "Came up in the retro of #127, a detour from the Cards window (#87)." A ticket that waits for a detour gets both GitHub's native link, as **Blocking** below shows, and a line in its "Blocked by" section, since **Read an issue** doesn't show the links.
- **Read an issue**: `gh issue view <number> --json number,title,body,labels,comments`.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Make an issue a sub-issue of a parent**: `gh issue create --parent <parent> ...`, or `gh issue edit <parent> --add-sub-issue <child>` afterwards (`gh` 2.94+). Older `gh`: `gh api --method POST repos/<owner>/<repo>/issues/<parent>/sub_issues -F sub_issue_id=<child-db-id>` (database id, as in **Blocking** below). Without sub-issues, put `Part of #<parent>` at the top of the child body.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Leave work to another issue**: when an issue, or its PR, leaves part of its work to another open issue, a comment on the other issue says what is left to it and why: the agent that builds the other issue reads only its body and comments (**Read an issue**).
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: an issue closes through the pull request that resolves it: the PR body says `Closes #<n>`, and GitHub closes the issue on merge. Use `gh issue close <number> --comment "..."` only for an issue no PR resolves, such as a duplicate or `wontfix`.

Infer the repo from `git remote -v`; `gh` does this automatically when run inside a clone.

## Where this sits

Lucas reads each ticket and spec before an agent builds it, and the rest of the body is written for that agent, in the code's names. So a ticket written for a spec, by `/to-tickets` or by hand, opens with a `## Where this sits` section, above its template's first section, as #183 shows. Its three parts name each thing in Lucas's words first, those of `GLOSSARY.md`, then its code name, such as `CardsWindowState`, if it needs one:

1. **The thread**, in one or two sentences from the roadmap down: the step of the open roadmap issue (its title starts with `Roadmap:`) that the work belongs to, or that it's outside the roadmap; where the spec came from, such as a grilling, a review or a bug; and the spec, by number.
2. **The spec's tickets**, as a table, `| Step | Ticket | What it does |`, one row per ticket in the order they're built. A ticket that can run beside others gets a step such as "any time after 1". This ticket's row is in bold, with `#<n>, this one` in its Ticket cell. The table shows order alone: GitHub shows each linked issue's state.
3. **In plain words**, a paragraph that starts "In plain words:": what the ticket changes, why, and what Lucas sees change, or that nothing does.

The table is complete only once every ticket has its number, so publish the tickets first, then give each its section (`gh issue edit <n> --body-file <file>`). A ticket added to the spec later gets a row in each sibling's table too.

A spec opens with the thread alone, up to where it came from, under the same heading: its Problem Statement already speaks from Lucas's side, and its tickets come later.

## How big a ticket is

A ticket is all one agent can build in one fresh context without compacting: up to about 1,500 changed lines, tests included. That is the size "sized to fit in a single fresh context window" means here, when `/to-tickets` drafts its slices. Each ticket costs about $14 before its first line, plus about $1 per 100 changed lines, so fewer, bigger tickets cost less, up to the size where a session compacts.

- A spec that fits in one ticket is one ticket, published as the spec's sub-issue like any other and built with `/implement` in one session.
- A spec splits into tickets only past that size, and its tickets land together, on one branch behind one PR (`/implement-spec`, in `CLAUDE.md`).
- A spec that needs Lucas at his Mac partway, such as a hand check before the next tickets can start, splits there into **stages**, one PR each, and the breakdown names each ticket's stage.
- Issues outside any spec, of one kind and one risk, join up to this size in one session and one PR, as `CLAUDE.md`'s skill map says.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues, using the `gh pr` equivalents:

- **Read a PR**: `gh pr view <number> --comments` and `gh pr diff <number>` for the diff.
- **List external PRs for triage**: `gh api --paginate 'repos/{owner}/{repo}/pulls?state=open' --jq '.[] | select(.author_association | IN("OWNER","MEMBER","COLLABORATOR") | not) | {number, title, author: .user.login, author_association, labels: [.labels[].name]}'`.
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, `gh pr close`.

GitHub shares one number space across issues and PRs, so a bare `#42` may be either: resolve with `gh pr view 42` and fall back to reading it as an issue (**Read an issue**).

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Read it as in **Read an issue** above.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body. `gh issue create --label wayfinder:map`.
- **Child ticket**: an issue linked to the map as a GitHub sub-issue (see **Make an issue a sub-issue of a parent**). Where sub-issues aren't enabled, add the child to a task list in the map body and put `Part of #<map>` at the top of the child body. Labels: `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed, the ticket is assigned to the driving dev.
- **Blocking**: GitHub's **native issue dependencies**, the canonical, UI-visible representation. Add an edge with `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`, where `<blocker-db-id>` is the blocker's numeric **database id** (`gh api repos/<owner>/<repo>/issues/<n> --jq .id`, _not_ the `#number` or `node_id`). GitHub reports `issue_dependencies_summary.blocked_by` (open blockers only, the live gate). Where dependencies aren't available, fall back to a `Blocked by: #<n>, #<n>` line at the top of the child body. A ticket is unblocked when every blocker is closed.
- **Frontier query**: list the map's open children (`gh issue list --state open`, scoped to the map's sub-issues / task list), drop any with an open blocker (`issue_dependencies_summary.blocked_by > 0`, or an open issue in the `Blocked by` line) or an assignee; first in map order wins.
- **Claim**: `gh issue edit <n> --add-assignee @me`, the session's first write.
- **Resolve**: `gh issue comment <n> --body "<answer>"`, then `gh issue close <n>`, then append a context pointer (gist + link) to the map's Decisions-so-far.
