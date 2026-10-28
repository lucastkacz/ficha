import FichaData
import SwiftUI

/// The Sync tab of Settings, in an app that syncs (ADR 0017): "Sync with
/// iCloud", and under it the status line, how sync stands and, while it's
/// off, what turning it on does. What the switch shows and the line says,
/// the model's `SyncTabState` decides.
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
                } footer: {
                    Text(
                        """
                        Your cards, their progress and the inbox stay the same on each of your devices, through \
                        your own iCloud. Each device keeps its own backups.
                        """,
                        comment: "Settings, under Sync, below the switch: what sync does.")
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

    /// What turning the switch on does beyond syncing again, as the state
    /// says.
    private func turningOnLine(_ turningOn: SyncTabState.TurningOn) -> Text {
        switch turningOn {
        case .sendsAllCardsAgain:
            Text(
                "\(AppVariant.current.name)'s data was deleted from iCloud. Turning sync on sends all your cards again.",
                comment: """
                    Settings, under Sync, after the user deleted the app's data in iCloud's settings, which turned \
                    sync off. The name is the app's.
                    """)
        }
    }

    /// Why turning the switch failed, as an alert says it, which closing it
    /// clears.
    private var failure: Binding<Failure?> {
        Binding {
            model.sync?.failure.map { failure in
                Failure(
                    title: failure.turningOn
                        ? LocalizedStringResource(
                            "Couldn't turn sync on", comment: "An alert's title in Settings' Sync tab.")
                        : LocalizedStringResource(
                            "Couldn't turn sync off", comment: "An alert's title in Settings' Sync tab."),
                    error: failure.error)
            }
        } set: {
            if $0 == nil {
                model.sync?.dismissFailure()
            }
        }
    }
}
