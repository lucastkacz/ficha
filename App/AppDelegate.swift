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
            let engine = try Engine(location: .folder(variant.dataFolder), time: SystemTimeSource())
            return AppModel(engine: engine, debugTools: nil)
        }
        // Ficha Dev's engine runs on the time its debug menu moves forward.
        let debugTools = try DebugTools(dataFolder: variant.dataFolder)
        return AppModel(engine: debugTools.engine, debugTools: debugTools)
    }

    /// What the menu and the capture window show, when the database is open.
    var model: AppModel? {
        try? opening.get()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard case .failure(let error) = opening else { return }
        showAlert(
            "\(AppVariant.current.name) no puede abrir tus fichas", explaining: error, style: .critical, button: "Salir"
        )
        NSApplication.shared.terminate(nil)
    }
}
