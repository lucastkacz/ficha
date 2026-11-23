# A node is written in the cloud and tested on GitHub's Macs, in two rounds per node

Ficha's pliego left open how a node with Swift splits between a Claude session in the cloud and a Mac. The cloud session is Linux, with no Swift or Xcode, so it builds and tests none of Ficha: FichaKit imports Apple's frameworks, 1,064 of its 1,161 tests run in FichaData or FichaCLI, and FichaCore links fsrs-rs as an XCFramework. Of the last 100 pull requests, 71 needed a Mac. CI's `macos-26` runners are GitHub's standard runners, free on a public repo, with 3 cores: on 2026-11-21 a full `make check` took 24 minutes, of which `swift test` took 4.9, and the tests themselves 61 seconds; the rest is compiling. Lucas wants all that can be done away from his Mac done there. In two rounds of debate on 2026-11-23, in the artifact "Nube y Mac", he chose, and approved as a decision the same day, what follows. It changes ADR 0030 in part: `/construir` took each issue test first, one at a time, with one commit per issue, and a node's branch was always named after its path.

- **GitHub's Macs test what the cloud writes.** A cloud session building a node pushes its branch to a draft PR, and each push runs a short round on GitHub, `make test` alone, about 8 minutes. Marking the PR ready runs the full `check` the ruleset requires, and the PR merges itself once it's green, so `make check` runs once, in CI. A session on Lucas's Mac tests on the Mac, as before.
- **Test first goes per node.** Every issue's test comes first, in one run, each seen to fail for its issue's reason; then the code of all, run until every test passes. A node of three issues takes two rounds, 16 minutes, not six. Each issue's test and its code go in commits that name it, since the first round runs on the tests alone, pushed before the code. Each test written for an issue carries Swift Testing's `.bug(id:)` trait, so a test that fails in a round leads to its issue, and what a red test needs that doesn't exist yet gets a stub that compiles, so one missing type doesn't hide the other tests.
- **Each acceptance criterion names its proof**: `Accept (test): …`, `Accept (picture): …` or `Accept (hand): …`. The pliego's Where it runs names the machine for each.
- **Lucas's Mac runs only what GitHub can't**, and only through Remote Control, after his OK on its card: the PR's pictures, until a probe shows GitHub's Macs can draw Ficha's windows, and the hand checks an agent can run there. `make upload`, `make install-iphone` and the checks by hand stay his.
- **In the cloud, a node's branch is the one the session is given**, `claude/…`, since a cloud session pushes only to its own branch unless Lucas allows another, and its PR's title starts with the node's path.
- **The guards hold in the cloud as on the Mac.** On 2026-11-23 none of the repo's hooks ran in a cloud session of the Claude project, whose directory was outside the repo's folder: an address `no-email-addresses.sh` blocks passed a Bash call there. And no hook matches the GitHub tools a cloud session merges, turns on auto-merge and writes files with. GitHub can't hold them instead: every PR, from the Mac or the cloud, is opened as Lucas, who can't approve his own. Until the hooks run there, a cloud session keeps the guards of ADR 0006 and the hooks itself, as `CLAUDE.md` says: it merges nothing, turns on auto-merge only for a PR without `risk:high`, writes to `main` only through a PR, and sends no email address.

## Considered options

- Lucas's Mac, through Remote Control, for the tests: 10 cores to 3, but it needs the Mac on, and loads it, which is what Lucas wants gone.
- A round per issue: six rounds of 8 minutes for a node of three, when compiling, not the tests, takes the time.
- Running only the failing test: the build is the 4 minutes, so it saves almost nothing.
- The short round run by hand from the cloud session, through `workflow_dispatch`: its runs don't show on the PR, and don't gate it.
- A branch named after the node in the cloud: each cloud session would need Lucas's leave to push to it.
- The pictures always from Lucas's Mac: it keeps his Mac in every PR that changes what he sees.
- A required review on `risk:high` PRs, from a CODEOWNERS file: every PR is opened as Lucas, who can't approve his own.

## Consequences

- `PLIEGO.md` gains Where it runs, after Hands-free, as the method's pliego template lays it out, and its two open items on the cloud close.
- `CLAUDE.md`'s Shipping says how a node is built from the cloud; `CODING_STANDARDS.md`'s Tests ask for `.bug(id:)`; `/construir`'s replanteo and build, and `method.md`'s Issues and branches, take the rounds, their commits and the proofs.
- Three issues: the short round on a draft PR and the full `check` once it's ready, in `check.yml`, `risk:high` (#478); the hooks in cloud sessions and on GitHub's tools, `risk:high` (#479); and the probe of the pictures on GitHub's Macs (#480).
- The method gains Cloud first (nube primero), generic, in `.claude/method/method.md` and `/preparar`, through PR #477: the work runs off the user's computer wherever another machine can do it, and a machine that costs money runs only where the user chose it. Ficha's split here is its first case.
- Provisional, until a debate changes them: the short round on a draft PR, the stubs, the proofs given to open issues at the replanteo, and the cloud session's branch.
- Open: whether GitHub's Macs can draw Ficha's windows, which the probe decides; how the hooks load in a cloud session, which their issue finds out; whether Remote Control's first card adds the `ficha` folder, or Lucas adds it by hand; and the load on Lucas's Mac, which this should end, or else an `/idea`.
- Standard practice: CI on pull requests and drafts, Swift Testing's `.bug` trait, test-first development. Our own: test-first rounds per node, a proof per acceptance criterion, and the PR's title naming the node.
