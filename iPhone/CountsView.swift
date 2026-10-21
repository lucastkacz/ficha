import FichaCore
import FichaData
import SwiftUI

/// How many cards there are and how many are due: the iPhone app's one screen,
/// a placeholder until the Review tab brings the tabs (#105). It counts again
/// whenever the app comes back to the foreground, since cards come due as time
/// passes.
struct CountsView: View {
    private let engine: Engine
    @Environment(\.scenePhase) private var scenePhase
    @State private var counts: Result<Counts, EngineError>

    init(engine: Engine) {
        self.engine = engine
        _counts = State(initialValue: Counts.counting(engine))
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
