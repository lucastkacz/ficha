# The platform: signing, the App Store's sandbox and iCloud sync: research findings

What the research for #161 found, for its grilling: what selling Ficha on the Mac App Store, in its sandbox and signed with Lucas's paid team, does to the suppressions, the `ficha` CLI and Lucas's data; what syncing the cards through iCloud takes; and what #166, #170 and #171 need from the same step. Researched on 2026-10-24 by agents, against `main` at `dd5abbf`, from Apple's documentation, the App Review Guidelines, WWDC sessions, the macOS 26.1 SDK's headers, Apple staff on the developer forums, Anki's manual and SQLite's docs. Nothing was built or run: what only a build can settle is an open question with its probe, at the end.

Each claim says where it comes from: a link to Apple's documentation, the guidelines or a session; **Apple staff** for a reply by Apple's engineers on the forums, most often Quinn, of Apple's developer support, which is advice, not documentation; **the SDK** for a header; **our inference** for reasoning no source states; and **a lead** for a claim only a third party makes. macOS 27 is the current release ([release notes](https://developer.apple.com/documentation/macos-release-notes)), Lucas's Mac runs 26.3, and Ficha targets 26.0.

## In short

**What blocks or risks the App Store plan**

1. **The CLI, and with it `/refine`.** Apple's documented way to ship a command-line tool in a sandboxed app crashes when a terminal runs it. The way that runs, a tool with a sandbox of its own sharing the cards through an App Group, has no word from Apple on whether App Review takes it, and macOS 27 denies by default access to another team's containers, which may catch Claude's terminal. Nor can a sandboxed CLI open the sound and image files #232 points it to by their path. Probes P3 and P4 settle it; App Intents through `shortcuts run` are the fallback (section 2).
2. **The meeting suppression.** Whether the camera and microphone readings work in the sandbox is unknown. If they need the camera and microphone entitlements, an app for learning that claims them without capturing anything risks App Review, and maybe a prompt (section 1, P1 and P2). Full screen works, by Apple staff's word; videos are unknown.
3. **Start at login turned itself on at first launch.** Guideline 2.4.5(iii) forbids it without consent: the real Ficha has to ask, and since #303 it does (section 1).
4. **Lucas's data.** Apple's container migration only moves, once, and can't reach the App Group's container. The path that loses nothing copies instead, from a last unsandboxed build signed by the team, and, our inference, the sandboxed app refuses to start empty (section 3).
5. **Sync needs its own answers where Apple's are wrong for Ficha.** An iCloud account change empties `CKSyncEngine`'s queue of unsent changes, and Apple says to delete local data on sign-out, but Ficha's cards exist before any sync. Our inference: Ficha tracks unsent changes in SQLite itself, which also catches the CLI's writes (section 5).
6. **No more ad hoc builds.** iCloud and push are restricted entitlements, so `make run` and `make install` need the team's signing, and a development-signed real Ficha would put Lucas's cards in CloudKit's Development environment, which the App Store build never reads (section 6).
7. **A privacy policy at a public URL**, linked from the app too (Guideline 5.1.1(i)). Since #303, `site/privacy.md` is the policy, and Settings' About tab links to it.

**What the grilling must decide** is listed in "Questions for the grilling", below the sections.

## 1. The suppressions in the sandbox

#12's prototype showed the detectors need no privacy permission (TCC). That says nothing about the App Sandbox, a separate layer: Quinn, of Apple's developer support, asks developers whose tools broke whether they mixed the two up (Apple staff, [thread 669151](https://developer.apple.com/forums/thread/669151)). So every reading has to be measured again in a sandboxed build (P1).

| Reading (`App/SuppressionDetector.swift`, `App/SystemMacSignals.swift`) | API | In the sandbox |
|---|---|---|
| Camera | CoreMediaIO, `kCMIODevicePropertyDeviceIsRunningSomewhere` | **Unknown** (P1). It may list no devices without `com.apple.security.device.camera` (only leads say so: [busylight #92](https://github.com/Vixen-Labs/busylight/issues/92), [SimulatorCamera #10](https://github.com/dautovri/SimulatorCamera/pull/10)). Not deprecated (the SDK). |
| Microphone | CoreAudio, `kAudioDevicePropertyDeviceIsRunningSomewhere` and the process objects | **Unknown** (P1). Our inference: listing devices likely works, since sandboxed apps play sound through the same layer with no entitlement; reading input devices may need `com.apple.security.device.audio-input`. The process objects only name apps in Diagnostics, so a failure there costs little. |
| Video | IOKit, `IOPMCopyAssertionsByProcess` | **Unknown** (P1). The header covers creating assertions, not reading other processes'. If it's blocked, only a temporary exception remains. |
| Full screen | `CGWindowListCopyWindowInfo` (layers, bounds, owners), `NSWorkspace`, `NSScreen` | **Works**: it returns every window's bounds when sandboxed, and without Screen Recording it only withholds names (Apple staff, [thread 792917](https://developer.apple.com/forums/thread/792917), [thread 706187](https://developer.apple.com/forums/thread/706187)). Only the window *image* calls are deprecated, in macOS 15 (the SDK, `CGWindow.h`). |
| A process's name, fallback | `sysctl(KERN_PROC_PID)` | **Unknown.** The sandbox denies listing processes, with no entitlement to lift it (Apple staff, [thread 691857](https://developer.apple.com/forums/thread/691857)); `sysctl` isn't covered. It's only a fallback. |
| Idle time | `CGEventSource.secondsSinceLastEventType` | Our inference: works. It reads a timestamp, not events, and listening to events is what needs Input Monitoring (Apple staff, [thread 735223](https://developer.apple.com/forums/thread/735223)). |
| Sleep and wake | `NSWorkspace`'s sleep and wake notifications | Our inference: works; they're ordinary AppKit notifications. |

**What the device entitlements would cost.** An app needs both a usage description and the entitlement before it "requests authorization or uses a capture device", or the system ends it ([Requesting authorization to capture and save media](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media)). Whether reading a device's state counts as using it, and so prompts, isn't documented (P2). App Review asks apps to "use APIs and frameworks for their intended purposes" (2.5.1) and to request access only to what the app's core functionality needs (5.1.1(iii)) ([guidelines](https://developer.apple.com/app-store/review/guidelines/)). Our inference: claiming the camera and microphone to notice a meeting invites questions, and a camera prompt would make the meeting suppression a product decision. Temporary exception entitlements need a justification in App Store Connect, and Apple publishes no criteria for accepting them ([App Sandbox information](https://developer.apple.com/help/app-store-connect/reference/app-uploads/app-sandbox-information)): a last resort.

**The rest of the app.**

| Code | In the sandbox |
|---|---|
| Start at login, `SMAppService.mainApp` (`App/StartAtLogin.swift`) | Works, and it's the way the store's sandbox allows (Apple staff, [thread 758985](https://developer.apple.com/forums/thread/758985)). But `StartAtLogin.turnOnAtFirstLaunch()` turned it on without asking, and Mac App Store apps "may not auto-launch or have other code run automatically at startup or login without consent" (Guideline 2.4.5(iii)). Since #303, `StartAtLogin.askAtFirstLaunch()` asks first. |
| The capture shortcut, Carbon's `RegisterEventHotKey` (`App/CaptureShortcut.swift`) | Our inference: works with no entitlement. Quinn lists it among the ways to get a global hot key (Apple staff, [thread 735223](https://developer.apple.com/forums/thread/735223)). |
| Import's `.fileImporter`, Export's `NSSavePanel` | Work with `com.apple.security.files.user-selected.read-write` ([Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)). Whether Export's atomic write, which writes a temporary file beside the chosen one first, is allowed is P8. |
| Backups' Show in Finder | Our inference: works; the folder shown becomes a path inside a container. |
| Backups' Delete…, `FileManager.trashItem` | A sandboxed app's trash "is within its sandbox directory" ([trashDirectory](https://developer.apple.com/documentation/foundation/url/trashdirectory)). If the copies go to a trash in the container, the dialog's promise that Lucas can put them back from the Trash breaks (P9). |
| Copy Instructions for an AI, and ⌘V and drags on a side's image or sound, `NSPasteboard` | Writing is unaffected. Since macOS 15.4, reading the general pasteboard asks the user, except for access "both user originated and paste related", and other pasteboards, such as a drag's, are always allowed ([NSPasteboard.AccessBehavior](https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum)). Ficha reads the general one only when the user presses ⌘V on a side; our inference is that this counts as such a paste. |
| Darwin notifications between the app and the CLI (`DatabaseChanges.swift`) | Our inference: probably work, since `notify.h` gives every process one namespace (the SDK). Apple's App Groups page doesn't list them among the ways sandboxed processes talk ([application-groups](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups)). If they fail, the app stops hearing the CLI's writes (P3). |
| `NSFileCoordinator` around opening the database (`Engine.swift`) | Our inference: works between two processes on a file both reach (P3). It fails closed: an error means the database doesn't open. |
| Preferences, `UserDefaults.standard` | Move to a file inside the app's container, so Lucas's settings don't follow on their own; that file belongs to the system's preferences process, so never copy it by hand (Apple staff, [thread 721805](https://developer.apple.com/forums/thread/721805)). |
| The data folder, `URL.applicationSupportDirectory` (`AppVariant.dataFolder`) | Resolves inside the container ([applicationSupportDirectory](https://developer.apple.com/documentation/foundation/url/applicationsupportdirectory)). `Engine` creates a database when there's none, so a sandboxed first launch with nothing moved silently starts an empty Ficha (our inference, from the code). |

## 2. The `ficha` CLI and `/refine`

**Apple's documented way doesn't run from a terminal.** Apple's article signs an embedded tool with exactly two entitlements, `com.apple.security.app-sandbox` and `com.apple.security.inherit`, so it takes its app's sandbox ([Embedding a helper tool in a sandboxed app](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app)). When a process that isn't sandboxed runs such a tool, "there's nothing to inherit", and it crashes with "Process is not in an inherited sandbox". Quinn's three fixes: sandbox the parent, unsandbox the child, or "Run the child in its own sandbox by removing the `com.apple.security.inherit` entitlement" (Apple staff, [thread 706390](https://developer.apple.com/forums/thread/706390)). Claude Code isn't sandboxed, and every executable in a Mac App Store app must be (Apple staff, [thread 733942](https://developer.apple.com/forums/thread/733942)). So the third fix is the one left.

**A tool with a sandbox of its own.** A command-line tool that wants its own sandbox embeds an Info.plist in its binary (`CREATE_INFOPLIST_SECTION_IN_BINARY`), which gives it a bundle identifier (Apple staff, [thread 669151](https://developer.apple.com/forums/thread/669151)). It then gets a container of its own, not the app's, so the two share the cards through an **App Group**: a folder, `~/Library/Group Containers/<group ID>/`, that apps of one team can share, which the system creates on first use ([containerURL(forSecurityApplicationGroupIdentifier:)](https://developer.apple.com/documentation/foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:))).

- **The group's ID.** macOS takes IDs that start with the Team ID, such as `<TeamID>.com.lucastkacz.ficha`, which need no provisioning profile, or iOS's `group.` IDs, which do; a bare executable can't carry a profile (Apple staff, [thread 721701](https://developer.apple.com/forums/thread/721701); [TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)). So the CLI takes a `<TeamID>.` group. The iPhone can't share a folder with the Mac anyway, so its own `group.` ID doesn't matter here (our inference).
- **No prompt for Ficha's own processes.** Since macOS 15, a process reaches a group container without asking the user when it claims the group and it comes from the Mac App Store, from TestFlight, or with a group ID that starts with its Team ID (Apple staff, same thread).
- **A prompt, or a denial, for others.** Since macOS 14, a process reading another app's container prompts the user, unless both are signed by the same team ([WWDC23, What's new in privacy](https://developer.apple.com/videos/play/wwdc2023/10053/)). On macOS 27, "Accessing files in other developer teams' app data containers and app group containers no longer prompts the user for authorization; such accesses are denied by default and can be managed by the user in Privacy & Security settings", and among its known issues, "a process without a bundle ID cannot be granted access to specific app data containers or app group containers owned by other developer teams", with Full Disk Access as the workaround ([macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)). Which code macOS holds responsible for a tool a terminal runs isn't documented (Apple staff, [thread 678819](https://developer.apple.com/forums/thread/678819)); users see their terminal named in such prompts (a lead: [ghostty discussion 4496](https://github.com/ghostty-org/ghostty/discussions/4496)). If macOS holds Claude responsible, `/refine` could be denied on macOS 27 until Lucas allows it in Privacy & Security, or gives Full Disk Access (P3).
- **App Review.** No guideline mentions command-line tools. Mac App Store apps must be "self-contained, single app installation bundles" that "cannot install code or resources in shared locations" (2.4.5(ii)), and may not "read or write data outside the designated container area" (2.5.2). Our inference: a sandboxed `ficha` inside the bundle, described in the notes for App Review, is allowed, and the app never installs it in `/usr/local/bin`. Whether the upload accepts a tool without `inherit` is P4.

**The options.**

| Option | From a terminal | Mac App Store | Cost |
|---|---|---|---|
| A tool that inherits the app's sandbox | No: it crashes | Yes | Useless for `/refine` |
| **A tool with its own sandbox and a `<TeamID>.` group** | Yes | Likely; unconfirmed (P4) | An Info.plist in the tool, the group in both, and the data folder in the group container |
| App Intents run with `shortcuts run` (section 4) | Yes | Yes, the standard path | Every command becomes an intent, with the limits in section 4 |
| The app serves the CLI over a socket in the group container | Through a client | Our inference: yes | The app must be running, and the client still meets the container's protection |
| An XPC service through a launch agent | Through a client | Unclear (Apple staff, [thread 689642](https://developer.apple.com/forums/thread/689642)) | An agent, a wrapper, and consent under 2.4.5(iii) |
| A separate CLI signed with Developer ID, outside the store | Yes | The store app can't install it (2.4.5(ii), (iv)) | A second channel, notarized, updated apart |

**Files the CLI is pointed to.** #232 leaves this step a CLI whose `approve`, `fix` and a new command put a sound or an image file from anywhere on the Mac on a card (its comment on #161). A sandboxed process opens only its containers and what the user picked in an open panel ([Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)), and a terminal tool has no panel. What's left:

- The file comes in on standard input, opened by the shell: `ficha … < ~/sound.m4a`. Our inference: the sandbox checks a file as it's opened, so one the shell opened and handed over reads fine (P3 checks it).
- `com.apple.security.files.downloads.read-only`, a standard entitlement that "may have read-only access to the Downloads folder" ([its page](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.downloads.read-only)): the file goes through Downloads.
- A temporary exception for paths in the home folder, which App Review may refuse (section 1).
- `shortcuts run --input-path`, which hands an intent the file (section 4).

**What `/refine` becomes** under the recommended option (our inference): the same commands, JSON in and out, at `/Applications/Ficha.app/Contents/Helpers/ficha`, with the cards in `~/Library/Group Containers/<TeamID>.com.lucastkacz.ficha/`. The skill's "run `make install`" becomes "install Ficha from the App Store or TestFlight". Maybe one prompt per session, or a denial on macOS 27, depending on P3.

**Can Ficha Dev stay unsandboxed?** Yes, the sandbox and the entitlements are per configuration (our inference). But the sandbox's surprises would then show up only in TestFlight builds; Dev and Ficha would keep their data in different kinds of folder; and `CFFIXED_USER_HOME`, which agents set to keep their runs of the CLI out of Lucas's folders, may not redirect a sandboxed CLI (P5). The alternative is a sandboxed Ficha Dev with its own group, `<TeamID>.com.lucastkacz.ficha.dev`, so `make run` meets the sandbox every day.

**One rule either way:** no locally signed, sandboxed build ever runs as `com.lucastkacz.ficha` before the real move. Its first launch creates the real container, which uses up any migration, and ties the container to a local signature, so the store's build prompts again later ([Migrating your app's files](https://developer.apple.com/documentation/security/migrating-your-app-s-files-to-its-app-sandbox-container); WWDC23 above).

## 3. Moving Lucas's data into the container

Lucas's data: `~/Library/Application Support/Ficha/` with `Ficha.sqlite` and its `-wal` and `-shm`, `Images/`, `Sounds/`, and `Backups/` with its shared images and sounds; and about 20 settings in `UserDefaults`. Ficha was never distributed, so this is a one-time move for one person; everyone else starts empty (our inference).

**Apple's container migration.** A `container-migration.plist` in the app lists what moves from the home folder into the container, at the app's first sandboxed launch, when its container is created ([Migrating your app's files to its App Sandbox container](https://developer.apple.com/documentation/security/migrating-your-app-s-files-to-its-app-sandbox-container)). It only moves: asked for a copy instead, Quinn answers "There's no way to do that as the container migration manifest is currently implemented" (Apple staff, [thread 763674](https://developer.apple.com/forums/thread/763674)). Its destinations are inside the app's own container, so it can't reach a group container; failures aren't reported (Apple staff, [thread 767586](https://developer.apple.com/forums/thread/767586)), and Ficha would then open an empty database. Moving the preferences file isn't documented. P6 tests it, if it's chosen after all.

| Path | Keeps the original | Reaches the group container | Settings | Risk |
|---|---|---|---|---|
| Container migration | No: it moves | No: the app moves it again | Only by moving the preferences file | No fallback; a failure or a test build that used it up means an empty Ficha |
| **The last unsandboxed build copies the data into the group container** | Yes | Yes | Exported to a file there, read by the sandboxed app | It must be signed by the team to claim the `<TeamID>.` group without a prompt (P7). Lucas stops using the old build once it's copied. |
| The sandboxed app asks Lucas to pick the old folder | Yes | Yes | Only if the path above exported them; otherwise set again by hand | One more step; the panel can open on the folder, and picking a folder gives access to all inside it ([Accessing files](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)) |
| Restoring one backup Lucas picks | Yes | Yes | No | Loses everything since that backup |

**SQLite.** A plain copy of a database in use, or one separated from its `-wal`, can be corrupt; the backup API and `VACUUM INTO` copy it safely ([How to corrupt an SQLite database](https://www.sqlite.org/howtocorrupt.html)). Ficha already copies with the backup API (`saveCopy` in `Backups.swift`), and its backups are single files, so they, the images and the sounds copy as plain files.

**The path that loses nothing** (our inference): the last unsandboxed build, signed by the team, copies the database with the backup API, copies `Images/`, `Sounds/` and `Backups/`, and exports the settings, into the group container, leaving the old folder untouched as the fallback. The sandboxed app, finding the old folder and nothing in the group container, refuses to start empty and says why. Picking the old folder by hand is the fallback for that copy.

## 4. Focus, Shortcuts and widgets (#166, #170, #171)

### Focus and Do Not Disturb (#166)

Three documented routes, none clean:

| Route | What Ficha learns | What it needs | The catch |
|---|---|---|---|
| `INFocusStatusCenter` | One `Bool`: whether some Focus silences Ficha. Not which Focus, and a Focus that allows Ficha's notifications doesn't count. | macOS 12. The Communication Notifications capability, a restricted entitlement, so a team-signed build with a profile; `NSFocusStatusUsageDescription`; the user's OK for Focus status and for notifications. | Apple meant it for messaging apps, and App Review asks apps to use APIs "for their intended purposes" (2.5.1). No change notification, so Ficha polls, and whether polling sees changes on macOS is unverified (P10). |
| A Focus filter (`SetFocusFilterIntent`) | The settings the user gave Ficha's filter in each Focus where they added it. | macOS 13, App Intents, no entitlement. The user adds the filter per Focus in System Settings. | It can't tell "any Focus is on", only the Focuses the user set it up in. A forum report of May 2026, a lead, says macOS 26.5 never calls `perform`, with no Apple reply and nothing in the release notes since (P11). |
| A Shortcuts automation | Whatever Ficha's action receives when it runs. | An App Intent such as "Hold back appearances", on or off; the user builds the automation on Do Not Disturb. | The user builds it by hand. Only Do Not Disturb is documented as a trigger on the Mac. |

Sources: [`INFocusStatusCenter`](https://developer.apple.com/documentation/intents/infocusstatuscenter); Apple's sample [Handling Communication Notifications and Focus Status Updates](https://developer.apple.com/documentation/usernotifications/handling-communication-notifications-and-focus-status-updates) ("the user doesn't appear focused to an app if an enabled Focus allows notifications from that app"); Apple staff: "Focus Status will only be available to apps that have the Communication Notifications capability" ([thread 682143](https://developer.apple.com/forums/thread/682143)); [Implementing communication notifications](https://developer.apple.com/documentation/usernotifications/implementing-communication-notifications) ("direct communications"); [Focus](https://developer.apple.com/documentation/appintents/focus) and [Defining your app's Focus filter](https://developer.apple.com/documentation/appintents/defining-your-app-s-focus-filter); WWDC22 [Meet Focus filters](https://developer.apple.com/videos/play/wwdc2022/10121/); the report on 26.5, a lead ([thread 826766](https://developer.apple.com/forums/thread/826766), not from Apple); the Shortcuts User Guide's [automations](https://support.apple.com/guide/shortcuts-mac/add-automations-apdfbdbd7123/mac).

Our inference: a Focus filter is the one route with no App Review risk. It lives in the app's own target, since a menu-bar app is running whenever an appearance could come, so it needs no extension and no App Group; Ficha reads the filter's `current` value at launch, for a Focus that changed while it was quit. Whether it works at all on macOS 26 and 27 is P11's question. The new suppression needs a name that clashes with neither **Focus mode** nor the "do not disturb" that **Suppression** tells us to avoid (`GLOSSARY.md`).

### A Shortcuts action (#170)

- **App Intents** are macOS 13 and later, need no entitlement, and an intent declared in the app runs in the app's own process, which the system launches if it isn't running ([Creating your first app intent](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent)). On macOS 26, `supportedModes` says whether running it brings the app forward; `openAppWhenRun` is deprecated ([supportedModes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes)). "Review now" fits `.background`, since the review panel never activates Ficha (our inference; P14 checks the panel shows).
- **`AppShortcutsProvider`** adds ready-made shortcuts that are "available as soon as someone installs your app" ([App Shortcuts](https://developer.apple.com/documentation/appintents/app-shortcuts)), and macOS 26 runs actions from Spotlight too ([WWDC25, Explore new advances in App Intents](https://developer.apple.com/videos/play/wwdc2025/275/)).
- **From a terminal**, `shortcuts run "<name>"` runs a shortcut from the user's library; text piped in becomes its input, `--output-path` writes its output, and it exits 0 or 1 ([Run shortcuts from the command line](https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac)). Whether it runs an App Shortcut by name, with no shortcut made by hand first, isn't documented (P13, which needs no build).
- **Signing.** Whether today's ad hoc build registers its intents isn't documented either way (P12). That answers #170's triage question: unknown, not "needs the team". Once the app is team-signed and sandboxed, nothing more is needed.
- **As a replacement for the CLI** (our inference): each `ficha` command could become an intent taking and returning JSON as text, run with `shortcuts run`. It's a poor fit: one hand-made shortcut per command unless P13 says otherwise, only 0 or 1 to tell errors apart, a hang if anything asks for input, and only a user guide to rely on. It's the fallback if the sandboxed CLI of section 2 fails.

### Widgets (#171)

- **Where and when.** Widgets on the Mac's desktop are macOS 14, and buttons and toggles in them (`Button(intent:)`) macOS 14 and iOS 17 ([WWDC23, Bring widgets to new places](https://developer.apple.com/videos/play/wwdc2023/10027/); [Adding interactivity](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)).
- **The sandbox.** A widget is an app extension, and "macOS app extensions must have App Sandbox enabled" (Apple staff, [thread 798886](https://developer.apple.com/forums/thread/798886)). It reads the cards from an App Group container it shares with the app: "a widget can access the database" there ([Developing a WidgetKit strategy](https://developer.apple.com/documentation/widgetkit/developing-a-widgetkit-strategy)). So a widget needs the database in the group container of section 2, and the team's signing (P15).
- **Which process rates a card.** "By default, the system runs the app intent in the same process as the widget extension" ([Adding interactivity](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)). A widget that turns a card over or rates it makes the extension a third process writing to the database, beside the app and the CLI. Pinning the intent to the app (`allowedExecutionTargets`) is macOS 27 ([IntentExecutionTargets](https://developer.apple.com/documentation/appintents/intentexecutiontargets)); a widget that only opens the review panel uses a link instead.
- **The reload budget.** "From 40 to 70 refreshes" a day for a widget viewed often, and a button's tap always reloads ([Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)). A few appearances a day fit (our inference).
- **The database from a widget.** GRDB's guide to sharing a database ([DatabaseSharing](https://swiftpackageindex.com/groue/grdb.swift/documentation/grdb/databasesharing)) has a process that only reads open it read-only, which needs the writers to keep the `-wal` and `-shm` files (persistent WAL). Ficha's `Engine` doesn't turn that on today. On the iPhone, a process suspended while it holds a SQLite lock in a shared container is killed (`0xdead10cc`, [SIGKILL](https://developer.apple.com/documentation/xcode/sigkill)), which GRDB's guide covers too.
- **iPhone widgets on the Mac.** macOS shows the iPhone's widgets on the Mac, and runs their buttons on the iPhone ([WidgetKit](https://developer.apple.com/documentation/widgetkit)). Until sync, those show the iPhone's cards, so the Mac first needs a widget of its own, as Apple staff confirm ([thread 773597](https://developer.apple.com/forums/thread/773597)).

## 5. iCloud sync

### `CKSyncEngine`

- **Requirements.** macOS 14 and iOS 17 (the SDK, `CKSyncEngine.h`), below Ficha's 26. "CKSyncEngine requires the CloudKit and Remote notifications entitlements" ([CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5)); both are restricted, so every build that syncs is team-signed with a profile. The records go in a custom zone of the private database, which counts against the user's iCloud storage ([privateCloudDatabase](https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase)).
- **What it does.** It schedules syncs, waits out a missing network or low power, retries the errors it lists as retryable, subscribes to pushes and fetches on them, and keeps a deduplicated list of pending changes (the SDK, `CKSyncEngine.h`, `CKSyncEngineState.h`). Whether a menu-bar app gets those fetches without registering for remote notifications is P17.
- **What Ficha writes.** The delegate's events, the batches to send, which `RecordZoneChangeBatch(pendingChanges:recordProvider:)` keeps within CloudKit's limits on its own (the SDK, `CKSyncEngineRecordZoneChangeBatch.h`), applying fetched changes to SQLite, saving each record's system fields, every non-retryable error (`serverRecordChanged`, `quotaExceeded`, `zoneNotFound`, `userDeletedZone`…), and the engine's state: "The sync engine does not persist this state to disk" (the SDK, `CKSyncEngineEvent.h`). Our inference: keep that state in the same SQLite database, in the same transaction as the changes it covers, since in WAL mode with `synchronous=NORMAL` a committed transaction "might roll back following a power loss" ([PRAGMA synchronous](https://www.sqlite.org/pragma.html#pragma_synchronous)); which setting Ficha runs with is P27.
- **Conflicts.** `serverRecordChanged` carries the server's record, which Ficha merges into and saves again ([serverRecordChanged](https://developer.apple.com/documentation/cloudkit/ckerror/code/serverrecordchanged)). Review-log entries never change, so as records named by a UUID they never conflict (our inference).
- **Linking CloudKit.** In sandboxed Release builds, an app whose binary doesn't link CloudKit.framework is denied CloudKit's service: the sandbox's access "is definitely based on the presence of the CloudKit framework", and Quinn's workaround is `print(CKRecord.self)` at launch (Apple staff, [thread 835400](https://developer.apple.com/forums/thread/835400)). Ficha's sync would live in FichaKit, so check the app's linked libraries (P18).

### Checking #161's notes "Sync without a connection"

Mostly right, with four corrections:

1. **An account change empties the queue.** "When the logged-in account changes, the sync engine will reset its internal state … it will clear any pending database or record zone changes that you may have added" (the SDK, `CKSyncEngineEvent.h`). So the engine's list can't be the only record of what still has to go up.
2. **Apple treats local data as the account's cache.** On sign-out and on switching accounts: "You should delete any locally-stored data for the previous account" (same header). Ficha's cards exist before any sync, so deleting them on sign-out loses them: Ficha needs its own answer.
3. **Anki keeps both reviews but not both steps.** For a card reviewed on two devices, "both reviews will be marked in the revision history", and "the card will be kept in the state it was when it was most recently answered" ([Anki: syncing](https://docs.ankiweb.net/syncing.html)). So Anki never moves a card up two steps. Ficha works the step out from the log (ADR 0002), so it needs the fix the note describes, or Anki's rule. The note's other case, one new card's first view on both devices, which makes `Ladder.standing(after:)` throw, needs the same choice.
4. **The CLI can't sync.** A standalone executable can't claim a restricted entitlement ([TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)), and GRDB's observation "does not detect changes performed by external processes" ([DatabaseSharing](https://swiftpackageindex.com/groue/grdb.swift/documentation/grdb/databasesharing)). Sync stays in the app.

Our inference from 1 and 4: track what still has to go up inside SQLite itself, in a table that triggers fill on every write, whichever process makes it. The app feeds those rows to the engine, which offers `hasPendingUntrackedChanges` for apps that track their own changes, so one design covers the CLI's writes, an account change and a crash.

**IDs.** Each row synced needs a record name unique in its zone, ASCII, up to 255 characters ([CKRecord.ID](https://developer.apple.com/documentation/cloudkit/ckrecord/id/init(recordname:zoneid:))). A UUID column beside today's integer IDs does it (our inference); only SQLiteData needs UUID primary keys. A tag is keyed by its name, which can hold accents and emoji, so its record name needs an encoding.

### Images and sounds

Sounds on cards (#232) travel as images do: a file of its own per sound, kept once for every card and backup that uses it. With no length limit, a sound weighs about 1 MB a minute, against 200 to 300 KB an image (#232's comment on #161).

- A record holds at most 1 MB; a `CKAsset` holds a file apart from it, up to 50 GB, encrypted by default ([CKRecord](https://developer.apple.com/documentation/cloudkit/ckrecord), [CKAsset](https://developer.apple.com/documentation/cloudkit/ckasset); Apple staff, [thread 827897](https://developer.apple.com/forums/thread/827897)). Fetched assets land in a folder the system cleans, so Ficha moves them into its own folders as they arrive.
- Our inference: one record per file, named by its content as the file is, so an image or a sound goes up once however many cards use it, and never changes.
- Deleting one is the risk: one device drops an image no card uses while another just gave it to a card. Anki syncs media deletions only "if they are made after media is fully in sync" ([Anki: syncing](https://docs.ankiweb.net/syncing.html)). The grilling picks a rule, such as never syncing deletions of images.
- The engine doesn't retry `quotaExceeded`; Apple says to prompt the user to free iCloud storage ([quotaExceeded](https://developer.apple.com/documentation/cloudkit/ckerror/code/quotaexceeded)). Ficha keeps working and keeps the changes pending (our inference). How much Lucas's first upload weighs is P26.

### Restoring as Anki does

Anki's manual: on a restore, "Anki disables automatic syncing and backups … close and re-open Anki to return to normal" ([backups](https://docs.ankiweb.net/backups.html)); a forced one-way sync sends the local copy up ("Upload"), and the other devices then choose Download; and "Forcing a one way sync only affects card syncing - media is synced as normal" ([syncing](https://docs.ankiweb.net/syncing.html)). The backups page doesn't say to upload after a restore: #161's comment joins the two pages, which is a fair reading.

The same with CloudKit (our inference, from the SDK's facts):

1. After a restore, the engine starts with `automaticallySync = false` until the next launch (`CKSyncEngineConfiguration.h`).
2. "Upload" deletes the cards' zone and uploads every row into a new one, best under a new name per restore, so the other devices see a deletion (P16 checks whether the same name would do).
3. The other devices hear `.deleted` (`CKSyncEngineEvent.h`): they drop their rows and take the new zone, their unsent changes included, as Anki's Download does. A device that sends first gets `zoneNotFound`, and must not create the old zone again, as Apple's sample does.
4. Images and sounds live in a zone of their own, which a restore leaves alone.

A purge from iCloud's settings arrives as `.purged`, and the SDK says local data "should be wiped and not re-uploaded". Whether Ficha wipes Lucas's cards then, or only turns sync off, is for the grilling.

### Environments, containers and Ficha Dev

| Build | CloudKit environment |
|---|---|
| Simulator | Development only ([CKContainer](https://developer.apple.com/documentation/cloudkit/ckcontainer)) |
| Development-signed, from Xcode or `make` | Development, unless its entitlement says Production (Apple staff, [thread 795826](https://developer.apple.com/forums/thread/795826)); "your app in development can access either the development or the production environment" ([Deploying an iCloud container's schema](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema)) |
| TestFlight and the App Store | Production only |
| Developer ID | Supported; which environment, unverified (P19) |

- A schema is built in Development and deployed to Production in the CloudKit Console, which copies the record types but no records; Production never drops a record type or a field ([Deploying an iCloud container's schema](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema)).
- "Once you've created a container, you can't delete or rename it" ([Enabling CloudKit](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app)).
- **The trap** (our inference): a development-signed build of the real Ficha puts Lucas's cards in Development, which TestFlight and the App Store never read and the Console's "Reset Environment" erases.
- **Ficha Dev**: the Development environment of the real app's container, the flow Apple documents, or a container of its own, `iCloud.com.lucastkacz.ficha.dev`, fully apart but with a second schema to keep in step, forever.

### SQLiteData

Point-Free's library ([README](https://github.com/pointfreeco/sqlite-data), [CloudKitSync](https://github.com/pointfreeco/sqlite-data/blob/main/Sources/SQLiteData/Documentation.docc/Articles/CloudKitSync.md)) wraps `CKSyncEngine` on GRDB. It requires primary keys that "must be globally unique identifiers, such as UUID", no unique constraint but the primary key, no renamed or removed columns, and new columns nullable or with a default; it resolves conflicts as "last edit wins" per column and turns BLOB columns into assets. Its docs don't say what it does on sign-out or with another process's writes. Our inference: for Ficha it means migrating every primary key, querying through its own library, and keeping images as files outside it, plus a dependency with several of its own and an ADR. `CKSyncEngine` directly fits Ficha's code better.

### A live SQLite file in iCloud Drive

Still ruled out: iCloud Drive copies the file while SQLite may be writing it, the corruption section 3's note on SQLite describes, and files in iCloud containers must go through file coordination, which SQLite doesn't use ([iCloud Design Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/DesigningForDocumentsIniCloud.html), archived).

## 6. Signing with the paid team

### The channels

| | Mac App Store and TestFlight | Developer ID | Development |
|---|---|---|---|
| Certificate | Apple Distribution, and Mac Installer Distribution for the package | Developer ID Application | Apple Development |
| Profile | For iCloud and push; TestFlight always | For iCloud and push | A Mac development profile, the Mac registered |
| App Sandbox | Required, on every executable | Optional | Optional |
| Hardened runtime | Optional, recommended | Required to notarize | Optional |
| Runs on Lucas's Mac | Installed by TestFlight or the App Store only | Yes, notarized | Yes, on registered Macs |

Sources: [Certificate types](https://developer.apple.com/help/account/reference/certificate-types); [TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles): "A Mac app that uses no restricted entitlements doesn't need a provisioning profile … The only exception to this rule is TestFlight", and "you can't run an App Store distribution signed app locally"; Guideline 2.4.5(i): Mac App Store apps "must be appropriately sandboxed"; Apple staff: "All App Store executables must be sandboxed" ([thread 733942](https://developer.apple.com/forums/thread/733942)) and, on the hardened runtime in the Mac App Store, "AFAIK it's still optional … I generally recommend that you enable it" ([thread 746048](https://developer.apple.com/forums/thread/746048)); [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution); [Supported capabilities (macOS)](https://developer.apple.com/help/account/reference/supported-capabilities-macos), where CloudKit, push and App Groups are available to the paid program and Developer ID alike.

### TestFlight on the Mac

Testers need macOS 13. "Each build is available to test for up to 90 days", and then it no longer opens ([TestFlight](https://testflight.apple.com/)). Up to 100 internal testers, App Store Connect users, need no review ([TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview)), and Xcode's "TestFlight Internal Only" keeps a build from going to the store ([Distributing your app](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)). Uploads go through Xcode, `xcodebuild -exportArchive`, `altool` or Transporter ([Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)). `ITSAppUsesNonExemptEncryption` in the Info.plist skips the export questions on each upload ([Export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)).

### One record for the Mac and the iPhone

A Mac app added to the iPhone app's record "uses the same Apple ID …, SKU, and bundle ID as the iOS app", and once both are approved it stays a universal purchase ([Add platforms](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms)). So the iPhone's real Ficha takes `com.lucastkacz.ficha`, as on the Mac, and one container, `iCloud.com.lucastkacz.ficha`, serves both (our inference). The same page asks an app on iPhone and iPad to support both; whether that binds an iPhone-only app is P23.

### Privacy

- "All apps must include a link to their privacy policy in the App Store Connect metadata field and within the app" (Guideline 5.1.1(i)): Ficha needs a privacy policy at a public URL, and a link to it in the app.
- App Privacy details are required for every app. Data "collected" means sent off the device where the developer can reach it ([App privacy details](https://developer.apple.com/app-store/app-privacy-details/)), and the private database "isn't visible in the developer portal" ([privateCloudDatabase](https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase)), so "Data Not Collected" should fit (our inference; P24).
- Required-reason APIs are enforced on iOS, not listed for macOS ([Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)). The iPhone app needs a `PrivacyInfo.xcprivacy` with `UserDefaults` (CA92.1) and file timestamps (C617.1) ([NSPrivacyAccessedAPIType](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)); the Mac's can share it.

### What changes in the repo

Our inference from the facts above, unless a source is named.

- **`make install`** builds Release ad hoc and copies it to `/Applications`. With iCloud and push, an ad hoc signature can't authorize them (TN3125). Lucas's daily Ficha comes from TestFlight (Production, what ships, an upload at least every 90 days), or from a development-signed build forced to Production, if a Mac development profile allows that value (P20). A TestFlight copy and a local build with the same bundle identifier share one container, so the same cards.
- **`make run`** (Ficha Dev on the Mac) needs Apple Development signing and the team's ID on the Mac too, which today lives only in `iPhone/Local.xcconfig`.
- **`make check` and CI** build the Mac app ad hoc and the iPhone's unsigned. Whether an entitlements file with iCloud and push breaks those builds is unverified (P21); if it does, the entitlements go only on team-signed builds. `swift test` and `make render` run unsigned, so code that creates a `CKContainer` stays out of their paths (P22).
- **Build numbers.** `CFBundleVersion` must grow with each upload ([CFBundleVersion](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion)). The Makefile counts commits, which only grows on `main`: upload from `main` alone, and keep Xcode's export from renumbering.
- **Ficha Dev on the iPhone** takes the paid team's ID in `iPhone/Local.xcconfig`; its profiles last about a year instead of 7 days (TN3125; [About your developer account](https://developer.apple.com/help/account/basics/about-your-developer-account)). Whether the paid team can register `com.lucastkacz.ficha.dev`, which the Personal Team registered, is P25.
- **Rules and records that change** when the platform lands: CLAUDE.md's "100% local" rule and the data folder it names, ADR 0001's "stays on the Mac" (a new ADR supersedes it), ADR 0004's shared file (now in the group container), and `/refine`'s "run `make install`".

## Questions for the grilling

**The sandbox and the CLI**

1. The CLI: a sandbox of its own with a `<TeamID>.` App Group (recommended), with App Intents through `shortcuts run` as the fallback if App Review or macOS 27 refuses it? And how it takes the sound and image files #232 gives it: on standard input, through the Downloads folder, or another way?
2. Ficha Dev: sandboxed too, with its own group, or left unsandboxed?
3. The meeting suppression, if the camera and microphone readings need their entitlements (P1, P2): claim them and explain them to App Review, keep only what works without them, or drop it?
4. Start at login: how the real Ficha asks at first launch.
5. Lucas's data: copied by a last unsandboxed build signed by the team (recommended), or picked by hand in the sandboxed app? Do the settings travel, or does Lucas set them again?

**Sync**

6. What syncs: cards, captures, the review log, tags, flags and burials, settings, the appearance log (each device plans its own), images, sounds?
7. The same card reviewed on two devices offline: Anki's rule (the latest review sets the card's step), which also settles one new card's two first views, or working out again from the joined log whether each review was ahead?
8. A card edited on both devices: the last edit wins per field, or the card is flagged too? Deleted on one and edited on the other: which wins?
9. Deleting images and sounds no card uses: never synced, or only once both devices are in sync?
10. Signing out of iCloud, switching accounts, or purging Ficha's data from iCloud's settings: keep the local cards and stop syncing, or do as Apple suggests and delete them?
11. Restore: Anki's flow, sync off until relaunch and then an "Upload" that replaces iCloud's copy?
12. `CKSyncEngine` directly, or SQLiteData?
13. Ficha Dev: syncs or not; the Development environment of the real container, or a container of its own?
14. iCloud full: how Ficha tells Lucas.

**Signing and shipping**

15. Lucas's daily Ficha: TestFlight, or a development-signed build forced to Production? What `make install` becomes.
16. Who uploads, and from where: from `main` alone, so the build number always grows.
17. Where the privacy policy lives, at a public URL.
18. The hardened runtime: on, as Apple staff recommend?

**#166, #170, #171**

19. #166: a Focus filter if P11 shows it works, a Shortcuts automation, or close the idea?
20. #170: "Review now" in the background, and a "Capture" action too?
21. #171: a widget that only shows a card and opens the review panel, or one that rates, as a third process writing to the database?

## Open questions and probes

Every probe that builds waits until no other Xcode build runs, uses Ficha Dev's bundle identifier or a throwaway one, never `com.lucastkacz.ficha`, and reads sandbox denials in Console, filtered on the subsystem `com.apple.sandbox.reporting` ([Discovering and diagnosing App Sandbox violations](https://developer.apple.com/documentation/security/discovering-and-diagnosing-app-sandbox-violations)). Those marked **before the grilling** change its answers; the rest can wait for the build.

**The sandbox and the CLI**

- **P1, before the grilling.** Do the detectors, idle time, the capture shortcut and start at login work sandboxed, with no device entitlements? On a branch, give Ficha Dev's Debug configuration the sandbox and an entitlements file with `com.apple.security.app-sandbox` alone. Watch Diagnostics idle, on a FaceTime call, with a YouTube video and with an app in full screen; press the capture shortcut; log `SMAppService.mainApp.status`. A right reading means it works; "can't tell" with a denial in Console means it's blocked; a wrong "not in use" with no denial is a silent filter, so compare with the unsandboxed build. Lucas makes the call and plays the video.
- **P2, before the grilling.** Do the camera and microphone entitlements unblock those readings, and do mere reads prompt or end the app? P1's build plus `com.apple.security.device.camera` and `com.apple.security.device.audio-input`, first without usage descriptions, then with them, resetting with `tccutil reset Camera com.lucastkacz.ficha.dev` (and `Microphone`) between runs. The app ending means a read counts as use; an alert means a prompt; readings with no alert leave App Review as the only risk.
- **P3, before the grilling.** Does a `ficha` with its own sandbox run from Claude's terminal and share the group container with the sandboxed app, on macOS 26 and on 27? Sign the CLI with the team, with `CREATE_INFOPLIST_SECTION_IN_BINARY` and the entitlements `com.apple.security.app-sandbox` and `com.apple.security.application-groups` = `<TeamID>.com.lucastkacz.ficha.dev`, and point both data folders at the group container. With P1's app open, run `ficha capture "x"` from Claude Code, and a command that reads a file from standard input (`< ~/Desktop/x.png`). No crash: it runs; the file read: standard input works for #232's files; the inbox updates within a second: Darwin notifications cross; no storage error: file coordination works; any "would like to access data from other apps" alert, or a denial on 27, and whom it names, answer who macOS holds responsible.
- **P4.** Does the upload accept a tool with its own sandbox and no `inherit`? Archive with P3's signing, then Organizer › Validate App, which involves no review. App Review's own answer waits for the real submission, with the CLI described in the notes for App Review.
- **P5.** Does `CFFIXED_USER_HOME` still keep a sandboxed CLI's data out of Lucas's folders? Run P3's CLI with it set to a scratch folder and see where the data lands.
- **P6.** Only if container migration is chosen after all: a throwaway app whose `container-migration.plist` moves a folder with a WAL database whose writer was killed, and its preferences file; check `PRAGMA integrity_check`, the rows, the settings and what's left behind.
- **P7.** Can an unsandboxed build signed by the team fill the group container before the sandboxed app's first launch, with no prompt? A tiny tool claiming `<TeamID>.com.lucastkacz.migrationprobe` writes a file there, and a sandboxed probe app with the same group reads it; again with the tool signed ad hoc, which should prompt.
- **P8.** Does Export's atomic write work on a file from the save panel? Export to the Desktop and to a USB drive from P1's build; a denial on a temporary name means writing in place instead.
- **P9.** Where does Backups' Delete… put a copy? Log `resultingItemURL` in P1's build: `~/.Trash` keeps the dialog right; a trash in the container means new wording, or deleting for good.

**Focus, Shortcuts and widgets**

- **P10.** Only if `INFocusStatusCenter` is chosen: a team-signed menu-bar app with the Communication Notifications capability logs `isFocused` every 5 seconds while Lucas turns Do Not Disturb and another Focus on and off, and adds the app to a Focus's allowed apps.
- **P11, before the grilling.** Is a Focus filter's `perform` called on Lucas's macOS 26.3, and on 26.5 and later? A team-signed app with a `SetFocusFilterIntent` holding one `Bool`; Lucas adds the filter to Do Not Disturb, turns it on and off, and relaunches the app while it's on; log each `perform` and `current` at launch.
- **P12.** Do App Intents register from today's ad hoc build? A menu-bar app with one intent and one App Shortcut, signed `-`, copied to `/Applications` and launched once: the action in the Shortcuts app means yes; otherwise sign it with the team and repeat. The same for a Focus filter in System Settings.
- **P13, before the grilling, no build.** Does `shortcuts run` run an App Shortcut by name? With any installed app whose App Shortcuts show in the Shortcuts app, run `shortcuts list` and `shortcuts run "<its title>"; echo $?`. "Couldn't find" or 1 means a shortcut made by hand first.
- **P14.** Does an intent in the background show the review panel without bringing Ficha forward? In P12's app, `perform` orders a non-activating panel front while another app is in front; log which app is active before and after.
- **P15.** Does a widget extension load from an ad hoc build, reach the group container, and hear the app's Darwin notifications, and in which process does its button's intent run? A minimal app with a sandboxed widget and the group `<TeamID>.com.lucastkacz.widgetprobe`, signed `-` and then with the team; check `pluginkit -m -p com.apple.widgetkit-extension` and the widget gallery, write a file to the group container from the widget, and log the process ID in a button's `perform`.

**Sync and signing**

- **P16.** Does deleting a zone and creating it again under the same name reach another device as a deletion? Two engines on one Mac with `automaticallySync = false`, as WWDC23's [Sync to iCloud with CKSyncEngine](https://developer.apple.com/videos/play/wwdc2023/10188/) shows: one deletes and recreates the zone, the other fetches; log its events.
- **P17.** Does a menu-bar app get the engine's fetches on push without calling `registerForRemoteNotifications`? A development-signed Ficha Dev on the Mac, an edit on the iPhone, and the Mac's log watched for a fetch with none asked for.
- **P18.** Is CloudKit.framework linked when the sync code lives in FichaKit? `otool -L` on a Release build's executable.
- **P19.** Which environment does a Developer ID export with CloudKit get? Read its `com.apple.developer.icloud-container-environment` with `codesign -d --entitlements :-`.
- **P20.** Can a Mac development profile authorize the Production environment? Read the profile's entitlements with `security cms -D -i` and look at the values allowed.
- **P21.** Does an entitlements file with iCloud and push break CI's ad hoc Mac build? Add one on a throwaway branch and read CI's error, or run `make build` locally once no other build runs.
- **P22.** What do `CKContainer` and `CKSyncEngine` do in a process with no entitlements, such as `swift test` or `make render`? A scratch executable that creates both, run unsigned.
- **P23.** Does a universal purchase require an iPhone-only app to support the iPad? Add the macOS platform to the iPhone app's record in App Store Connect and read what it asks.
- **P24.** Does App Store Connect accept "Data Not Collected" for cards in the user's private database? Answer its questionnaire; no Apple source settles it.
- **P25.** Can the paid team register `com.lucastkacz.ficha.dev`, which the Personal Team registered? Switch `iPhone/Local.xcconfig` to the paid team and run `make install-iphone`.
- **P26.** How big is the first upload of Lucas's data, against his iCloud storage? Count the rows and the images' bytes through the `ficha` CLI, in a session where Lucas asks for it.
- **P27.** Which `PRAGMA synchronous` and `journal_mode` does Ficha's connection run with? A test that reads both through the engine's connection.
