import AppKit
import FichaCore
import FichaData
import FichaICloud
import FichaSVG
import os

private let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "icloud")

/// Opens the database in this app's own data folder when the app launches,
/// and starts the appearances and, in Ficha Dev, sync through iCloud. When it
/// can't open it, the app says why and quits: Ficha doesn't run without its
/// cards. It and `SecondDevice` are the only files of the app that load
/// CloudKit, so `make render` leaves them out.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The app, once it launched with its cards, for its App Intents, which
    /// macOS runs in the app's process.
    private(set) static weak var launched: AppDelegate?

    /// The open database, or why it couldn't be opened, which includes not
    /// reading the settings that decide a card's progress, and in Ficha Dev
    /// not knowing how far its debug menu moved its time.
    let opening = Result { () throws -> AppModel in
        let variant = AppVariant.current
        guard variant.hasDebugMenu else {
            // The real Ficha always runs on the system's time. Its imports
            // draw SVGs through its SVG drawer, as Ficha Dev's do.
            let svgDrawer = variant.svgDrawerIdentifier
            return try AppModel(
                engine: try Engine(
                    location: .folder(try variant.dataFolder), time: SystemTimeSource(),
                    drawingSVGsWith: { ServiceSVGDrawer(serviceName: svgDrawer) }))
        }
        // Ficha Dev's engine runs on the time its debug menu moves forward.
        return try AppModel(debugTools: try DebugTools(dataFolder: try variant.dataFolder))
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
    /// What the Mac tells Ficha, once the app launched with its cards.
    private var mac: SystemMacSignals?
    /// This Mac's sync through iCloud, once the app launched with its cards,
    /// when it syncs (`AppVariant.syncsThroughICloud`).
    private var iCloud: CloudKitSync?
    /// Ficha Dev's second device, once its debug menu opened it.
    private var secondDevice: SecondDevice?

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

    /// Opens the Diagnostics window: what each detector sees right now,
    /// whether a Focus holds appearances back, and the latest appearances.
    /// When it's open, it comes forward.
    func openDiagnostics() {
        guard let model, let mac else { return }
        open(&diagnosticsWindow) {
            AppWindow(
                title: String(localized: "Diagnostics", comment: "The Diagnostics window's title."),
                content: DiagnosticsView(model: model, mac: mac))
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

    /// Holds appearances back, or stops, as Ficha's filter in a Focus says
    /// when macOS runs it as the Focus turns on or off.
    func focusChanged(holdsBack: Bool) {
        mac?.focusChanged(holdsBack: holdsBack)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        switch opening {
        case .success(let model):
            let mac = SystemMacSignals { model.now }
            let panel = ReviewPanel(model: model, mac: mac)
            let appearances = AppearanceLoop(model: model, mac: mac, panel: panel)
            self.mac = mac
            self.panel = panel
            self.appearances = appearances
            // Before the alert at first launch, which an App Intent can run
            // during.
            Self.launched = self
            appearances.start()
            model.startBackups()
            startSyncing(model)
            captureShortcut.whenPressed = { [weak self] in self?.openCapture() }
            turnOnCaptureShortcut()
            StartAtLogin.askAtFirstLaunch()
            sayIfSettingsAreUnreadable()
        case .failure(let error):
            showAlert(
                String(localized: "\(AppVariant.current.name) can't open your cards"), explaining: error,
                style: .critical, button: String(localized: "Quit")
            )
            NSApplication.shared.terminate(nil)
        }
    }

    /// Starts syncing `model`'s cards through iCloud, when the app syncs and
    /// while Settings' switch is on: what waits now, those changes made while
    /// the app didn't run included, and then each change to the database,
    /// whichever process made it. The sync follows the switch as it's turned
    /// on and off (`CloudKitSync`).
    private func startSyncing(_ model: AppModel) {
        guard AppVariant.current.syncsThroughICloud else { return }
        // CloudKit stops a process that isn't signed for iCloud, as #316
        // probed, so a build signed without it leaves sync off instead.
        guard signedEntitlement("com.apple.developer.icloud-services") != nil else {
            logger.fault("Sync through iCloud stays off: this build isn't signed for iCloud")
            return
        }
        let iCloud = CloudKitSync(engine: model.engine, zones: .ficha, device: "This Mac")
        self.iCloud = iCloud
        Task { await iCloud.run() }
    }

    /// Opens the second device's Cards window, for Ficha Dev's debug menu,
    /// opening the second device first if it isn't open.
    func openSecondDeviceCards() {
        openedSecondDevice()?.openCards()
    }

    /// Opens the second device's review panel with the cards a review now
    /// brings there, for Ficha Dev's debug menu.
    func reviewNowOnSecondDevice() {
        openedSecondDevice()?.reviewNow()
    }

    /// Sends what waits and fetches what changed now, on this Mac and on the
    /// second device once it's open, for Ficha Dev's debug menu, instead of
    /// waiting for iCloud's engine.
    func syncNow() {
        let thisMac = iCloud
        let secondDevice = secondDevice
        Task {
            await thisMac?.syncNow()
            await secondDevice?.syncNow()
        }
    }

    /// Ficha Dev's second device, opened if it isn't yet, or nil when it
    /// can't be, which an alert says why.
    private func openedSecondDevice() -> SecondDevice? {
        if let secondDevice {
            return secondDevice
        }
        guard let debugTools = model?.debugTools else { return nil }
        guard let iCloud else {
            showAlert(
                "Ficha Dev doesn't sync, so it has no second device",
                details: """
                    It doesn't sync through iCloud when FICHA_DEV_SCRATCH opens a scratch folder, or when it isn't \
                    signed for iCloud. Build it with make run, with your team's ID in iPhone/Local.xcconfig, as \
                    docs/development.md says.
                    """,
                style: .warning, button: "OK")
            return nil
        }
        do {
            let device = try SecondDevice(debugTools: debugTools, beside: iCloud)
            secondDevice = device
            return device
        } catch {
            showAlert("Couldn't open the second device", explaining: error, style: .warning, button: "OK")
            return nil
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
