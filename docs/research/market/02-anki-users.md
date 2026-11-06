# 02 Anki's users in general
Sources read: about 60 (18 blog posts, essays and studies, 20 forum threads, 6 GitHub issues plus 2 ranked issue lists, 14 Hacker News threads, 1 store page). Covered from 2011 to 2026.

How to read the counts: long HN threads were read in part (the first 100,000 to 200,000 characters) and tallied by a fast reading model, so every count is rough and themes overlap. HN skews technical; forum regulars skew to power users. No source measures churn: the Anki team publishes no such figure that I could find.

## Findings

### What people value, and why they stay

Ranked by mentions across threads and posts:

1. **It works.** [SAID] The most common praise in every general thread: about 20 comments across two HN threads ([2024 OLD](https://news.ycombinator.com/item?id=39163094), [2025](https://news.ycombinator.com/item?id=44020591)) credit exams, interviews, languages or careers. In a [survey of 89 first-year medical students at one school](https://pmc.ncbi.nlm.nih.gov/articles/PMC12662189/) (Oct 2025), 94% used it and 87.8% believed it contributed significantly to their success.
2. **Free, open, and yours.** [SAID] About 15 of about 170 comments read in the [Feb 2026 ownership thread](https://news.ycombinator.com/item?id=46861313), with about 6 on data portability and about 10 fearing decline under commercial pressure. It barely comes up (0 to 3 mentions) in the 2024 thread: [INFERRED] people take it for granted until it looks threatened. The [forum replies](https://forums.ankiweb.net/t/ankis-growing-up/68610) (about 18) repeat the fear of free features moving behind paywalls. iOS reviewers like the one-time payment with no ads ([store page](https://apps.apple.com/us/app/ankimobile-flashcards/id373493387), read Nov 2026).
3. **Flexibility and community.** [SAID] Add-ons, shared decks and templates: about 15 comments across the 2024 and 2025 threads. Near-universal among medical students, per a [competitor's blog](https://noun.town/blog/is-anki-still-worth-using-in-2026/) (Jun 2026, sells a language game).
4. **Better scheduling.** [SAID] FSRS drew about 10 mentions in 2024 and 2025, some reporting lower workload. It is the most reacted issue in Anki's repo ([#3616](https://github.com/ankitects/anki/issues/3616), 69 reactions; [#2443](https://github.com/ankitects/anki/issues/2443), 41).
5. **People return to it.** [SAID] Long-term users describe breaks and coming back, having tried rivals: [one since 2011](https://anecdata.mataroa.blog/p/on-srs-anki/) (Jan 2024, OLD), [one of 12 years](https://momomori-eki.net/2020/08/04/twelve-years-of-anki/) (2020, OLD), who says routine suits them. [INFERRED] The years of review history and cards built are part of what keeps them; both writers treat the collection as an asset not to restart.

Felt reward matters too: 95.1% of those medical students felt accomplished after finishing reviews ([same study](https://pmc.ncbi.nlm.nih.gov/articles/PMC12662189/)). Some keep it as a reference library rather than a study tool ([Ask HN 2022, OLD](https://news.ycombinator.com/item?id=31872982)).

### The main criticism, and why people quit

**Complaints, ranked.** Mentions summed over 8 HN threads from 2020 to 2026, 10 segments read ([1](https://news.ycombinator.com/item?id=25160204), [2](https://news.ycombinator.com/item?id=22492381), [3](https://news.ycombinator.com/item?id=24957617), [4](https://news.ycombinator.com/item?id=35209775), [5](https://news.ycombinator.com/item?id=39163094), [6](https://news.ycombinator.com/item?id=41913751), all OLD; [7](https://news.ycombinator.com/item?id=44020591), [8](https://news.ycombinator.com/item?id=46861313), recent). [INFERRED] from [SAID]:

| Rank | Pain | About | Share |
|---|---|---|---|
| 1 | Backlog and daily burden | 57 | 27% |
| 2 | Habit, boredom, chore feeling, motivation | 50 | 23% |
| 3 | Making cards | 38 | 18% |
| 4 | Interface | 34 | 16% |
| 5 | Setup, configuration, install | 24 | 11% |
| 6 | iOS price | 10 | 5% |

I left out one broad bucket from the 2020 thread for cards (about 30) and one for UI (about 25), since they mix complaint with advice. Adding them back makes cards first and UI second, ahead of backlog, so ranks 1 to 4 are close and depend on what you count. The first two are one problem in practice for many: the load is what turns into dread.

**Exit stories, ranked.** Tallies of 34 HN comments from people who stopped, found by searching ["stopped using"](https://hn.algolia.com/api/v1/search?query=anki%20stopped%20using&tags=comment&hitsPerPage=50) and ["gave up"](https://hn.algolia.com/api/v1/search?query=anki%20gave%20up&tags=comment&hitsPerPage=50) (2013 to 2026, three about other SRS apps) [SAID]:

- Did not help in real use, or the material wasn't worth it: 9
- Backlog or daily load: 7
- Making cards: 6
- Other, such as app failures or too-long intervals: 6
- Boredom: 2. UI: 2. Setup: 1. Goal finished: 1

This differs from the complaints: people grumble most about the load, but a large share of those who leave say it wasn't paying off. Blogs echo this, with the caveat that several of the loudest sell something:

- **Load and burnout:** [one writer](https://fullchee.github.io/public-notes/Soft-Skills/Learning/Why-I-quit-Anki) (quit May 2022, back that August, stopped again June 2025 once the goal ended) reviewed late at night to clear the queue. [Another](https://esrh.netlify.app/posts/2022-02-17-400-days-of-spaced-repetition) (2022, OLD) nearly quit at 400 to 500 reviews a day. [KanjiKen](https://main-kanjiken.web.app/blog/why_i_stopped_using_anki) (Oct 2024, OLD, sells a kanji app) blames hours of catch-up. [NeonLingo](https://www.neonlingo.com/blog/anki-burnout) (Aug 2026, sells an extension) says the same, admitting it has only anecdotes.
- **Doesn't transfer:** a [98,000-review essay](https://miguelconner.substack.com/p/anki-is-already-dead) (Aug 2025, promotes the author's tool) says learners recognize the card rather than the word. [MindDory](https://dev.to/minddory/i-built-a-flashcard-app-after-burning-out-on-anki-heres-what-i-learned-47ml) (Mar 2026, sells an app) argues the same. A [2014 LessWrong post](https://www.lesswrong.com/posts/As9E3HfgED2zkTAfB/a-vote-against-spaced-repetition) (OLD) says many of about 30 classmates quit after about five tests for poor returns.
- **Interface:** [one writer left for Mochi](https://slims-hhofner-com.vercel.app/blog/on-quitting-anki) (Jun 2022, OLD, sells nothing).
- **Never started:** [one long-time advocate](https://www.masterhowtolearn.com/2020-10-31-why-i-no-longer-tell-my-friends-about-anki-supermemo/) (2020, OLD) says most friends had no felt need; some quit within days.

### How the pain divides

- **Backlog: the largest single pain.** [SAID] The mechanism is the same everywhere: a few missed days, a pile, avoidance, a deleted deck. Medical students (one school, 2025): 82.1% found Anki overwhelming, 67.9% said it made them anxious, 68.3% felt frustrated with unfinished reviews ([study](https://pmc.ncbi.nlm.nih.gov/articles/PMC12662189/)). The [2025 LessWrong guide](https://www.lesswrong.com/posts/7Q7DPSk4iGFJd8DRk/an-opinionated-guide-to-using-anki-correctly) calls the backlog from too many new cards the classic way to die out, and its main advice is a review cap of about 20 a day. A [July 2026 forum proposal](https://forums.ankiweb.net/t/proposal-backlog-recovery-planner-to-prevent-user-churn-burnout/70487) asks for a recovery planner, with no data and no developer reply.
- **Card making: second for those who write their own.** [SAID] Tedious, and maddening on a phone ([2026](https://news.ycombinator.com/item?id=46861313)). One user says a batch-generation add-on is [what kept them from quitting](https://news.ycombinator.com/item?id=45359524) (Sep 2025). Shared decks don't solve it: quality varies, and users lose interest.
- **Interface: real, and mostly a beginner's wall.** [SAID] Dated, clunky, many nested dialogs ([2022 brainstorm, OLD](https://forums.ankiweb.net/t/brainstorming-for-modern-ui-anki-3-0/), 113 replies, 12,923 views). Terms like note, card, leech, cloze confuse newcomers, and most people skip the manual ([2024 thread, OLD](https://forums.ankiweb.net/t/revisiting-onboarding-decks-and-tutorials/43692)). The [Feb 2026 handover post](https://forums.ankiweb.net/t/ankis-growing-up/68610) itself names usability and onboarding as long-standing problems.
- **Setup: smaller, but flared in 2025.** [SAID] The terminal-style launcher alarmed people ([forum](https://forums.ankiweb.net/t/new-25-07-5-launcher-process-poor-user-experience/66080), about 8 people, Aug to Dec 2025, no data on anyone giving up). On GitHub, install issues add up to over 100 reactions ([offline installer](https://github.com/ankitects/anki/issues/4241) 37, [glibc](https://github.com/ankitects/anki/issues/4167) 29, [launcher GUI](https://github.com/ankitects/anki/issues/4152) 18, [cold start](https://github.com/ankitects/anki/issues/4314) 15, [silent install](https://github.com/ankitects/anki/issues/4229) 8). A new launcher [shipped by June 2026](https://forums.ankiweb.net/t/updates-from-the-anki-team-june-2026/70120), which also calls add-ons not user friendly.
- **Something else:** iOS price ($24.99, [78,725 views on the top forum thread](https://forums.ankiweb.net/t/free-version-of-the-iphone-app/), Feb to Mar 2025 replies, about 4 of 9 people on price). Reliability in iOS reviews, 4.0 from 2.4K ratings ([store page](https://apps.apple.com/us/app/ankimobile-flashcards/id373493387)). Fear about the new owner.

### Wished-for features, ranked

[INFERRED] from forum size, GitHub reactions and HN mentions, which measure different people and don't add up cleanly:

1. **Lighter load and recovery.** FSRS as default (69 reactions), load balancing, pause or vacation mode ([HN, 2020 OLD](https://news.ycombinator.com/item?id=25160204)), recovery planner.
2. **Modern, simpler interface and onboarding.** [Default card template thread](https://forums.ankiweb.net/top?period=all): 205 replies, 12,097 views. UI brainstorm as above.
3. **Faster card making, often with AI.** About 3 to 5 comments per recent HN thread, many add-ons, and a forum reply saying it is not a core feature (Feb 2026, search snippet only, probably [this thread](https://forums.ankiweb.net/t/automating-deck-flashcard-creation-in-anki/68943)).
4. **Cheaper or free iOS.** Rejected in the developer's FAQ as quoted in that thread.
5. **Widgets and reminders.** Detail below.
6. **Motivation: streaks, goals, heatmaps.** [#4085](https://github.com/ankitects/anki/issues/4085) (17 reactions, open), where a maintainer wants a streak that drops rather than resets; [goals thread](https://forums.ankiweb.net/t/beyond-streaks-daily-weekly-anki-goals/62943) (Jun 2025).
7. **Android parity:** [TTS](https://github.com/ankidroid/Anki-Android/issues/5793) 64 reactions, [scheduler](https://github.com/ankidroid/Anki-Android/issues/4905) 40, [profiles](https://github.com/ankidroid/Anki-Android/issues/2545) 26. All old and closed.

### Reviewing without sitting down to a session

**People already do this by hand.** [SAID] Queues, buses, waiting rooms, bathroom stalls ([2020, OLD](https://news.ycombinator.com/item?id=24957617), [2020, OLD](https://news.ycombinator.com/item?id=22492381)), public transit ([Dec 2024](https://news.ycombinator.com/item?id=42452527)); about 85 cards a day in spare-minute bursts ([2020, OLD](https://www.gresearch.com/article/anki-as-learning-superpower-computer-science-edition/)). 74.7% of the medical students said they could exercise and use Anki at once.

**Widgets: a steady, small request over six years.** [SAID] Five forum threads, about 30 people with some overlap:
- [iOS widget](https://forums.ankiweb.net/t/adding-a-widget-for-the-ios-app/4355): 11 people, 2020 to 2022, OLD. Ideas include a flippable card and a due-card question about hourly.
- [iOS 17 interactive](https://forums.ankiweb.net/t/anki-widget-for-ios-17-now-interactive/31554): study from the home screen, 2023, OLD.
- [AnkiMobile widget](https://forums.ankiweb.net/t/ankimobile-widget/32633): about 11 people, Jul 2023 to Aug 2025, then [6 more](https://forums.ankiweb.net/t/ankimobile-widget/32633?page=2) to Oct 2026; 30 replies, 3,213 views. It cites a Reddit post with 500+ votes (second-hand, unverified).
- [Widgets, notifications, Watch](https://forums.ankiweb.net/t/ios-widgets-notifications-watch-app-other-features/57853): 4 people, Mar to Dec 2025. Asks for card widgets, quiz notifications with a random card, a Watch app.
- [AnkiDroid widgets](https://forums.ankiweb.net/t/widgets-for-ankidroid/45006): 6 people, 2024 to 2025. Counts and a heatmap.

The requests split: [INFERRED] a little over half want a nudge (due counts, streak, heatmap), and about a third to a half want the card itself. The lead developer answered "keep an eye on demand" in 2020 and 2023, then in Aug 2025: "I don't think passive exposure without active recall is going to do much." ([thread](https://forums.ankiweb.net/t/ios-widgets-notifications-watch-app-other-features/57853)). AnkiMobile has no widget as of Oct 2026 by the thread's latest posts.

**Reminders: wanted, and neglected on Android.** [SAID] AnkiDroid's notifications were [broken for five or six years](https://github.com/ericli3690/gsoc-ankidroid-report), with a maintainer calling them a common complaint on Google Play ([#6552](https://github.com/ankidroid/Anki-Android/issues/6552), open since 2020, 6 reactions). A 2025 Summer of Code project rebuilt them; **card previews in notifications were dropped after a maintainer debate, left to an add-on**. On iOS, reminders exist but only in the app's preferences ([2024, OLD](https://forums.ankiweb.net/t/notification-options/50544)). Other reminder requests: [Android thresholds](https://forums.ankiweb.net/t/feature-request-notification-improvements-for-ankidroid/67354), Nov 2025; [desktop OS alerts](https://forums.ankiweb.net/t/suggestion-add-notifications-to-anki/67355), Nov 2025; [desktop, 2020, OLD](https://forums.ankiweb.net/t/idea-review-reminder-notifications/1630).

**Reviewing in place, not just being reminded.** [SAID] Scattered but specific:
- [Show a card at every phone unlock](https://github.com/ankidroid/Anki-Android/issues/4709): 15 reactions, 60 comments, 2017 to 2024, OLD. Maintainers said to build it as a separate app; a bot closed it.
- [Pop-ups over other windows, without opening Anki](https://forums.ankiweb.net/t/add-on-for-reviewing-card-at-intervals/41130): Feb 2024, OLD.
- [Overdue cards arriving by email, one click to answer](https://news.ycombinator.com/item?id=42521773): Dec 2024. There, a maker of a daily vocabulary email says Anki was hard to return to after a break, while a small daily message makes restarting easy.
- [Built own morning push](https://news.ycombinator.com/item?id=40997232) because they wanted reminders without opening an app, used over four years: Jul 2024, a random note rather than Anki.
- [Voice control, hands-free](https://github.com/ankidroid/Anki-Android/issues/1717): 23 reactions, 59 comments, 2011 to 2026; closed as not planned in 2022, with a new plea in June 2026.

**Others fill the gap.** [CLAIMED] [Ruzu Pop-ups](https://github.com/RuzuStudios/ruzu-pop-ups) (add-on, 8 stars, text only) shows cards in a small window while you work. [Anki Reminders](https://forums.ankiweb.net/t/anki-reminders-email-text-nudges-so-you-never-miss-a-day/71408) (Oct 2026) sends one email or text a day, $1/month for texts, no replies yet. From search snippets only: AnkiLock (locks apps until reviews are done), lock-screen flashcard apps FlashStacks and FlipUp, and new-tab extensions for browsers.

## Words people use

Everyday words, not quotations; see Blockers for why this list carries no verbatim phrases.

- The load: pile, backlog, wall of cards, death spiral, overwhelmed, catch-up ([HN 2025](https://news.ycombinator.com/item?id=44020591), [forum 2026](https://forums.ankiweb.net/t/proposal-backlog-recovery-planner-to-prevent-user-churn-burnout/70487), [LessWrong 2025](https://www.lesswrong.com/posts/7Q7DPSk4iGFJd8DRk/an-opinionated-guide-to-using-anki-correctly))
- The feeling: chore, burnout, boring, repetitive, soul-destroying ([Ask HN Oct 2024, OLD](https://news.ycombinator.com/item?id=41913751), [2022 post](https://esrh.netlify.app/posts/2022-02-17-400-days-of-spaced-repetition), [HN Dec 2024](https://news.ycombinator.com/item?id=42452527))
- Cards: tedious, friction, time-consuming, maddening on a phone ([HN 2026](https://news.ycombinator.com/item?id=46861313), [HN Sep 2025](https://news.ycombinator.com/item?id=45359524))
- Interface: clunky, ugly, dated, gray, hard to use, too much text ([HN 2020](https://news.ycombinator.com/item?id=24957617), [2022 post](https://slims-hhofner-com.vercel.app/blog/on-quitting-anki))
- What they want: review while working on other things, no need to open the app, a reminder to check unfinished decks, one click ([Ruzu](https://github.com/RuzuStudios/ruzu-pop-ups), [forum 2024](https://forums.ankiweb.net/t/add-on-for-reviewing-card-at-intervals/41130), [forum 2026](https://forums.ankiweb.net/t/ankimobile-widget/32633?page=2), [HN 2024](https://news.ycombinator.com/item?id=42521773))
- Praise: superpower, transformative, free, without fail ([G-Research 2020](https://www.gresearch.com/article/anki-as-learning-superpower-computer-science-edition/), [HN 2025](https://news.ycombinator.com/item?id=44020591), [2024 post](https://anecdata.mataroa.blog/p/on-srs-anki/))

## Evidence against

- **The review-without-a-session wish is small in general talk.** In the broad HN threads, notifications, widgets and idle-moment reviewing drew about 0 to 3 mentions per thread of 100 to 170 comments, against dozens for the load. In the [2025 thread](https://news.ycombinator.com/item?id=44020591), one 100-comment segment had none. Reactions are low (15 to 23 at most), [Anki's own repo](https://api.github.com/search/issues?q=repo:ankitects/anki+is:issue+notification+OR+reminder+OR+widget+OR+tray&sort=reactions&order=desc&per_page=20) has no highly reacted issue on it, and the pop-up add-on has 8 stars. The Reddit angle may show more.
- **The developer's objection is about learning.** He doubts passive exposure; the requests that show a card without rating fall under it. Requests with active answers (unlock, pop-up, email) do not.
- **Interruption has costs.** Repeated alarms are crude and break into sessions ([2020, OLD](https://forums.ankiweb.net/t/idea-review-reminder-notifications/1630)); a backlog number in a reminder adds stress ([2024, OLD](https://forums.ankiweb.net/t/notification-options/50544)); a daily job that opens Anki is easy to ignore and teaches ignoring ([HN 2015, OLD](https://hn.algolia.com/api/v1/search?query=anki%20widget&tags=comment&hitsPerPage=40)). Against that, a user with a due-count badge finds it [motivating](https://news.ycombinator.com/item?id=42521773).
- **Backlog may be self-inflicted.** Veterans say capping cards fixes it, and that missed days are no disaster ([HN 2020, OLD](https://news.ycombinator.com/item?id=25160204)). Yet [FSRS's workload gains are disputed](https://github.com/ankitects/anki/issues/3616): a reply asked for real-user data and got none, and a 2025 MaiMemo test of about 8,900 new users saw no efficiency gain.
- **Making cards is also valued.** Several say writing cards teaches more than reviewing ([2022, OLD](https://news.ycombinator.com/item?id=31872982), [2024, OLD](https://news.ycombinator.com/item?id=39163094)), so removing it may remove the benefit.
- **The interface has defenders.** Forum replies ask to keep it, and fear redesign ([2026](https://forums.ankiweb.net/t/ankis-growing-up/68610)). One user calls Anki hard at first, then excellent ([HN Dec 2025](https://news.ycombinator.com/item?id=46264492)). Forum regulars doubt onboarding is the problem ([2024, OLD](https://forums.ankiweb.net/t/revisiting-onboarding-decks-and-tutorials/43692)).
- **Some exits aren't failures.** Goals end, or people move to immersion ([one writer](https://fullchee.github.io/public-notes/Soft-Skills/Learning/Why-I-quit-Anki), HN tallies). Anki doesn't nag, and [one user likes that](https://news.ycombinator.com/item?id=42884736) (Jan 2025); another in that thread says that lack of pressure is why most people drift away.
- **"Anki is dead" is a sales pitch** in most of its forms: the sources saying it sell a replacement. The medical students, heaviest users, report high distress and high reward at once.

## Blockers

- **Verbatim quotes:** my operating rules allow at most one word-for-word quote per response, stricter than the brief's "a few". The report carries one, and "Words people use" lists plain vocabulary with sources instead.
- **Not readable:** [Why I'm Quitting Anki after 12 Years](https://japaneselevelup.com/?p=26463) (certificate error, search snippet only; says no regret a month later). [Why Anki doesn't work for me](https://medium.com/@iandanforth/why-anki-doesnt-work-for-me-69ef1944943b) (Medium 403, snippet only; stops after a couple of months at a wall of effort). greaterwrong.com refused connections; I used lesswrong.com, whose guide page cut off before the comments. Capterra 403. EA Forum 429. Two forum topics returned 404 (merged by moderators). Chrome Web Store showed no details for Ruzu.
- **Not found:** the LessWrong survey said to show most users quit (a comment cites it; no figures seen). Any published churn data, or results of the Anki team's add-on survey.
- **Lucas could help:** opening those two blog posts in his browser, only if wanted; neither would change the ranking. Anki's own numbers aren't public.
