---
name: entregar
description: Deja lo construido conforme a obra, con la decisión, sus issues, el pliego y el plano al día; la retro, solo si algo se torció.
disable-model-invocation: true
---

# Entregar

The user typed `/entregar` once a node's PR merged, or with the PR to deliver. Leave everything as built, and look back only if something went sideways. Read [`../../method/method.md`](../../method/method.md) first, then the pliego. With no pliego, tell the user `/preparar` comes first, and stop.

## 1. As built

The PR is the one the user names, or this session's last merged one. Read it with its commits, its issues and every comment.

- **Each issue it closed**: where what was built differs from what the issue asked, such as a criterion dropped or a choice made while building, a comment on the issue says what and why. What's left undone becomes an issue in its area, written as [`../../method/method.md`](../../method/method.md) says.
- **The decision**: its artifact marks each piece built, linked to the PR.
- **The pliego and the plano**: they match the code as merged. What still differs goes in a PR of its own, through the three checks.

Done when every issue the PR closed, and its decision, tell what was built.

## 2. Clean up

What the pliego says follows a merge, such as removing the merged branch's folders.

## 3. A retro, only if something went sideways

Sideways is a check that failed more than once, a replanteo or a change order that stopped the work, the user correcting the work, or a node that took far longer than its size. Then: what happened, why, and the change to the method, the pliego or the project's tools that would have avoided it, as a Task issue in the area of the way of working. With nothing sideways, no retro.

## 4. Tell the user

One line: what was delivered, by the decision's title, linked; what's left, by the issues' titles, linked; and the next step.
