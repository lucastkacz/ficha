# 29 five-issues
Sources read: 55 in full or nearly, plus about 25 searches' snippets. Covered from 2012 to 2026.

**Limit on all five:** I found no poll or usage statistic for any of them. Every count below is of forum posters, who are self-selected and skew to people with a problem. Anki's forums are `[A]`, others `[N]`. `[OLD]` means before 2024-11-05.

## Findings

### 1. Free review outside the schedule

**How much it's used.** No figure found. `[INFERRED]` One could be computed: the public [FSRS-Anki-20k dataset](https://huggingface.co/datasets/open-spaced-repetition/FSRS-Anki-20k) marks filtered reviews, and says it removes those made with rescheduling off (search result only).

**What Anki does.** `[CLAIMED]` [The manual](https://docs.ankiweb.net/filtered-decks.html) offers presets (forgotten cards, review ahead, preview new, by state or tag). Rescheduling is **on by default**. Off gives a preview mode where cards return as they were. It warns that review ahead doesn't suit repeated use.

**Who asks.** `[A][SAID]` One search surfaced about 11 threads of people stopped by "finished for now"; I read 5:
- 3 of the 5 name an exam: [Jan 2026](https://forums.ankiweb.net/t/to-cram-a-deck-as-long-as-i-want/68168), [May 2025](https://forums.ankiweb.net/t/help-how-to-review-cards-continuously-every-day-or-anytime-i-want-when-anki-says-congratulations-you-have-finished-this-deck-for-now/61446), [Apr 2024](https://forums.ankiweb.net/t/custom-study-feature/43639) `[OLD]`.
- 2 simply want to review at will, and are newer users: [2024](https://forums.ankiweb.net/t/how-to-review-all-the-cards-of-a-deck/47389), [2021](https://forums.ankiweb.net/t/my-decks-say-ive-completed-the-deck-today-but-i-want-to-use-it-again/16189) `[OLD]`.

**Other uses, 1 person each:** forgotten cards most days for years ([2023](https://forums.ankiweb.net/t/weird-custom-study-review-forgotten-cards-behaviour/37004) `[OLD]`); same-day cramming of forgotten cards, and pronunciation or shadowing practice without logging ([2025](https://forums.ankiweb.net/t/do-filtered-decks-have-an-effect-on-fsrs/60365)). "A free hour" as such appears once, in the May 2025 thread, as free time before an exam.

**It's confusing.** `[A][SAID]` In the 2025 thread, regulars gave differing accounts of whether rescheduling-off answers are logged, ending with: logged as Filtered, unused by FSRS. The 2023 poster found remembered cards repeating 4 to 6 times after an update. 2 of the 5 askers failed to set it up at first.

**Rivals.** All 5 checked have something:
- [Mochi](https://mochi.cards/docs/reviewing/cramming/) `[CLAIMED]`: any cards, due or not, answers change nothing, with filters including retention rate. No store review mentions it.
- Brainscape `[CLAIMED]`, search result of its help pages: Review All and Browse, while recommending Study Mode.
- [Felician's library guide](https://felician.libguides.com/strategiesandapps/flashcards) describes a Quizlet cram mode; its spaced mode is a separate, web-only one, per [its help page](https://help.quizlet.com/hc/en-au/articles/48324742264077-Studying-with-Spaced-Repetition) (search result).
- RemNote: its help lists "practice all cards". A [long-running request](https://forum.remnote.io/t/study-a-folder-without-affecting-srs/1536) for study without affecting SRS has conflicting replies on whether it works, and staff called it hard (search result).

**Among non-Anki users.** `[N][SAID]` A [merged RemNote request](https://feedback.remnote.com/p/quizlet-s-learning-mod) comes from someone used to Quizlet's free study (search result), and a [Logseq thread](https://discuss.logseq.com/t/flashcards-do-flashcards-only-work-with-spaced-repetition/8597) asks the same. Only those 2 found.

**Verdict.** `[INFERRED]` Asked often, mostly by newcomers and near exams. Nobody calls it a dealbreaker in those words, though one exam-bound poster sounds desperate.

**Fit with seconds.** `[INFERRED]` It's a sit-down session, a different shape from a card in passing. No source discusses it from an app built for short moments.

### 2. Formatting and Markdown

**Native Markdown in Anki.** `[A][SAID]` [The main thread](https://forums.ankiweb.net/t/integrating-markdown-into-anki/23621), 2022–Dec 2024: about 12 posters, about 7 for, 3 against. Several of the 7 want it only for import or as a field mode. Anki's developer said Markdown can't represent all HTML, so conversion is one-way. A later reply reports him saying it's not a priority (search result, unverified).

**Add-ons.** At least 6 tools exist: [Markdown input](https://forums.ankiweb.net/t/markdown-input-support-thread/22514) (7+ posters, 2022–24, mostly positive, some bugs), Better Markdown, anki-markdown, markdown2anki, Obsidian_to_Anki, Mdmath. A [template method](https://forums.ankiweb.net/t/markdown-support/52895) (2024–25, 5 posters) hit limits with lists, cloze and dark mode.

**Plain bold and color.** `[A][SAID]` About 10 of 18 results in one search are people upset at losing bold or color coming *into* Anki from Excel, Docs or dictionaries, e.g. [2023](https://forums.ankiweb.net/t/words-are-not-transferred-in-bold-and-color-when-transferring-files-to-anki/32518) `[OLD]`. One user [tested several note types and machines](https://forums.ankiweb.net/t/change-in-font-styling-formatting-in-recent-update-makes-cards-harder-to-read/44963) because bold grew harder to see (2024, `[OLD]`, 5 posts). [One student](https://forums.studentdoctor.net/threads/anki-memory-optimizing-background-colors-fonts.1353424) bolds what the answer must contain (search result).

**Do imports without formatting feel broken?** Direct evidence on bold being lost is thin: I found no thread complaining of it when leaving Anki.
- `[CLAIMED]` Vendors warn in advance. [Mochi](https://mochi.cards/docs/import-and-export/importing/) strips CSS and JavaScript and converts HTML to Markdown, so cards may look different. [RemNote](https://help.remnote.com/en/articles/6751471-importing-from-anki) says custom CSS isn't imported.
- `[N][SAID]` Complaints I could see are about worse things: [missing media and illegible cards from AnKing](https://forum.remnote.io/t/anki-import-bug-slow-import-illegible-format-cards-crashes-the-app/3434) and blank cloze cards in RemNote (search results, undated, likely `[OLD]`).
- `[INFERRED]` Decks vary widely, so the loss likely depends on the deck.

**Rivals.**
- Mochi's [store page](https://apps.apple.com/us/app/mochi-cards/id1507775056) leads with Markdown (4.6 of 175, Oct 2026). Of its visible reviews, 1 praises hiding text for conjugations and 1 finds reformatting pasted text slow. Praise of Markdown itself comes from the listing, not users. A [WaniKani thread](https://community.wanikani.com/t/srs-flashcards-program-mochi/46971) praises the interface.
- Quizlet sells bold, italics, underline and highlight only in Plus: [2019 press](https://campustechnology.com/articles/2019/10/17/quizlet-adds-smart-content-scanning-tool.aspx) `[OLD]` and its help page (search result).

**AI-written files.** [1 thread](https://forums.ankiweb.net/t/markdown-import-support/46804) (2024, `[OLD]`) wanted Markdown bold on import, and solved it with an AI-written script.

**Verdict.** `[INFERRED]` Bold and color are cared for quietly: people notice when they vanish. Markdown as syntax is a smaller wish, from card writers, some of them programmers. No dealbreaker statement found.

**Fit with seconds.** `[INFERRED]` Formatting costs nothing when answering. Its cost falls on writing and on the app. I found no study on whether bold shortens reading.

### 3. Typing the answer

**What Anki does.** `[CLAIMED]` [The manual](https://docs.ankiweb.net/templates/fields.html): one comparison per card, one line, not on AnkiWeb, with options to ignore accents or case. You still rate the card yourself. A note type for it ships by default.

**How much it's used.** No figure found. The nearest counts come from WaniKani, where typing is forced, so posters lean to wanting out:

| Thread | Posters | Self-grade | Typing | Unclear |
|---|---|---|---|---|
| [2018](https://community.wanikani.com/t/anyone-else-using-primarily-anki-for-wk/34259) `[OLD]` | 8 (page 1) | 4 | 2 | 2 |
| [2023](https://community.wanikani.com/t/should-i-keep-using-the-anki-mode-add-on/60156) `[OLD]` | 12 (page 1) | 5 | 3 | 4 |

**For it.** `[SAID]` It stops self-deception, in both threads. Judging oneself is tiring (1). Subjects named: children's English spelling ([2022](https://forums.ankiweb.net/t/type-in-the-answer/17035) `[OLD]`), Finnish ([2024](https://forum.readlang.com/t/feature-request-classic-flashcards-mode-with-optional-typing/264) `[OLD]`), Japanese input practice ([2025](https://forums.ankiweb.net/t/remembering-your-answer/54304)), language spelling ([Brainscape board](https://brainscape.featureos.app/p/type-answers), search result), CLI commands ([RemNote](https://forum.remnote.io/t/make-flashcards-interactive-perhaps-having-to-type-in-a-word-or-phrase-thats-being-tested-for/8499), search result). Second-hand from Reddit: Korean typing speed, listening cards. So: spelling and script, mostly in languages.

**Against it.** `[SAID]` Slower ("You can always think faster than you type," [Anki forum, 2025](https://forums.ankiweb.net/t/remembering-your-answer/54304)). Phones: the 2018 poster's main reason, and [virtual keyboards are error-prone](https://forums.ankiweb.net/t/fr-autocorrect-on-typing-answer/55109) (2025). A Reddit post, second-hand, calls it a heavy deterrent. Writing every card out takes too long (1, 2025).

**Wanted when it exists.** `[SAID]` Optional, card by card (2: Readlang, RemNote). Retype until right ([2025](https://forums.ankiweb.net/t/is-there-any-method-to-force-correct-answer-typing-before-proceeding-to-next-card/67006), [2024](https://forums.ankiweb.net/t/instant-type-answer-feedback-problem-and-fix/49076) `[OLD]`). Autocorrect: a regular replied that it defeats the feature's purpose. A [scratchpad add-on](https://forums.ankiweb.net/t/a-simple-floating-scratchpad-for-typing-answers-in-anki/70607) (Aug 2026) exists for typing on any card without a check.

**Research.** [Sundqvist et al., 2017](https://pmc.ncbi.nlm.nih.gov/articles/PMC5478738/) `[OLD]` compared typing or writing with mental retrieval, on paired associates, not flashcard apps: a small advantage at one week in 2 of 4 experiments, and an average d of 0.07 across 13. The authors credit retrieval itself, not the response. This doesn't test learning a spelling.

**Rivals.** [RemNote](https://help.remnote.com/en/articles/7752298-typing-in-answers) `[CLAIMED]`: optional per card, exact, fuzzy or AI matching, and it preselects a rating you can change. StudySmarter has a keyboard button ([help](https://studysmarter.zendesk.com/hc/en-gb/articles/4471309936284-Type-the-answer-feature), search result). Brainscape: only a request seen. Mochi: unconfirmed.

**On notifications and widgets.** I found **no app** offering it, which isn't proof. One search returned 5 store listings; [MemoryPush](https://apps.apple.com/hn/app/memorypush-flashcard-study/id6745531048?l=en-GB) reveals the back on long-press and mentions no typing. [AnkiDroid Companion](https://github.com/unalkalkan/AnkiDroid-Companion) doesn't say. The sheets in `20-unprompted-cards.md`, read as a cross-check, describe flip, hover and reveal. Third-party tutorials say iOS widgets allow only buttons and toggles; one guide disagrees.

**Verdict.** `[INFERRED]` A minority, mostly language learners who care about spelling, want it strongly. Others avoid it for time; the WaniKani counts lean that way. The one dealbreaker found runs against it: 1 poster would quit WaniKani if forced to type.

**Fit with seconds.** `[INFERRED]` The sharpest conflict of the five: sources on cost name time, phones above all. Optional, per-card typing is how requesters reconcile it.

### 4. Several sounds on one side

**How common.** No count across decks found. A small sample, surfaced by search, not random; only Kaishi's template was read directly:

| Deck | Sounds on a side | Source |
|---|---|---|
| Kaishi 1.5k, Japanese (1.6k GitHub stars) | Word and sentence, both on the back | [template](https://github.com/donkuri/Kaishi) |
| Language Atlas, Japanese | Two files per word, word and sentence; side unknown | [seller's page](https://languageatlas.com/?p=4064062), €99 |
| Kelciour German | Word audio, sentences; sentence audio unknown | [page](https://kelciour.notion.site/German-167745ea252080e4b7cbc1bba3d48314) (search result) |
| ÜBERDeck Lite, German | Sentence audio named; word audio not | [2026](https://forums.ankiweb.net/t/uberdeck-lite-free-german-deck-200-cards-a1-a2-audio-sentences-beautiful-design/68453), seller's post |
| Spanish 5,000 frequency deck | None | [Migaku](https://migaku.com/blog/spanish/best-spanish-anki-decks) (search result; sells a rival) |

`[INFERRED]` Word plus sentence audio is an established pattern in Japanese decks at least; elsewhere unknown. Template order decides which comes first, and Kaishi's lists the word first. Two forms exist: separate fields, and several `[sound:]` tags in one field ([2025](https://forums.ankiweb.net/t/click-on-texts-to-play-multiple-audio/67494), with German Goethe decks mentioned).

**Do people care?** `[A][SAID]` About 5 threads concern several sounds, each with 2–10 posters, mostly people scripting cards: play in sequence on click (above), [play one at random](https://forums.ankiweb.net/t/how-to-get-several-audio-files-in-one-field-to-play-randomly/67521) (2025), [several recordings for listening](https://forums.ankiweb.net/t/multiple-audio-cards/48875), as a poster says Memrise did (2024, `[OLD]`), [replay all](https://forums.ankiweb.net/t/resolved-play-all-media-option-in-controls/50391) (2024, `[OLD]`), and a [repeat count](https://forums.ankiweb.net/t/option-to-set-how-many-times-each-mp3-plays-during-auto-advance/66928) (search result). About 4 titles want *less*: [replay only the back](https://forums.ankiweb.net/t/replay-audio-replays-both-front-and-back-would-only-like-to-hear-the-back/5144), [a key for back audio](https://forums.ankiweb.net/t/is-there-a-shortcut-key-to-play-only-the-back-side-audio/58997), no front audio on the back (search results).

**Importers.** I found **no complaint** about any app keeping only one sound, which may only mean few tried.

**Verdict.** `[INFERRED]` Hardly anyone talks about it directly. Its weight would come from the decks people import, which forums can't measure.

**Fit with seconds.** `[INFERRED]` Word then sentence audio lengthens a back, though nobody here measures it.

### 5. Sync's status

**Knowing it's done, in iCloud apps.** `[N][SAID]` The largest count in this report:
- [Apple Photos, 2018](https://discussions.apple.com/thread/8486157) `[OLD]`: **394 "me too"** on not seeing sync in progress. A reply points to a progress bar in Photos.
- Infuse, at least 6 threads, 2019–2025, each small: [indicator](https://community.firecore.com/t/icloud-sync-indicator/18314) (1 like); [is my backup complete](https://community.firecore.com/t/if-using-icloud-sync-how-do-i-know-my-cloud-backup-is-complete/35213) (2021, before a device reset; answered by a "Last Updated" line); "When is it happening?" (3 replies, 438 views); progress bar (0 replies, 217 views); home-screen status (2 replies, 100 views, 2025). Figures for the last three are from a related-topics list.
- [DEVONthink, 2020](https://discourse.devontechnologies.com/t/how-do-you-know-when-initial-icloud-database-upload-has-completed/60405) `[OLD]`: "complete" doesn't mean uploaded, and no reliable way to tell was given.
- [Ulysses, 2018–19](https://talk.macpowerusers.com/t/ulysses-having-issues-with-icloud-sync-15-20-groups-with-sheets-not-downloading/9662) `[OLD]`: 8+ posters, mainly wanting sync to be dependable and clear; some left it.

`[INFERRED]` People ask at set-up moments: first upload, new device, before a reset.

**Silent failure hurts flashcard users.** `[N][SAID]` Pleco: [lost cards when iCloud was switched off](https://www.plecoforums.com/threads/lost-all-my-flashcards-when-icloud-drive-switched-off.4632/latest). Mental Case: [sync switched off unasked](https://mentalfaculty.tenderapp.com/discussions/suggestions/10354-my-iphone-studies-app-cloud-sync-was-switched-off-not-by-me-after-turning-on-mac-studies-app-sync), and scheduling not carried over. All search results, with few people.

**In Anki** `[A][SAID]` (it syncs through AnkiWeb, not iCloud). About 8 of 10 results in one search are stuck or timed-out syncs, so failure more than display. On display: [spinner gone](https://forums.ankiweb.net/t/sync-animation-no-longer-occurs-2-18-3/45601) (2024, `[OLD]`, 5 posters, 2 want clearer feedback, 2 don't mind); [users review without knowing media still syncs](https://forums.ankiweb.net/t/review-screen-should-inform-of-ongoing-media-syncs/61334) (2025, 5 posters; 1 hadn't understood the icon; the developer suggests a message on missing media).

**A progress bar specifically.** Few ask. `[SAID]` Beyond Photos and Infuse, Dropbox's removal of "time left" drew [almost 20 pages of complaints](https://www.dropboxforum.com/discussions/101001014/time-left-in-sync-has-been-removed-from-the-dropbox-desktop-app/332451/replies/344202) (search result, about 2019, `[OLD]`, large files). `[INFERRED]` Mostly people ask a yes or no, "is it done?", and percent only for big transfers.

**What apps can know.** `[CLAIMED]` [Ulysses](https://help.ulysses.app/subscription-synchronization/synchronization-issues) says its insight into iCloud is limited and it can't force a sync. [QuickPlanX](https://quickplanx.pages.dev/docs/sync/troubleshooting/assess) says timing is the system's (search result).

**iCloud space.** `[CLAIMED]` [Apple](https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase.md): private data counts against the user's quota (search result). Ulysses says that over the limit it can't sync. **I found no user worried about a flashcard or similar app's iCloud share.** The Pleco ["iCloud storage" thread](https://plecoforums.com/threads/icloud-storage.3411) (2012, `[OLD]`) just asks for sync.

Size worries do appear where a limit bites: [Anki's 250 MB collection limit](https://forums.ankiweb.net/t/how-can-i-see-my-storage-usage-and-quota/13725) (2021, `[OLD]`, 6 posters, and a confusing usage figure); about 8 of 16 results in one size search. One user [asks how to shrink a 3.6 GB collection](https://forums.ankiweb.net/t/anki-size-tips-lagging-issues/69800) (May 2026).

**Verdict.** `[INFERRED]` A common small irritation, with one big count from Apple's own app. Not a dealbreaker, but silent failure can cost trust. Space is a concern only once someone hits a limit.

**Fit with seconds.** `[INFERRED]` Nothing here slows a card. People look for it at set-up, away from reviewing.

## Words people use

Paraphrased except the one quote above (see Blockers). The links are in Findings.
- Free review: finished for now; I want to go again; nothing works; cram; preview; without affecting SRS.
- Formatting: bold and red gone; can't tell if it's bold; speed of Markdown (Mochi's listing).
- Typing: near enough isn't enough; lying to myself; no time or patience; forces me to be specific; firetruck becoming firetrick.
- Sounds: all or nothing; only the first plays; random clip for listening.
- Sync: no idea if it's working; only the last completed sync; would feel better if it did or didn't work.

## Evidence against

- **Against free review:** forum regulars repeatedly discourage cramming, and say four weeks is enough for normal scheduling. One [advises leaving rescheduling on](https://forums.ankiweb.net/t/do-filtered-decks-have-an-effect-on-fsrs/60365), since unlogged study affects memory unseen by FSRS. A reply there asks why anyone would want it. So askers may be beginners who adapt: the 2024 poster later accepted Anki's approach.
- **Against formatting:** [one user wants to paste without formatting](https://forums.ankiweb.net/t/paste-without-formatting/47709); [bold can break MathJax](https://forums.ankiweb.net/c/anki/card-design/6.md?page=2) (search result); embedded HTML bloats decks, by about 70% in one creator's estimate.
- **Against typing:** the research effect is tiny. Against that, typing's fans report catching errors self-grading misses, which the research doesn't test.
- **Against sounds mattering:** few threads, and some want less audio. Against dismissing it: premade decks may hold many such cards whatever forums say.
- **Against sync status:** [one user asks to turn off "sync complete" notices](https://forums.ankiweb.net/t/request-add-an-option-to-disable-sync-complete-notifications/70238) (June 2026); 2 posters in the spinner thread don't mind; failures, not display, fill the threads. The 394 count is 8 years old, for a photo library far bigger than cards.

## Blockers

- **No usage data:** Anki publishes none that I found. Lucas could count, over the Anki packages he already holds, how many sides have two or more sounds, by deck, and how many cards use bold, italics or color and `{{type:}}`. That's the best evidence for items 2, 3 and 4, and it needs no site.
- **AnkiWeb add-on pages** rendered empty for reading, so no ratings; I saw no download numbers anywhere. Lucas could open add-on pages for type-answer and Markdown tools and note their ratings.
- **Reddit:** only snippets, marked second-hand. Search results listed Reddit mirrors; I opened none, per the brief.
- **Refused or empty:** Brainscape and Quizlet help (403); `forum.remnote.io` (redirect loop); RemNote's and Brainscape's feature boards and Kelciour's Notion pages (empty, so no vote counts); Dropbox's thread (title only). Lucas could open the two boards for vote counts.
- **Apple's documents** on widget input and notification text replies weren't read: the search returned only third parties.
- **Premade deck layouts** beyond Kaishi are unverified; I downloaded none.
- **Quoting:** my rules allow one short quote per report, stricter than the brief, so "Words people use" is paraphrased. A session without that limit could copy originals from the links.
