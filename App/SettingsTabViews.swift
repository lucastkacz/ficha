import AppKit
import FichaCore
import ServiceManagement
import SwiftUI

/// The General tab of Settings: what the app does around the cards.
struct GeneralSettings: View {
    @Bindable var model: AppModel
    /// The shortcut that opens "Capture…" from any app, which Settings changes.
    let captureShortcut: CaptureShortcutRegistration
    /// Whether the system starts the app at login, as it said last.
    @State private var startAtLogin = StartAtLogin.status

    var body: some View {
        Section {
            startAtLoginToggle
            Toggle("Show how many cards are due in the menu bar", isOn: $model.showsDueCount)
            LabeledContent("Capture shortcut") {
                CaptureShortcutRecorder(registration: captureShortcut)
            }
        } footer: {
            Text(
                """
                A capture shortcut needs two of Control, Option and Command at least, so it doesn't take what \
                you type or another app's shortcut. While you type one, Esc keeps the old one and Delete turns \
                it off.
                """)
        }
        // Lucas may change it in System Settings meanwhile, even before he
        // first picks this tab.
        .onAppear { startAtLogin = StartAtLogin.status }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            startAtLogin = StartAtLogin.status
        }
    }

    /// Whether the app starts at login, which only the real Ficha does.
    @ViewBuilder private var startAtLoginToggle: some View {
        if StartAtLogin.isAvailable {
            Toggle(
                isOn: Binding(
                    get: { [.enabled, .requiresApproval].contains(startAtLogin) }, set: { turnStartAtLogin(on: $0) })
            ) {
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

    /// Turns starting at login on or off, and says why when macOS refuses.
    private func turnStartAtLogin(on: Bool) {
        do {
            try StartAtLogin.turn(on: on)
        } catch {
            showAlert(
                String(localized: "Couldn't change whether \(AppVariant.current.name) starts at login"),
                explaining: error, style: .warning, button: String(localized: "OK"))
        }
        startAtLogin = StartAtLogin.status
    }
}

/// The Appearances tab of Settings: when the review panel shows up on its
/// own, and what holds it back.
struct AppearancesSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Section {
            Picker(selection: activeHoursStart) {
                ForEach(0..<model.settings.activeHours.upperBound, id: \.self) { hour in
                    Text(hourOfDay(hour)).tag(hour)
                }
            } label: {
                Text("Start at", comment: "Settings, under Appearances: the hour active hours start at.")
            }
            Picker(selection: activeHoursEnd) {
                ForEach((model.settings.activeHours.lowerBound + 1)...24, id: \.self) { hour in
                    Text(hourOfDay(hour)).tag(hour)
                }
            } label: {
                Text("End at", comment: "Settings, under Appearances: the hour active hours end at.")
            }
            Picker(selection: $model.settings.separation) {
                spans(separations, including: model.settings.separation)
            } label: {
                Text(
                    "At least this long apart",
                    comment: "Settings, under Appearances: the least time between two appearances.")
            }
            Picker("Cards per appearance", selection: $model.settings.cardsPerAppearance) {
                counts(1...10, including: model.settings.cardsPerAppearance)
            }
            Picker("New cards per day", selection: $model.settings.newCardsPerDay) {
                counts(0...20, including: model.settings.newCardsPerDay)
            }
            Picker(selection: $model.settings.lookAhead) {
                spans(lookAheads, including: model.settings.lookAhead)
            } label: {
                Text(
                    "Bring along cards due within",
                    comment:
                        "Settings, under Appearances: the look-ahead, how soon a card due later may come along.")
            }
            Picker(selection: $model.settings.waitAfterWaking) {
                spans(waitsAfterWaking, including: model.settings.waitAfterWaking)
            } label: {
                Text(
                    "After the Mac wakes, wait",
                    comment: "Settings, under Appearances: how long an appearance waits once the Mac wakes.")
            }
        }
        Section("Hold appearances back during") {
            Toggle(isOn: applies(.meeting)) {
                Text("Meetings")
                Text("The camera or the microphone in use")
            }
            Toggle(isOn: applies(.video)) {
                Text("Videos")
                Text("An app keeping the display awake")
            }
            Toggle("Full-screen apps", isOn: applies(.fullScreen))
            Picker(selection: $model.settings.waitAfterSuppression) {
                spans(waitsAfterSuppression, including: model.settings.waitAfterSuppression)
            } label: {
                Text(
                    "Then wait",
                    comment:
                        "Settings, under Hold appearances back during: how long an appearance waits once a meeting, a video or a full-screen app ends."
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

/// The Review panel tab of Settings: how the panel behaves when it shows up
/// on its own, and whether it offers to flag a card forgotten often, after
/// how many “Don't know”.
struct ReviewPanelSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Section {
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
                    comment:
                        "Settings, under Review panel: when the panel takes the keyboard as it shows up on its own."
                )
            }
            Picker(selection: $model.settings.idleBeforeTakingKeyboard) {
                spans(idleTimes, including: model.settings.idleBeforeTakingKeyboard, in: [.seconds])
            } label: {
                Text(
                    "Idle for",
                    comment: """
                        Settings, under Review panel: how long Lucas must be idle before the panel takes the \
                        keyboard, in the "Once you're idle" focus mode.
                        """)
            }
            .disabled(model.settings.focusMode != .onceIdle)
            Picker(selection: $model.settings.autoClose) {
                spans(autoCloses, including: model.settings.autoClose)
            } label: {
                Text(
                    "Close it when untouched for",
                    comment:
                        "Settings, under Review panel: how long it stays open untouched before it closes on its own."
                )
            }
        } footer: {
            Text("When it shows up on its own. Opened with Review now, it takes the keyboard at once.")
        }
        Section {
            Toggle(isOn: offersToFlag) {
                Text(
                    "Offer to flag a card you forget often",
                    comment:
                        "Settings, under Review panel: whether the panel offers to flag a card the user keeps answering “Don't know” to, so it gets fixed."
                )
                Text(
                    "So it gets fixed. Ficha never flags a card on its own.",
                    comment: "Settings, under Review panel: below the offer to flag a card forgotten often.")
            }
            // While the offer is on.
            if let number = Binding($model.settings.forgottenOftenAfter) {
                Stepper(value: number, in: 4...20) {
                    Text(
                        "After forgetting it \(number.wrappedValue) times",
                        comment:
                            "Settings, under Review panel: how many “Don't know” answers to one of a card's ways, since its front or back last changed, bring the offer to flag it."
                    )
                }
            }
        } footer: {
            Text(
                """
                Each “Don't know” counts, since the card's front or back last changed. If you don't flag it, the \
                panel offers again after half as many more.
                """)
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

/// The Ladder tab of Settings: the ladder's steps, each picked from a list
/// that keeps it longer than the step before it and shorter than the one
/// after it, so every ladder Lucas makes is one the engine can use. A change
/// re-times every card from its history.
struct LadderSettings: View {
    @Binding var ladder: Ladder

    var body: some View {
        Section {
            ForEach(Array(ladder.waits.enumerated()), id: \.offset) { index, wait in
                HStack {
                    Picker(selection: step(index, waiting: wait)) {
                        spans(ladderSteps.filter { fits($0, at: index) }, including: wait)
                    } label: {
                        Text("Step \(index + 1)", comment: "Settings: a step of the ladder, counted from 1.")
                    }
                    Button {
                        change { waits in
                            if waits.indices.contains(index) {
                                waits.remove(at: index)
                            }
                        }
                    } label: {
                        Label {
                            Text("Remove Step \(index + 1)", comment: "Settings: removes a step of the ladder.")
                        } icon: {
                            Image(systemName: "minus.circle")
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(ladder.waits.count == 1)
                }
            }
            Button("Add Step") {
                if let next = nextStep {
                    change { $0.append(next) }
                }
            }
            .disabled(nextStep == nil)
        } footer: {
            Text(
                """
                Each time you know a card, it climbs a step and waits that long to be due again. A change re-times \
                every card from its history, and a card beyond a shorter ladder's end sits on its last step.
                """)
        }
    }

    /// The wait of the step at `index`, which waits `wait` as its row shows.
    /// The row may outlive its step for a moment once Lucas removes it, so
    /// the step is never read by its index.
    private func step(_ index: Int, waiting wait: Duration) -> Binding<Duration> {
        Binding(
            get: { wait },
            set: { newWait in
                change { waits in
                    if waits.indices.contains(index) {
                        waits[index] = newWait
                    }
                }
            })
    }

    /// Whether `wait` fits the step at `index`: longer than the step before
    /// it and shorter than the one after it.
    private func fits(_ wait: Duration, at index: Int) -> Bool {
        let waits = ladder.waits
        return (index == 0 || waits[index - 1] < wait) && (index == waits.count - 1 || wait < waits[index + 1])
    }

    /// The wait a new last step gets: the first in the list after the last
    /// step's, or nil when there's none.
    private var nextStep: Duration? {
        ladderSteps.first { $0 > ladder.waits[ladder.waits.count - 1] }
    }

    /// Changes the ladder's waits with `edit`, unless that doesn't leave a
    /// ladder.
    private func change(_ edit: (inout [Duration]) -> Void) {
        var waits = ladder.waits
        edit(&waits)
        if let changed = Ladder(waits: waits) {
            ladder = changed
        }
    }
}

/// A tab of Settings with some of the settings that decide a card's
/// progress, in a grouped form, which says when the engine couldn't keep a
/// change to them, as the Backups tab says what it couldn't do.
struct ProgressSettingsForm<Settings: View>: View {
    let model: AppModel
    let settings: Settings

    var body: some View {
        Form { settings }
            .formStyle(.grouped)
            .failureAlert(failure)
    }

    /// Why the last change couldn't be kept, as an alert says it, which
    /// closing it clears.
    private var failure: Binding<Failure?> {
        Binding {
            model.progressSettingsFailure.map { error in
                Failure(
                    title: LocalizedStringResource(
                        "Couldn't save the change",
                        comment: """
                            An alert's title in Settings, when a change to the ladder, the new cards per day or the \
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
}

/// The About tab of Settings: which version of the app this is, as macOS's
/// About panel shows it. Under the app's icon and name come its version and
/// its copyright line, from its Info.plist: "Version", the release version,
/// then the build in parentheses. Lucas can select the text, to copy it.
struct AboutTab: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(verbatim: AppVariant.current.name)
                .font(.title2.bold())
            Text(versionLine)
            if let copyright = infoPlistValue("NSHumanReadableCopyright") {
                Text(verbatim: copyright)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// The release version, then the build in parentheses.
    private var versionLine: String {
        guard let version = infoPlistValue("CFBundleShortVersionString"), let build = infoPlistValue("CFBundleVersion")
        else {
            return String(localized: "Unknown version", comment: "Settings' About tab, when the build doesn't say.")
        }
        return String(
            localized: "Version \(version) (\(build))",
            comment: "Settings' About tab: the release version, then the build number in parentheses.")
    }

    /// The app's Info.plist value for `key`, which the build sets.
    private func infoPlistValue(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
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
/// The look-aheads to pick from, up to `ReviewSettings.longestLookAhead`,
/// which the ladder counts on to tell two devices' reviews apart.
private let lookAheads: [Duration] = [0, 5, 10, 15, 20, 30, 45, 60].map(Duration.minutes)
/// The auto-closes to pick from.
private let autoCloses: [Duration] = [1, 2, 3, 5, 10, 15, 20, 30, 60].map(Duration.minutes)
/// The waits after the Mac wakes to pick from.
private let waitsAfterWaking: [Duration] = [0, 1, 2, 3, 5, 10, 15].map(Duration.minutes)
/// The idle times to pick from, before the review panel takes the keyboard.
private let idleTimes: [Duration] = [1, 2, 3, 5, 10, 15, 30].map { .seconds($0) }
/// The waits after a suppression to pick from.
private let waitsAfterSuppression: [Duration] = [0, 1, 2, 3, 5, 10, 15].map(Duration.minutes)
/// The ladder steps to pick from: from 10 minutes to a year, the standard
/// ladder's among them.
private let ladderSteps: [Duration] =
    [10, 15, 20, 30].map(Duration.minutes) + [1, 2, 3, 4, 6, 8, 12].map { Duration.minutes($0 * 60) }
    + [1, 2, 3, 4, 5, 6, 7, 10, 12, 14, 21, 30, 45, 60, 75, 90, 120, 180, 365].map { Duration.minutes($0 * 24 * 60) }
