import Foundation
import ServiceManagement
import os

/// The login item's log, which says when starting at login changes.
private let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "login item")

/// Whether the app starts when Lucas logs in, through the system's login
/// items (`SMAppService`), which System Settings also shows and changes. The
/// real Ficha does from its first launch on, until Lucas turns it off; Ficha
/// Dev never does, so it can't get in the real Ficha's way.
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

    /// Turns starting at login on the first time the real Ficha launches,
    /// since that's its default. Later launches leave it as Lucas left it,
    /// here or in System Settings. When macOS refuses, the log says why, and
    /// the next launch tries again.
    static func turnOnAtFirstLaunch() {
        guard isAvailable, !Preferences.startsAtLoginIsSetUp else { return }
        do {
            try turn(on: true)
        } catch {
            // `turn(on:)` logged why.
            return
        }
        Preferences.startsAtLoginIsSetUp = true
    }

    /// Turns starting at login on or off, in the real Ficha.
    static func turn(on: Bool) throws(StartAtLoginError) {
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
            throw StartAtLoginError(appName: AppVariant.current.name, turningOn: on, reason: error)
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
