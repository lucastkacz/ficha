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

    /// The app's way into Lucas's cards, for the menu, the capture window and
    /// the review panel, when the database is open.
    var model: AppModel? {
        try? opening.get()
    }

    /// The shortcut that opens "Capture…" from any app, while one is on.
    let captureShortcut = CaptureShortcutRegistration()
    /// The capture window, from the last time it showed.
    private var captureWindow: CaptureWindow?
    /// The review panel, once the app launched with its cards.
    private var panel: ReviewPanel?
    /// What shows the review panel on its own, once the app launched with its
    /// cards.
    private var appearances: AppearanceLoop?

    /// Opens the capture window with empty fields, or brings it forward
    /// when it's open, with what Lucas typed. Either way it takes the
    /// keyboard.
    func openCapture() {
        if let captureWindow, captureWindow.isVisible {
            captureWindow.bringForward()
            return
        }
        guard let model else { return }
        let window = CaptureWindow(model: model)
        window.show()
        captureWindow = window
    }

    /// Opens the review panel with the cards a review now brings, or brings
    /// it forward when it's open.
    func openReviewPanel() {
        panel?.openReviewNow()
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
            let mac = SystemMacSignals { model.now }
            let panel = ReviewPanel(model: model, mac: mac)
            let appearances = AppearanceLoop(model: model, mac: mac, panel: panel)
            self.panel = panel
            self.appearances = appearances
            appearances.start()
            captureShortcut.whenPressed = { [weak self] in self?.openCapture() }
            turnOnCaptureShortcut()
        case .failure(let error):
            showAlert(
                String(localized: "\(AppVariant.current.name) can't open your cards"), explaining: error,
                style: .critical, button: String(localized: "Quit")
            )
            NSApplication.shared.terminate(nil)
        }
    }

    /// Turns on the shortcut that opens "Capture…" from launch: the real
    /// Ficha's, or, in Ficha Dev, its debug menu's when it's on. When another
    /// app has it, the menu shows no shortcut next to "Capture…", and the log
    /// says why; when macOS refuses it for another reason, an alert says so.
    private func turnOnCaptureShortcut() {
        let shortcut =
            if model?.debugTools?.capturesWithShortcut == true {
                CaptureShortcut.fichaDev
            } else {
                AppVariant.current.captureShortcut
            }
        guard let shortcut else { return }
        do {
            try captureShortcut.turnOn(shortcut)
        } catch .taken {
            // Expected when another app has it: Settings will let Lucas pick
            // another (#18).
        } catch {
            showAlert(
                String(localized: "\(AppVariant.current.name) couldn't turn on its capture shortcut"),
                explaining: error, style: .warning, button: String(localized: "OK"))
        }
    }

    /// An open panel closes as Esc closes it, so it goes into the appearance
    /// log, and its cards stay as they were.
    func applicationWillTerminate(_ notification: Notification) {
        panel?.close(.byLucas)
    }
}
