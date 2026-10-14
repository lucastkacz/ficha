import AppKit
import FichaCore
import FichaData

/// Opens the database in this app's own data folder when the app launches.
/// When it can't, the app says why and quits: Ficha doesn't run without its
/// cards.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The open database, or why it couldn't be opened.
    let opening = Result { () throws(EngineError) -> AppModel in
        AppModel(engine: try Engine(location: .folder(AppVariant.current.dataFolder), time: SystemTimeSource()))
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
