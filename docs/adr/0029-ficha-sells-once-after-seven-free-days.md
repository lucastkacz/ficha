# Ficha sells once, after seven free days counted from the first card

Ficha sells on the App Store for the Mac and the iPhone together (#160). Lucas wants to recover the Apple membership and, if possible, one month of Claude, about $300, not to live on it, and the market research (#452) found it worth that as a small bet and no more. On 2026-11-06, grilling #252, #459 and #458, he chose one payment of $4.99, which covers both apps and takes about 71 sales at Apple's 15% cut. It comes after seven days with all of Ficha for free, counted from the user's first card and not from the download, since someone who downloads it and waits five days shouldn't lose them. Once they're over, a hard paywall leaves only Buy, Restore Purchases and Export until the user pays. The research doesn't show this to be the most profitable: its only trial figures are for subscriptions, so the trial's shape and length are Lucas's call, not evidence.

## Considered options

- A subscription of about $0.99 a month that unlocks an AI agent making cards (#252): it needs a server of Ficha's own, an identity per user and a cost per generation, and it reverses ADR 0001 and ADR 0012. Billing is the top or tied complaint in 5 of 6 AI card apps with Trustpilot reviews (report 17). `.out-of-scope/ai-agent-that-makes-cards.md` says when Lucas would think about it again.
- $9.99, as the research proposed: it had no evidence for the exact number, and nothing it found separates that from $4.99. Under $10 drew no complaints in 3 of 3 r/macapps threads, few threads, and no complaint isn't praise. A price is also easier to raise than to lower.
- Free with a limit on cards, as NotchWise does with 1 deck and 50 cards: someone who wants to remember a few things might never reach it, and one Anki deck passes it on the first day. That part is inference.
- Paying up front, with no trial: no purchase code in the app, but people ask to try first (reports 16, 22, 24, 27), and what they need to try here is whether cards showing up on their own bother them.
- Five days or two weeks: Lucas reads interest as peaking early, which one study's fall of about 14% in answers per day loosely supports (Schneegass, report 25) without measuring sales. Seven days holds a whole working week wherever it starts, and lets the first days' cards come back after several days. It's one number, which can change before launch if the beta says otherwise.
- A softer paywall, with the Cards window open to read: Lucas finds it too lenient, and Export already hands over the cards.

## Consequences

- The paywall deletes nothing. Cards and progress stay as they were, sync keeps running unseen, and paying brings everything back.
- Export there has to carry the progress, which today's text file doesn't, and Lucas doesn't want to leave anyone without it. That's #457's `.apkg`, so #457 comes before #459.
- The friends' beta (#359) has the paywall, as in production, since Lucas wants to learn whether they reach the seventh day. So #459 comes before it. TestFlight charges nothing, so pressing Buy only shows that they got there, and from memory those purchases don't carry to the App Store.
- "The first card" is the first review, as the review log has it: a snoozed appearance and Anki's imported reviews don't count, and the iPhone can't know that a notification arrived.
- From a summarizing read of guideline 3.1.1, which the spec checks against its text: a non-subscription app's free trial is a non-consumable in-app purchase at $0 named "XX-day Trial", and before it starts the app says how long it lasts, what stops at its end and what full use costs. If that's required, the clock starts with that purchase's tap, just before the first card. The spec also settles where the notice shows, since the iPhone has no Welcome page.
- One purchase covers both apps through Apple's universal purchase: one App Store Connect record and one bundle ID, as `project.yml` already has for the Mac's Release. Apple's page describes adding the Mac to an iPhone app's record, and Ficha's starts from the Mac, so the spec checks that direction.
- StoreKit talks to Apple, as iCloud does, so ADR 0017's rule stands: no connections of Ficha's own, no accounts of its own, no analytics. The privacy policy adds the purchase.
- Family Sharing stays off at launch: Apple lets it be turned on later, and never off.
- Ficha comes with no decks: a newcomer who doesn't come from Anki still opens it empty. Lucas sends each friend a deck to their taste as a file, and their import is part of the test, so the beta won't show how a stranger does with an empty app. What strangers get stays open in #458.
- Standard practice: Apple's in-app purchase, its restore and its universal purchase. Our own: counting the trial from the first card, and the paywall's three buttons.
