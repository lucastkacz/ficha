# Built with Matt Pocock's skills, plus a skill map

Ficha is built by agents following the standard `mattpocock-skills` plugin instead of a hand-made process, partly as an experiment: after about a month, Lucas compares it with a project built the hand-made way. Lucas doesn't memorize commands, and Claude can't see the skills only he can run, so `CLAUDE.md` maps each situation to the command Claude suggests. Our own additions cover what the plugin leaves out on purpose: CI, branch protection, the merge policy, hooks and the Swift standards.

## Consequences

- When the plugin's version changes, the skill map in `CLAUDE.md` is updated from the plugin's own router, `ask-matt`.
- `docs/agents/` holds the setup skill's templates as they come, except one rule of ours in the issue tracker's: an issue closes through the pull request that resolves it.
- The `/refine` skill, which refines the inbox, is ours too: no plugin covers Ficha's content.
