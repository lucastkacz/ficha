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
    /// The Cards window, once Lucas opened it.
    private var cardsWindow: CardsWindow?
    /// The Diagnostics window, from the last time it showed.
    private var diagnosticsWindow: AppWindow?
    /// The Settings window, from the last time it showed.
    private var settingsWindow: AppWindow?
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

    /// Opens the Cards window, or brings it forward when it's open: there's
    /// only one.
    func openCards() {
        guard let model else { return }
        let window = cardsWindow ?? CardsWindow(model: model)
        window.open()
        cardsWindow = window
    }

    /// Opens the Diagnostics window: what each detector sees right now, and
    /// the latest appearances. When it's open, it comes forward.
    func openDiagnostics() {
        guard let model else { return }
        open(&diagnosticsWindow) {
            AppWindow(
                title: String(localized: "Diagnostics", comment: "The Diagnostics window's title."),
                content: DiagnosticsView(model: model))
        }
    }

    /// Opens the Settings window: every default Lucas can change, in tabs.
    /// When it's open, it comes forward.
    func openSettings() {
        openSettings(on: nil)
    }

    /// Opens the Settings window on its Backups tab, as "Last backup failed"
    /// in the menu does. When it's open, it comes forward on that tab.
    func openBackupSettings() {
        openSettings(on: .backups)
    }

    /// Opens the Settings window on `tab`, or on the tab Lucas left it on
    /// last. When it's open, it comes forward, on `tab` if there's one.
    private func openSettings(on tab: SettingsTab?) {
        guard let model else { return }
        if let tab, let tabs = settingsWindow?.contentViewController as? SettingsTabViewController {
            tabs.select(tab)
        }
        open(&settingsWindow) {
            AppWindow(
                tabs: SettingsTabViewController(
                    model: model, captureShortcut: captureShortcut,
                    closeReviewPanel: { [weak self] in self?.panel?.close(.byLucas) }, openingOn: tab))
        }
    }

    /// Brings `window` forward when it's open, and otherwise shows the one
    /// `make` makes, in its place.
    private func open(_ window: inout AppWindow?, making make: () -> AppWindow) {
        if let window, window.isVisible {
            window.bringForward()
            return
        }
        let made = make()
        made.show()
        window = made
    }

    /// Opens the review panel with the cards a review now brings, or brings
    /// it forward when it's open.
    func openReviewPanel() {
        panel?.openReviewNow()
    }

    /// Asks the engine right away whether the review panel shows up on its
    /// own, for Ficha Dev's debug menu, and shows it if so, as every check
    /// does, noting an appearance a suppression holds back: what the check
    /// came to, or nil before the app launched with its cards.
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
            model.startBackups()
            captureShortcut.whenPressed = { [weak self] in self?.openCapture() }
            turnOnCaptureShortcut()
            StartAtLogin.turnOnAtFirstLaunch()
            sayIfSettingsAreUnreadable()
        case .failure(let error):
            showAlert(
                String(localized: "\(AppVariant.current.name) can't open your cards"), explaining: error,
                style: .critical, button: String(localized: "Quit")
            )
            NSApplication.shared.terminate(nil)
        }
    }

    /// Turns on the shortcut that opens "Capture…" from launch, as Lucas left
    /// it in Settings. When another app has it, the menu and Settings show no
    /// shortcut, and the log says why; when macOS refuses it for another
    /// reason, an alert says so.
    private func turnOnCaptureShortcut() {
        guard let shortcut = Preferences.captureShortcut else { return }
        do {
            try captureShortcut.turnOn(shortcut)
        } catch .taken {
            // Expected when another app has it: Lucas can pick another in
            // Settings.
        } catch {
            showAlert(
                String(localized: "\(AppVariant.current.name) couldn't turn on its capture shortcut"),
                explaining: error, style: .warning, button: String(localized: "OK"))
        }
    }

    /// Says which stored settings couldn't be read, as when they were edited
    /// by hand, if any: they're at their defaults until Lucas sets them
    /// again, and a capture shortcut is off.
    private func sayIfSettingsAreUnreadable() {
        guard !Preferences.unreadable.isEmpty else { return }
        let names = Preferences.unreadable.sorted().formatted(.list(type: .and))
        showAlert(
            String(localized: "Some settings couldn't be read"),
            details: String(
                localized: """
                    \(AppVariant.current.name) couldn't read these settings, as when they're edited by hand: \
                    \(names). They're at their defaults, and a capture shortcut is off, until you set them again in \
                    Settings.
                    """,
                comment: "An alert at launch. The names are the settings' names in the app's preferences."),
            style: .warning, button: String(localized: "OK"))
    }

    /// An open panel closes as Esc closes it, so it goes into the appearance
    /// log, and its cards stay as they were.
    func applicationWillTerminate(_ notification: Notification) {
        panel?.close(.byLucas)
    }
}
