import AppKit
import FichaCore
import FichaData

/// Opens the database in this app's own data folder when the app launches,
/// and starts the appearances. When it can't open it, the app says why and
/// quits: Ficha doesn't run without its cards.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The open database, or why it couldn't be opened, which in Ficha Dev
    /// includes not knowing how far its debug menu moved its time.
    let opening = Result { () throws -> AppModel in
        let variant = AppVariant.current
        guard variant.hasDebugMenu else {
            // The real Ficha always runs on the system's time.
            return AppModel(engine: try Engine(location: .folder(variant.dataFolder), time: SystemTimeSource()))
        }
        // Ficha Dev's engine runs on the time its debug menu moves forward.
        return AppModel(debugTools: try DebugTools(dataFolder: variant.dataFolder))
    }

    /// What the menu and the capture window show, when the database is open.
    var model: AppModel? {
        try? opening.get()
    }

    /// The review panel, once the app launched with its cards.
    private var panels: ReviewPanels?
    /// What shows the review panel on its own, once the app launched with its
    /// cards.
    private var appearances: AppearanceLoop?

    /// Opens the review panel with the cards a review now brings, or brings
    /// it forward when it's open.
    func openReviewPanel() {
        panels?.openReviewNow()
    }

    /// Asks the engine right away whether the review panel shows up on its
    /// own, for Ficha Dev's debug menu, and shows it if so: what the check came
    /// to, or nil before the app launched with its cards.
    func checkAppearanceNow() -> AppearanceCheck? {
        appearances?.check()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        switch opening {
        case .success(let model):
            let mac = SystemMacSignals()
            let panels = ReviewPanels(model: model, mac: mac)
            let appearances = AppearanceLoop(model: model, mac: mac, panels: panels)
            self.panels = panels
            self.appearances = appearances
            appearances.start()
        case .failure(let error):
            showAlert(
                String(localized: "\(AppVariant.current.name) can't open your cards"), explaining: error,
                style: .critical, button: String(localized: "Quit")
            )
            NSApplication.shared.terminate(nil)
        }
    }

    /// An open panel closes as Esc closes it, so it goes into the appearance
    /// log, and its cards stay as they were.
    func applicationWillTerminate(_ notification: Notification) {
        panels?.closeAsLucasWould()
    }
}
