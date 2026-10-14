import AppKit
import FichaCore
import FichaData

/// Opens the database in this app's own data folder when the app launches.
/// When it can't, the app says why and quits: Ficha doesn't run without its
/// cards.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The open database, or why it couldn't be opened.
    let opening = Result { () throws(EngineError) -> AppModel in
        let variant = AppVariant.current
        let location = DatabaseLocation.folder(variant.dataFolder)
        guard variant.hasDebugMenu else {
            // The real Ficha always runs on the system's time.
            return AppModel(engine: try Engine(location: location, time: SystemTimeSource()), debugTools: nil)
        }
        // Ficha Dev runs on the time its debug menu moves forward, and so
        // does everything the engine does for it.
        let time = DebugTools.savedTime()
        let engine = try Engine(location: location, time: time)
        return AppModel(engine: engine, debugTools: DebugTools(engine: engine, time: time))
    }

    /// What the menu and the capture window show, when the database is open.
    var model: AppModel? {
        try? opening.get()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard case .failure(let error) = opening else { return }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "\(AppVariant.current.name) no puede abrir tus fichas"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Salir")
        NSApplication.shared.activate()
        alert.runModal()
        NSApplication.shared.terminate(nil)
    }
}
