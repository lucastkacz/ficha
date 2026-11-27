import AppKit
import FichaCore
import FichaData
import ServiceManagement
import SwiftUI

/// A tab of Settings, as `SettingsTab` lays it out (#492): a grouped form
/// with the tab's sections, in their order, each with its rows, in theirs,
/// under its heading and over its footer, as the desktop mock draws them. It
/// scrolls to its foot as Settings is asked to show one of its sections,
/// once each time it's asked, and says what Lucas did there that couldn't
/// be done.
struct SettingsTabContent: View {
    let tab: SettingsTab
    @Bindable var model: AppModel
    /// The shortcut that opens "Capture…" from any app, which General changes.
    let captureShortcut: CaptureShortcutRegistration
    /// How wide the tab is, as wide as Settings, which Advanced's table of
    /// copies fits.
    let width: CGFloat
    /// Closes the review panel, if it's open, before a restore.
    let closeReviewPanel: () -> Void
    /// Opens the Diagnostics window.
    let openDiagnostics: () -> Void
    /// Where Settings was asked to scroll to.
    let scroll: SettingsScroll
    /// How many of `scroll`'s requests the tab followed, so it follows each
    /// once, and not again each time Lucas picks the tab.
    @State private var followedRequests = 0
    /// Where the form is scrolled to.
    @State private var position = ScrollPosition()

    var body: some View {
        Form {
            ForEach(tab.sections, id: \.self) { section in
                SettingsSectionView(
                    section: section, model: model, captureShortcut: captureShortcut, width: width,
                    openDiagnostics: openDiagnostics)
            }
        }
        .formStyle(.grouped)
        .scrollPosition($position)
        .onChange(of: scroll.requests, initial: true) {
            follow(scroll)
        }
        .settingsTabActions(tab, model: model, closeReviewPanel: closeReviewPanel)
    }

    /// Scrolls to the form's foot when `scroll` asked last for one of the
    /// tab's sections, unless the tab followed that request already. In
    /// Advanced, the one tab that scrolls, the foot shows the section only
    /// when it's one of its last, Backups, the copies or Diagnostics; Settings
    /// is asked only for Backups and Diagnostics, which Advanced, as tall as
    /// Interruptions, shows there with Backups' heading. Our own: the foot in place of the section, since a grouped form on
    /// macOS 26 scrolls to no row's or section's `id`, with
    /// `ScrollViewReader` or `ScrollPosition`, as `make render`'s pictures
    /// showed, though it scrolls to an edge.
    private func follow(_ scroll: SettingsScroll) {
        guard scroll.requests > followedRequests else { return }
        followedRequests = scroll.requests
        guard let section = scroll.section, tab.sections.contains(section) else { return }
        // A turn later, once the form has its rows: as Settings opens, the
        // form is first asked only for its size, before it has any. The
        // toolbar, as it comes in, moves the form's offset, which undid a
        // scroll to a y in `make render`, but not one to an edge.
        Task {
            position.scrollTo(edge: .bottom)
        }
    }
}

extension View {
    /// What the form of `tab` says and asks over it, and reads as it shows:
    /// Pace and Advanced say when a change to a setting that decides a card's
    /// progress couldn't be kept; Pace, when Put it first failed; Sync,
    /// what its switch couldn't do; and Advanced asks before a restore or a
    /// deletion of copies, closing the review panel with `closeReviewPanel`
    /// before a restore.
    @ViewBuilder
    fileprivate func settingsTabActions(
        _ tab: SettingsTab, model: AppModel, closeReviewPanel: @escaping () -> Void
    ) -> some View {
        switch tab {
        case .general, .interruptions:
            self
        case .pace:
            failureAlert(progressSettingsFailure(of: model))
                .failureAlert(putItFirstFailure(of: model))
                .onAppear {
                    model.pace.read(model.settings)
                }
        case .sync:
            syncActions(model: model)
        case .advanced:
            failureAlert(progressSettingsFailure(of: model))
                .backupsActions(model: model, closeReviewPanel: closeReviewPanel)
        }
    }
}

/// Why the last change to a setting that decides a card's progress couldn't
/// be kept, as an alert says it, which closing it clears.
private func progressSettingsFailure(of model: AppModel) -> Binding<Failure?> {
    Binding {
        model.progressSettingsFailure.map { error in
            Failure(
                title: LocalizedStringResource(
                    "Couldn't save the change",
                    comment: """
                        An alert's title in Settings, when a change to the pace, the scheduling settings or the \
                        forgotten-often count couldn't be saved; the alert says why under it.
                        """),
                error: error)
        }
    } set: {
        if $0 == nil {
            model.progressSettingsFailure = nil
        }
    }
}

/// Why Put it first, in the Pace tab, failed, as an alert says it, which
/// closing it clears.
private func putItFirstFailure(of model: AppModel) -> Binding<Failure?> {
    Binding {
        model.pace.failure.map { failure in
            Failure(
                title: LocalizedStringResource(
                    "Couldn't put \(Deck.shownName(failure.deck)) first in the queue",
                    comment: """
                        An alert's title in Settings' Pace tab, with the name of the deck Put it first was for; the \
                        alert says why under it.
                        """),
                error: failure.error)
        }
    } set: {
        if $0 == nil {
            model.pace.dismissFailure()
        }
    }
}

/// A section of a tab of Settings: its rows, as `SettingsSection` lists them,
/// under its heading and over its footer, as the desktop mock draws them.
/// Decks to sync shows only while only the cards in the decks Lucas chooses
/// sync.
private struct SettingsSectionView: View {
    let section: SettingsSection
    @Bindable var model: AppModel
    let captureShortcut: CaptureShortcutRegistration
    let width: CGFloat
    let openDiagnostics: () -> Void

    var body: some View {
        switch section {
        case .general:
            Section {
                rows
            } footer: {
                Text(
                    """
                    A capture shortcut needs two of Control, Option and Command at least, so it doesn't take what \
                    you type or another app's shortcut. While you type one, Esc keeps the old one and Delete turns \
                    it off.
                    """)
            }
        case .cardSize:
            Section {
                rows
            } footer: {
                Text(
                    "⌘+ and ⌘− make a card larger or smaller in the review panel and the Cards window, and ⌘0 returns it to its normal size.",
                    comment:
                        "Under the Card size row of Settings: the keys that change it. ⌘+, ⌘− and ⌘0 stay as they are."
                )
            }
        case .about, .diagnostics:
            Section {
                rows
            }
        case .howFast:
            Section {
                rows
            } header: {
                Text(
                    "How fast?",
                    comment: "A heading of Settings' Pace tab, over the paces: how fast new cards come.")
            } footer: {
                HowFastFooter(pace: model.pace)
            }
        case .upNext:
            Section {
                rows
            } header: {
                Text(
                    "Up next",
                    comment: "A heading of Settings' Pace tab, over the queue of decks new cards come from.")
            } footer: {
                Text(
                    """
                    New cards come from the first deck until you've met them all, then from the next. Cards you've \
                    met keep coming from every deck.
                    """,
                    comment: "Settings, under Up next, in the Pace tab: below the queue of decks.")
            }
        case .whenFichaShowsUp:
            Section {
                rows
            } header: {
                Text(
                    "When \(AppVariant.current.name) shows up",
                    comment: """
                        A heading of Settings' Interruptions tab, with the app's name: over the active hours, how \
                        often the review panel shows up on its own and with how many cards.
                        """)
            }
        case .holdAppearancesBack:
            Section {
                rows
            } header: {
                Text("Hold appearances back during")
            }
        case .reviewPanel:
            Section {
                rows
            } header: {
                Text(
                    "The review panel",
                    comment: """
                        A heading of Settings' Interruptions tab: over how the review panel behaves when it shows \
                        up on its own.
                        """)
            } footer: {
                Text("When it shows up on its own. Opened with Review now, it takes the keyboard at once.")
            }
        case .sync:
            Section {
                rows
            } footer: {
                SyncSection.footer
            }
        case .decksToSync:
            if model.sync?.onlyChosenDecks == true {
                Section {
                    rows
                } header: {
                    SyncSection.decksHeader
                } footer: {
                    SyncSection.decksFooter
                }
            }
        case .learningSteps:
            Section {
                rows
            } header: {
                Text("Learning steps", comment: "Settings, under Advanced: the header of the learning steps.")
            } footer: {
                Text(
                    "A new card waits each step in turn before it graduates. With none, its first review graduates it.",
                    comment: "Settings, under Advanced: below the learning steps.")
            }
        case .relearningSteps:
            Section {
                rows
            } header: {
                Text("Relearning steps", comment: "Settings, under Advanced: the header of the relearning steps.")
            } footer: {
                Text(
                    """
                    A card you forget waits each step in turn before it graduates again. With none, it gets FSRS's \
                    interval at once.
                    """,
                    comment: "Settings, under Advanced: below the relearning steps; a card forgotten is a lapse.")
            }
        case .retention:
            Section {
                rows
            } footer: {
                Text(
                    """
                    A higher retention means shorter intervals and more reviews a day. A change applies from each \
                    card's next review.
                    """,
                    comment: """
                        Settings, under Advanced: below the desired retention and the longest interval, as Anki's \
                        manual says it; a change never moves a card's due time.
                        """)
            }
        case .forgottenOften:
            Section {
                rows
            } footer: {
                Text(
                    """
                    Each “Forgot” to a card out of its learning and relearning steps counts, since the card's front \
                    or back last changed. If you don't flag it, the panel offers again after half as many more.
                    """,
                    comment: """
                        Settings, under Advanced: below the offer to flag a card forgotten often, which counts \
                        Anki's lapses. “Forgot” is the review panel's button that records Anki's Again, also on key \
                        1.
                        """)
            }
        case .backups:
            Section {
                rows
            } header: {
                BackupsSection.header
            } footer: {
                BackupsSection.footer
            }
        case .copies:
            Section {
                rows
            } footer: {
                CopiesFooter(model: model)
            }
        }
    }

    /// The section's rows, in their order.
    private var rows: some View {
        ForEach(section.rows, id: \.self) { row in
            SettingsRowView(
                row: row, model: model, captureShortcut: captureShortcut, width: width,
                openDiagnostics: openDiagnostics)
        }
    }
}

/// A row of Settings, as `SettingsRow` names it: a setting Lucas changes, or
/// what a row says or does. A row with nothing to show, as the number of
/// times a card is forgotten before the offer to flag it, while the offer is
/// off, shows nothing.
private struct SettingsRowView: View {
    let row: SettingsRow
    @Bindable var model: AppModel
    let captureShortcut: CaptureShortcutRegistration
    let width: CGFloat
    let openDiagnostics: () -> Void

    var body: some View {
        switch row {
        case .startAtLogin:
            StartAtLoginRow()
        case .dueCountInMenuBar:
            Toggle("Show how many cards are due in the menu bar", isOn: $model.showsDueCount)
        case .captureShortcut:
            LabeledContent("Capture shortcut") {
                CaptureShortcutRecorder(registration: captureShortcut)
            }
        case .cardSize:
            cardSize
        case .version:
            VersionRow()
        case .privacyPolicy:
            PrivacyPolicyRow()
        case .pace:
            PaceRows(model: model)
        case .queue:
            QueueRows(model: model)
        case .activeHoursStart: InterruptionRow(setting: .activeHoursStart, model: model)
        case .activeHoursEnd: InterruptionRow(setting: .activeHoursEnd, model: model)
        case .separation: InterruptionRow(setting: .separation, model: model)
        case .cardsPerAppearance: InterruptionRow(setting: .cardsPerAppearance, model: model)
        case .lookAhead: InterruptionRow(setting: .lookAhead, model: model)
        case .waitAfterWaking: InterruptionRow(setting: .waitAfterWaking, model: model)
        case .meetings: InterruptionRow(setting: .meetings, model: model)
        case .videos: InterruptionRow(setting: .videos, model: model)
        case .fullScreenApps: InterruptionRow(setting: .fullScreenApps, model: model)
        case .waitAfterSuppression: InterruptionRow(setting: .waitAfterSuppression, model: model)
        case .takeTheKeyboard: ReviewPanelRow(setting: .takeTheKeyboard, model: model)
        case .idleBeforeTakingTheKeyboard: ReviewPanelRow(setting: .idleBeforeTakingTheKeyboard, model: model)
        case .closeWhenUntouched: ReviewPanelRow(setting: .closeWhenUntouched, model: model)
        case .syncWithICloud:
            SyncSwitchRow(model: model)
        case .cardsToSync:
            CardsToSyncRow(model: model)
        case .decksToSync:
            DecksToSyncRows(model: model)
        case .learningSteps:
            StepsSettings(list: .learning, scheduler: $model.settings.scheduler)
        case .relearningSteps:
            StepsSettings(list: .relearning, scheduler: $model.settings.scheduler)
        case .desiredRetention:
            DesiredRetentionRow(scheduler: $model.settings.scheduler)
        case .longestInterval:
            LongestIntervalRow(scheduler: $model.settings.scheduler)
        case .offerToFlag: ForgottenOftenRow(setting: .offerToFlag, model: model)
        case .forgottenOftenAfter: ForgottenOftenRow(setting: .forgottenOftenAfter, model: model)
        case .backupsFolder:
            BackupsFolderRow(model: model)
        case .backupFrequency:
            BackupFrequencyRow(model: model)
        case .backupsKept:
            BackupsKeptRow(model: model)
        case .lastBackup:
            LastBackupRow(model: model)
        case .copies:
            CopiesTable(model: model, width: width)
        case .diagnostics:
            diagnostics
        }
    }

    /// How large a card's text and images show, as the Mac's locale writes a
    /// percent, which follows the keys while Settings is open. Ficha has no
    /// View menu, so this is what says the size can change, and the footer
    /// which keys change it.
    private var cardSize: some View {
        Picker(
            String(
                localized: "Card size",
                comment: "A row of Settings that picks how large a card's text and images show, from 80% to 200%."),
            selection: $model.cardSize
        ) {
            ForEach(CardSize.steps, id: \.percent) { size in
                Text(size.percent.formatted(.percent)).tag(size)
            }
        }
    }

    /// The button that opens the Diagnostics window, which the menu opens
    /// too, until #541 takes it out of the menu (ADR 0041).
    private var diagnostics: some View {
        LabeledContent {
            Button(action: openDiagnostics) {
                Text("Open Diagnostics", comment: "Settings, under Advanced: opens the Diagnostics window.")
            }
        } label: {
            Text("Diagnostics")
            Text(
                "What each detector sees right now, and the latest appearances.",
                comment: "Settings, under Advanced: below Diagnostics, what its window shows.")
        }
    }
}

/// Whether the app starts at login, which only the real Ficha does, with
/// what the system says when it waits for Lucas's OK in System Settings.
private struct StartAtLoginRow: View {
    /// Whether the system starts the app at login, as it said last.
    @State private var startAtLogin = StartAtLogin.status

    var body: some View {
        Group {
            if StartAtLogin.isAvailable {
                Toggle(isOn: Binding(get: { startAtLogin.startsAtLogin }, set: { turnStartAtLogin(on: $0) })) {
                    Text("Start at login")
                    if startAtLogin == .requiresApproval {
                        Text("Allow it in System Settings, in Login Items.")
                    }
                }
                if startAtLogin == .requiresApproval {
                    Button("Open Login Items", action: StartAtLogin.openLoginItems)
                }
            } else {
                Toggle(isOn: .constant(false)) {
                    Text("Start at login")
                    Text("\(AppVariant.current.name) never does, so it doesn't get in the real Ficha's way.")
                }
                .disabled(true)
            }
        }
        // Lucas may change it in System Settings meanwhile, even before he
        // first picks this tab.
        .onAppear { startAtLogin = StartAtLogin.status }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            startAtLogin = StartAtLogin.status
        }
    }

    /// Turns starting at login on or off, which says why when macOS refuses,
    /// and shows what the system says then.
    private func turnStartAtLogin(on: Bool) {
        StartAtLogin.turn(on: on)
        startAtLogin = StartAtLogin.status
    }
}

/// Which version of the app this is, at General's foot, as macOS's About
/// panel says it: beside the app's icon, its name, its version, "Version",
/// the release version, then the build in parentheses, and its copyright
/// line, from its Info.plist. Lucas can select the text, to copy it.
private struct VersionRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: AppVariant.current.name)
                    .font(.headline)
                Text(versionLine)
                if let copyright = infoPlistValue("NSHumanReadableCopyright") {
                    Text(verbatim: copyright)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    /// The release version, then the build in parentheses.
    private var versionLine: String {
        guard let version = infoPlistValue("CFBundleShortVersionString"), let build = infoPlistValue("CFBundleVersion")
        else {
            return String(
                localized: "Unknown version", comment: "Settings, at the foot of General, when the build doesn't say.")
        }
        return String(
            localized: "Version \(version) (\(build))",
            comment: "Settings, at the foot of General: the release version, then the build number in parentheses.")
    }

    /// The app's Info.plist value for `key`, which the build sets.
    private func infoPlistValue(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}

/// A link that opens Ficha's privacy policy in the browser, at General's
/// foot.
private struct PrivacyPolicyRow: View {
    /// Where Ficha's privacy policy is published: `site/privacy.md`, which
    /// GitHub Pages publishes through `.github/workflows/pages.yml`.
    private static let address = "https://lucastkacz.github.io/ficha/privacy/"

    var body: some View {
        if let url = URL(string: Self.address) {
            Link("Privacy Policy", destination: url)
        } else {
            // A written-out address always makes a URL. Were it not to, the
            // address shows instead, for the user to copy.
            Text(verbatim: Self.address)
                .textSelection(.enabled)
        }
    }
}

/// How fast?'s paces, in the Pace tab, each a row a click picks, as the mock
/// draws them: its name, and under it its new cards a day and when every
/// deck in the queue is all met at it, with its radio at the trailing side.
/// Picking one sets Lucas's new cards a day for every deck together, which
/// syncs as the other settings that decide a card's progress do.
private struct PaceRows: View {
    @Bindable var model: AppModel

    var body: some View {
        ForEach(model.pace.paces, id: \.pace) { option in
            let isChosen = option.pace == model.pace.pace
            Button {
                model.settings.newCardsPerDay = option.pace.newCardsPerDay
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: option.pace.name)
                        Text(verbatim: line(option))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    PaceRadio(isChosen: isChosen)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isChosen ? [.isSelected] : [])
        }
    }

    /// What a pace's row says under its name: "2 new a day · queue met by
    /// mid-December", or its new cards a day alone while no deck waits for
    /// new cards.
    private func line(_ option: PaceTabState.PaceOption) -> String {
        let newCardsADay = option.pace.newCardsADay
        guard let wording = option.wording else { return newCardsADay }
        return wording.startsToday
            ? String(
                localized: "\(newCardsADay) · queue met \(wording.text)",
                comment: """
                    Settings, under How fast?, in the Pace tab: below a pace's name, its new cards a day, then when \
                    every deck in the queue is all met at it, starting with today, as in “queue met today or \
                    tomorrow”.
                    """)
            : String(
                localized: "\(newCardsADay) · queue met by \(wording.text)",
                comment: """
                    Settings, under How fast?, in the Pace tab: below a pace's name, its new cards a day, then when \
                    every deck in the queue is all met at it, as a day or a month.
                    """)
    }
}

/// What How fast? says under its paces: when every deck in the queue is all
/// met at Lucas's pace, or that no deck waits for new cards; nothing while
/// the queue can't be read, as Up next says why, or with no new cards a day.
private struct HowFastFooter: View {
    let pace: PaceTabState

    var body: some View {
        if pace.unreadable == nil {
            if pace.queue.isEmpty {
                Text(
                    "No deck waits for new cards.",
                    comment: "Settings, under How fast?, in the Pace tab: no deck in the queue has new cards.")
            } else if let wording = pace.queueMet {
                wording.startsToday
                    ? Text(
                        "At this pace, you'll have met every deck in your queue \(wording.text).",
                        comment: """
                            Settings, under How fast?, in the Pace tab: when the last deck in the queue is all met, \
                            starting with today, as in “today or tomorrow”.
                            """)
                    : Text(
                        "At this pace, you'll have met every deck in your queue by \(wording.text).",
                        comment: """
                            Settings, under How fast?, in the Pace tab: when the last deck in the queue is all met, \
                            as a day or a month.
                            """)
            }
        }
    }
}

/// Up next's rows, in the Pace tab: each deck in the queue new cards come
/// from, in its order, with its emoji and name, and under them whether its
/// new cards come now or next, how many it has to meet and when they're all
/// met, with Put it first while it would pass a deck, as the mock draws it;
/// or that no deck waits, or why the queue couldn't be read.
private struct QueueRows: View {
    @Bindable var model: AppModel

    var body: some View {
        if let error = model.pace.unreadable {
            Text(error.localizedDescription)
                .foregroundStyle(.secondary)
        } else if model.pace.queue.isEmpty {
            Text(
                "No deck waits. Add one from the Cards window.",
                comment: "Settings, under Up next, in the Pace tab, while no deck has new cards."
            )
            .foregroundStyle(.secondary)
        } else {
            ForEach(model.pace.queue) { deck in
                HStack(spacing: 10) {
                    Group {
                        if let emoji = deck.deck.shownEmoji {
                            Text(verbatim: emoji)
                        } else {
                            Image(systemName: CardGroup.deck(Deck.defaultName).symbol)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 22)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: Deck.shownName(deck.deck.name))
                        Text(verbatim: line(deck))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if deck.offersPutItFirst {
                        Button {
                            model.pace.putFirst(deck.deck.name, with: model.settings)
                        } label: {
                            Text(
                                "Put it first",
                                comment: """
                                    A button of Settings' Pace tab, beside a deck in the queue: its new cards come \
                                    first.
                                    """)
                        }
                    }
                }
            }
        }
    }

    /// What a deck's row says under its name: "Now · 12 cards to meet · on
    /// track for mid-December", "Next · …", without when they're all met
    /// while Lucas meets no new card a day.
    private func line(_ deck: PaceTabState.QueueRow) -> String {
        let count = deck.newCards
        return switch (deck.isNow, deck.wording) {
        case (true, let wording?):
            String(
                localized: "Now · \(count) cards to meet · on track for \(wording.text)",
                comment: """
                    Settings, under Up next, in the Pace tab: below the name of the deck new cards come from now, how \
                    many of its new cards are still to meet, and when they'll all be.
                    """)
        case (true, nil):
            String(
                localized: "Now · \(count) cards to meet",
                comment: """
                    Settings, under Up next, in the Pace tab: below the name of the deck new cards come from now, how \
                    many of its new cards are still to meet.
                    """)
        case (false, let wording?):
            String(
                localized: "Next · \(count) cards to meet · on track for \(wording.text)",
                comment: """
                    Settings, under Up next, in the Pace tab: below the name of a deck that waits its turn, how many \
                    of its new cards are still to meet, and when they'll all be.
                    """)
        case (false, nil):
            String(
                localized: "Next · \(count) cards to meet",
                comment: """
                    Settings, under Up next, in the Pace tab: below the name of a deck that waits its turn, how many \
                    of its new cards are still to meet.
                    """)
        }
    }
}

/// A row of Interruptions' When Ficha shows up and Hold appearances back
/// during: when the review panel shows up on its own, and what holds it
/// back.
private struct InterruptionRow: View {
    /// The rows it draws, each named by its `SettingsRow`, so a row sent
    /// here that it doesn't draw fails to compile, not to show.
    enum Setting {
        case activeHoursStart, activeHoursEnd, separation, cardsPerAppearance, lookAhead, waitAfterWaking, meetings,
            videos, fullScreenApps, waitAfterSuppression
    }

    let setting: Setting
    @Bindable var model: AppModel

    var body: some View {
        switch setting {
        case .activeHoursStart:
            Picker(selection: activeHoursStart) {
                ForEach(0..<model.settings.activeHours.upperBound, id: \.self) { hour in
                    Text(hourOfDay(hour)).tag(hour)
                }
            } label: {
                Text("Start at", comment: "Settings, under Interruptions: the hour active hours start at.")
            }
        case .activeHoursEnd:
            Picker(selection: activeHoursEnd) {
                ForEach((model.settings.activeHours.lowerBound + 1)...24, id: \.self) { hour in
                    Text(hourOfDay(hour)).tag(hour)
                }
            } label: {
                Text("End at", comment: "Settings, under Interruptions: the hour active hours end at.")
            }
        case .separation:
            Picker(selection: $model.settings.separation) {
                spans(separations, including: model.settings.separation)
            } label: {
                Text(
                    "At least this long apart",
                    comment: "Settings, under Interruptions: the least time between two appearances.")
            }
        case .cardsPerAppearance:
            Picker("Cards per appearance", selection: $model.settings.cardsPerAppearance) {
                counts(1...10, including: model.settings.cardsPerAppearance)
            }
        case .lookAhead:
            Picker(selection: $model.settings.lookAhead) {
                spans(lookAheads, including: model.settings.lookAhead)
            } label: {
                Text(
                    "Bring along cards due within",
                    comment:
                        "Settings, under Interruptions: the look-ahead, how soon a card due later may come along.")
            }
        case .waitAfterWaking:
            Picker(selection: $model.settings.waitAfterWaking) {
                spans(waitsAfterWaking, including: model.settings.waitAfterWaking)
            } label: {
                Text(
                    "After the Mac wakes, wait",
                    comment: "Settings, under Interruptions: how long an appearance waits once the Mac wakes.")
            }
        case .meetings:
            Toggle(isOn: applies(.meeting)) {
                Text("Meetings")
                Text("The camera or the microphone in use")
            }
        case .videos:
            Toggle(isOn: applies(.video)) {
                Text("Videos")
                Text("An app keeping the display awake")
            }
        case .fullScreenApps:
            Toggle("Full-screen apps", isOn: applies(.fullScreen))
        case .waitAfterSuppression:
            Picker(selection: $model.settings.waitAfterSuppression) {
                spans(waitsAfterSuppression, including: model.settings.waitAfterSuppression)
            } label: {
                Text(
                    "Then wait",
                    comment:
                        "Settings, under Hold appearances back during: how long an appearance waits once a meeting, a video, a full-screen app or a Focus ends."
                )
            }
        }
    }

    /// The hour active hours start at, which stays before the one they end at.
    private var activeHoursStart: Binding<Int> {
        Binding(
            get: { model.settings.activeHours.lowerBound },
            set: { model.settings.activeHours = $0..<model.settings.activeHours.upperBound })
    }

    /// The hour active hours end at, which stays after the one they start at.
    private var activeHoursEnd: Binding<Int> {
        Binding(
            get: { model.settings.activeHours.upperBound },
            set: { model.settings.activeHours = model.settings.activeHours.lowerBound..<$0 })
    }

    /// Whether `suppression` holds appearances back.
    private func applies(_ suppression: Suppression) -> Binding<Bool> {
        Binding(
            get: { model.settings.suppressionsThatApply.contains(suppression) },
            set: { applies in
                if applies {
                    model.settings.suppressionsThatApply.insert(suppression)
                } else {
                    model.settings.suppressionsThatApply.remove(suppression)
                }
            })
    }
}

/// A row of Interruptions' The review panel: how the panel behaves when it
/// shows up on its own.
private struct ReviewPanelRow: View {
    /// The rows it draws, each named by its `SettingsRow`, as
    /// `InterruptionRow`'s are.
    enum Setting {
        case takeTheKeyboard, idleBeforeTakingTheKeyboard, closeWhenUntouched
    }

    let setting: Setting
    @Bindable var model: AppModel

    var body: some View {
        switch setting {
        case .takeTheKeyboard:
            Picker(selection: $model.settings.focusMode) {
                Text("Never", comment: "Settings: the review panel never takes the keyboard on its own.")
                    .tag(FocusMode.never)
                Text(
                    "Once you're idle", comment: "Settings: the review panel takes the keyboard once Lucas is idle."
                )
                .tag(FocusMode.onceIdle)
                Text("Always", comment: "Settings: the review panel takes the keyboard as it shows up.")
                    .tag(FocusMode.always)
            } label: {
                Text(
                    "Take the keyboard",
                    comment: """
                        Settings, under Interruptions: when the review panel takes the keyboard as it shows up on \
                        its own.
                        """)
            }
        case .idleBeforeTakingTheKeyboard:
            Picker(selection: $model.settings.idleBeforeTakingKeyboard) {
                spans(idleTimes, including: model.settings.idleBeforeTakingKeyboard, in: [.seconds])
            } label: {
                Text(
                    "Idle for",
                    comment: """
                        Settings, under Interruptions: how long Lucas must be idle before the review panel takes \
                        the keyboard, in the "Once you're idle" focus mode.
                        """)
            }
            .disabled(model.settings.focusMode != .onceIdle)
        case .closeWhenUntouched:
            Picker(selection: $model.settings.autoClose) {
                spans(autoCloses, including: model.settings.autoClose)
            } label: {
                Text(
                    "Close it when untouched for",
                    comment: """
                        Settings, under Interruptions: how long the review panel stays open untouched before it \
                        closes on its own.
                        """)
            }
        }
    }
}

/// A row of Advanced's offer to flag a card forgotten often: whether the
/// panel offers to flag it, and, while it does, after how many lapses, each
/// a “Forgot”, Anki's Again, while the card is out of its learning and
/// relearning steps.
private struct ForgottenOftenRow: View {
    /// The rows it draws, each named by its `SettingsRow`, as
    /// `InterruptionRow`'s are.
    enum Setting {
        case offerToFlag, forgottenOftenAfter
    }

    let setting: Setting
    @Bindable var model: AppModel

    var body: some View {
        switch setting {
        case .offerToFlag:
            Toggle(isOn: offersToFlag) {
                Text(
                    "Offer to flag a card you forget often",
                    comment:
                        "Settings, under Advanced: whether the review panel offers to flag a card the user keeps answering “Forgot”, Anki's Again, to while it's out of its learning and relearning steps, so it gets fixed."
                )
                Text(
                    "So it gets fixed. Ficha never flags a card on its own.",
                    comment: "Settings, under Advanced: below the offer to flag a card forgotten often.")
            }
        case .forgottenOftenAfter:
            // While the offer is on.
            if let number = Binding($model.settings.forgottenOftenAfter) {
                Stepper(value: number, in: 4...20) {
                    Text(
                        "After forgetting it \(number.wrappedValue) times",
                        comment:
                            "Settings, under Advanced: how many “Forgot” answers, Anki's Again, to one of a card's ways while it was out of its learning and relearning steps, Anki's lapses, since its front or back last changed, bring the offer to flag it."
                    )
                }
            }
        }
    }

    /// Whether the panel offers to flag a card forgotten often: turned on,
    /// it offers after the default number.
    private var offersToFlag: Binding<Bool> {
        Binding(
            get: { model.settings.forgottenOftenAfter != nil },
            set: { offers in
                model.settings.forgottenOftenAfter = offers ? ReviewSettings.defaults.forgottenOftenAfter : nil
            })
    }
}

extension FocusedValues {
    /// Whether the keyboard is in Advanced's Longest interval field, where
    /// ⌘⌫ deletes what's before the insertion point, not Backups' copies.
    @Entry var isEditingLongestInterval: Bool?
}

/// Advanced's desired retention, which Settings steps a percent at a time,
/// within what the scheduler takes, as `Scheduler`'s changes decide.
private struct DesiredRetentionRow: View {
    @Binding var scheduler: Scheduler

    var body: some View {
        LabeledContent {
            HStack {
                Text(scheduler.desiredRetention, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                Stepper(value: retention, in: Scheduler.desiredRetentions, step: 0.01) {
                    name
                }
                .labelsHidden()
                .accessibilityValue(Text(scheduler.desiredRetention, format: .percent))
            }
        } label: {
            name
            Text(
                "From \(Scheduler.desiredRetentions.lowerBound, format: .percent) to \(Scheduler.desiredRetentions.upperBound, format: .percent)",
                comment: "Settings, under Advanced: below the desired retention, the least and the most it can be.")
        }
    }

    /// The desired retention's name.
    private var name: Text {
        Text(
            "Desired retention",
            comment: "Settings, under Advanced: how likely the user wants to be to remember a card when it's due.")
    }

    /// The desired retention, which Settings steps a percent at a time.
    private var retention: Binding<Double> {
        Binding(
            get: { scheduler.desiredRetention },
            set: { retention in change(&scheduler) { $0.changingDesiredRetention(to: retention) } })
    }
}

/// Advanced's longest interval, in days, typed or stepped, which a number
/// typed past its bounds stops at, as `Scheduler`'s changes decide.
private struct LongestIntervalRow: View {
    @Binding var scheduler: Scheduler

    var body: some View {
        LabeledContent {
            HStack {
                TextField(value: longestInterval, format: .number) {
                    name
                }
                .labelsHidden()
                .focusedValue(\.isEditingLongestInterval, true)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 64)
                Stepper(value: longestInterval, in: Scheduler.longestIntervalsInDays) {
                    name
                }
                .labelsHidden()
            }
        } label: {
            name
            Text(
                "In days, up to \(Scheduler.longestIntervalsInDays.upperBound, format: .number)",
                comment: "Settings, under Advanced: below the longest interval, its unit and the most it can be.")
        }
    }

    /// The longest interval's name.
    private var name: Text {
        Text(
            "Longest interval",
            comment: "Settings, under Advanced: the longest a card can wait after a review, in days.")
    }

    /// The longest interval, in days, which a number typed past its bounds
    /// stops at.
    private var longestInterval: Binding<Int> {
        Binding(
            get: { scheduler.longestIntervalInDays },
            set: { days in change(&scheduler) { $0.changingLongestInterval(toDays: days) } })
    }
}

/// Changes `scheduler` to what `edit` makes of it, unless it makes none.
private func change(_ scheduler: inout Scheduler, with edit: (Scheduler) -> Scheduler?) {
    if let changed = edit(scheduler) {
        scheduler = changed
    }
}

/// A step's row in Settings' Advanced tab: the step's place in its list,
/// from 0, and its interval. A form tells its rows apart by their IDs across
/// its sections, so each list's rows have their own, or the form mixes up the
/// two lists' rows and draws them in the wrong sections.
private struct StepRow: Identifiable {
    struct ID: Hashable {
        let list: Scheduler.StepList
        let index: Int
    }

    let list: Scheduler.StepList
    let index: Int
    let interval: Duration

    var id: ID { ID(list: list, index: index) }
}

/// The rows of a list of steps in Settings' Advanced tab, the learning steps
/// or the relearning steps, as FSRS spaces cards with them, as Anki's deck
/// options hold them (#404): each picked from the intervals `Scheduler`
/// offers it, which keeps a step longer than the one before it and shorter
/// than the one after it, then a button that adds one. A list may have none.
/// A change applies from each card's next review.
private struct StepsSettings: View {
    /// Which steps they are.
    let list: Scheduler.StepList
    /// The settings that hold them.
    @Binding var scheduler: Scheduler

    var body: some View {
        ForEach(scheduler.steps(list).enumerated().map { StepRow(list: list, index: $0.offset, interval: $0.element) })
        { row in
            let index = row.index
            let interval = row.interval
            HStack {
                Picker(selection: step(index, lasting: interval)) {
                    spans(scheduler.intervals(forStep: index, of: list), including: interval)
                } label: {
                    Text(
                        "Step \(index + 1)",
                        comment: "Settings, under Advanced: a learning or relearning step, counted from 1.")
                }
                Button {
                    change(&scheduler) { $0.removingStep(index, of: list) }
                } label: {
                    Label {
                        Text(
                            "Remove Step \(index + 1)",
                            comment: "Settings, under Advanced: removes a learning or relearning step.")
                    } icon: {
                        Image(systemName: "minus.circle")
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        }
        Button {
            change(&scheduler) { $0.addingStep(to: list) }
        } label: {
            Text("Add Step", comment: "Settings, under Advanced: adds a learning or relearning step at the end.")
        }
        .disabled(scheduler.addingStep(to: list) == nil)
    }

    /// The interval of the step at `index`, which lasts `interval` as its row
    /// shows. The row may outlive its step for a moment once Lucas removes
    /// it, so the step is never read by its index.
    private func step(_ index: Int, lasting interval: Duration) -> Binding<Duration> {
        Binding(
            get: { interval },
            set: { newInterval in change(&scheduler) { $0.changingStep(index, of: list, to: newInterval) } })
    }
}

/// The hour of the day `hour` starts at, as the Mac writes it, like "9:00":
/// 24 is midnight, at the end of the day.
private func hourOfDay(_ hour: Int) -> String {
    let start = DateComponents(calendar: .autoupdatingCurrent, year: 2001, month: 1, day: 1, hour: hour)
    return start.date?.formatted(date: .omitted, time: .shortened) ?? "\(hour)"
}

/// The options of a picker of counts: `range`, along with `current`.
@ViewBuilder
private func counts(_ range: ClosedRange<Int>, including current: Int) -> some View {
    ForEach(Set(range).union([current]).sorted(), id: \.self) { count in
        Text(count, format: .number).tag(count)
    }
}

/// The options of a picker of spans of time: `options`, along with `current`,
/// shortest first, in words, like "20 minutes", in `units`.
@ViewBuilder
private func spans(
    _ options: [Duration],
    including current: Duration,
    in units: Set<Duration.UnitsFormatStyle.Unit> = [.days, .hours, .minutes]
) -> some View {
    ForEach(Set(options).union([current]).sorted(), id: \.self) { span in
        Text(span.formatted(.units(allowed: units, width: .wide))).tag(span)
    }
}

/// The separations to pick from.
private let separations: [Duration] = [10, 15, 20, 30, 45, 60, 90, 120, 180, 240].map(Duration.minutes)
/// The look-aheads to pick from.
private let lookAheads: [Duration] = [0, 5, 10, 15, 20, 30, 45, 60].map(Duration.minutes)
/// The auto-closes to pick from.
private let autoCloses: [Duration] = [1, 2, 3, 5, 10, 15, 20, 30, 60].map(Duration.minutes)
/// The waits after the Mac wakes to pick from.
private let waitsAfterWaking: [Duration] = [0, 1, 2, 3, 5, 10, 15].map(Duration.minutes)
/// The idle times to pick from, before the review panel takes the keyboard.
private let idleTimes: [Duration] = [1, 2, 3, 5, 10, 15, 30].map { .seconds($0) }
/// The waits after a suppression to pick from.
private let waitsAfterSuppression: [Duration] = [0, 1, 2, 3, 5, 10, 15].map(Duration.minutes)
