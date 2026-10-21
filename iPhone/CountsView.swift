import FichaCore
import FichaData
import SwiftUI

/// How many cards there are and how many are due: the iPhone app's one screen,
/// a placeholder until the Review tab brings the tabs (#105). It counts again
/// whenever the app comes back to the foreground, since cards come due as time
/// passes. In Ficha Dev, debug buttons move its time forward and bring the
/// next appearance now.
struct CountsView: View {
    private let engine: Engine
    private let notifications: CardNotifications
    /// Ficha Dev's time, which the engine runs on and the debug buttons move
    /// forward.
    private let time: DebugTimeSource
    @Environment(\.scenePhase) private var scenePhase
    @State private var counts: Result<Counts, EngineError>
    /// How far ahead of the system's time Ficha Dev's time is.
    @State private var timeShift: Duration
    /// What the last debug button did, or why it couldn't, once one was
    /// pressed.
    @State private var debugOutcome: String?

    init(engine: Engine, notifications: CardNotifications, time: DebugTimeSource) {
        self.engine = engine
        self.notifications = notifications
        self.time = time
        _counts = State(initialValue: Counts.counting(engine))
        _timeShift = State(initialValue: time.shift)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch counts {
                case .success(let counts):
                    List {
                        LabeledContent {
                            Text(counts.cards, format: .number)
                        } label: {
                            Text("Cards", comment: "On the iPhone's placeholder screen: how many cards there are.")
                        }
                        LabeledContent {
                            Text(counts.due, format: .number)
                        } label: {
                            Text("Due", comment: "On the iPhone's placeholder screen: how many cards are due.")
                        }
                        if AppVariant.current.hasDebugMenu {
                            debugSection
                        }
                    }
                case .failure(let error):
                    ContentUnavailableView {
                        Label("Couldn't count your cards", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error.localizedDescription)
                    }
                }
            }
            .navigationTitle(AppVariant.current.name)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                counts = Counts.counting(engine)
            }
        }
    }

    /// Ficha Dev's debug tools, in English and verbatim, as on the Mac: they
    /// aren't translated (ADR 0009). How far its time moved comes first, then
    /// the steps that move it, the Mac's debug menu's, and then the button
    /// that brings the next appearance, which comes after moving the time to
    /// bring cards that came due.
    private var debugSection: some View {
        Section {
            Text(verbatim: timeShift == .zero ? "On the system's time" : "Time moved forward by \(inWords(timeShift))")
                .foregroundStyle(.secondary)
            ForEach(DebugTimeSource.steps, id: \.self) { step in
                Button {
                    moveTimeForward(by: step)
                } label: {
                    Text(verbatim: "Move forward \(inWords(step))")
                }
            }
            Button {
                debugOutcome = notifications.bringNextAppearanceNow()
            } label: {
                Text(verbatim: "Bring the next appearance now")
            }
        } header: {
            Text(verbatim: "Debug")
        } footer: {
            if let debugOutcome {
                Text(verbatim: debugOutcome)
            }
        }
    }

    /// Moves Ficha Dev's time forward by `step`, for good, as the Mac's debug
    /// menu does. Cards may come due, so it counts them again and plans the
    /// appearances again, whose notifications come at the real times that
    /// match the moved time. When it can't, it says why under the buttons.
    private func moveTimeForward(by step: Duration) {
        do {
            try time.moveForward(by: step)
        } catch {
            debugOutcome = "Couldn't move the time forward: \(error.localizedDescription)"
            return
        }
        timeShift = time.shift
        // What the last button did, like an appearance brought a few seconds
        // ahead, no longer holds: the new plan replaces it.
        debugOutcome = nil
        counts = Counts.counting(engine)
        notifications.planAgain()
    }
}

/// How many cards there are, buried and flagged ones too, and how many are due.
private struct Counts {
    let cards: Int
    let due: Int

    /// What `engine` counts now, or why it couldn't, by the default settings
    /// until the iPhone has a Settings tab (#107).
    static func counting(_ engine: Engine) -> Result<Counts, EngineError> {
        Result { () throws(EngineError) in
            Counts(cards: try engine.cards().count, due: try engine.progress(.defaults).due)
        }
    }
}

/// A span of time in words, in English, like "1 day, 2 hours", as the Mac's
/// debug menu says it.
private func inWords(_ duration: Duration) -> String {
    duration.formatted(.units(allowed: [.days, .hours, .minutes], width: .wide).locale(Locale(identifier: "en")))
}
