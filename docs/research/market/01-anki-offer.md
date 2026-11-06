# 01 What Anki offers
Sources read: about 60. Covered from 2013 to 2026 (the 2013 FAQ and the 2020-2023 threads are marked `[OLD]`).

## Findings

### Platforms and prices (read 2026-11-05)

| Platform | Offer | Price |
|---|---|---|
| Desktop (Windows, macOS 13+, Linux), 26.09.4 | Full app, add-ons | Free |
| AnkiWeb | Sync, study in a browser, shared decks and add-ons | Free |
| AnkiMobile (iPhone, iPad), 26.10 | Official app, offline, no add-ons | $24.99 once |
| AnkiDroid, 2.25.3 stable | Volunteer app, donations through OpenCollective | Free |

- `[CLAIMED]` Desktop, AnkiWeb and AnkiDroid terms: [Anki's site](https://apps.ankiweb.net/); AnkiMobile: [App Store US](https://apps.apple.com/us/app/ankimobile-flashcards/id373493387), seller Anki Software, LLC, no in-app purchases shown. 1 source each.
- `[CLAIMED]` AnkiWeb's collection limit is 100MB compressed and 250MB uncompressed, with 100MB per media file ([FAQ](https://faqs.ankiweb.net/are-there-limits-on-file-sizes-on-ankiweb.html), undated, seen as a search result). Data may be deleted after about six months unused ([manual](https://docs.ankiweb.net/manual/syncing.md)).
- **Price history.** `[CLAIMED]` About $25 since at least 2013, per a [FAQ](https://docs.ankiweb.net/faqs/why-does-ankimobile-cost-more-than-a-typical-mobile-app.md) whose comparisons date from 2013 `[OLD]`. It says trying lower prices lost money. I found no dated change. `[SAID]` In February 2026 Elmes promised it stays a one-time $25 ([forum](https://forums.ankiweb.net/t/ankis-growing-up/68610/110)).
- **Abroad.** ¥4,000 in [Japan](https://apps.apple.com/jp/app/id373493387) `[CLAIMED]`. EUR 29.99, GBP 24.99, TRY 1,299.99, a 39-store median of $30.20, on 2026-09-08, from [Mindomax](https://www.mindomax.com/is-anki-free), which sells a competing app.
- **Complaints.** `[SAID]` At least 4 forum threads object to the price: [UK 2024](https://forums.ankiweb.net/t/why-33-for-uk-users-and-free-to-android-users/48645), [Brazil](https://forums.ankiweb.net/t/suggestion-please-consider-regional-pricing-for-brazilian-students/62383), [Turkey 2025](https://forums.ankiweb.net/t/why-is-this-app-this-expensive-in-app-store/67593), and one from [September 2026](https://forums.ankiweb.net/c/ankimobile/suggestions/20) (title only). The first two seen as search results.

### Reminders, widgets, lock screen, reviewing outside a session (the core)

`[INFERRED]` **No official Anki app, on any platform, shows or answers a card from a widget, notification, lock screen or watch.** Every official surface sends you into the app. This rests on the manuals, release notes and forum threads below, and on finding no release that says otherwise.

**Desktop**
- `[CLAIMED]` No reminder setting at all. [Preferences](https://docs.ankiweb.net/manual/preferences.md) has only a Timebox, an in-session progress message.
- `[SAID]` Add-ons only run while Anki is open ([forum 2024](https://forums.ankiweb.net/t/notification-options/50544), 1 add-on developer). The closest I found: [Anki pop up](https://forums.ankiweb.net/t/add-on-for-reviewing-card-at-intervals/41130) (2024), which hides Anki for a timed break after a set number of cards. Its requester wanted a corner pop-up with a card and got a hidden Anki that returns. Also a "Due Cards Badge" add-on, known only from a [search result](https://www.patreon.com/posts/95926583). I found no maintained menu-bar or macOS-notification add-on.

**AnkiWeb**
- `[INFERRED]` No reminders found in its docs. It is a browser study page and sync.

**AnkiMobile**
- `[CLAIMED]` Two things: one [alert at a chosen time](https://docs.ankiweb.net/ankimobile/preferences.md) with the review count, and a due-count badge. [26.10](https://forums.ankiweb.net/t/ankimobile-26-10-is-out/74202) (2026-11-03) adds New, Learning and Review toggles for what the badge counts. Its notes mention no widget. `[CLAIMED]` A [`anki://` URL scheme](https://apps.apple.com/us/app/ankimobile-flashcards/id373493387) to open a deck arrived in 25.07.
- `[SAID]` These fail unreliably. At least 7 threads, 2020 to 2026, report it: [2023](https://forums.ankiweb.net/t/notifications-not-working-on-ios/28976) `[OLD]`, [2025](https://forums.ankiweb.net/t/notification-badges-on-iphone-not-showing-up/56610), [2025-26](https://forums.ankiweb.net/t/functional-notifications-are-essential-for-ankimobile/66148), and 4 related threads named on those pages.
- `[SAID]` Elmes's explanation: the app is offline-first, so it must work out due counts as it closes, before iOS stops it; looking further ahead costs battery. In 2023 he said iOS closing the app is why they fail `[OLD]`; [a 2023 thread](https://forums.ankiweb.net/t/add-notification-badge-background-refresh/37673) `[OLD]` ruled out checks every 30 minutes. His 2025 reply tracks a first-learning-card alert in a public issue, so that one is on the list.
- `[SAID]` **Widgets:** 4 threads, none shipped. [2020](https://forums.ankiweb.net/t/adding-a-widget-for-the-ios-app/4355) `[OLD]`, [2023, interactive](https://forums.ankiweb.net/t/anki-widget-for-ios-17-now-interactive/31554) `[OLD]`, [main thread](https://forums.ankiweb.net/t/ankimobile-widget/32633) (30 replies, July 2023 to 2026-10-30), and [a wider one in 2025](https://forums.ankiweb.net/t/ios-widgets-notifications-watch-app-other-features/57853). On page 1 of the main thread, roughly: heatmap or calendar 5 mentions, due counts 3, random card 3, streak 3, reminder or quick entry 3.
- `[SAID]` **Lock screen:** a plain logo widget was asked for in [May 2026](https://forums.ankiweb.net/t/ankimobile-widget/32633?page=2). No answer on substance.
- `[SAID]` **Watch:** Elmes in [2021](https://forums.ankiweb.net/t/feature-request-apple-watch-version/10031/2) `[OLD]` called it unlikely: battery, screen, unsupported technology.
- `[SAID]` **Card in a notification:** asked for in 2025; Elmes doubted that passive exposure helps ([same thread](https://forums.ankiweb.net/t/ios-widgets-notifications-watch-app-other-features/57853)).
- `[SAID]` **Background sync:** absent. [One thread](https://forums.ankiweb.net/t/ios-autosync-whats-the-status/41400) has 17 replies and another [35](https://forums.ankiweb.net/c/ankimobile/24?page=1), live in October 2026. Users loop Apple Shortcuts as a workaround; Elmes said in 2024 it needs major changes.
- `[SAID]` **The new team:** no commitment I could find. [On 2026-10-30](https://forums.ankiweb.net/t/ankimobile-widget/32633?page=2) AnkiHub's Andrew Sanchez pointed the widget thread at another app's grid widgets as inspiration. `[INFERRED]` Weak sign of interest, not a plan.

**AnkiDroid**
- `[CLAIMED]` Shipped today: notify when "more than n cards due", which [requires the widget](https://docs.ankidroid.org/manual.html) (manual, 2026-10-17). Users report the [lowest threshold is 10](https://forums.ankiweb.net/t/add-a-notification-option-for-any-cards-due/70296) (July 2026). A [1x1 widget](https://forums.ankiweb.net/t/widgets-for-ankidroid/45006) shows due count and estimated minutes; deck-picker and stats widgets were built under a 2024 Summer of Code project, and I did not confirm their release. [2.24](https://forums.ankiweb.net/t/ankidroid-2-24-0-changelog/69614) and [2.25](https://forums.ankiweb.net/t/ankidroid-2-25-changelog/71237) only fixed and polished widgets.
- `[SAID]` A [2025 Summer of Code report](https://github.com/ericli3690/gsoc-ankidroid-report) calls the old system broken for years and built its replacement: per-deck and global reminders, snooze, only-if-no-reviews. Its author says **card previews in notifications were left to an add-on, by maintainers' decision.**
- `[CLAIMED]` That replacement is still not on by default: [a 2026-10-28 bug report](https://github.com/ankidroid/Anki-Android/issues/22848) on a 2.26 alpha enables it at Developer options, Work in progress, "Enable new notifications". The [roadmap](https://forums.ankiweb.net/t/ankidroid-vs-anki-desktop-feature-parity-and-future-roadmap/71601) (October 2026) puts reminders under longer-term work. `[SAID]` A forum user [tells others](https://forums.ankiweb.net/t/add-a-notification-option-for-any-cards-due/70296) how to unlock it by tapping the logo six times.

**Third parties filling the gap**
- `[CLAIMED]` [Micro Review for AnkiDroid](https://github.com/BenoitMarchand/Micro_Review_for_AnkiDroid), a fork of AnkiDroid-Companion: answer from a notification, lock-screen wallpaper or widget, with scheduled reminders. Tiny: 1 star, no release visible.
- `[CLAIMED]` [amgi](https://github.com/antigluten/amgi), an open-source iOS client on Anki's engine: home-screen widgets, on-device Watch app, Shortcuts, AnkiWeb sync. 315 stars. Build from source; no App Store release shown.
- `[SAID]` [FareGate](https://forums.ankiweb.net/t/block-social-media-until-daily-reviews-are-done/68810.md) (August 2026, its maker's own post): blocks chosen iPhone apps until a review is done.

### 2025 and 2026

**Ownership**
- `[CLAIMED]` On [2026-02-02](https://forums.ankiweb.net/t/ankis-growing-up/68610.md), Damien Elmes said he was handing business operations and open-source stewardship to AnkiHub gradually, citing long hours and stress. He stays involved at a lower level. He [says he started the talks](https://forums.ankiweb.net/t/ankis-growing-up/68610/110).
- `[CLAIMED]` [AnkiHub's post](https://forums.ankiweb.net/t/ankis-growing-up/68610/2.md): core code stays open source, mobile apps stay supported, no price changes planned, professional design coming, AnkiHub subscriptions unchanged. Governance undecided, with a formal model promised "in the coming weeks". `[INFERRED]` I found no published model nine months on, though I may have missed it.
- `[CLAIMED]` The Anki trademark remains with [Ankitects Pty Ltd](https://apps.ankiweb.net/). The new team has its [first stable release, 26.05](https://forums.ankiweb.net/t/updates-from-the-anki-team-june-2026/70120/1.md), and [recent releases](https://github.com/ankitects/anki/releases) are published by Sanchez. An AnkiHub developer [led AnkiMobile 26.10](https://forums.ankiweb.net/t/ankimobile-26-10-is-out/74202).
- `[CLAIMED]` AnkiDroid stays self-governed, "no plans or agreements". `[SAID]` Yet its most active maintainer, David Allison, [joined AnkiHub full-time](https://news.ycombinator.com/item?id=46861313), and said AnkiDroid continues as usual.

**Releases**
- `[CLAIMED]` [25.07](https://newreleases.io/project/github/ankitects/anki/release/25.07) brought FSRS-6 and a terminal launcher. [26.05](https://github.com/ankitects/anki/releases/tag/26.05) (16 June) replaced it with a normal installer that needs no network, and raised the minimum to macOS 13.
- `[CLAIMED]` [26.08](https://github.com/ankitects/anki/releases) added an experimental editor and an Experiments section. 26.09 removed old import modules, which affects add-ons like AnkiConnect. [26.09.4](https://forums.ankiweb.net/t/anki-26-09-4-released-critical-security-update) (2026-11-04) fixed critical code-execution holes, one through shared decks, one macOS-only.
- `[CLAIMED]` AnkiMobile had no App Store update from [25.09 (2025-09-08)](https://apps.apple.com/us/app/ankimobile-flashcards/id373493387) to 26.10 (2026-11-03), about 14 months. A 26.01 beta existed. 26.10 redesigns Browse and the deck list.
- `[CLAIMED]` AnkiDroid: [7 major releases in 2025](https://forums.ankiweb.net/t/ankidroid-2025-wrapped/68014), with 2.26 near beta.

**FSRS**
- `[CLAIMED]` On fsrs-rs 6.6.2. Whether it is the default is **contested**: blogs say default since 25.07, but the [25.07 notes](https://newreleases.io/project/github/ankitects/anki/release/25.07) don't say so, the [manual](https://docs.ankiweb.net/manual/deck-options) says you enable it, and [issue #3616](https://github.com/ankitects/anki/issues/3616) was still being asked about in August 2026. All but the release notes seen as search results.

**What worries users** `[SAID]`
- First forum page: of 18 replies, about 7 supportive, 1 conditional, 5 worried, 5 other ([page 1](https://forums.ankiweb.net/t/ankis-growing-up/68610.md)). Next page: 4 supportive, 7 mixed, 6 worried, 1 other ([page 2](https://forums.ankiweb.net/t/ankis-growing-up/68610?page=2)). The whole thread has 141 replies and [67,352 views](https://forums.ankiweb.net/c/anki/announcements/25), the most-viewed announcement listed.
- Worries: paywalls, conflict of interest with paid AnkiHub, what "core code" excludes, no governance, a redesign of the UI. Hacker News, 573 points and 252 comments: about 12 sceptical, about 6 cautiously optimistic, of the part I read ([thread](https://news.ycombinator.com/item?id=46861313)).
- r/Anki's moderators [declined AnkiHub's request](https://reddit.sentinel-team.org/posts/1r44evg/snapshots/2026-02-16T22%3A35%3A01.454964Z) to take over the subreddit, and commenters called the approach creepy (second-hand, a third-party snapshot, 224 points).
- The upgrade path: 25.07 to 25.09.4 can't update themselves to 26.05 ([note](https://forums.ankiweb.net/t/an-important-note-about-updating-to-26-05-and-later), 14,818 views). The move of the [manual to a new site](https://forums.ankiweb.net/t/updates-from-the-anki-team-june-2026/70120?page=2) drew 3 complaints; the new logo drew comment.

**What pleases users** `[SAID]`
- An add-on developer welcomed regular app builds, and another user the new team, in the [same June thread](https://forums.ankiweb.net/t/updates-from-the-anki-team-june-2026/70120?page=2).
- The team [admits the add-on system is hard](https://forums.ankiweb.net/t/updates-from-the-anki-team-june-2026/70120/1.md) and plans to fix it.

### Add-ons

AnkiWeb's list shows ratings and thumbs, **no downloads**. `[CLAIMED]` About [3.8k add-ons](https://huggingface.co/datasets/Ya-Alex/anki-addons). I couldn't read AnkiWeb itself, so these two lists are second-hand, and both publishers have an interest.

| Add-on | Ratings, Oct 2026 ([Bullock](https://www.lilachbullock.com/?p=180293), paid placements exist) | Thumbs up, Sep 2026 ([Mindomax](https://www.mindomax.com/best-anki-add-ons), competitor; top 25 updated within a year) |
|---|---|---|
| Ankimon (Pokémon-style game) | 2,479 | 2,229 |
| Review Heatmap | 2,315 (last updated 2022) | not listed |
| Synapse | 1,381 | 953 |
| Image Occlusion Enhanced | 1,011 (last updated 2022) | not listed |
| AwesomeTTS | 930 | not listed |
| HyperTTS | 699 | 630 |
| AnkiBrain (AI) | 586 | 543 |
| Onigiri (new look) | 563 | not listed |
| AnkiConnect | 518 | 440 |
| Anki Leaderboard | 446 | 348 |
| AnkiHub | 400 | not listed |
| FSRS Helper | not listed | 317 |

- `[INFERRED]` What they reveal: motivation, streaks and games (Ankimon, Heatmap, Leaderboard, Life Drain); AI and card making (Synapse, AnkiBrain); sound; a nicer look; automation from outside (AnkiConnect); a better scheduler. **None of these 11, nor Mindomax's 25, is a reminder or notification add-on.** That may partly be because add-ons run only while Anki is open, so absence doesn't prove absence of need.
- `[CLAIMED]` Decay: [42 of the 100 most liked](https://www.mindomax.com/best-anki-add-ons) were last updated before Anki 23.10; 13 are capped at old versions (competitor's count). `[SAID]` Add-ons on all platforms through a JavaScript API are [years out](https://forums.ankiweb.net/t/ankimobile-suggestions/58430.md) (one user's guess: 2030).
- `[SAID]` Anki Leaderboard had about 4,000 active users in January 2025 (r/Anki title, second-hand through a mirror, seen as a search result).

### How many people use it

No one publishes a total. `[SAID]` Users [looked and failed](https://forums.ankiweb.net/t/how-many-downloads-or-active-users-does-anki-have/23461) in 2022 `[OLD]`.

| Figure | Source and date | Solidity |
|---|---|---|
| AnkiDroid 4.0M unique users, 4.48M devices, Google Play only | [Team post, 2025-12-31](https://forums.ankiweb.net/t/ankidroid-2025-wrapped/68014) | Solid origin, but `[INFERRED]` a running total, not active use. The post also says "doubled"; its figures show about 25% |
| AnkiDroid 260k daily active (220k a year before) | [Team post, 2024-12-24](https://forums.ankiweb.net/t/ankidroid-2024-roundup-2-20-1-changelog/53538) | Best activity figure; 2 years old; Play only |
| AnkiDroid US active devices 348,982 | [Forum, 2025-01](https://forums.ankiweb.net/t/off-topic-has-anki-had-a-spike-due-to-tiktok-users-migrating-to-rednote/54476) | One contributor's reading of Play stats |
| AnkiDroid 10M+ lifetime, desktop "same ballpark" | [Elmes, 2023-03-28](https://forums.ankiweb.net/t/anki-downloads-statistics/28788) `[OLD]` | His word, no data |
| Play: 24.5M installs, 4.8, 168K ratings | [AppGoblin, crawled 2026-11-04](https://appgoblin.info/apps/com.ichi2.anki) | Tracker. [Another](https://apppricinglab.com/app/google_play/com.ichi2.anki) says 10.0M, 158.7K (January 2026). Google's own page unread |
| AnkiMobile US 4.0, 2.4K ratings; Japan 3.9, 494, #1 paid Education | [US](https://apps.apple.com/us/app/ankimobile-flashcards/id373493387), [Japan](https://apps.apple.com/jp/app/id373493387), today | Solid as ratings, not as users. No sales figures |
| 68.3% of 560 US medical students | 2020 survey, via [a seller's blog](https://studycardsai.com/blog/medical-student-anki-statistics) seen as a search result | Self-selected, second-hand |

## Words people use

- "Functional Notifications Are Essential for AnkiMobile" (2025 [thread title](https://forums.ankiweb.net/t/functional-notifications-are-essential-for-ankimobile/66148))
- "about half the time", on badges working ([forum, 2025](https://forums.ankiweb.net/t/notification-badges-on-iphone-not-showing-up/56610))
- "completely broken", on AnkiDroid's old notifications ([2025 report](https://github.com/ericli3690/gsoc-ankidroid-report))
- "I will keep an eye on demand for this", Elmes's repeated answer ([2023](https://forums.ankiweb.net/t/ankimobile-widget/32633) `[OLD]`)
- "rather skeptical about the actual efficacy", Elmes on passive card widgets ([2025](https://forums.ankiweb.net/t/ios-widgets-notifications-watch-app-other-features/57853))
- "a terrible idea", a forum moderator on app-return nudges ([July 2026](https://forums.ankiweb.net/t/suggestion-using-well-established-behaviour-psychology-to-make-user-return-back-to-app-for-studying/70527))
- "trust needs to be earnt", Elmes ([February 2026](https://forums.ankiweb.net/t/ankis-growing-up/68610/110))

## Evidence against

- **Demand for widgets is visible but not loud.** The main thread gathered 30 replies in over 3 years; [4 of 30](https://forums.ankiweb.net/c/ankimobile/suggestions/20) recent AnkiMobile suggestion topics touch the subject. The "500+ votes in one day" heatmap request is one forum user's report of Reddit, unverified.
- **Many who ask want stats, not cards.** Heatmap and due counts come up more than a card on the widget. The AnkiDroid streak-widget [request](https://forums.ankiweb.net/t/review-streak-progress-widget/56569) has no replies.
- **Part of the community rejects the idea.** Elmes doubts passive review, and in the July 2026 thread 2 regulars said users must own their study. That thread's author says the actual problem is forgetting to review.
- **The App Store reviews I could read** mention price and sync, none mention widgets or notifications. It is a small sample.
- **The gap is narrowing.** AnkiDroid's reminders exist behind a flag. AnkiMobile 26.10 touches notifications and the team is shipping faster. Elmes tracks a learning-card alert. Sanchez's comment suggests some interest. A widget could ship with no warning.
- **Some notifications do work.** Forum threads select for failures, so the failure rate is unknown.
- **Against the ownership fears:** nine months on, I found no price change, and sync and desktop remain free. Hacker News commenters point to the AGPL and self-hosted sync, and [one former paid developer](https://forums.ankiweb.net/t/ankis-growing-up/68610.md?page=6) says AnkiHub handled that work fairly.
- **Against neglect of iOS:** 26.10 is a large update, though it came after a 14-month gap.

## Blockers

- **AnkiWeb's add-on pages** came back empty to WebFetch (they need JavaScript), so add-on numbers are second-hand. The Hugging Face dataset's query API refused sorting (422, 500). Lucas could open [the list](https://ankiweb.net/shared/addons) and paste the top rows, or an agent with shell access could read that dataset's files.
- **Google Play's page** came back truncated and AppBrain gave 403, so Play's own install bucket is unread. Lucas could open [the listing](https://play.google.com/store/apps/details?id=com.ichi2.anki) and read it.
- **Reddit** is only second-hand, through snapshots and search results; some mirrors were down.
- **Not tested on a device.** Whether AnkiMobile's alerts fire, and AnkiDroid 2.25's real settings, rest on documents and reports. Lucas could check 26.10 on his iPhone if he owns it.
- **Unavailable:** a Patreon page (410) and a PubMed Central paper behind a CAPTCHA, which I left alone. I read 100,000 of the Hacker News thread's 154,000 characters. All pages were read through WebFetch's summarizer, so counts by thread are rough, and I never saw AnkiWeb's own usage figures or AnkiMobile's sales, which aren't published.
