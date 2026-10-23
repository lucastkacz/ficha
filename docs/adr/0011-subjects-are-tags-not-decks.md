# Subjects are tags, not decks

Lucas sometimes wants subjects apart: the topics an exam covers first (#36), or a course he's done with out of his reviews (#154). Anki splits cards into decks, each card in one, each deck with its own settings and studied on its own. Ficha keeps a single stream of cards and gives tags two switches instead: a priority tag brings its cards first, and setting a tag aside takes its cards out of reviews for now, without burying them. Appearances are short and spread through the day, so mixing subjects is the point, and Anki's own manual keeps decks for broad categories, since related cards reviewed together are easy to guess from context. Decks would also double the settings and screens on the Mac and the iPhone. Burying every card of a finished subject, with nothing new, was the other option: it mixes "not for now" with "not anymore", and misses the cards that get the tag later.

## Consequences

- Set aside comes third in the order of the glossary's **Standing**: a burial or a flag wins over it, and it wins over the card's other tags, a priority tag among them or not. So fixing or unburying a card with a tag set aside leaves it set aside.
- A tag is a priority tag, set aside, or neither: setting aside a priority tag drops its priority.
- Which tags are priority tags or set aside is stored with the cards, not as a setting of each device, so the backups keep it, and iCloud sync would carry it if #161 builds it. This replaces #36's brief, which kept priority tags in the Mac's preferences.
- Nothing reviews one tag alone: a priority tag brings its cards first, and the others still come when there's room.
- A set-aside card's wait keeps running, as a buried card's does, so a tag set aside for a while comes back with a backlog, which drains as ADR 0003 says.
