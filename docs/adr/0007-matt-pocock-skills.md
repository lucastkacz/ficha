# Built with Matt Pocock's skills, plus a skill map

Ficha is built by agents following the standard `mattpocock-skills` plugin instead of a hand-made process, partly as an experiment: after about a month, Lucas compares it with a project built the hand-made way. Lucas doesn't memorize commands, and Claude can't see the skills only he can run, so `CLAUDE.md` maps each situation to the command Claude suggests. Our own additions cover only what the plugin leaves out on purpose: CI, branch protection, the merge policy, hooks and the Swift standards.

## Consequences

- When the plugin's version changes, the skill map in `CLAUDE.md` is updated from the plugin's own router, `ask-matt`.
- The `/refine` skill, which turns captures into cards, is ours too: no plugin covers Ficha's content.
