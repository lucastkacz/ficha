# 27 launches
Sources read: 58, plus 8 HN search listings (27 HN threads, 5 Product Hunt pages, 20 developer, press or forum posts, 6 Apple pages). Covered from 2014 to 2026.

Method: HN threads were read through the public Algolia API and are linked at news.ycombinator.com. Comment counts are rough, from a summarizing fetch of each whole thread. Points are as of 2026-11-05. Almost no flashcard launch states revenue, so points here aren't sales.

## Findings

### Which launches worked, with numbers

**A plain new flashcard app usually falls flat on HN.** [INFERRED from counts] Of the top 50 of 388 hits for "show hn flashcards" ([listing](https://hn.algolia.com/api/v1/search?query=show%20hn%20flashcards)), 41 have 10 points or fewer and the median is about 3. The listing favors high scores, so the true median is likely lower.

| Kind of launch | Points / comments, year |
|---|---|
| Content or tool for a narrow, mostly developer, need | [AWS cards](https://news.ycombinator.com/item?id=27264500) 365/118, 2021, free; [LeetCode scheduler](https://news.ycombinator.com/item?id=40173237) 206/100, 2024; [Code Cards](https://news.ycombinator.com/item?id=13521066) 152/52, 2017; [Fata](https://news.ycombinator.com/item?id=48489163) 124/53, 2026, about $13/month |
| Tools that feed or improve Anki | [Anki AI Utils](https://news.ycombinator.com/item?id=42534931) 253/43, 2024; [Ankify](https://news.ycombinator.com/item?id=31294306) 180/62, 2022; [MDAnki](https://news.ycombinator.com/item?id=22385408) 179/72, 2020; [Anki-LLM](https://news.ycombinator.com/item?id=45790443) 60/23, 2025 |
| General apps with a clear idea | [Ginkgo Notes](https://news.ycombinator.com/item?id=42317393) (cards by email) 244/94, 2024; [21st Night](https://news.ycombinator.com/item?id=27662266) 123/128, 2021; [Zorbi](https://news.ycombinator.com/item?id=27863409) 118/62, 2021; [CleverDeck](https://news.ycombinator.com/item?id=14605313) (iOS) 108/96, 2017; [Mochi](https://news.ycombinator.com/item?id=20029466) 91/31, 2019; [Flash Notes](https://news.ycombinator.com/item?id=39962415) (iOS, Mac) 82/25, 2024 |
| Flat: native or Anki-compatible | [Funky Flashcards](https://news.ycombinator.com/item?id=46205560) 6/2, 2025; [Koshka](https://news.ycombinator.com/item?id=43278688) 5/2, 2025; [Feyn](https://news.ycombinator.com/item?id=41467655) 7/1, 2024; [Owl](https://news.ycombinator.com/item?id=43573453) 14/15, 2025; [Discito](https://news.ycombinator.com/item?id=48910518) (FSRS-6, iOS) 1/0, 2026 |
| Flat: new delivery channel | [flashcasts](https://news.ycombinator.com/item?id=39777720) (podcast feed) 3/1, 2024; [FlashTabs](https://news.ycombinator.com/item?id=9032444) (new tab) 10/1, 2015 [OLD]; [Yeerodite](https://news.ycombinator.com/item?id=24910878) (passive learning) 7/1, 2020 [OLD]; [Orange Crumbs](https://news.ycombinator.com/item?id=49109957) (Anki while reading HN) 3/0, 2026; [Loudwalk](https://news.ycombinator.com/item?id=50209300) 4/1, 2026 |

**Mac menu-bar apps do well on HN when they solve one specific, felt problem.** [INFERRED, 50 hits scanned] [Claude usage meter](https://news.ycombinator.com/item?id=46544524) 161/49, 2026; [MeetingBar](https://news.ycombinator.com/item?id=23991111) 131/54, 2020 [OLD]; [Nightwatch](https://news.ycombinator.com/item?id=49952148) 89/28, 2026. All three are open source. Most of the [listing](https://hn.algolia.com/api/v1/search?query=show%20hn%20menu%20bar%20app%20mac&tags=story) got 1 to 5 points.

**A paid Mac app can still draw a big thread.** [Godspeed](https://news.ycombinator.com/item?id=39756325), 328/223, 2024, $150 once or about $8/month [CLAIMED in thread]. About 10 to 12 comments object to the price, 5 to 6 defend it. No sales stated.

**Product Hunt flashcard launches are small.** [FlashCard](https://www.hunted.space/product/flashcard) 12 upvotes, 20 comments, #27, "Anki, but simpler", macOS, free; [StackCards](https://www.hunted.space/product/stackcards) 14, 16, #62, iOS, offline, lifetime purchase; [Repetra](https://hunted.space/product/repetra) 4, 3, #160. These come from a third-party tracker, undated. I found no stated revenue in about 12 flashcard launches seen.

**Sales from small Mac launches** [SAID by each maker]:

| App | Result | Channel |
|---|---|---|
| [Wins](https://news.ycombinator.com/item?id=38388608), 2023 | 1,612 licenses, $9,485 in 15 months; 701 from its site, 911 unnamed | "I don't know how to market or promote" |
| [TableFlip](https://christiantietze.de/posts/2019/05/mac-app-store-proceeds) [OLD 2019] | 1 to 2 copies a day after one post and one tweet | Suspected store search |
| [DisplayBuddy](https://www.starterstory.com/stories/i-launched-a-mac-app-with-zero-advertising-800-customers-in-first-8-months), menu-bar, $3.99 [OLD 2021] | 800+ customers in 8 months, about $5,000; figures disagree on the page; site sells memberships | Retweets, an iMore review, a podcast, then Google; cold press mostly unanswered |
| [Redacted](https://soff.es/blog/redacted-for-mac-launch), $4.99 [OLD 2015] | Top of Product Hunt, 538 upvotes; #8 top paid in the US with 59 US units, [$302 first-day profit](https://www.macrumors.com/2015/05/07/redacted-mac-app-profits/) | Twitter video, Product Hunt |
| [ExtraBar](https://www.producthunt.com/p/extrabar/one-month-later-380-users-4-major-updates-and-extrabar-is-just-getting-started), about 2026 | 380 users in a month | Product Hunt; a known r/macapps user's review |
| [Chunk](https://hackernoon.com/lite/i-turned-a-failed-product-hunt-launch-into-a-top-3-win-on-a-budget), menu-bar, 2025 | 10 upvotes, then about 300 and #3 on relaunch; downloads nearly doubled | Video, edited screenshots, comment swaps |
| [Noticky](https://www.indiehackers.com/product/noticky), $6, undated | 15 sales in 3 days, 150+ in 10 weeks; Product Hunt almost nothing | Search snippet only |
| [Primitive](https://medium.com/@fogleman/product-launch-post-mortem-primitive-for-macos-2eee316134ad) [OLD] | 70% of revenue in 3 days | HN front page; search snippet only |

### Why they worked or fell flat

- **A first flat post isn't final** [4 launches]. CleverDeck [3 points](https://news.ycombinator.com/item?id=14554068), then 108 a week later. Zorbi [6](https://news.ycombinator.com/item?id=27852021), then 118 a day later. 21st Night [1](https://news.ycombinator.com/item?id=26388502), then 123 three months later. Chunk 10, then about 300.
- **Page quality is what a maker blames** [SAID, 1, Chunk]: no video, raw screenshots, no branding.
- **Replying in the thread seems to help** [INFERRED, 3 threads: AWS cards, Godspeed, Nightwatch].
- **Product Hunt gives a spike and feedback more than sales** [SAID, 2 makers plus Redacted's numbers]. [HiyokoBar](https://dev.to/hiyoyok/what-i-learned-building-hiyokobar-a-menubar-app-that-does-one-thing-per-click-2a4h), 2026, whose post links its own products, calls it worth doing once for feedback.
- **The spike decays fast** [SAID, 3 apps]. [Unread](https://mjtsai.com/blog/2014/07/28/a-candid-look-at-unreads-first-year/), iOS [OLD 2014], made half its first-year sales in five days; a store front-page feature slowed the fall without a spike.
- **Praise for offline, no account and one-time purchase is real, on a tiny launch** [SAID, StackCards' commenters]. They also asked for Anki import and spaced repetition.

### What HN commenters say to a new flashcard app

Counted across 15 threads with real discussion: Ginkgo, Flash Notes, CleverDeck, 21st Night, Zorbi, Fata, Owl, [FlipCards](https://news.ycombinator.com/item?id=45128621) (42/25, 2025), the LeetCode scheduler, Mochi, Ankify, Anki AI Utils, AWS cards, [Hibou](https://news.ycombinator.com/item?id=10433615) [OLD 2015], [Manabi Reader](https://news.ycombinator.com/item?id=36674259) (105/57, 2023). [SAID; tally INFERRED]

| Objection | Threads | Peak comments |
|---|---|---|
| Why not Anki? It's free, how do you differ? | 8 of the 11 that compete with it | LeetCode about 12, FlipCards about 11 |
| Paying: too high, unclear, wants a trial, no subscription | about 9 of 15 | Manabi about 10 |
| Memorizing isn't understanding, or making cards is the learning | about 8 | Zorbi, Anki AI Utils about 5 |
| Unclear page: jargon, no comparison, "screams GPT" | about 7 | FlipCards about 6 |
| Lock-in: export, Anki import, open source | about 7 | Zorbi about 5 |
| Missing platform, usually Android | about 6 | |
| Which algorithm? Why not FSRS? | about 5 | Ginkgo, FlipCards about 5 |
| Offline or private storage | about 4 | Mochi about 3 |
| Account needed to try | about 3 | FlipCards about 5 |

- **A hidden price costs trust** [SAID]. Owl's maker admitted no business model existed, and 2 commenters held back from signing up. Ginkgo drew about 3 on price and about 3 asking for a trial.
- **Missing Anki import was called a dealbreaker** [SAID, 1, 21st Night's first post].
- **Inflated claims get checked** [SAID, 1, Fata's "10000+ developers"].
- **Email split Ginkgo's thread**: about 10 against (inbox overload), a few for. About 5 wanted active recall; about 3 wanted push, iMessage or WhatsApp.
- **Menu-bar objections differ**: clutter, belongs in a widget (1, Nightwatch); is it safe, since it reads the Keychain (3 to 4, Claude meter, whose post led with being signed and notarized); Gatekeeper warnings on an unnotarized build (2+, MeetingBar).

### What indie Mac developers say brought sales

- **Word of mouth, and marketing major versions to existing customers** [SAID, [VirtualHostX](https://tyler.io/2014/07/28/a-candid-look-at-the-financial-side-of-building-mac-apps-on-your-own/), OLD 2014]: about $200,000 lifetime, almost no ads; raising the price from $7 to $49 didn't cut sales.
- **Store search** [SAID, 1 Mac app; [TableFlip's stats](https://christiantietze.de/posts/2019/06/tableflip-app-store-stats/) credit search for all attributed sales, but only a third could be attributed; OLD 2019]. On iOS, [a dictionary app](https://news.ycombinator.com/item?id=48321215) reports almost all downloads from search (search snippet).
- **Press**: reviews mattered when reached through a contact, not cold (DisplayBuddy). Unread's maker thought influential reviews may matter more than a store feature. [Roddy Munro](https://roddymunro.substack.com/p/was-2022-my-best-indie-year-yet) saw an install spike from an iMore list, at MRR under $100 (OLD 2022). **I found no developer naming MacStories as a sales source with numbers**, in 3 searches.
- **Setapp**: no payout numbers from any developer. DisplayBuddy reports 6,000+ users there. A [Mac Power Users thread](https://talk.macpowerusers.com/t/developer-s-motivation-for-participating-in-setapp-bundlehunt-etc/28045), March 2022, about 11 people, names discovery, recurring income and later full-price buyers, against cannibalized sales and price perception. Company scale, [OLD 2018](https://www.dice.com/career-advice/setapp-proves-worth-developers): 15,500 paying of about 300,000 users.
- **Newsletters and sponsorships**: TableFlip announced a sponsorship; I couldn't find the result. Search found rates, such as [$1,200 a week at Swift by Sundell](https://john-sundell.squarespace.com/sponsor), and no outcomes.
- **YouTube**: no Mac developer stating an effect, in 2 searches.
- **Reddit** (second-hand only): r/macapps comes across as good for feedback and early users, weak for sales. In a [search snippet](https://clearfounder.com/presenting-launch), a post in the sub's monthly top 5 registered no sales of its own, with 77% of $520 coming after Product Hunt.
- **Group sales**: [Indie App Santa](https://roddymunro.substack.com/p/was-2022-my-best-indie-year-yet) gave a one-day download jump for an app made free. [Indie App Sales](https://512pixels.net/2024/11/indie-app-sales-2/) had 400+ apps in November 2024; no results published.
- **Direct versus store**: among multi-channel Mac developers, [52% of revenue is direct, and about 20% rely on the store alone](https://state-of-mac-software.pages.dev/market.html) (MacPaw survey of about 400, via an independent 2026 page; MacPaw owns Setapp).
- **Charts are thin**: Redacted's 59 US units reached #8. [AnkiMobile](https://apps.apple.com/us/app/ankimobile-flashcards/id373493387) shows #1 in Education top paid at $24.99, with 2.4K ratings [CLAIMED, store page, read 2026-11-05].

### How App Store search and keywords bring customers here

- **Search leads, on iOS.** Apple says [nearly 65% of downloads follow a search](https://www.macrumors.com/2025/12/18/app-store-search-results-more-ads-2026/) (December 2025) [CLAIMED]. [Sensor Tower: 70% for non-games, 2020](https://sensortower.com/blog/app-store-download-sources-report-2021) [OLD, vendor, snippet]. No Mac figure found.
- **What ranks.** [Apple](https://developer.apple.com/app-store/search/): "text relevance" (title, subtitle, keywords, primary category) plus "user behavior" (downloads, ratings, reviews). Keywords: 100 characters, not repeating the name.
- **Rival names are out.** Apple lists "Competing app names" and unauthorized trademarks as not to include, and calls improper keywords a common reason for rejection. [Guideline 2.3.7](https://developer.apple.com/app-store/review/guidelines/) bars packing metadata with "popular app names". I'm not a lawyer; angle 26 covers the name.
- **Ads now eat organic results on iOS** [SAID, 2 developers, [via Pixel Envy, 2026-05-29](https://pxlnv.com/linklog/another-ad-app-store-search/)]. After Apple's second search ad, a dictionary app's total stayed flat, organic fell, paid rose, spend nearly doubled.
- **The Mac may have no such ads** [INFERRED, unconfirmed]. A [November 2025 forum question](https://developer.apple.com/forums/thread/806737), unanswered, reports Apple's ads site won't take a Mac app. Another [quotes Apple requiring an iPhone or iPad app](https://developer.apple.com/forums/thread/693552) (snippet, undated).
- **Category demand** is only sellers' estimates: [165k to 220k monthly searches](https://myapptemplates.pages.dev/app-ideas/flashcard-spaced-rep) from an app-template seller (snippet, page now 404); [$406k MRR](https://trustmrr.com/startup/flashcards-learn-study?metric=mrr) for one flashcard app (snippet, unverified). Weak evidence.
- **Sources show without app code.** Apple's [acquisition page](https://developer.apple.com/help/app-store-connect-analytics/acquisition/acquisition/) splits search, browse, web and app referrers. [Campaign links](https://developer.apple.com/help/app-store-connect-analytics/acquisition/campaign-links) need no code and appear from 5 first-time downloads. Promo-code downloads show as "Unavailable".

### Which launch would be honest for a small paid app with no account or analytics

What the evidence supports for any such app, not advice on one. [INFERRED unless marked]

- **Price and trial up front.** Hidden prices drew the most avoidable complaints. Funky Flashcards states $14.99, 7 days, no refunds outright. Apple allows a [free timed trial as a free non-consumable IAP named "XX-day Trial"](https://developer.apple.com/app-store/review/guidelines/).
- **Trying without signing up** answers an objection in 3 threads.
- **Saying how it relates to Anki**, the first question in 8 of 11 threads. Funky Flashcards says "completely independent of Anki" while reading its decks [CLAIMED].
- **Only claims that survive checking.** A site tracker can break the claim: [one privacy app's maker](https://www.producthunt.com/p/panicmode/staying-honest-about-privacy) disclosed an ad script as "a bit ironic". [Póca](https://pocareader-web.pages.dev/making) names its one analytics tool. Manabi's maker said in the thread that analytics were removed.
- **Measuring without the app**: App Store Connect sources, one campaign link per post, launch-date comparison, asking buyers by email. It stays approximate, as TableFlip's third shows.
- **Modest numbers stated as modest.** Wins' public 1,612 licenses earned 119 points and pricing advice: about 10 of about 25 comments said its price was too low.

## Words people use

Via summarizing fetches, so check before quoting further.
- "So basically the same features as Anki except it's paid?" ([21st Night](https://news.ycombinator.com/item?id=27662266))
- "I really dislike the 'per month' monetization." ([CleverDeck](https://news.ycombinator.com/item?id=14605313))
- "the text on the website screams GPT and is off-putting." ([Flash Notes](https://news.ycombinator.com/item?id=39962415))
- "35/yr for an app you may use everyday is spot on." (same)
- "Email is the only thing I have conditioned myself to reliably check" ([Ginkgo](https://news.ycombinator.com/item?id=42317393))
- "$150 for a todo app... ouch." ([Godspeed](https://news.ycombinator.com/item?id=39756325))

## Evidence against

- **HN points may say little about buyers.** Many top launches are free or open source, and HN skews to developers who distrust closed tools. Only Primitive and Wins tie HN to sales.
- **"Why not Anki?" isn't universal.** Flash Notes, Fata and Hibou drew almost none, and Zorbi's thread also had people calling Anki overdue for replacement.
- **Paying isn't always the objection.** Flash Notes' $35 a year was called right, Godspeed has defenders at $150, and AnkiMobile tops its paid chart at $24.99.
- **Against "search is everything" on the Mac:** Wins sold 701 licenses from its own site, DisplayBuddy names Google, and direct is 52% of multi-channel revenue.
- **Against "a flat launch means a weak app":** four relaunches jumped sharply. Chunk's used comment swaps, so upvotes can be organized.
- **A new delivery channel is neither enough nor doomed.** Ginkgo's email reached 244 points; five similar ideas stayed at 10 or under.
- **Recency:** most Mac sales evidence is from 2014 to 2021. Silence on MacStories, YouTube and newsletters may reflect what's written up, not what works.

## Blockers

5 blockers.
- **Reddit** refused, as `README.md` says; r/macapps appears only second-hand. The Reddit session `blockers.md` proposes could search it for "sales" and "launch".
- **Indie Hackers, Medium, clearfounder.com, Thinktapwork's blog**: 403 or closed connections, 3 tries on clearfounder (Noticky, Primitive, a $300,000 solo Mac AMA, a $1,000/month sound-effects app). Lucas could open these and paste the text.
- **Setapp's 2024 survey PDF** came back as bytes; PDF rendering isn't installed. Pasted text would add channel figures.
- **App Store charts and search, Mac above all**, weren't fetchable. Lucas could search "flashcards" and "anki" in the Mac App Store and send the top 20. Keyword popularity needs an ASO tool's account.
- **Product Hunt's category and Mochi pages** returned 404; hunted.space omits dates.
