import FichaCore
import FichaData
import SwiftUI

/// The Diagnostics window's content: what each detector sees right now, and
/// whether Ficha's Focus filter holds appearances back, and the latest
/// appearances, with how each one closed or what held it back, so
/// Lucas can tell whether the suppressions work. It reads both again every
/// second while it's open.
struct DiagnosticsView: View {
    let model: AppModel
    /// What the Mac tells Ficha, which says whether a Focus holds
    /// appearances back.
    let mac: SystemMacSignals
    @State private var detection: Detection?
    /// Whether a Focus holds appearances back, or nil when Ficha couldn't
    /// read its filter at the last look.
    @State private var isFocusHoldingBack: Bool? = false
    @State private var appearances: Result<[AppearanceLogEntry], EngineError>?

    var body: some View {
        Form {
            Section("Right now") {
                if let detection {
                    LabeledContent {
                        reading(detection.cameras)
                    } label: {
                        Text("Camera", comment: "A detector in Diagnostics: the cameras in use.")
                    }
                    LabeledContent {
                        reading(detection.microphones)
                    } label: {
                        Text("Microphone", comment: "A detector in Diagnostics: the microphones in use.")
                    }
                    LabeledContent {
                        reading(detection.microphoneApps)
                    } label: {
                        Text("Apps using the microphone", comment: "In Diagnostics: which apps use a microphone.")
                    }
                    LabeledContent {
                        reading(detection.displayAwake)
                    } label: {
                        Text(
                            "Keeping the display awake",
                            comment: "A detector in Diagnostics: the apps keeping the display awake, as a video does.")
                    }
                    LabeledContent {
                        reading(detection.fullScreen)
                    } label: {
                        Text("Full screen", comment: "A detector in Diagnostics: the app in front in full screen.")
                    }
                }
                LabeledContent {
                    switch isFocusHoldingBack {
                    case true?:
                        Text("Holding appearances back", comment: "In Diagnostics: what Ficha's Focus filter says.")
                    case false?:
                        Text("Not holding appearances back", comment: "In Diagnostics: what Ficha's Focus filter says.")
                    case nil:
                        Text("Can't tell", comment: "A detector the OS didn't answer, in Diagnostics.")
                    }
                } label: {
                    Text(
                        "Focus filter",
                        comment: """
                            In Diagnostics: Ficha's filter in a Focus of macOS, which the user adds in System \
                            Settings.
                            """)
                }
            }
            Section("Latest appearances") {
                switch appearances {
                case .success(let entries) where entries.isEmpty:
                    Text("No appearance yet.")
                        .foregroundStyle(.secondary)
                case .success(let entries):
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        LabeledContent {
                            Text(outcome(entry.outcome))
                        } label: {
                            Text(
                                "\(entry.shownAt.formatted(date: .abbreviated, time: .shortened)) · \(trigger(entry.trigger))",
                                comment: """
                                    An appearance log entry in Diagnostics: when it showed, or was held back, and what \
                                    opened the review panel.
                                    """)
                        }
                    }
                case .failure(let error):
                    Text(error.localizedDescription)
                        .foregroundStyle(.secondary)
                case nil:
                    EmptyView()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 520)
        .task {
            while !Task.isCancelled {
                refresh()
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
        }
    }

    /// Reads the detectors, the Focus filter and the appearance log again.
    private func refresh() {
        detection = Detection.read()
        isFocusHoldingBack = mac.cantTell.contains(.focus) ? nil : mac.suppressions.contains(.focus)
        appearances = Result { () throws(EngineError) in try model.latestAppearances(20) }
    }

    /// What a detector sees, in words.
    private func reading(_ reading: DetectorReading) -> Text {
        switch reading {
        case .inUse(let names):
            Text("In use: \(names.formatted(.list(type: .and)))", comment: "What a detector sees in Diagnostics.")
        case .notInUse:
            Text("Not in use", comment: "What a detector sees in Diagnostics.")
        case .unknown:
            Text("Can't tell", comment: "A detector the OS didn't answer, in Diagnostics.")
        }
    }

    /// What opened the review panel, in words.
    private func trigger(_ trigger: Trigger) -> String {
        switch trigger {
        case .appearance:
            String(localized: "On its own", comment: "In Diagnostics: the review panel showed up on its own.")
        case .reviewNow:
            String(
                localized: "With review now",
                comment: """
                    In Diagnostics: Lucas opened the review panel with Review now, from the menu or the Shortcuts app.
                    """)
        }
    }

    /// How an appearance closed, or what held it back, in words.
    private func outcome(_ outcome: AppearanceLogEntry.Outcome) -> String {
        switch outcome {
        case .finished: String(localized: "Finished", comment: "How an appearance closed, in Diagnostics.")
        case .snoozed: String(localized: "Snoozed", comment: "How an appearance closed, in Diagnostics.")
        case .autoClosed: String(localized: "Closed on its own", comment: "How an appearance closed, in Diagnostics.")
        case .heldBack(.meeting):
            String(
                localized: "Held back by a meeting", comment: "In Diagnostics: the camera or the microphone was in use."
            )
        case .heldBack(.video):
            String(localized: "Held back by a video", comment: "In Diagnostics: an app kept the display awake.")
        case .heldBack(.fullScreen):
            String(
                localized: "Held back by a full-screen app",
                comment: "In Diagnostics: the app in front was in full screen.")
        case .heldBack(.focus):
            String(
                localized: "Held back by a Focus",
                comment: "In Diagnostics: a Focus of macOS was on, and Ficha's filter in it holds appearances back.")
        }
    }
}
