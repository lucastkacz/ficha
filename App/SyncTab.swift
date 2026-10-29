import FichaData
import SwiftUI

/// The Sync tab of Settings, in an app that syncs (ADR 0017): "Sync with
/// iCloud", and under it the status line, how sync stands and, while it's
/// off, what turning it on does; then which cards sync, every one or only
/// those with the tags the user ticks in a list, a tree of tags inside tags
/// (ADR 0021), each with what its images and sounds weigh (ADR 0020). What
/// the switch shows, the line says and the list holds, the model's
/// `SyncTabState` decides.
struct SyncTab: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            if let sync = model.sync {
                Section {
                    Toggle(isOn: Binding(get: { sync.switchIsOn }, set: { model.sync?.turnSync(on: $0) })) {
                        Text(
                            "Sync with iCloud", comment: "Settings, under Sync: the switch that turns sync on and off.")
                        statusLine(sync.status)
                    }
                    .disabled(!sync.canTurnSwitch)
                    Picker(
                        selection: Binding(
                            get: { sync.onlyChosenTags }, set: { model.sync?.syncOnlyChosenTags($0) })
                    ) {
                        Text("Every card", comment: "Settings, under Sync: the choice that syncs every card.")
                            .tag(false)
                        Text(
                            "Only cards with the tags you choose",
                            comment: "Settings, under Sync: the choice that syncs only the cards with ticked tags."
                        )
                        .tag(true)
                    } label: {
                        Text("Cards to sync", comment: "Settings, under Sync: the choice of which cards sync.")
                    }
                    .pickerStyle(.radioGroup)
                    .disabled(!sync.canChoose)
                } footer: {
                    Text(
                        """
                        Your cards, their progress and the inbox stay the same on each of your devices, through \
                        your own iCloud. Each device keeps its own backups.
                        """,
                        comment: "Settings, under Sync, below the switch: what sync does.")
                }
                if sync.onlyChosenTags {
                    tagsSection(sync)
                }
            }
        }
        .formStyle(.grouped)
        .failureAlert(failure)
        .onAppear {
            model.sync?.read()
        }
    }

    /// The status line under the switch, as the state says how sync stands.
    @ViewBuilder
    private func statusLine(_ status: SyncTabState.Status) -> some View {
        switch status {
        case .on(let lastSynced?):
            Text(
                "Last synced \(lastSynced.formatted(date: .abbreviated, time: .shortened))",
                comment: "Settings, under Sync: when this Mac last synced, with the date and time.")
        case .on(nil):
            Text(
                "Not synced yet",
                comment: """
                    Settings, under Sync: sync is on, and this Mac hasn't synced yet, or not since the app's data \
                    was deleted from iCloud.
                    """)
        case .iCloudFull:
            Text(
                "iCloud is full: your changes wait until you free up space",
                comment: "Settings, under Sync: iCloud refused what this Mac sent, for lack of room.")
        case .off(let turningOn, let sending):
            if let turningOn {
                turningOnLine(turningOn)
            }
            if let sending {
                Text(
                    "Turning it on sends \(sending.formatted(.byteCount(style: .file))) of images and sounds to your iCloud.",
                    comment: """
                        Settings, under Sync, while sync is off: what the images and sounds turning sync on sends \
                        weigh, said from 100 MB.
                        """)
            }
        case .noAccount:
            Text("No iCloud account", comment: "Settings, under Sync: this Mac isn't signed into iCloud.")
        case .checkingAccount:
            Text(
                "Checking your iCloud account…",
                comment: "Settings, under Sync: the app is asking whether this Mac is signed into iCloud.")
        case .unreadable(let error):
            Text(error.localizedDescription)
        }
    }

    /// The list of tags to choose from, as a tree, each row named and
    /// indented as the state says, with a checkbox and what the images and
    /// sounds of its cards, and of the cards of the tags inside it, weigh,
    /// when they weigh anything. A tag inside a ticked tag shows ticked, since
    /// it syncs with it, and its checkbox waits.
    private func tagsSection(_ sync: SyncTabState) -> some View {
        Section {
            if sync.tags.isEmpty {
                Text(
                    "Your cards have no tags yet.",
                    comment: "Settings, under Sync: the list of tags to choose is empty, as no card has a tag."
                )
                .foregroundStyle(.secondary)
            }
            ForEach(sync.tagRows) { row in
                let tag = row.tag
                // In a stack, the checkbox comes before the name, as macOS lists
                // them; a form's label would put it after.
                HStack {
                    Toggle(isOn: Binding(get: { tag.isTicked }, set: { model.sync?.choose(tag.name, $0) })) {
                        Text(verbatim: row.title)
                    }
                    .toggleStyle(.checkbox)
                    .disabled(!tag.canChoose)
                    .help(
                        tag.canChoose
                            ? Text(verbatim: "")
                            : Text(
                                "It syncs with the ticked tag it sits inside.",
                                comment: """
                                    Settings, under Sync: the tooltip of a tag's checkbox, ticked and waiting, inside a \
                                    ticked tag.
                                    """))
                    Spacer()
                    if let weight = tag.weight {
                        Text(weight.formatted(.byteCount(style: .file)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, CGFloat(row.level) * 20)
                .disabled(!sync.canChoose)
            }
        } header: {
            Text("Tags to sync", comment: "Settings, under Sync: the heading of the list of tags to choose.")
        } footer: {
            Text(
                """
                Only the cards with a ticked tag go up to iCloud, with their images and sounds. Unticking a tag \
                deletes nothing: its cards stay on each of your devices.
                """,
                comment: "Settings, under Sync, below the list of tags: what ticking and unticking a tag does.")
        }
    }

    /// What turning the switch on does beyond syncing again, as the state
    /// says.
    private func turningOnLine(_ turningOn: SyncTabState.TurningOn) -> Text {
        switch turningOn {
        case .sendsCardsAgain(onlyChosenTags: false):
            Text(
                "\(AppVariant.current.name)'s data was deleted from iCloud. Turning sync on sends all your cards again.",
                comment: """
                    Settings, under Sync, after the user deleted the app's data in iCloud's settings, which turned \
                    sync off. The name is the app's.
                    """)
        case .sendsCardsAgain(onlyChosenTags: true):
            Text(
                """
                \(AppVariant.current.name)'s data was deleted from iCloud. Turning sync on sends the cards with the \
                tags you choose again.
                """,
                comment: """
                    Settings, under Sync, after the user deleted the app's data in iCloud's settings, which turned \
                    sync off, while only the cards with ticked tags sync. The name is the app's.
                    """)
        case .replacesICloudsCopy:
            Text(
                "You restored a copy of your cards. Turning sync on replaces iCloud's copy with this Mac's.",
                comment: """
                    Settings, under Sync, after the user restored a backup, which turned sync off: turning it on \
                    replaces the cards in iCloud, and on the user's other devices, with this Mac's.
                    """)
        case .sendsCardsForTheFirstTime(onlyChosenTags: true):
            Text(
                """
                This Mac had cards before it ever synced, so sync waits for you. Turning it on sends the cards \
                with the tags you choose to your iCloud.
                """,
                comment: """
                    Settings, under Sync, on a Mac that had cards before it ever synced, which left sync off: \
                    turning it on sends the cards with ticked tags.
                    """)
        case .sendsCardsForTheFirstTime(onlyChosenTags: false):
            Text(
                """
                This Mac had cards before it ever synced, so sync waits for you. Turning it on sends all your \
                cards to your iCloud.
                """,
                comment: """
                    Settings, under Sync, on a Mac that had cards before it ever synced, which left sync off: \
                    turning it on sends every card.
                    """)
        }
    }

    /// The title of the alert that says why `action` failed.
    private func title(_ action: SyncTabState.Failure.Action) -> LocalizedStringResource {
        switch action {
        case .turningOn:
            LocalizedStringResource("Couldn't turn sync on", comment: "An alert's title in Settings' Sync tab.")
        case .turningOff:
            LocalizedStringResource("Couldn't turn sync off", comment: "An alert's title in Settings' Sync tab.")
        case .choosing:
            LocalizedStringResource(
                "Couldn't change which cards sync", comment: "An alert's title in Settings' Sync tab.")
        }
    }

    /// Why turning the switch, or choosing which cards sync, failed, as an
    /// alert says it, which closing it clears.
    private var failure: Binding<Failure?> {
        Binding {
            model.sync?.failure.map { failure in
                Failure(title: title(failure.action), error: failure.error)
            }
        } set: {
            if $0 == nil {
                model.sync?.dismissFailure()
            }
        }
    }
}
