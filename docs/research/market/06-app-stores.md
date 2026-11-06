# 06 app-stores
Sources read: 56 (39 pages of Apple's review feed, holding about 1,840 reviews; 9 App Store pages; Apple's search API; 7 others). Covered from 2018 to 2026.

How to read the counts: all feeds were read on 2026-11-05 at `https://itunes.apple.com/<country>/rss/customerreviews/page=<n>/id=<id>/sortby=mostrecent/json`. Each page holds up to 50 reviews. The fetch tool returned one line per review, not the raw text, and I tagged the themes myself, so treat theme counts as within about 10%. A review can carry several tags. "Low" means 1 to 3 stars. Reviews before 2024-11 are `[OLD]`. No review text is from Google Play (see Blockers).

## Findings

### Ratings, volume and prices, US store, read 2026-11-05

`[CLAIMED]` from Apple's [search API](https://itunes.apple.com/search?term=anki&entity=software&country=us&limit=8) and each app's App Store page. "Written avg" is `[INFERRED]`: my mean of the stars in the reviews I read, which runs well below the store's figure in every app.

| App (feed) | Rating | Ratings | Written avg | Reviews read | Price tiers |
|---|---|---|---|---|---|
| [AnkiMobile](https://itunes.apple.com/us/rss/customerreviews/id=373493387/sortby=mostrecent/json) | 4.04 | 2,380 | 2.95 | 300 + 50 most helpful | $24.99 once, no in-app purchases |
| AnkiDroid (Play) | 4.8, secondhand | 158.7K, [tracker](https://apppricinglab.com/app/google_play/com.ichi2.anki) with a 2026-01 update date | not read | 0 | Free |
| [Quizlet](https://itunes.apple.com/us/rss/customerreviews/id=546473125/sortby=mostrecent/json) | 4.78 | 1,140,450 | 3.81 | 100 + 50 helpful | [Plus $9.99 and $44.99; Unlimited and Go $44.99; Teacher $35.99](https://apps.apple.com/us/app/quizlet-more-than-flashcards/id546473125); page doesn't say which period |
| [Brainscape](https://itunes.apple.com/us/rss/customerreviews/id=442415567/sortby=mostrecent/json) | 4.76 | 21,628 | 4.48 | 100 | [Pro $19.99/mo, $59.99/6 mo, $95.99/yr, $199.99 lifetime](https://apps.apple.com/us/app/brainscape-study-flashcards/id442415567) |
| [RemNote](https://itunes.apple.com/us/rss/customerreviews/id=1545429784/sortby=mostrecent/json) | 4.83 | 1,701 | 4.15 | 100 | [Pro $14.99/mo, $149.99/yr; Pro + AI $29.99/mo, $299.99/yr; MCAT tiers up to $399.99](https://apps.apple.com/us/app/remnote-notes-flashcards/id1545429784) |
| [Mochi](https://itunes.apple.com/us/rss/customerreviews/id=1507775056/sortby=mostrecent/json) | 4.62 | 175 | 4.00 | 49 | [Free; Pro $5/mo](https://mochi.cards/pricing/) on its site |
| [Memrise](https://itunes.apple.com/us/rss/customerreviews/id=635966718/sortby=mostrecent/json) | 4.78 | 217,621 | 3.58 | 100 | [$24.99/mo, $61.99/yr, lifetime $329.99, offer $131.99](https://apps.apple.com/us/app/memrise-language-learning-app/id635966718) |
| [Knowt](https://itunes.apple.com/us/rss/customerreviews/id=6463744184/sortby=mostrecent/json) | 4.73 | 11,257 | 3.40 | 100 | [Ultra $9.99/wk, $14.99 to $24.99/mo, $59.99 to $149.99/yr](https://apps.apple.com/us/app/knowt-ai-flashcards-notes/id6463744184) |
| [Readwise Highlights](https://itunes.apple.com/us/rss/customerreviews/id=1476885528/sortby=mostrecent/json) | 4.81 | 1,514 | 4.15 | 100 | [Lite $4.99 to $6.99/mo, $52.99 to $66.99/yr; Full $8.99 to $12.99/mo, $94.99 to $119.99/yr](https://apps.apple.com/us/app/readwise-highlights/id1476885528) |
| [Vocabulary](https://itunes.apple.com/us/rss/customerreviews/id=1084540807/sortby=mostrecent/json) | 4.77 | 221,986 | 2.98 | 200 + 50 helpful | [$9.99 to $14.99 short plans, $35.99 to $69.99 long, lifetime $149.99](https://apps.apple.com/us/app/vocabulary-learn-words-daily/id1084540807) |
| [Word of the Day](https://itunes.apple.com/us/rss/customerreviews/id=987136347/sortby=mostrecent/json) | 4.67 | 39,025 | n/a | 50 | Free with premium |
| [Noji](https://itunes.apple.com/us/rss/customerreviews/id=1573585542/sortby=mostrecent/json) | 4.57 | 14,028 | 3.46 | 50 | Free with premium |
| [AlgoApp](https://itunes.apple.com/us/rss/customerreviews/id=689185915/sortby=mostrecent/json) | 4.67 | 20,066 | n/a | 50 | Free with premium |
| [SmartCards+](https://itunes.apple.com/us/rss/customerreviews/id=1210521987/sortby=mostrecent/json) | 4.57 | 2,307 | n/a | 50 | Free with premium |
| [Cogni](https://itunes.apple.com/us/rss/customerreviews/id=6737768905/sortby=mostrecent/json) | 4.71 | 1,689 | n/a | 37 | Free with premium |
| [Widget Vocabulary](https://itunes.apple.com/us/rss/customerreviews/id=6775767149/sortby=mostrecent/json) | 4.73 | 488 | n/a | 6 | Pay to use, per its reviews |

All are alive: every iOS app had a release in 2026-10 or 2026-11. AnkiMobile's is notable: 25.09 (2025-09-08) to 26.10 (about 2026-11-03), a 14-month gap `[CLAIMED]`.

### Low-rated complaints, ranked and counted `[SAID]`

**AnkiMobile US**, 172 low of 300 (120 one-star, 113 five-star), 2023-11 to 2026-11:
1. Hard to use, confusing, dated UI, no guide: about 64
2. Price not worth it, unexpected charge, should be free: about 56
3. Sync, import or deck transfer fails: about 36
4. Weaker than desktop, needs a computer: about 24
5. Daily limits or scheduler hide cards: about 16 (6 of them on the forced V3 scheduler, 2023-24 `[OLD]`)
6. Images or audio missing: about 10
7. Slow updates: about 7. Lost cards: about 6. Login: about 6

Other countries, same app ([es](https://itunes.apple.com/es/rss/customerreviews/id=373493387/sortby=mostrecent/json), [de](https://itunes.apple.com/de/rss/customerreviews/id=373493387/sortby=mostrecent/json), [jp](https://itunes.apple.com/jp/rss/customerreviews/id=373493387/sortby=mostrecent/json), 50 each; [ar](https://itunes.apple.com/ar/rss/customerreviews/id=373493387/sortby=mostrecent/json), 7, mostly old):
- German: 34 low of 50. Missing against desktop about 15, price about 14, UI about 10. The most critical store read.
- Spanish: 30 low of 50, back to 2018. Missing against PC about 11, price about 7, no Spanish UI 5 `[OLD]`.
- Japanese: 28 low of 50. Pasted Goodnotes images broken 6, hard to use about 5, price or charges about 5.
- Argentina: only 7 reviews since 2010, no pattern.

The 26.10 redesign is too new to judge: 1 one-star and 1 five-star US, 1 two-star German on smaller text.

**Others:**

| App | Low / read | Ranked complaints |
|---|---|---|
| Quizlet | 36/100, 2026-10-18 to 11-03 | Paywall on Learn, tests, images 15; update broke or lost work 9 |
| Quizlet [es](https://itunes.apple.com/es/rss/customerreviews/id=546473125/sortby=mostrecent/json) | 28/50, 2024 to 2026 | Paywall or price about 11; "are you human" checks 2 |
| Brainscape | 13/100 | Paywall 5; forced confidence rating 3; bugs 2; content errors 2 |
| RemNote | 23/100 | Mobile lag and bugs about 11; paywall or "not free" 5, all 2026; spam email 3 `[OLD]`; navigation 3 |
| Mochi | 14/49, back to 2020 | Bugs 5; missing features 5; no guide 1; VoiceOver 1 |
| Memrise | 41/100 | Won't load, progress lost about 14; billing and paywall about 10; forced AI about 6 |
| Knowt | 43/100 | Paywall about 13; surprise charges of about $60 to $150 about 12; AI features fail about 9; bugs about 8 |
| Readwise | 24/100, back to 2022 | Import or sync about 8; price about 7; forced onboarding 3 |
| Vocabulary | 116/200, 2026-08-10 to 11-02 | Paywall, revealed after setup 31; wrong, obscure or AI-made words 26; trial or renewal charge 21; too many notifications 10; widget faults 8; audio broken 8; explicit words about 5 |
| Word of the Day | 30/50 | Forced ads before the word about 15; streak falsely lost 7; paywall 5; widget faults 4; AI art 3 |
| Noji | 22/50 | Lost account or cards 6; free cap of 50 a day and price 6; ads 2 |
| AlgoApp | 21/50 | Bugs 7; billing 7; free cap cut from 100 to 80, 2 |
| SmartCards+ | 31/50, back to 2023 | Free cap of 15 to 20 a day about 8 `[OLD]`; paywall 5; crashes 5; Watch broken 4 `[OLD]` |
| Cogni | 19/37 | "Not the real Anki" 5; surprise payment 5; bugs and sync 5 |

### What high-rated reviews praise, and their words `[SAID]`

- **AnkiMobile** (128 of 300 at 4 or 5 stars, 35 of 50 by most helpful): worth the price, works for exams and languages, official and original against copycats (about 12), powerful, customizable, plain, no ads or account. Medicine and Japanese recur.
- **Quizlet, Knowt:** grades and test results, by school students. Knowt: AP exams about 20 of 57 at 4 or 5 stars, and "free". Quizlet: helps study, cramming.
- **Brainscape:** easy, confidence rating, free, quick sessions.
- **RemNote:** notes and cards in one place, retention, responsive developers.
- **Mochi:** simple, clean, no ads, beautiful, better than Anki about 5, markdown.
- **Memrise:** real people and native speakers, better than Duolingo (about 6), no lives or streak pressure (3).
- **Readwise:** daily review as a habit, resurfacing old highlights, morning routine (about 29 of 76).
- **Vocabulary, Word of the Day:** new words, fun, design, daily habit.

### Price, subscriptions and paywalls `[SAID]`

- **AnkiMobile's one-time price splits people.** About 130 of 250 recent US reviews (pages 2 to 6) mention price: roughly 82 negative, 49 positive. By [most helpful](https://itunes.apple.com/us/rss/customerreviews/id=373493387/sortby=mosthelpful/json) it flips: of 29 mentions, 12 positive, 7 mixed, 10 negative.
- The negatives are mostly about value, not paying: they paid and couldn't make it work, so $25 felt wasted. At least 12 object that Android or desktop is free. About 8 say they were charged without meaning to buy, some reading the app as free `[INFERRED: buyers expected a simple flashcard app]`.
- The positives name the model: one payment, no subscription, supporting the developer. One 4-star (2026-02) fears a future subscription under a new owner.
- Abroad: German 25 critical against 6 favorable, at about €30. Japanese 16 mentions at about ¥4,000, split, with some calling it cheap for what it does.
- **Subscriptions draw the angrier text.** Knowt and Vocabulary lead with surprise charges: 12 and 21. In Vocabulary about 8 say a promised reminder before the charge never came.
- **Paywall shown only after long setup** is a named grievance in Vocabulary (about 8, plus the [Spanish](https://itunes.apple.com/es/rss/customerreviews/id=1084540807/sortby=mostrecent/json) and [German](https://itunes.apple.com/de/rss/customerreviews/id=1084540807/sortby=mostrecent/json) feeds: 22 of 50 German reviews mention price).
- **Free tier cut after people relied on it** recurs in Quizlet (a 2022-23 cluster in most helpful `[OLD]`, 34 of 50 mention price), SmartCards+, AlgoApp, Word of the Day, Memrise.
- **Daily review caps** draw complaints wherever they appear: SmartCards+ about 8, Noji about 4, AlgoApp 2, Cogni 1.
- **People asking outright for one-time purchase:** Vocabulary 2, Word of the Day 1, Readwise 2 `[OLD]`. RemNote's [$395 lifetime](https://itunes.apple.com/us/rss/customerreviews/id=1545429784/sortby=mostrecent/json) drew 1 complaint.
- **AI as a thing people pay for and resent:** Knowt about 3, Memrise about 6, RemNote 2, Noji 2, Vocabulary about 5 on AI art or sentences. A few praise it: Brainscape, RemNote and Readwise, about 8 in all.

### Notifications, widgets and reminders `[SAID]`

- **Reviewers of Anki hardly raise them.** AnkiMobile: 3 of 300 US (no widget or reminders, 1-star 2025; asks for a widget, 4-star 2024; asks for a Watch app, 5-star 2025). Abroad, 1 each of 50: push and widget requested (Japan), icon badges unreliable (Germany), Watch requested (Spain `[OLD]`). Most helpful: 0 of 50. About 1%, in all.
- **In Vocabulary they're central:** about 59 of 343 reviews (17%) across US, Spanish and German feeds. People came for the Lock Screen and widget. About 14 of 200 recent US reviews praise them, including 6 who rate the app low otherwise. By [most helpful](https://itunes.apple.com/us/rss/customerreviews/id=1084540807/sortby=mosthelpful/json), 16 of 50 mention them, about 9 favorably.
- **Their complaints are about control.** About 10 of 200: too many (reports of 6, 20 and about 30 a day), can't set the frequency, can't mute, a setting that disappeared. 2 report ads via the Lock Screen or Live Activities. 2 ask for one word a day, and a German 4-star for the same. Others: widget paywalled or revoked after cancelling (4), doesn't refresh or stuck (4), obscure or sexual words shown on the home screen (2).
- **Word of the Day:** 5 widget mentions, 4 negative: black after an update, different word from the app, makes you open the app. 1 downloaded it mainly for the widget.
- **Widget Vocabulary:** only 6 reviews, 1 favorable on seeing words all day, 1 couldn't get it onto the screen.
- **Readwise:** favorable. About 7 of 100, wanting more notifications, a bigger widget, an alert before losing a streak, and praising daily reminders and emails.
- **Noji:** 4 praise reminders, in near-identical wording `[INFERRED: possibly prompted]`. **Knowt:** 2 praise them. **Mochi:** 1 asks for a daily reminder `[OLD]`. **AlgoApp:** 1 asks for a streak widget.
- **Annoyance elsewhere:** Brainscape, 1 two-star on guilt-style messages. Memrise, 1 praises reminders but hates daily-goal screens; 1 praises the absence of nagging. Quizlet, 1 on streak pop-ups `[OLD]`. RemNote, 3 on email `[OLD]`.
- **Apple Watch:** SmartCards+ has 7 mentions, 3 praising it, 4 that it never loads decks (2023 `[OLD]`, praise as late as 2026-01). Vocabulary, 3 favorable. AnkiMobile, 2 requests.

## Words people use

Sentences above are paraphrased. These are recurring terms, with the feed they come from.

- **Anki, praise:** worth it, worth every penny, one-time, no subscription, no ads, official, original, gold standard, learning curve. Most helpful, one reviewer: "not flashy and has a learning curve" ([feed](https://itunes.apple.com/us/rss/customerreviews/id=373493387/sortby=mosthelpful/json)).
- **Anki, complaint:** not user friendly, not intuitive, confusing, archaic, clunky, outdated, waste of money, wasted $25, refund, needs a computer.
- **Subscriptions:** scam, paywall, free trial, charged, subscription fatigue, greedy, bait and switch, everything costs money.
- **Vocabulary:** Lock Screen, widget, daily words, spam, can't control, AI slop, obscure.
- **Simple apps:** simple, clean, minimal, sleek, no fuss, Anki alternative.
- **Low effort:** low effort, all day, without trying, instead of scrolling, a few minutes.

## Evidence against

- **Written reviews overstate the anger.** Every store rating sits above the written mean, by 0.3 to 1.8 stars. Vocabulary holds 4.77 from 221,986 ratings while its written mean is 2.98 `[INFERRED: stars come largely from in-app prompts, and the annoyed write]`. Paywalls and heavy notifications have not visibly hurt its volume.
- **"Hard to use" comes largely from newcomers.** Long-time 5-star reviewers accept the plain UI, and by most helpful AnkiMobile reads 35 of 50 favorable. Recency also favors buyers in their first days `[INFERRED]`.
- **Few notification requests from Anki users doesn't show they don't want them.** People rarely review for what no app has offered, and desktop parity crowds it out `[INFERRED]`. It also doesn't show they do.
- **Notifications are not a clean positive.** Vocabulary's complaints nearly match its praise, and these are word-of-the-day users, not spaced-repetition users. No reviewer I read describes flashcards reviewed through notifications working over time.
- **One-time isn't loved everywhere:** Germany's 25 to 6 runs hard against it, and many US negatives are from people who'd rather have a free app than a subscription.
- **Paywalls don't sink everything:** Brainscape has 78 five-star reviews of 100, many praising its free tier, with Pro at $95.99 a year. Readwise reviewers often call it pricey and keep it.
- **Sample quality:** some reviews mismatch rating and text (at least 5). 7 five-star Knowt reviews share the date 2026-07-07, about AP exams `[INFERRED: possibly a prompt]`. Feeds show the latest 500 at most, per app and country.
- **Thin secondary sources:** [JustUseApp](https://justuseapp.com/en/app/373493387/ankimobile-flashcards/reviews) (sells virtual privacy cards for trials) agrees on AnkiMobile: sync, dated look, learning curve, from 21 samples. Its [Vocabulary page](https://justuseapp.com/en/app/1084540807/vocabulary-learn-words-daily/reviews), 31 samples, reads friendlier than the recent feed, with undated older reviews.

## Blockers

- **Google Play, all apps.** `play.google.com` pages came back empty through WebFetch, with and without parameters. For AnkiDroid I also tried chrome-stats (403), AppBrain (403), AppFollow (timeout), Kimola's report (410), APKPure (rating only, 17 reviews, no text) and Grand Screen (3 truncated reviews, 2025-10; 4.8 from 149,309, a catalog page). So AnkiDroid has no counted reviews here, the largest gap in this report. A [2021 forum thread](https://forums.ankiweb.net/t/disappointed-in-ankidroid/9583) `[OLD]` is the only direct complaint, from one person.
- **How Lucas could help:** open AnkiDroid's Play page in the app's browser pane in a session of its own and sort by lowest rating, or export reviews with an AppFollow or Sensor Tower account if he has one.
- **Apple's feed:** gives no vote counts, and the fetch tool returns summaries, so wording in the lists above comes through it. Paid tiers listed on App Store pages don't say the period or the country for each item, so periods above are read from descriptions or inferred from the price. Nothing was logged into.
