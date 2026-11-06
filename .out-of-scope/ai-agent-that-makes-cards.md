# An AI agent that makes cards for the user

The user would give it a source or just a topic, such as "the signals of truco", and an agent would ask how many cards they want and make them, paid through a subscription. Ficha has no such agent. "Copy Instructions for an AI" lets anyone make cards with their own AI and import the file, for free, with more steps.

## Why this is out of scope

Ficha holds no AI and has no server or accounts of its own (ADR 0001, ADR 0012, ADR 0017), and it sells once, with no subscription (ADR 0029). An agent would need a server, an identity per user and a cost per generation, and a subscription would change what sets Ficha apart. Billing is the top or tied complaint in 5 of 6 AI card apps with Trustpilot reviews, a site that draws the angry (report 17 in `docs/research/market/`).

Lucas decided this on 2026-11-06, adding that it isn't needed now. He'd think about it again once the app is published and takes off, say past 100 downloads: a subscription for AI features on demand, such as cards to learn truco's rules and signals, with its own grilling and ADR.

## Prior requests

- #252: "Research a business model, with an AI agent that makes cards for the user"
