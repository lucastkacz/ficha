import AppKit
import ServiceManagement
import os

/// The login item's log, which says when starting at login changes.
private let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "login item")

/// Whether the app starts when the user logs in, through the system's login
/// items (`SMAppService`), which System Settings also shows and changes. The
/// real Ficha asks on its Welcome page (`WelcomeWindow`), and does when the
/// user says so, until they turn it off; Ficha Dev never does, so it can't get
/// in the real Ficha's way.
enum StartAtLogin {
    /// Whether the app may start at login: only the real Ficha.
    static var isAvailable: Bool {
        AppVariant.current.mayStartAtLogin
    }

    /// Whether the system starts the app at login now: on, off, or on once
    /// Lucas allows it in System Settings.
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    /// Turns starting at login on or off, in the real Ficha. When macOS
    /// refuses, the log says why, and an alert says what to do about it.
    static func turn(on: Bool) {
        guard isAvailable else { return }
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error(
                "Couldn't turn \(on ? "on" : "off", privacy: .public) starting at login: \(String(describing: error), privacy: .public)"
            )
            showAlert(
                String(localized: "Couldn't change whether \(AppVariant.current.name) starts at login"),
                explaining: StartAtLoginError(appName: AppVariant.current.name, turningOn: on, reason: error),
                style: .warning, button: String(localized: "OK"))
            return
        }
        logger.info("Turned \(on ? "on" : "off", privacy: .public) starting at login")
    }

    /// Opens System Settings at the login items, where Lucas allows the app
    /// to start at login.
    static func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Why starting at login couldn't be turned on or off. Its message says what
/// to do about it.
struct StartAtLoginError: LocalizedError {
    /// The app's name.
    let appName: String
    /// Whether it was being turned on.
    let turningOn: Bool
    /// What macOS said.
    let reason: any Error

    var errorDescription: String? {
        if turningOn {
            String(
                localized: """
                    macOS didn't let \(appName) start at login (\(reason.localizedDescription)). Try \
                    again, or add it in System Settings > General > Login Items.
                    """)
        } else {
            String(
                localized: """
                    macOS didn't stop \(appName) from starting at login \
                    (\(reason.localizedDescription)). Try again, or remove it in System Settings > General > Login \
                    Items.
                    """)
        }
    }
}

extension SMAppService.Status {
    /// Whether macOS starts the app at login: when it's on, or on once the
    /// user allows it in System Settings, as Settings' switch shows it.
    var startsAtLogin: Bool {
        self == .enabled || self == .requiresApproval
    }
}

extension AppVariant {
    /// Whether the app may start at login: the real Ficha, and never Ficha
    /// Dev, so it can't get in the real Ficha's way.
    var mayStartAtLogin: Bool {
        switch self {
        case .dev: false
        case .real: true
        }
    }
}
