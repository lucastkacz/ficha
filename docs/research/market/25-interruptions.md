# 25 interruptions
Sources read: 34 pages (8 long papers or essays read nearly whole; the rest abstracts, short articles, forum threads and store pages), plus about 20 papers known only from search excerpts, marked "(excerpt)". Covered from 2000 to 2026.

**The strongest overall point:** no study found tests a flashcard shown uninvited during real desktop work, against a focused session, with a delayed memory test. Everything below on that question is an inference from neighbouring work.

## Findings

### 1. Learning in small moments

**Wait-learning (the best-known work; promising, weakly tested).**
- WaitChatter: 20 people, two weeks, quizzes while waiting for a chat reply, 57 new words on average. People were most receptive right after sending a message. [CLAIMED by authors] No control group appears in what I could read, and no delayed-retention figure. [abstract, CHI 2015, OLD](https://pg.ucsd.edu/publications/waitlearning-IM-chat-second-language-learning_CHI-2015.txt)
- Its author says it does not suit fluency or complex subjects, and fits flashcard-style memorizing. [SAID, [MIT News, 2015, OLD](https://news.mit.edu/2015/learn-language-while-you-text-0514)] That article's claim that it is less intrusive is not a reported measure.
- WaitSuite extended this to five kinds of wait in a two-week study. A feasibility study found it worked better at the start of a wait. (excerpt) [TOCHI 2017, OLD](https://up.csail.mit.edu/other-pubs/tochi16-waitsuite.pdf). The press release says users checked social media less; it gives no retention or annoyance data. [CLAIMED, [ScienceDaily, 2017, OLD](https://www.sciencedaily.com/releases/2017/04/170417155022.htm)]
- I found no HCI paper called "ReMind"; only a [Chrome extension](https://chromewebstore.google.com/detail/nhgcgkgifbbdngcggeichoaabckekamb) of that name.

**Notification and unlock delivery (solid on exposure, silent on memory).**
- The closest study: Schneegass et al., 30 people, three weeks, within-subject, Android. Median answers per day: 2 in a normal app, 5.5 in a persistent notification, 8 on each unlock. The model estimated +43% and +54% against the normal app. Answers fell about 14% per day. **Retention was not measured.** 18 of 30 preferred the notification; 15 named unlock their least favourite. Correctness stayed above 91% everywhere, on two-option tasks. [Paper, 2021](https://ar5iv.labs.arxiv.org/html/2109.07944)
- That notification waited to be answered; it was not a timed pop-up. [INFERRED] Its results may not carry over to a card that appears unasked.
- Dingler et al.: notification-triggered vocabulary sessions increased quick sessions, which participants liked. (excerpt, via later papers) [MobileHCI 2017, OLD](https://unpaywall.org/10.1145%2F3098279.3098565)
- MemReflex: flashcards reported effective "even while walking and distracted". The abstract gives no numbers, and it comes from the system's authors. [MobileHCI 2012, OLD](https://www.microsoft.com/en-us/research/publication/memreflex-adaptive-flashcards-for-mobile-microlearning/)
- LingoQ: 28 workers, three weeks, quizzes from their own work queries; consistent engagement, gains for beginners. It tests relevance, not interruption. [CHI 2026](https://arxiv.org/abs/2509.17477)

**Spacing itself (strong).**
- A large randomized trial of 26,258 physicians: 58.03% vs 43.20% on learning, d = 0.62. It supports spacing, not interrupting. (excerpt) [Academic Medicine, 2024](https://pubmed.ncbi.nlm.nih.gov/39250798/)
- Kerfoot's emailed spaced questions: 537 randomized residents, daily emails for 27 weeks, with gains at two years. Only 38% were retested, and the author held equity in the vendor. 95% of the spaced group wanted more. (excerpt) [2009, OLD](https://www.gwern.net/docs/spaced-repetition/2009-kerfoot.pdf)

**"Microlearning" as a category (weak).** An umbrella review of 15 reviews calls it effective but finds a notable lack of theory, and reports no effect sizes on the page I read. [Liyanage, 2026](https://jipe.sljol.info/articles/80). Much trade writing on this comes from training vendors, which I excluded.

**Evidence that offering retrieval is not enough.** A pre-registered MOOC experiment found no effect of retrieval practice, with high non-compliance. [Davis et al., 2018](https://www.learning-analytics.info/journals/index.php/JLA/article/view/6098). The authors' earlier experiments found no difference between randomized groups; gains appeared only in a self-selected subset who engaged. [Authors' guest post, 2016, OLD](https://learningscientists.org/blog/2016/9/20-1)

### 2. Fatigue, the cost to work, and how long people keep it up

**Cost of interruption (strong in the lab, for sequence-heavy work).**
- About 300 people: interruptions averaging 2.8 seconds roughly doubled sequence errors; 4.4 seconds tripled them. Other error types did not rise. (excerpt) [Altmann et al., 2014, OLD](https://www.interruptions.net/literature/Altmann-JExpPsycholGen14.pdf), [MSU press, 2013, OLD](https://msutoday.msu.edu/news/2013/brief-interruptions-spawn-errors). A short card is therefore not automatically harmless. [INFERRED]
- Merely receiving a phone notification hurt an attention task, without touching the phone. Sample not given on the page. [Stothart et al. via InformationWeek, 2015, OLD](https://www.informationweek.com/it-leadership/smartphone-notifications-kill-your-concentration)
- Interrupted workers finish as fast, with more stress and effort. (excerpt, through a secondary page I didn't vet) [Mark et al., CHI 2008, OLD](https://contextcost.pages.dev/the-research). The popular "23 minutes to recover" figure is unreliable: secondary sources disagree on it, so I don't use it.
- Interruptions raise annoyance and anxiety, more so mid-task. [Survey of the field, 2017, OLD](https://ar5iv.labs.arxiv.org/html/1711.10171)
- Useful content can still be disruptive. (excerpt; 20 users, 10,372 notifications) [Mehrotra et al., CHI 2016, OLD](https://discovery.ucl.ac.uk/id/eprint/1502364/)

**Notification load and fatigue.**
- People already get about 60-100 notifications a day. [Survey, 2017, OLD](https://ar5iv.labs.arxiv.org/html/1711.10171)
- 237 people in India for two weeks, by self-report: batches three times a day improved attention, mood and control. Hourly batches gave few benefits. No alerts at all raised anxiety and fear of missing out. No memory measures. [Authors' summary of Fitz et al., 2019](https://communities.springernature.com/posts/batching-notifications-can-improve-attention-well-being-and-productivity)
- 30 people, one day with no notifications: less distracted, more productive, but more anxious and less connected. Two years on, 13 of 22 who had intended changes had kept them. [Pielot & Rello, 2017, OLD](https://ar5iv.labs.arxiv.org/html/1612.02314)

**Learning apps specifically.**
- Duolingo, about 200 million reminders: novelty effects are real, and a repeated reminder loses force, so it penalizes recently seen messages. It is the maker's own account, with a stake in the result. I couldn't read the lift figures. [Duolingo blog, 2022](https://blog.duolingo.com/oi-e-o-duo-inteligencia-artificial-por-tras-do-meme/), [KDD 2020 paper, OLD](https://research.duolingo.com/papers/yancey.kdd20.pdf)
- 12,071 users of an English app: incoming-message-style notifications worked best, and too many reversed the gain. (excerpt) [2016 paper, OLD](https://scholars.ncu.edu.tw/en/publications/effects-of-push-notifications-on-learner-engagement-in-a-mobile-l/)
- Vendor claims of a threshold, such as losses above three pushes a day, have no traceable method; I discard them. [Example](https://www.lifescapes.org/362303.html)

**How long it lasts.** No study found of push or pop-up learning runs longer than about four weeks; Kerfoot's 27 weeks of daily email is the nearest long run. The authors read Schneegass's daily drop as a possible novelty effect. Reminders may also create dependence: a four-week study found they helped repetition but hindered automaticity, while event-based cues built it. (excerpt) [Stawarz et al., CHI 2015, OLD](https://discovery.ucl.ac.uk/id/eprint/1468224/).
### 3. What people report

**The evidence is thin. I found no first-person account, good or bad, of anyone keeping a desktop pop-up for months.** Reddit, the likeliest place, was out of reach.

**Pop-ups during work, about 5 places and roughly 10 people.**
- Ruzu Pop-ups (Anki): 8 GitHub stars, so a small niche. [Repo](https://github.com/RuzuStudios/ruzu-pop-ups). Reviews split: one calls it intrusive and annoying, one used it for an hour while browsing social media and was satisfied. (SAID, search excerpt of a [listing mirror](https://ankivn.pages.dev/addons/ruzu-pop-ups) that then returned 404). Its [Chrome version](https://chrome.google.com/webstore/detail/mpjdjilfcgmndfnailloidpemknemeno): 4.2 from 9 ratings. (excerpt)
- An Anki forum poster wanted small pop-ups while in other programs, then asked for random intervals of 2-30 minutes. 4 posters, 2024. [SAID, thread](https://forums.ankiweb.net/t/add-on-for-reviewing-card-at-intervals/41130)
- A break-timer add-on: one user calls it "amazing", one says it helped catch up. 6 users, 2024-2026. It hides Anki rather than popping up. [SAID, thread](https://forums.ankiweb.net/t/support-thread-anki-pop-up-after-10-cards-take-a-3-minute-break-by-shige/41242)
- Obsidian's popup plugin: about 202 downloads, default every 120 minutes, quiet hours, 90-second auto-close, and full-screen skipping on Windows only. No reviews. [CLAIMED, 2026](https://www.obsidianstats.com/plugins/sr-popup-review)

**The Mac specifically.**
- Wunderbar, a menu-bar word display, about 42 HN comments, 2024: few discuss distraction. The complaints are menu-bar space and a stray rude word during screen sharing. One critic says seeing the translation at once makes you feel you know it, and wants click-to-reveal. [SAID, thread](https://news.ycombinator.com/item?id=39999163)
- Makers all promise no disturbance, and none shows a review saying so. PopCards: cards "pop up gently without disrupting your work, meetings, or flow". [CLAIMED](https://popcards.app/). NotchWise hides during screen sharing, Focus and presentations. [CLAIMED, 0 reviews shown](https://apps.apple.com/app/notchwise/id6760242442). VocaBar advertises no pop-ups at all, a sign the pop-up is seen as a negative. [CLAIMED](https://apps.apple.com/app/id6744346351) [INFERRED]
- No user feedback on [GlimpseWords](https://www.producthunt.com/products/glimpsewords/reviews) or [Purrfect Memory](https://alternativeto.net/software/purrfect-memory/about). Silence likely means few users, not no complaints. [INFERRED]

**Guilt, about 6 sources, each one or few people.** It attaches to the backlog number, more than to the interruption.
- A big due count in a reminder raised stress for 1 of 5 posters; a developer replied that limits should prevent it. [SAID, 2024](https://forums.ankiweb.net/t/notification-options/50544)
- Falling behind is demoralizing; Nielsen needed weeks of rising quotas after a seven-month gap. [SAID, 2018, OLD](https://augmentingcognition.com/ltm.html)
- A blogger caps Anki at one pomodoro and pauses new cards to tame the pile. [SAID, 2026](https://blog.vslira.net/2026/01/one-pomodoro-of-anki-day-is-enough-for.html)
- HN commenters quit over review load and monotony, about 5 comments across threads. (SAID, search excerpts) [1](https://news.ycombinator.com/item?id=35520264), [2](https://news.ycombinator.com/item?id=35511357), [3](https://news.ycombinator.com/item?id=44020922)
- Duolingo's guilt messages: commentary only, no survey found. (excerpt) [Example](https://thewolfpacket.org/8181/opinions/satire-duo-the-owl-wreaking-havoc-on-chs-one-reminder-at-a-time/)

**Do they keep it on?** Across Anki and RemNote forums, visible requests lean toward *more or better* notifications, not fewer: at least 5 Anki threads. One has 728 views, another 2,430. [SAID, list of threads](https://forums.ankiweb.net/t/feature-request-notification-improvements-for-ankidroid/67354), [RemNote, excerpt](https://forum.remnote.io/t/notifications-for-flashcards/9552). These posters chose to be there, so the sample leans pro-reminder. [INFERRED] Requests do include narrower control, such as no alerts for new cards.

### 4. Is a card out of context remembered as well?

**Unknown, directly. Neighbouring lab work suggests this:**
- **New material suffers more than review.** Dividing attention at study clearly hurts later memory; at retrieval accuracy mostly holds, at the cost of slower responses. Strong and repeated. [Craik et al., via Atlas of Science, 2019, OLD](https://atlasofscience.org/is-retrieval-from-memory-automatic/), [Naveh-Benjamin et al., 2000, OLD](https://link.springer.com/content/pdf/10.3758/BF03209344.pdf) (excerpt)
- **Whether a distracted review still strengthens memory is contested.**
  - Against: items retrieved under divided attention were remembered less two days later. (excerpt) [Dudukovic et al., 2009, OLD](https://link.springer.com/content/pdf/10.3758/MC.37.7.953.pdf)
  - For: 96 undergraduates, two-day delay; the testing effect was not reduced, and was numerically larger, 0.08 vs 0.05. [Tse et al., 2019, OLD](https://www.frontiersin.org/articles/10.3389/fpsyg.2019.00969/full)
  - Mixed: little effect on tested items, but restudied items fell. (excerpt; link is my best match, unconfirmed) [Mulligan et al., 2021](https://bohrium.dp.tech/paper/arxiv/39285101)
  - Tse et al. blame the conflict partly on distractor type: non-verbal ones may understate the cost. Verbal work, such as writing or reading, would be the harder case. [INFERRED]
- **Same-day scores can hide the loss.** Divided attention in class left same-class quizzes intact, but lowered later exams. (excerpt) [Glass & Kang, 2019, OLD](https://cms.cloudfront.ualberta.ca/centre-for-teaching-and-learning/media-library/teaching-institute/2019/dividing-attention-in-the-classroom-reduces-exam-performance.pdf). Correctness in the app would then flatter. [INFERRED]
- **These tests are concurrent tasks.** A card on screen is usually a switch, not simultaneous work, so these results may not transfer. [INFERRED] Attention residue, the previous task lingering after a switch, is the likelier cost, and it is untested on flashcards. (excerpt) [Leroy, 2009, OLD, via a blog](https://siliconcanals.com/the-psychology-of-attention-residue-and-how-i-have-started-minimizing-it/)
- **In the field:** Schneegass participants reported being too rushed to answer properly. Nielsen finds reviews harder when his mind isn't calm. [SAID, 2018, OLD](https://augmentingcognition.com/ltm.html)

### 5. Which design choices help

| Choice | Evidence | Strength |
|---|---|---|
| Deliver at breakpoints, not mid-task | Less annoyance, anxiety and errors, with no time cost: a [talk summary](https://rosetta.to/u/stanford/paying-attention-to-interruption-a-human-centered-approach?t=0) gives 36%, 47% and 50%. [Iqbal & Bailey, 2007-08, OLD](https://www.interruptions.net/literature/Iqbal_Bailey-CHI07.pdf) (excerpt). Coarser breaks cost less. | Strong in the lab |
| Defer briefly | 680,000+ users: response time down 49.7%, opens up to about 5.5%. Run with Yahoo Japan. [Okoshi et al., 2017, OLD](https://research.lycorp.co.jp/jp/papers/198) (excerpt). Busy turns to free in about 2 minutes, by 113 users. [Survey](https://ar5iv.labs.arxiv.org/html/1711.10171) | Strong for phones; measures response, not memory |
| Start of a wait, after an action | WaitChatter and WaitSuite above | Promising, small |
| Few, not hourly | Three times a day beat hourly, for general alerts (Fitz) | Medium; self-report |
| Vary, avoid sameness | Duolingo's novelty result | Medium; vendor |
| No forced answer | Notification liked over blocking unlock (Schneegass) | Small |
| User control | Interruption cost varies by person ([survey](https://ar5iv.labs.arxiv.org/html/1711.10171)); participants asked for time windows and task counts (Schneegass) | Medium |
| Aim at idle moments | Predicted boredom made people more open to suggested content; 54 users. (excerpt) [Pielot et al., 2015, OLD](https://techxplore.com/news/2015-09-user-consume-content.amp) | Small |

The Mac has less timing evidence than the phone. Desktop breakpoint work is older and lab-based; logs predicted breakpoint type at 69-87%. [Survey](https://ar5iv.labs.arxiv.org/html/1711.10171). I found no such work for a learning card.

A card as a pause is not supported either. In a meta-analysis of micro-breaks, 22 samples, 2,335 people, vigor rose (d = .36), fatigue fell (d = .35), and performance did not significantly change, with cognitive tasks at d = -.09. Those are rest breaks, not tests. [Albulescu et al., 2022](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0272460)

## Words people use

- "bothers me that I have to answer the task or dismiss the app" ([study participant, 2021](https://ar5iv.labs.arxiv.org/html/2109.07944))
- "not focused enough to answer the questions conscientiously" ([same study](https://ar5iv.labs.arxiv.org/html/2109.07944))
- "almost what I needed", of an interval add-on ([Anki forum, 2024](https://forums.ankiweb.net/t/add-on-for-reviewing-card-at-intervals/41130))
- "highly intrusive and annoying little window" (add-on review, second-hand through a search result)
- "adds to my stress", of a big due count ([Anki forum, 2024](https://forums.ankiweb.net/t/notification-options/50544))
- "got the habit to stick for me", of reminders (HN, search excerpt)
- "somewhat demoralizing and discouraging", on falling behind ([Nielsen, 2018](https://augmentingcognition.com/ltm.html))

## Evidence against

- **Against "interrupting tires people":** embedded prompts raised exposure in Schneegass; forums ask for more notifications; 95% of Kerfoot's group wanted more. Removing general alerts entirely also raised anxiety.
- **Against "timing is what matters":** in one study of 11 people, content mattered more than timing. [Fischer et al., via survey](https://ar5iv.labs.arxiv.org/html/1711.10171). Two summaries of related work disagree on early-task interruptions: one finds the start of a task less disruptive, [another](https://www.erichorvitz.com/disruptmemory.htm) finds early interruptions cost the goal more often.
- **Against "distracted review is worthless":** Tse et al. and the Mulligan line, above. Against "it's fine": Dudukovic and Glass & Kang.
- **Against "small moments work":** Davis's null at scale. No retention data in the main notification studies.
- **Against the interruption studies' strength:** mostly artificial tasks or self-report, so the cost in a real workday is not established.
- **Against my own "guilt comes from backlog" reading:** it rests on forums of people who already use Anki, and those bothered by interruptions may simply have left silently.

## Blockers

1. **Reddit**, the richest source for question 3, refuses automated reading. I ignored Reddit mirror sites in the results, as the brief requires. Lucas could help by pointing to threads, or another agent's archive access could query "popup flashcards", "Anki notifications turned off" and "menu bar flashcards".
2. **Full PDFs.** WebFetch returned binary for WaitSuite, Cai's thesis, Duolingo's KDD paper, Draxler and others, and page rendering failed because poppler isn't installed. So I have no delayed-recall numbers for WaitChatter/WaitSuite and no Duolingo lift figures. Installing poppler, or Lucas exporting those PDFs to text, would fix this; WaitSuite is the most worthwhile.
3. **PMC, PubMed, Springer and MDPI** answered with a browser check, a cookie wall, a login redirect or a 403, and I did not get around them. PubMed and PMC citations above are search excerpts. Stawarz's UCL page, Harvard Magazine and a TU/e opinion piece also gave 403.
4. **Store reviews.** AnkiWeb's and the Chrome Web Store's pages rendered empty. Lucas could open Ruzu Pop-ups' AnkiWeb page, linked from [its repo](https://github.com/RuzuStudios/ruzu-pop-ups), in a browser, or check PopCards' App Store reviews, for what real users say.
