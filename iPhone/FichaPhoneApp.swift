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
/// are and how many are due. Its appearances arrive as card notifications,
/// whose buttons answer the cards, and which it plans again each time it opens
/// or comes back to the foreground. When it can't open the cards, it says why.
@main
struct FichaPhoneApp: App {
    /// The open database, with the sample cards, and the notifications of its
    /// appearances, or why it couldn't be opened. It runs on the system's time
    /// until Ficha Dev can move its time forward (#105).
    private let opening = Result { () throws -> Opened in
        // The database keeps iOS's default file protection, which opens it
        // from the first unlock after the iPhone starts, so a card
        // notification's buttons reach it while the iPhone is locked.
        let engine = try Engine(location: .folder(AppVariant.current.dataFolder), time: SystemTimeSource())
        try SampleCards.loadIfThereAreNoCards(into: engine)
        return Opened(engine: engine, notifications: CardNotifications(engine: engine))
    }
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            switch opening {
            case .success(let opened):
                CountsView(engine: opened.engine, notifications: opened.notifications)
            case .failure(let error):
                ContentUnavailableView {
                    Label("\(AppVariant.current.name) can't open your cards", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Rendering.sayScreenIsUp()
            if case .success(let opened) = opening {
                opened.notifications.clearAndPlanAgain()
            }
        }
    }
}

/// The open database, and the notifications of its appearances.
private struct Opened {
    let engine: Engine
    let notifications: CardNotifications
}
