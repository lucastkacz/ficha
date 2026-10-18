import FichaCore
import FichaData
import SwiftUI

/// The Diagnostics window's content: what each detector sees right now, and
/// the latest appearances, with how each one closed or what held it back, so
/// Lucas can tell whether the suppressions work. It reads both again every
/// second while it's open.
struct DiagnosticsView: View {
    let model: AppModel
    @State private var detection: Detection?
    @State private var appearances: Result<[AppearanceLogEntry], EngineError>?

    var body: some View {
        Form {
            Section("Right now") {
                if let detection {
                    LabeledContent("Camera") { reading(detection.cameras) }
                    LabeledContent("Microphone") { reading(detection.microphones) }
                    LabeledContent("Keeping the display awake") { reading(detection.displayAwake) }
                    LabeledContent("Full screen") { reading(detection.fullScreen) }
                    LabeledContent("Holds appearances back") { Text(holdsBack(detection.suppressions)) }
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
                                comment: "An appearance log entry in Diagnostics: when it showed, and what opened it.")
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

    /// Reads the detectors and the appearance log again.
    private func refresh() {
        detection = Detection.now()
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

    /// What holds appearances back now, in words.
    private func holdsBack(_ suppressions: Set<Suppression>) -> String {
        let names = Suppression.allCases.filter(suppressions.contains).map(name)
        return names.isEmpty
            ? String(localized: "Nothing", comment: "No suppression holds appearances back, in Diagnostics.")
            : names.formatted(.list(type: .and))
    }

    /// A suppression's name, as Diagnostics shows it.
    private func name(_ suppression: Suppression) -> String {
        switch suppression {
        case .meeting: String(localized: "A meeting", comment: "A suppression: the camera or the microphone is in use.")
        case .video: String(localized: "A video", comment: "A suppression: an app keeps the display awake.")
        case .fullScreen:
            String(localized: "A full-screen app", comment: "A suppression: the app in front is in full screen.")
        }
    }

    /// What opened the review panel, in words.
    private func trigger(_ trigger: Trigger) -> String {
        switch trigger {
        case .appearance: String(localized: "Appearance", comment: "What opened the review panel, in Diagnostics.")
        case .reviewNow: String(localized: "Review now", comment: "What opened the review panel, in Diagnostics.")
        }
    }

    /// How an appearance closed, or what held it back, in words.
    private func outcome(_ outcome: AppearanceLogEntry.Outcome) -> String {
        switch outcome {
        case .finished: String(localized: "Finished", comment: "How an appearance closed, in Diagnostics.")
        case .snoozed: String(localized: "Snoozed", comment: "How an appearance closed, in Diagnostics.")
        case .autoClosed: String(localized: "Closed on its own", comment: "How an appearance closed, in Diagnostics.")
        case .heldBack(let suppression):
            String(
                localized: "Held back: \(name(suppression))",
                comment: "An appearance a suppression held back, in Diagnostics, with the suppression.")
        }
    }
}
