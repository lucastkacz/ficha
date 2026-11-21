---
name: debate
description: Debate una idea con vos en un artifact, ronda por ronda: preguntas con opciones, maquetas y una recomendación, hasta que se pueda decidir.
disable-model-invocation: true
---

# Debate

The user typed `/debate` with an Idea issue, a topic, or after answering a round. Take the idea to where every question whose answer changes what gets built has one. Read [`../../method/method.md`](../../method/method.md) and [`../../method/artifacts.md`](../../method/artifacts.md) first, then the pliego. With no pliego, tell the user `/preparar` comes first, and stop.

When the debate's artifact already has a round and the user says they answered, start at **3**.

## 1. Gather

- **The idea**: its issue with every comment, or the user's words.
- **What bears on it**: the pliego's items, its open ones first; the plano's parts it touches, and their rules; the glossary's words; the decision records it touches; the code it touches, read, not assumed.
- **The facts its options rest on**: from official documentation, each with its link, and a number from a measure or a simulation, never a guess. A fact nobody can find yet is a question for the user, or an open item.

Done when you can name each question whose answer changes what gets built, and the facts behind each option.

## 2. A round

Up to five questions, those the others depend on first, written as [`../../method/artifacts.md`](../../method/artifacts.md) says: each in the user's terms, with 2 to 4 options shown, not described, the one you recommend and why, and a note. A visual choice gets a mock of each option; a choice about behavior, a short movie or a simulation's numbers.

The debate is one artifact: a tab per round, the earlier ones with their answers, and the idea's issue linked from its home.

Tell the user in one line, with the link, and end the turn.

Done when the round's tab passes the checks of [`../../method/artifacts.md`](../../method/artifacts.md), and the user has its link.

## 3. Read the answers

Read the round's answers and notes from the artifact's database. Each is the user's own word: a note that questions the question itself makes it next round's first.

Done when every question of the round has its answer, or a note that says why not. Then:

- **Something still changes what gets built**: back to **2**, with the new round.
- **Nothing does**: on to **4**.

## 4. Close

The artifact's last tab: what each round settled, in a line each, and what stays open, with why it can wait. Tell the user in one line, and suggest `/decision`.

The open items the debate settled, and its new words, are written with the decision, by `/decision`.

Done when the last tab is published, and the user has the line.
