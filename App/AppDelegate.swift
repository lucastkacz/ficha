import AppKit
import FichaCore
import FichaData
import os

private let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "launch")

/// Opens Lucas's cards when the app launches, from this app's own data folder.
/// When the database can't be opened, it says why and quits: Ficha doesn't run
/// without its cards.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The open cards, or nil when the database couldn't be opened.
    let model: AppModel?
    private let failure: EngineError?

    override init() {
        do throws(EngineError) {
            let engine = try Engine(location: .folder(AppVariant.current.dataFolder), time: SystemTimeSource())
            model = AppModel(engine: engine)
            failure = nil
        } catch {
            model = nil
            failure = error
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let failure else { return }
        logger.error("Couldn't open the database: \(failure.localizedDescription)")
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "\(AppVariant.current.name) no puede abrir tus fichas"
        alert.informativeText = failure.localizedDescription
        alert.addButton(withTitle: "Salir")
        NSApplication.shared.activate()
        alert.runModal()
        NSApplication.shared.terminate(nil)
    }
}
