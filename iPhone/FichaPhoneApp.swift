import FichaCore
import FichaData
import SwiftUI

// Stage 1 builds the iPhone app only as Ficha Dev, in the Debug configuration
// (#97): the real Ficha on the iPhone, a Release build, comes with stage 2.
#if !FICHA_DEV
    #error("The iPhone app builds only as Ficha Dev, in the Debug configuration, until stage 2 of #97.")
#endif

/// Ficha on the iPhone, for now Ficha Dev with the sample cards (#97). It opens
/// the engine in a data folder in its own Application Support, loads the sample
/// cards the first time it opens with no cards, and shows how many cards there
/// are and how many are due. When it can't open them, it says why.
@main
struct FichaPhoneApp: App {
    /// The open database, with the sample cards, or why it couldn't be opened.
    /// It runs on the system's time until the debug tools come (#107).
    private let opening = Result { () throws -> Engine in
        let engine = try Engine(location: .folder(AppVariant.current.dataFolder), time: SystemTimeSource())
        try SampleCards.loadIfThereAreNoCards(into: engine)
        return engine
    }

    var body: some Scene {
        WindowGroup {
            switch opening {
            case .success(let engine):
                CountsView(engine: engine)
            case .failure(let error):
                ContentUnavailableView {
                    Label("\(AppVariant.current.name) can't open your cards", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                }
            }
        }
    }
}
