# Developing Ficha

How to build Ficha, try a change and work on it, one section for each task. The [README](../README.md) explains the app itself.

## Run it

Requires macOS 26 and the Xcode that [`.xcode-version`](../.xcode-version) names, the one CI runs, so a `make check` that passes on your Mac passes on CI too. `make check` stops first when your Mac's Xcode is another one, as when the App Store updates it on its own. To move to a newer Xcode, update your Mac's Xcode and the file together. The iPhone app also needs that Xcode's iOS platform (Xcode › Settings › Components).

```bash
make bootstrap   # installs XcodeGen, shellcheck and actionlint
make run         # builds and opens Ficha Dev, the development app
make upload      # from main: uploads the real Ficha to TestFlight, signed with your team
```

The real Ficha comes from TestFlight, as "Upload to TestFlight" below says, and runs in the App Sandbox, as in the Mac App Store ([ADR 0018](adr/0018-the-app-and-the-cli-each-run-in-a-sandbox.md)). It keeps its cards in its App Group's folder, which its `ficha` and its widget share: `~/Library/Group Containers/<your team's ID>.com.lucastkacz.ficha/Ficha/`. Its preferences are in its sandbox's own folder, `~/Library/Containers/com.lucastkacz.ficha/`. Its last build without the sandbox moved Lucas's data there from `~/Library/Application Support/Ficha/` ([#309](https://github.com/lucastkacz/ficha/issues/309)):

- It copies the database through SQLite's online backup, and `Images/`, `Sounds/` and `Backups/` as files, into a hidden folder beside the new one. It checks what it copied (SQLite's integrity check, the same rows in every table, the same files), and only then gives it the folder's name, unless the old database changed meanwhile, as when a `ficha` command writes, which SQLite's `PRAGMA data_version` tells.
- The old folder stays as it was. While the move fails, the app and its `ficha` work from the old folder, and the next launch tries again, first removing any hidden folder a move that was killed or crashed left.
- From then on, it keeps all its preferences in `Preferences.plist` in the new folder, written again as one changes. The sandboxed Ficha reads them in at the first launch that finds the file, and never again.
- SQLite's online backup and its integrity check are SQLite's documented ways to copy a database in use and to check it. The rest is our own: the hidden folder renamed into place, the comparison of rows and files, `PRAGMA data_version` read to catch another process's write, and the preferences carried in a plist that's read in once.
- The log's `data move` category says what the new folder held once it matched, or why the move failed:

```bash
/usr/bin/log show --last 1d --info --predicate 'subsystem == "com.lucastkacz.ficha" AND category == "data move"'
```

Ficha Dev is a separate app, with its own menu-bar icon, data and preferences, so it runs next to Ficha without touching your cards.

Ficha Dev runs in the App Sandbox too, signed with Apple Development and your paid team, whose ID it takes from `iPhone/Local.xcconfig`, as [On the iPhone](#on-the-iphone) explains. Without that file, as in CI, `make build` builds Ficha Dev unsigned, which checks the code but can't run in the sandbox, and `make run` stops and says so. A new worktree hasn't the file either, since git ignores it: copy it there from the main folder.

Its cards are in its App Group's folder, which its `ficha` shares: `~/Library/Group Containers/<your team's ID>.com.lucastkacz.ficha.dev/Ficha Dev/`, with the database, `Images/`, `Sounds/` and `Backups/`, laid out as the real Ficha's. Its preferences are in its sandbox's own folder, `~/Library/Containers/com.lucastkacz.ficha.dev/`. Before its sandbox, Ficha Dev kept its cards in `~/Library/Application Support/Ficha Dev/`, which stays as it was: the sandboxed Ficha Dev started empty, and its debug menu loads the sample cards.

Ficha Dev's menu also has "Debug", to try a change in minutes: it loads sample cards, written by hand, moves Ficha Dev's time forward and checks for an appearance right away. Its time keeps running from there, stays ahead when Ficha Dev restarts, and Ficha Dev's `ficha` runs on it too. The real Ficha has no such menu and always runs on the system's time. To start Ficha Dev over, with no cards and on the system's time, quit it and move its folder, `Ficha Dev` in its App Group's folder, to the Trash, and start over in iCloud too, as "Sync through iCloud" below says, or iCloud brings the cards back.

### Sync through iCloud

Ficha Dev syncs its cards through your iCloud, in the Development environment of Ficha's container, `iCloud.com.lucastkacz.ficha`, apart from the real Ficha's, which will sync in Production ([ADR 0017](adr/0017-cards-sync-through-the-users-own-icloud.md)). iCloud and push are restricted entitlements, which need a provisioning profile: with your team's ID there, `make build` has Xcode make one through the account in Xcode › Settings › Accounts, and register the Mac with your team the first time. The real Ficha builds the same code with sync off, until it holds those entitlements ([#318](https://github.com/lucastkacz/ficha/issues/318)): signed with the team, it holds none of iCloud's, and CloudKit stops an app that asks for a container without them.

It syncs while it runs: it catches up on what changed in iCloud as it starts, sends each change as it's made, by the app or by its `ficha`, and fetches what another device changed when iCloud pushes it. CloudKit's engine, asked to fetch, asks iCloud nothing unless a push came, so to fetch right away Ficha Dev starts its engine again, catching up first, which is our own. It syncs only while the Sync tab's switch is on, which deleting Ficha's data in System Settings › iCloud turns off too: the cards stay, and turning it on sends again all those that sync ([ADR 0017](adr/0017-cards-sync-through-the-users-own-icloud.md)). A restore turns it off too, and turning it on replaces the cards that sync on the other devices with the restored ones. Under the switch, the Sync tab chooses every card or only those in the decks ticked in its tree, and in the decks inside them ([ADR 0020](adr/0020-selective-sync.md), as [ADR 0024](adr/0024-cards-live-in-decks-and-tags-label-them-as-in-anki.md) changes it): a card that stops syncing leaves iCloud as a record holding its deck alone, and stays on each device. A Mac that held cards before it ever synced starts with the switch off, as Lucas's real Ficha does after the update that brought it; a new install, Ficha Dev's sample cards and a `FICHA_DEV_SCRATCH` run start on a database with no cards, so they sync.

The images and sounds sync in a zone named `Files`, and the cards in the newest cards' zone iCloud holds: `Cards`, the one before #317, or one a device made, named after when and why, such as `Cards.1761650000000.restore`. No name is used twice: a zone deleted and saved again under its own name reaches the other devices as changed, never deleted, as [#316](https://github.com/lucastkacz/ficha/issues/316) probed. A device that starts syncing, in a new account or after a deletion of Ficha's data, fetches first and joins the newest zone, or makes one, `Cards.<time>.new`, when iCloud holds none. Turning sync on after a restore makes `Cards.<time>.restore`, which each device that last synced in an older zone takes in place of its cards, after saving a copy of them, "Before taking iCloud's copy", in its Backups; a device that never synced in that account joins it. A device deletes the zones older than its own. The names and these rules are our own (`Packages/FichaKit/Sources/FichaData/ICloudZones.swift`).

Debug's "Second device" opens another copy of the cards, in `Ficha Dev-second-device`, beside Ficha Dev's folder, which syncs as one more device: "Cards…" opens its Cards window, and "Review now" its review panel. iCloud doesn't push a change to the device that made it, and both run on this Mac, so each fetches as soon as the other sent a change: our own stand-in for the push. "Sync now" sends what waits and fetches, on both. To start the second device over, quit Ficha Dev and move its folder to the Trash.

Starting Ficha Dev or its second device over brings their cards back from iCloud as they start, and loading the sample cards again adds a second copy of each to iCloud. To start over in iCloud too, quit Ficha Dev, move both folders to the Trash, and reset the Development environment in CloudKit Console (below), which deletes every record there and leaves the real Ficha's, in Production, as they are.

The log says what each device sent and fetched, and why it couldn't. zsh has a `log` of its own, so the full path:

```bash
/usr/bin/log stream --level info --predicate 'subsystem == "com.lucastkacz.ficha" AND category IN {"icloud", "sync"}'
```

What iCloud holds is in [CloudKit Console](https://icloud.developer.apple.com/), signed in with your developer account: Ficha's container, the Development environment, and its private database as your own iCloud account.

### The widget

Each app has a widget, "Next Card" in the widget gallery, which shows the card a review now would start with, or when the next one comes ([#308](https://github.com/lucastkacz/ficha/issues/308)). Its files are in `Widget/`, a WidgetKit extension in the app's `Contents/PlugIns`, sandboxed in the app's App Group, where it reads the database alone. It picks the card as review now does, by this Mac's cards per appearance, which the app hands it in the group's defaults, so it says to open the app until the app has run once. A click on it opens the app through a link of its scheme, the build setting `FICHA_URL_SCHEME` in both Info.plists, `ficha-dev://review-now?card=<id>&way=<way>` for Ficha Dev's, which starts a review now with that card; while the review panel is open, it comes forward instead, unless it's showing See more.

It stays up to date as WidgetKit documents: its timeline has an entry at each time what it shows changes as time passes, such as the next card's due time, and the app asks WidgetKit to reload it, within the budget of reloads WidgetKit gives a widget a day, only when what it shows changed: as the app launches, 30 seconds after a burst of changes to the database ends, the CLI's included, once the review panel closes, which holds reloads back while it's open, when this Mac's settings change, and after Debug moves Ficha Dev's time. The extension runs only while WidgetKit asks it for a timeline, so it listens to nothing. Ficha Dev's widget runs on Ficha Dev's time too, and its entries go on the system's, which WidgetKit's timeline runs on.

`make build` registers the extension with macOS at the build's path, without launching the app. When several builds registered it, as from several worktrees, macOS picks one, by rules Apple doesn't document: `pluginkit -m -p com.apple.widgetkit-extension -v | grep ficha` lists each with its path. The log says what the widget showed and when the app reloaded it:

```bash
/usr/bin/log stream --level info --predicate 'subsystem == "com.lucastkacz.ficha" AND category == "widget"'
```

### Upload to TestFlight

The real Ficha reaches your Mac through TestFlight, as the App Store build will ([#310](https://github.com/lucastkacz/ficha/issues/310)). Once a pull request merged, from the main folder, on `main`:

```bash
make upload
```

- It runs from `main` alone, with nothing uncommitted, and only when `main` is GitHub's, so each build is one of `main`'s commits. Anywhere else it stops and says why.
- It archives the real Ficha for Intel and Apple silicon, signed with Apple Development, into `.build/upload/`. The export signs it again with Apple Distribution and uploads it to App Store Connect, through the account in Xcode › Settings › Accounts, as Xcode's Organizer does: neither the repo nor CI holds a secret, and CI never uploads. When the export says "No Accounts", `xcodebuild` can't reach that account until Xcode refreshes its sign-in: open Xcode › Settings › Accounts, sign in again if it asks, and run `make upload` again, as [Apple's developer forums](https://developer.apple.com/forums/thread/744834) report.
- [`ExportOptions.plist`](../ExportOptions.plist) keeps each build to TestFlight's internal testers: such a build can't reach external testers or the App Store, so a version for the App Store will take an export of its own. It also keeps the build number as the Makefile sets it, `main`'s count of commits, which grows with each merge, as App Store Connect needs. The version, `MARKETING_VERSION` in `project.yml`, changes by hand.
- The app's Info.plist says Ficha uses no encryption that needs a declaration (`ITSAppUsesNonExemptEncryption`), so App Store Connect asks nothing about it.
- Once App Store Connect has processed the build, in some minutes, TestFlight's internal group gets it, and you install it from the TestFlight app. A build lasts 90 days.
- To check what the sandbox lets each part reach, read the archive's entitlements: `codesign -d --entitlements - .build/upload/Ficha.xcarchive/Products/Applications/Ficha.app`, and the same for its `Contents/Helpers/ficha`, `Contents/PlugIns/FichaWidget.appex` and `Contents/XPCServices/SVGDrawer.xpc`. Only the SVG drawer holds `com.apple.security.network.client`.

Archiving and exporting with `xcodebuild`, and the keys of `ExportOptions.plist`, are Apple's documented way (`xcodebuild -help` lists them). The check that `make upload` runs from GitHub's `main`, and the build number from git, are our own.

## On the iPhone

The iPhone app is on its way ([#97](https://github.com/lucastkacz/ficha/issues/97)). For now it's only Ficha Dev, which loads the sample cards the first time it opens and shows how many cards there are and how many are due. It needs iOS 26, on an iPhone: there's no iPad version. Its files are in `iPhone/`, and `make check` builds it for the simulator, as CI does.

Its appearances arrive as card notifications, which the app plans ahead ([ADR 0010](adr/0010-iphone-appearances-are-notifications-planned-ahead.md)): it asks whether it may send them the first time it opens, and plans again each time it opens or comes back to the foreground, when it also clears the ones iOS still shows. Each one brings a card, with buttons that show when you press and hold it: a new card whole, with "Got it", or a due card's front, with "Don't know", "Sort of" and "Know it". A button answers the card without opening the app or unlocking the iPhone, and the appearance's next card arrives right away, without sound. Tapping the notification only opens the app. To watch one arrive without waiting, press "Bring the next appearance now", under Debug, and lock the iPhone, or the simulator with ⌘L: the next planned appearance arrives 5 seconds later. While the app is in front, iOS doesn't show its notifications.

Debug also moves Ficha Dev's time forward, by the steps of the Mac's menu, so cards come due without waiting. Ficha Dev's time keeps running from there and stays ahead when the app opens again. Moving it counts the cards again and plans the appearances again, each notification at the real time that matches its appearance's time by Ficha Dev's: one whose time came already arrives a second later, while the app is in front, so to watch it, bring it with "Bring the next appearance now" and lock the iPhone. To start Ficha Dev over on the iPhone, with the sample cards and on the system's time, delete it and install it again.

It installs on your iPhone from the Mac, signed with your paid team, which signs Ficha Dev on the Mac too. The first time:

1. Xcode › Settings › Accounts: sign in with your developer account's Apple ID.
2. Write the team's ID in `iPhone/Local.xcconfig`, which git ignores, as a line like `DEVELOPMENT_TEAM = ABCDE12345`. The file is our own convention: `Signing.xcconfig` includes it with Xcode's `#include?`, which skips a file that isn't there, as in CI. Apple's developer site shows the ID in your account's Membership details, and Keychain Access as the Organizational Unit of your "Apple Development" certificate.
3. Connect the iPhone with a cable, unlock it and trust the Mac. On the iPhone, turn on Settings › Privacy & Security › Developer Mode, which restarts it.

Then, each time, with the iPhone unlocked, on the cable or on the Mac's Wi-Fi, from the folder where you wrote `iPhone/Local.xcconfig`:

```bash
make install-iphone   # builds Ficha Dev for the iPhone paired with this Mac and installs it
```

After the first install, trust the developer on the iPhone, in Settings › General › VPN & Device Management, before opening it. With `iPhone/Local.xcconfig` written, Xcode's Run button signs it too, with the `iPhone` scheme.

A free Apple ID's limits, apps that stop opening after 7 days and 3 such apps on the iPhone, don't bind a paid team. Ficha Dev opens until its provisioning profile expires, and installing it again, the same way, renews it and keeps its cards.

### In the simulator

After `make build-iphone`, these commands install Ficha Dev in the simulator that's running, open it, and show what it logged in the last 5 minutes:

```bash
xcrun simctl install booted ".build/DerivedData/Build/Products/Debug-iphonesimulator/Ficha Dev.app"
xcrun simctl launch booted com.lucastkacz.ficha.dev
xcrun simctl spawn booted log show --last 5m --info --predicate 'subsystem == "com.lucastkacz.ficha"'
```

- `booted` is the simulator that's running, which the Simulator app boots. With more than one running, simctl picks one of them, so name the one you want by its UDID instead, from `xcrun simctl list devices booted`.
- Without `--info`, the log leaves out the app's info lines, such as how many appearances it planned. Its first line, `getpwuid_r did not find a match for uid 501`, comes from the simulator and is harmless.
- The same command with `--predicate 'process == "usernotificationsd"'` shows iOS's side of the card notifications, among every app's. Each of Ficha Dev's requests that reached iOS is a `Forwarding addRequest: com.lucastkacz.ficha.dev` line, so `| grep -c 'Forwarding addRequest: com.lucastkacz.ficha.dev'` counts the notifications Ficha Dev handed iOS, which should add up to the app's "Planned … appearances" lines, plus one next card for each answer whose appearance goes on. That's iOS's own logging, which Apple doesn't document: a later iOS may word it otherwise.
- Locking the simulator, with ⌘L, makes the app active for a moment before it goes to the background, so what it does as it becomes active runs then too, such as planning again.
- To answer a card notification, swipe it left and press View, which shows its buttons. When Ficha Dev isn't running, iOS launches it in the background for the answer, so an answer logged from a new process ID while the app was running may mean it crashed: a bullet below says how to tell. Each answer logs `Recorded an answer from a card notification`, and whether the appearance goes on or is over. A rating for a card that isn't due within 20 minutes, how far an appearance looks ahead, is refused, and the log says why: "Bring the next appearance now" brings the next appearance early, with the cards it brings at its time. So to try the ratings, answer a new card with "Got it", which makes it due an hour later, press "Move forward 1 hour", under Debug, which takes the app's Due count above 0, and then bring the next appearance.
- To swipe a card notification away, swipe it left until it goes, or swipe it left and press Clear. iOS tells Ficha Dev, launching it in the background when it isn't running, and the app logs `Recorded a card notification swiped away`: its appearance is a snooze, and the next one comes after the separation, with the same cards. An appearance left alone is a snooze too, which the engine notes the next time the app plans. One that arrives while Ficha Dev is in front never shows, so it's one left alone: leave the app before it arrives.
- A crash writes nothing to the app's log, and iOS starts the app again for the next answer, so the log goes on from a new process ID as if nothing had happened. After each try, look for a crash report newer than the install: `ls -lt ~/Library/Logs/DiagnosticReports ~/Library/Logs/DiagnosticReports/Retired | grep 'Ficha Dev'` lists them newest first, as `Ficha Dev-<date>-<time>.ips` in the Mac's time, and each report's `pid` is the ID the crashed process has in the log. The file is a line of JSON, then the report as JSON, as Apple's [Interpreting the JSON format of a crash report](https://developer.apple.com/documentation/xcode/interpreting-the-json-format-of-a-crash-report) describes, and the thread with `"triggered": true` holds the frames where the app stopped. The command lists `Retired/` too because macOS moves the reports there later, as soon as a few hours after, which Apple doesn't document.
- To watch the app react to a change in its data, use one of its own debug tools: "Load the sample cards again", which [#107](https://github.com/lucastkacz/ficha/issues/107) will add, or, to watch it plan again meanwhile, "Bring the next appearance now" or one of the "Move forward" buttons. Claude's Bash commands can't reach the data otherwise, on purpose: the app's folder in the simulator has `Application Support/Ficha Dev/` in its path, and so has the name of the notification the engine posts when the database changes, which `notifyutil` would post. `.claude/settings.json` denies any Bash command with `Application Support/Ficha` in it, to keep Lucas's cards out of reach (CLAUDE.md), and that covers these too.

## The apps' texts

The texts each app shows live in its String Catalog, `App/Localizable.xcstrings` for the Mac's, `Widget/Localizable.xcstrings` for the Mac's widget and `iPhone/Localizable.xcstrings` for the iPhone's, which the builds compile but never fill. After changing a text, run `make strings` and commit the catalog with the change. Xcode's export, which builds both apps, brings in the new texts with their comments, and drops the ones the code no longer has, or marks them stale when they have plural variations. `make check`, and so CI, fails while a catalog is out of date, and shows how it differs.

When a text with plural variations changes, the export brings the new text in plain, without them: move the variations over from the stale entry by hand, delete the stale entry, and run `make strings` again, which should change nothing.

## Refining

What you capture waits in the inbox, with the cards you flag and the follow-ups: what you ask about a card in the review panel. To turn it into cards, open Claude Code in this repository's folder and type `/refine`. Claude goes through it ten items at a time and, following [the content guide](content-guide.md), proposes cards for each capture, with Both ways on those whose back leads to their front, a fix or a burial for each flagged card, one you keep forgetting included, front first or back first, how to add each expansion to its card, and new cards with its card's tags for each follow-up. Point it to an image or a sound file on your Mac, and it proposes the card and the side it goes on, and copies the file into Downloads, the one folder the sandboxed `ficha` reads from. It also tidies your tags and card types: ask it to rename, move, merge or delete a tag, pin it, color it or give it an emoji, or to make, rename or delete a type of your own, and it proposes each change with the cards it reaches. It writes only what you approve, through the installed Ficha's `ficha` command.

## The `ficha` command

Ficha ships with a command-line tool inside the app. Claude uses it to turn your captures into cards and to fix the cards you flag, and you can capture from a terminal with it:

```bash
/Applications/Ficha.app/Contents/Helpers/ficha capture "serendipia" --source "Un ensayo de Borges"
```

`ficha --help` lists its commands; each one prints JSON. `ficha unbury` brings back a card you buried. `ficha attach` puts an image or a sound file from your Mac on a side of a card, and `ficha detach` takes one off; `ficha approve`, `ficha approve-expansion` and `ficha fix` take them too. `ficha cards` says which cards go both ways, and `ficha approve` and `ficha fix` set it. `ficha tags` lists every tag with its counts, and `ficha tag` renames, deletes, pins and colors tags; `ficha types` lists the card types, and `ficha type` makes, renames, gives an emoji to and deletes your own. Each change syncs, as the Cards window's does. `ficha restore` lists the copies in Ficha's Backups folder, newest first, and `ficha restore <copy>`, with a copy's name, restores it, as the Backups tab in Settings does: only while Ficha isn't running, since it would go on with the cards it has open. On a Mac that syncs, it turns sync off, as the Backups tab does. To type just `ficha`, add an alias to `~/.zshrc`:

```bash
alias ficha="/Applications/Ficha.app/Contents/Helpers/ficha"
```

Each `ficha` runs in a sandbox of its own, so it reads the files it puts on cards from your Downloads folder alone: a file elsewhere is refused, with a message that says to copy it to Downloads. The names of the images and sounds Ficha holds work as before. The `ficha` inside Ficha Dev, which `make build` puts in `.build/DerivedData/Build/Products/Debug/Ficha Dev.app/Contents/Helpers/`, works on Ficha Dev's cards.

### Agents' runs of Ficha Dev's `ficha`

An agent that tries Ficha Dev's `ficha` runs it on a scratch folder of its own, so Ficha Dev's cards stay as they were:

```bash
FICHA_DEV_SCRATCH=agent-304 <Ficha Dev's ficha> capture "serendipia"
```

- `FICHA_DEV_SCRATCH=<name>`, with letters, digits, `-` and `_`, makes Ficha Dev's `ficha` open the cards in `Scratch/<name>/`, in Ficha Dev's App Group's folder: a data folder of its own, which starts empty, on the system's time. The open Ficha Dev doesn't hear it, since the notification of a change is named after the database's path. Only Ficha Dev's build reads the variable, and the folder has to be in the group's folder, since the sandbox lets the CLI write nowhere else. The variable is our own, which [#301](https://github.com/lucastkacz/ficha/issues/301) probed.
- Ficha Dev itself, opened with `open -n --env FICHA_DEV_SCRATCH=<name> <Ficha Dev.app>`, runs on the scratch folder too. It syncs through iCloud in zones of its own, `Files-<name>` and cards' zones such as `Cards-<name>.1761650000000.new`, in the same account as Ficha Dev, whose devices leave them alone, so an agent's cards never reach Ficha Dev's. Its second device, under Debug, syncs in them too.
- To delete a scratch run's zones from iCloud once it's done, run Ficha Dev's binary itself with `--delete-scratch-zones`, which shows no window and takes neither the pointer nor the keyboard: `FICHA_DEV_SCRATCH=<name> "<Ficha Dev.app>/Contents/MacOS/Ficha Dev" --delete-scratch-zones`. It prints the zones it deleted, or that there were none, and deletes no zone but that run's, so Ficha Dev's own zones stay. It needs a build signed for iCloud, since the CLI's process can't reach it, and it's our own.
- `CFFIXED_USER_HOME`, which keeps the render tool's files in a scratch home, doesn't keep a sandboxed CLI's apart: the group's folder doesn't follow it.
- `.claude/settings.json` keeps Claude out of both groups' folders, so the scratch folders stay. Starting Ficha Dev over leaves them, since they're beside its `Ficha Dev` folder: to delete them, move the group folder's `Scratch` to the Trash.
- In a worktree, Claude's Bash refuses to run a path with a space, like `Ficha Dev.app/Contents/Helpers/ficha`, and a heredoc beside a command. A two-line script in the scratchpad that runs the CLI, `exec "<path>" "$@"`, gets around the first, and a file gets around the second: `ficha approve 1 < cards.json`.
- An unsigned build's `ficha`, as from a worktree without `iPhone/Local.xcconfig`, says it isn't signed with its App Group and opens nothing.

## A window's picture

`make render` draws one of the app's windows as a PNG, with Ficha Dev's sample cards, without showing anything on screen or taking the mouse or the keyboard, so it runs while you use your Mac:

```bash
make render ARGS="cards"
make render ARGS="cards --dark --click 600,66 --click 360,529 --out .build/render/by-due-dark.png"
make render ARGS="cards --key cmd+f --type serendip --out .build/render/search.png"
```

- The PNG goes to `.build/render/<window>-<light|dark>.png` unless `--out` says otherwise, at the display's scale.
- The cards are Ficha Dev's sample cards after twelve days of reviews, from 8 October 2026: some climbing at different paces, two sent back to the first step, one flagged with a note, one buried, and the rest new, with a capture waiting in the inbox, below the flagged card, for Convert to Card; and then three new cards made by hand, with no type and no capture, which the sidebar's No Type lists: the third row has Argentina's flag on its front and the Sun of May on its back, with a sound there too, a tone of 12 seconds.
- Each run opens the window as the app does the first time: at its first size, and the Cards window with Front, Media, Step and Due, newest first, whatever an earlier run clicked. macOS keeps the tool's preferences, where the app keeps a window's frame, columns and order, in your home's `Library/Preferences/Render.plist`, whatever `CFFIXED_USER_HOME` says, so the tool empties them as it starts and as it ends.
- Before the capture, the tool clicks, presses keys and types in the window, in the order its options give:
  - `--click <x>,<y>` clicks in points from the window's top-left corner: on a row of the table or the sidebar, to select it, or on a column's header, to sort by it. The modifier keys it holds down go before the point: in a table that selects several rows, `cmd+360,169` adds a row to the selection or takes it out, and `shift+360,217` selects the rows from the last one clicked to it. To find a point, render once and read it off the PNG.
  - `--key <keys>` presses a key, after the modifier keys it holds down: `cmd+f`, `cmd+a`, `escape`, `return`, `shift+tab`. The tool's usage lists the keys and modifiers it knows. As AppKit does, the key goes first to the window as a key equivalent, which a button's keyboard shortcut takes, then to the main menu, and then, when nothing took it, to what holds the focus. A key that nothing takes plays the system's alert sound, as in the app. The tool makes each press as the keyboard does, from the key's place on a US keyboard, and the Mac's keyboard layout says what it types: with a layout whose letters or digits are elsewhere, like AZERTY or Dvorak, it stops and says so.
  - `--type <text>` types into what holds the focus, like a text field after its shortcut or a click: `--type 'una palabra'` for text with spaces.
  - `--copy-image <flag|sun>` copies a picture the tool draws to its own pasteboard, for `--key cmd+v` to paste, since the tool can't drag a file: the flag, 1800 × 1125 pixels, comes in shrunk, and the sun has a transparent background. A card's side takes it while its text or its image well has the focus, as in `--key cmd+n --type '¿Qué país tiene esta bandera?' --copy-image flag --key cmd+v`.
  - `--copy-sound` copies a sound file the tool writes, a tone of 12 seconds, to its own pasteboard, as Finder copies a file, for `--key cmd+v` to paste. A card's side takes it once its sound well has the focus, the next `--key tab` after its image well.
  - A row of the sidebar below what the window shows, like No Type: click a row of the sidebar, then press the first letters of the one you want, each with `--key`, as in `--click 80,68 --key n --key o`. The sidebar selects that row and scrolls to it, as Finder's does. `--type` refuses it, since the focus isn't in a text field.
  - After each one, the tool prints what holds the focus, the first responder of the window or of its open sheet, so you can check that a shortcut went where it should: for a text field, its field editor, the field and its placeholder.
- The tool's main menu has only the Edit menu's shortcuts, copied from what SwiftUI gives the app, so ⌘Z, ⇧⌘Z, ⌘X, ⌘C, ⌘V and ⌘A undo, redo, cut, copy, paste and select all as they do there. The copy is our own, since the tool doesn't run the app's `App`: a command the app adds to the Edit menu with `.commands` needs adding to `editMenuItems` in `main.swift` too. It leaves out the app's other menus, whose shortcuts, like ⌘Q, ⌘H and ⌘M, quit the app, hide it or minimize its windows. Cut, Copy and Paste use a pasteboard of the tool's own, which it deletes when it's done, so it never pastes your clipboard into a picture nor changes it.
- A sheet, an alert or a confirmation the window opens, as SwiftUI's `.sheet`, `.alert` and `.confirmationDialog` do, goes below the desktop picture too, before macOS shows it, and the PNG shows it over the window, where macOS puts it. While it's open, the clicks, the keys and the typing go to it, as in the app, and the line the tool prints says when the focus is in it. A click outside it fails and says where it is: the window doesn't take clicks while its sheet is open.
- Buttons, SwiftUI's or an alert's, don't react to the tool's clicks: on macOS 26 a button takes its clicks through a gesture recognizer, which didn't fire for the tool's, whether sent to the button, to the window or to the recognizer. Press one through its keyboard shortcut instead, with `--key`: in a sheet, an alert or a confirmation, `return` presses the default button and `escape` Cancel, and hidden buttons answer theirs too. An alert's or a confirmation's button also takes the focus from a click, so `--click` on it and then `--key space` presses it.
- What the tool can't do yet, for a ticket that needs it to extend: right-click, as on a table's headers for their menu, or double-click; keep a menu or a popover the window opens, like a picker's, below the desktop picture, as it does sheets; and take a list or a table out of a sheet that opened with it, as New Deck… does with the Change Deck sheet's tree: the tool crashes with an `NSRangeException` as the list stops observing the sheet's first responder, which the subclass the tool makes the sheet an instance of seems to break, since the sheet opens after the list starts observing it (#380).
- The window and its sheet act as the key window, with the title bar's buttons in color, but their selections and default buttons stay gray.
- The window is in English, the app's base language: the tool leaves the String Catalog out.
- The windows so far: `cards`, `cards-tags`, the Cards window on ciencia once some sample tags sit inside others and five are pinned, in an order of their own, so that its sidebar shows the pinned tags, one inside another by its whole path, then All Tags…, `cards-all-tags`, the same on All Tags, pendientes a tag no card carries, with every tag as a tree with its Cards and Due columns and its Pinned checkbox, three parents open, each level sorted by Cards, the most first, and economía selected, whose cards `--key return` lists in All Tags' place, with Back and its name as the window's title, and which `--key cmd+delete` asks whether to delete, or, after a `--click` on a row and a `cmd+` click on another, the two tags, `cards-decks`, the Cards window on Idiomas, one of the decks the sample cards sit in, with its sidebar's Decks section, Default first, then every deck as a tree with how many of its cards are due, Idiomas and Ciencias with a color and an emoji, which the decks inside them show too, Ciencias and Humanidades closed, so that Sociedad shows, set aside, grayed with the deck inside it, the bar above the card list with Idiomas's name, its Actions menu and its cards' tags, and two cards selected, which `--key cmd+d` asks to move in the Change Deck sheet, and where `--key cmd+n` opens the card form with its Deck field on Idiomas, `cards-deck-tag`, the same on Idiomas › Español with historia, one of its tags, chosen above the card list, which lists only the deck's cards that carry it, `cards-new-deck`, the Cards window on Idiomas › Español with the card form on a new card in that deck and the New Deck sheet over it, since the tool can't open the Deck field's menu, the focus in the sheet's name field, which `--type <name>` fills, `cards-types`, the Cards window on Ley, one of four card types of the user's own the tool gives the sample, one with no card and one with no emoji, its sidebar scrolled to its end, so that it shows its Types section, since a click in the sidebar stops the tool there, `cards-new-type`, the Cards window with the card form on a new card and the New Type sheet over it, since the tool can't open the type picker, the focus in the sheet's name field, which `--type <name>` fills, `cards-new-type-editor`, the same over the Cards window editing a card, `cards-import`, the Cards window with its Import sheet on the preview of a file the tool writes, which `--key return` imports, `cards-import-anki`, the same on an Anki package the tool writes with SQLite and `zip`, `cards-anki-imported`, the Cards window once that package came in with its progress, on the card of the femur, which climbed since from the step the import put it on, `cards-import-heavy`, the Import sheet on a zip whose images weigh 240 MB while sync is on, which says they go up to iCloud, `backups`, Settings on its Backups tab, `backups-failed`, the same once a backup failed, `appearances`, `review-panel` and `ladder`, Settings on those tabs, with the settings that decide a card's progress, which the engine keeps, not Ficha's, `sync`, Settings on its Sync tab once the Mac synced, `sync-no-account`, the same signed out of iCloud, `sync-full`, while iCloud is full, `sync-off`, once the user turned sync off, with 800 MB of images and sounds for turning it on to send, `sync-purged`, once a purge of Ficha's data in iCloud turned it off, `sync-restored`, once a restore turned it off, `sync-chosen-decks`, syncing only the cards in two ticked decks, Ciencias and Idiomas › Español, in the tree of every deck, Default first, with what its images and sounds weigh, the decks inside a ticked one ticked and waiting, `sync-first`, off since the Mac held cards before it ever synced, `menu-icloud-full`, the menu's content while iCloud is full, drawn in a window as SwiftUI lays it out there, with buttons for its items, since the tool can't open the menu itself, `about`, Settings on its About tab, which says "Unknown version", since the tool has no Info.plist, `start-at-login`, the alert the real Ficha shows at its first launch, drawn from its own window as `runModal()` would show it, `diagnostics`, the Diagnostics window while a Focus holds appearances back, once it held one back on the sample cards; its detectors read the Mac that draws it, so check the picture names no app of yours before you commit it; and `panel-card`, the review panel on a new card in Ciencias › Psicología, with its deck, in Ciencias's color and emoji, and its three tags, drawn on a gradient in a window, since the panel's own window has nothing behind its Liquid Glass below the desktop picture. The Import sheet before a file is chosen is `cards --key cmd+shift+i`, since the tool can't drive the open panel, and the Export sheet is `cards --key cmd+shift+e`, which stops before its save panel. The tool bundles no instructions for an AI, so the Import sheet's Copy Instructions for an AI says they're missing. For the Backups tab, the Sync tab and the menu while iCloud is full, the sample cards go in Ficha Dev's data folder in the tool's scratch home, in Application Support, where Ficha Dev kept it before its sandbox, which the tool runs outside: for the Backups tab with a backup each of the last eight days, of which it keeps seven, a copy before an update and a copy before a restore, and for the Sync tab with its files on the disk to weigh. The tool deletes the folder as it ends, so render these one at a time. Another window is one more case in `Window`, in `model(for:)` and in `window(_:model:)`, in `scripts/render/Sources/Render/main.swift`.
- The tool compiles the app's own files, through `scripts/render/Sources/Render/App`, a link to `App/`, so `make check` builds it: a change to the app that breaks it fails the check.

### The iPhone's screen

`make render-iphone` takes the iPhone app's opening screen as PNGs, light and dark. It builds Ficha Dev for the simulator, as `make build-iphone` does, makes a simulator of the newest iOS the Mac has and the first iPhone it offers, which simctl lists by generation, newest first, boots it without the Simulator app, takes the pictures in it, and deletes it, so the simulators you and other sessions use stay as they were. It takes about a minute, and shows nothing on screen:

```bash
make render-iphone
make render-iphone ARGS="--out .build/render/counts"
```

- The PNGs go to `.build/render/iphone-light.png` and `iphone-dark.png`, or `<path>-light.png` and `<path>-dark.png` with `--out <path>`, at the iPhone's scale: 1206 by 2622 pixels for an iPhone 17 Pro. The status bar shows 9:41 and a full battery, as Apple's pictures do.
- The tool opens Ficha Dev with `-FichaRendering`, which only Ficha Dev takes (`iPhone/Rendering.swift`). Then the app doesn't ask whether it may send notifications, since iOS's alert would cover its screen, and plans none, and once its screen is up it says so on its standard output. The tool waits for that, and then for the screen to stay the same for more than seven seconds, longer than a notification's banner stays: a new simulator shows one, "Ready for Apple Intelligence", in its first half minute.
- The simulator has `/tmp` and `/var/folders` of its own, so simctl writes the app's standard output to a scratch folder in `.build/render`, which the tool deletes with the simulator.
- When Ficha Dev doesn't open, doesn't say its screen is up within a minute, or its screen doesn't settle within another, the tool stops, says so, and keeps `<path>-<light|dark>-failed.png`, the screen then, and `-failed.log`, what the app logged. When another simctl command fails, it says what it couldn't do after simctl's own message. Either way, it deletes its simulator.
- Only the opening screen so far: the tool doesn't tap or type yet. `make check` doesn't run it, since a new simulator takes most of its minute.
- The commands are simctl's, which `xcrun simctl help` documents. A simulator for each run, the line the app says once its screen is up, and the wait for a still screen are our own: Apple's own way to drive an app and wait for its screen is a UI test target, with XCTest.

## The PR's pictures

A PR that changes what you see shows it in pictures, which `make render` draws for the Mac and `make render-iphone` for the iPhone, so you can decide from its body. They never reach `main`:

1. Copy the PNGs to `pr-images/<issue>/` and commit them on the PR's branch.
2. Remove the folder in the next commit.
3. Link each picture from the PR's body by the first commit's full SHA, with a width that fits the body, like 560 for the Cards window and 280 for the iPhone: `<img alt="Sorted by Due, a card selected" width="560" src="https://raw.githubusercontent.com/lucastkacz/ficha/<sha>/pr-images/<issue>/by-due-light.png">`. Say under them which commit they come from and that the next one removes it.

The squash merge leaves both commits off `main`, and GitHub keeps a PR's commits after its branch is deleted, so the links keep working.

## Cleaning up after a merge

Each change is built in a worktree of its own, in `.claude/worktrees/`, with build folders of several GB. Once its PR merges, `make clean-merged`, run from the main folder on `main`, removes it:

```bash
make clean-merged
```

- For each folder in `.claude/worktrees/`, the implementers' `agent-*` included, it removes the worktree, its build folders and its branch only when nothing is lost: the worktree has no uncommitted changes (`git status --porcelain` prints nothing), and its branch's last commit is a merged PR's head (`headRefOid`), or inside one, as an implementer's branch joined into its spec's branch is. The squash merge leaves those commits off `main`, and the PR keeps them.
- Every other worktree stays, listed with the reason: uncommitted changes, an open PR, a last commit no merged PR holds, or a branch with no commits of its own off `main`, as a session's that has only just started.
- Claude Code locks a session's worktree while the session runs, naming its process, and leaves the lock when it ends. A worktree whose process still runs stays, so archive the finished session first; a lock whose process ended is lifted. Any other lock keeps its worktree. Reading Claude Code's locks is our own.
- It deletes the branches with `git branch -D` without asking, since the check above stands in for the prompt. The prompt stays for `git branch -D` typed by hand (`.claude/settings.json`).
- Then it updates `main` with `git pull --ff-only`.
- It reads the last 200 merged PRs through `gh`, and removes nothing when it can't reach them. `scripts/test-clean-merged.sh`, which `make check` runs, tests it on a scratch repo with a fake `gh`.

## The README's pictures

The pictures in `docs/images/` show the app's own views with Ficha Dev's sample cards, captured without showing anything on screen. After a change to the review panel or the capture window, capture them again the same way, with a throwaway Swift package outside the repo:

1. The package depends on `Packages/FichaKit` by path, whose FichaData has the sample cards, and links in the `App/` files the views need, such as `ReviewPanelView.swift`, `ReviewPanelModel.swift` and, for the capture window, `CaptureView.swift` with `AppModel.swift` and what it uses. Its target defines `FICHA_DEV` and is isolated to the main actor, as the app's is.
2. It opens an engine on an in-memory database and a `ManualTimeSource`, loads `SampleCards`, meets five new cards through review now, one each time, and moves the time an hour and a second forward, so they're due.
3. Each picture is a borderless window with the review panel on a gradient, inside the same window so the Liquid Glass has something to show through. The card's front gets its back's height, the panel at the top, so the two pictures line up side by side. The capture window is a titled panel like `CaptureWindow`, captured with its shadow and drawn on the same gradient. So that it looks as it does with the keyboard, without taking it, the panel overrides `isKeyWindow` and AppKit's private `_hasActiveAppearance`: fine for a throwaway package, never for the app.
4. Each window goes below the desktop picture (`CGWindowLevelForKey(.desktopWindow) - 1`, ignoring the mouse), where macOS still draws it but nobody sees it, and `screencapture -x -l <window number>` captures it at the display's scale, with `-o` when the window's shadow should stay out. Run it with `CFFIXED_USER_HOME` set to a scratch folder, as `make render` does, so the app's files stay out of your home. Its preferences are the package's own, under its name, never Ficha Dev's.

The menu can't be captured this way: it only draws while it's open on screen, and then it takes the mouse and keyboard, so it needs Lucas's OK and a few seconds of his screen. The same package builds an `NSMenu` with the items `MenuContent` shows in the real Ficha, opens it with `popUp(positioning:at:in:)` over the gradient in a floating window, captures that window's rectangle with `screencapture -x -R` from a timer that runs while the menu is open, and closes the menu with `cancelTracking()`.
