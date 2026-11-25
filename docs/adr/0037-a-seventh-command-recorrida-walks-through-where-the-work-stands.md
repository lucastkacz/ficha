# A seventh command, /recorrida, walks through where the work stands

Coming back to Ficha after a few days, Lucas twice in a week had to ask where it stood: on 2026-11-19 ("I don't even remember where this was left"), and on 2026-11-23, when a session drew the artifact "Dónde está Ficha" by hand. None of ADR 0030's six commands answers that: they take an idea from Lucas's words to the code, and the session-start hook lists the open issues with no dates and no why. On 2026-11-25 he asked for a command that tells what was done last, why, and what comes next, reading the backlog, and approved it as proposed in the artifact "Recorrida", with a real recorrida of Ficha that day. It changes ADR 0030 in part, whose method had six commands.

- **`/recorrida`, outside the flow.** The six take an idea to the code and back; the seventh walks through where they all stand, as a site's director walks a building site before work resumes. Only Lucas types it, as the others, and it can run at any time, in a session in the cloud, as the debates and decisions do: it reads GitHub, the repo and the artifacts, and keeps its page's sources with theirs.
- **It only reads.** It changes no issue, PR or file of the project, writes only its own page, and names what it finds out of place with the command that fixes it.
- **Since the last recorrida**, or the date Lucas gives; the first time, the last seven days.
- **What it reads**: each PR merged since then, with the why from its issues' `El problema` and its decision records; what `/entregar` left; the open issues by area and node; the artifacts waiting for Lucas's answer; the open PRs; the pliego's open items; and the order of the work, where the pliego says it lives, which in Ficha is the roadmap issue (#160).
- **What it leaves**: one page, published again to the same link each time, with since when, what was done and why, where it stands and what comes next; and a line in the chat with what changed and the next step.
- **What comes next**: one step with its command and why, the first that holds of: what waits for Lucas; what's half done, for `/entregar`, `/debate` or `/decision`; the next node in the order of the work, for `/construir`; and what waits to be sorted or shaped, for `/idea`, `/debate`, `/decision` or `/preparar`. Under it, the rest that waits.
- **Claude suggests it** when Lucas comes back after a few days, or asks where things stand or what's next: a row in `CLAUDE.md`'s table, which sessions on his Mac and in the cloud both read.
- **`/entregar` leaves its last line on the merged PR too**, in English and starting with `Delivered:`, so a recorrida can tell a PR delivered from one that waits for `/entregar`.

## Considered options

- `/retomar` or `/estado` as its name: plainer, but the method's words come from building works, as pliego, replanteo and conforme a obra do.
- Always the last seven days, or the last ten PRs: either shows again what Lucas already saw, or misses what came before after a long break.
- A new page each time, or a message alone: a page per run scatters the links, and a message has no room for the why or the areas; the history is already in the PRs.
- Only the next step, or everything by area with no first: one hides what waits for Lucas, the other leaves him to choose among every ready issue.
- The session-start hook suggesting it after three days with no PR: hooks don't run in cloud sessions yet (#479), where most work runs, and the change would make the PR `risk:high`.

## Consequences

- `.claude/skills/recorrida/` holds the command; `.claude/method/method.md` names it and its word, and `.claude/method/artifacts.md` its page.
- `CLAUDE.md`'s table suggests it; `PLIEGO.md`'s How we work names the order of the work, and its Where it runs puts the recorridas in the cloud; the pliego's template asks every project for the order of the work.
- The page's sources and its link go where the pliego keeps artifacts' sources, so the next recorrida updates the same page.
- Standard practice: a status page that reads the tracker. Our own: the recorrida, a read-only command among the method's, and its order of what comes next.
