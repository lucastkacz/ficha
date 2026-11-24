# Issue tracker: GitHub

Issues for this repo live as GitHub issues, with the method's types, area labels and body, which `.claude/method/method.md` describes, with how to create, retype and list them through `gh`. On Lucas's Mac, the `gh` CLI does every operation below. A cloud session can't use all of `gh`, as `PLIEGO.md`'s Where it runs says, so it takes each operation's form **from the cloud**: its own GitHub tools, such as `issue_read`, and `gh api`'s route `search/issues` to find issues.

## Conventions

- **Create a detour**: an issue that comes up while building another, such as a retro's change or a tool an issue needs, is a detour. Its body starts with the issue it came up in, so GitHub lists it in that issue's timeline: "Came up in the retro of #127, a detour from the Cards window (#87)." An issue that waits for a detour gets a `Blocked by` line in its folded part for the agent, since **Read an issue** doesn't show the links, and GitHub's native link too wherever the session can add it, as **Blocking** below says.
- **Create an issue, or change its type**: through `gh`, as `.claude/method/method.md` says. From the cloud: `issue_write`'s `create`, with its `type`, `labels` and any `assignees`; its `update` with `type` changes the type.
- **Read an issue**: `gh issue view <number> --json number,title,issueType,body,labels,comments`. From the cloud: `issue_read`'s `get`, then its `get_comments`, since `get` leaves the comments out.
- **List issues**: `gh issue list --state open --json number,title,issueType,body,labels,comments --jq '[.[] | {number, title, type: .issueType.name, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label`, `--type` and `--state` filters. From the cloud: `gh api -X GET search/issues -f per_page=100 -f q='repo:lucastkacz/ficha is:issue is:open type:<Type> label:"<area>"' --jq '[.items[] | {number, title, type: .type.name, body, labels: [.labels[].name]}]'`, with the qualifiers the list needs, then each issue's comments with `issue_read`'s `get_comments`, since the search gives only their count.
- **Make an issue a sub-issue of a parent**: `gh issue edit <parent> --add-sub-issue <child>` once both exist (`gh` 2.94+). Older `gh`: `gh api --method POST repos/<owner>/<repo>/issues/<parent>/sub_issues -F sub_issue_id=<child-db-id>` (database id, as in **Blocking** below). From the cloud: `sub_issue_write`'s `add`, with the child's database id, its `id` in `search/issues`' results. Without sub-issues, put `Part of #<parent>` at the top of the child body.
- **Comment on an issue**: `gh issue comment <number> --body "..."`. From the cloud: `add_issue_comment`.
- **Leave work to another issue**: when an issue, or its PR, leaves part of its work to another open issue, a comment on the other issue says what is left to it and why: the agent that builds the other issue reads only its body and comments (**Read an issue**).
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`. From the cloud: `issue_write`'s `update` with `labels`, every label the issue keeps, since the list replaces its labels.
- **Blocking**: GitHub's **native issue dependencies**, the canonical, UI-visible representation. Add an edge with `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`, where `<blocker-db-id>` is the blocker's numeric **database id** (`gh api repos/<owner>/<repo>/issues/<n> --jq .id`, _not_ the `#number` or `node_id`). GitHub reports `issue_dependencies_summary.blocked_by` (open blockers only). An issue is unblocked when every blocker is closed. From the cloud, whose GitHub tools have no route for dependencies: the same `gh api` calls where the session's own instructions allow `gh api` beyond searches, and otherwise the `Blocked by` line alone.
- **Close**: an issue closes through the pull request that resolves it: the PR body says `Closes #<n>`, and GitHub closes the issue on merge. Use `gh issue close <number> --reason "not planned" --comment "..."` only for an issue no PR resolves, such as a duplicate or one Lucas decided against. From the cloud: `add_issue_comment`, then `issue_write`'s `update` with `state` `closed` and `state_reason` `not_planned`.

Infer the repo from `git remote -v`; `gh` does this automatically when run inside a clone. From the cloud, the GitHub tools take it as owner `lucastkacz` and repo `ficha`.

## How big an issue is

An issue is all one agent can build in one fresh context without compacting: up to about 1,500 changed lines, tests included. Each costs about $14 before its first line, plus about $1 per 100 changed lines, so fewer, bigger issues cost less, up to the size where a session compacts. `/decision` sizes them so.

- A node's PR holds all its ready issues, each in commits that name it; with several, one `builder` writes every issue's test, for `/construir`'s first round, and then each issue's code is built in a fresh context of its own, by a `builder`.
- A node that needs Lucas at his Mac partway, such as a hand check before its next issues can start, goes in as two PRs, split there.

## Hand checks

What only Lucas can check by hand on his Mac waits in one open issue, assigned to him, whose title starts with `Hand checks`:

```
gh issue list --state open --search 'in:title "Hand checks"' --json number,title,issueType,labels,assignees,body,comments
```

From the cloud, this search, then the issue's comments with `issue_read`'s `get_comments`:

```
gh api -X GET search/issues -f q='repo:lucastkacz/ficha is:issue is:open in:title "Hand checks"' --jq '[.items[] | select(.title | startswith("Hand checks")) | {number, title, type: .type.name, labels: [.labels[].name], assignees: [.assignees[].login], body}]'
```

Each check is a comment of its own, since an issue's body holds only 65,536 characters, and the body's **The checks** lists them, one task-list line each, under the part of Ficha it checks. When none is open, the next check opens one like the last one, which the same command finds with `--state closed --limit 1`, or from the cloud with `is:closed` and `-f sort=created`, its first result: its title, its type, its labels, its assignee, its opening paragraphs as far as they still hold, and the check's own line alone under **The checks**. A PR whose change needs Lucas's hands adds each of its checks as soon as it opens, since a check names its PR:

1. Post each check as a comment of its own on that issue (`gh issue comment <n> --body-file <file>`; from the cloud, `add_issue_comment`), written as the checks already there are: a heading with its name in Lucas's words, the issue and the PR it came from, what the PR couldn't try, numbered steps, and a task list of when it's done that ends with "Anything that felt off is written here."
2. Read the body afresh, add a line for each check, written as the lines already there are, and write the body back (`gh issue edit <n> --body-file <file>`; from the cloud, `issue_write`'s `update` with `body`).
3. Add the links to the checks' comments to the PR's body (`gh pr edit <pr> --body-file <file>`; from the cloud, `update_pull_request` with `body`).

Lucas tells a session how a check went, and that session ticks it: it reads the body afresh, ticks the check's line and writes the body back, then posts what he said as a comment that links the check's. A check that found a bug stays unticked until the fix is on `main` and Lucas checks again, and the session suggests `/idea` for the bug. Once every line is ticked, the session closes the issue (`gh issue close <n> --reason completed`; from the cloud, `issue_write`'s `update` with `state` `closed` and `state_reason` `completed`).

The iPhone's checks keep issues of their own until the iPhone starts.
