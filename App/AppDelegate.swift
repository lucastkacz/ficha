import AppKit
import FichaCore
import FichaData

/// Opens the database in this app's own data folder when the app launches.
/// When it can't, the app says why and quits: Ficha doesn't run without its
/// cards.
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

    /// The review panel, while it's open.
    private var reviewPanel: ReviewPanelWindow?

    /// Opens the review panel with the cards a review now brings, in place of
    /// any it had open.
    func openReviewPanel() {
        guard let model else { return }
        reviewPanel?.close()
        let panel = ReviewPanelWindow(model: model.startReviewNow())
        panel.show()
        reviewPanel = panel
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // PROTOTYPE for #10, throwaway: this branch is never merged.
        FocusPrototype.shared.runFromLaunchArguments()
        guard case .failure(let error) = opening else { return }
        showAlert(
            "\(AppVariant.current.name) no puede abrir tus fichas", explaining: error, style: .critical, button: "Salir"
        )
        NSApplication.shared.terminate(nil)
    }
}
