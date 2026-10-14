import Foundation

/// Which app this build is: Ficha Dev, for development, or the real Ficha, so
/// work in progress never touches the real Ficha or Lucas's cards. Each build
/// configuration in `project.yml` names its app, gives it its own bundle
/// identifier (and so its own preferences) and sets the flag `current` reads.
/// The `ficha` CLI compiles this file too, so the CLI built with each app
/// opens that app's cards.
enum AppVariant {
    /// Ficha Dev, which `make run` builds and opens.
    case dev
    /// The real Ficha, which `make install` puts in /Applications.
    case real

    /// The app this build is. A build that doesn't say doesn't compile, so it
    /// can never fall back on the real Ficha's data folder.
    static var current: AppVariant {
        #if FICHA_DEV
            return .dev
        #elseif FICHA_REAL
            return .real
        #else
            #error("This build doesn't say which app it is: set FICHA_DEV or FICHA_REAL in project.yml.")
        #endif
    }

    /// The app's name, the same as its product name in `project.yml`.
    var name: String {
        switch self {
        case .dev: "Ficha Dev"
        case .real: "Ficha"
        }
    }

    /// The menu-bar icon, an SF Symbol: different for each app, so Lucas can tell them apart.
    var menuBarSymbol: String {
        switch self {
        case .dev: "hammer"
        case .real: "character.book.closed"
        }
    }

    /// Whether the app has the debug menu, which loads sample cards and moves
    /// the app's time forward, so Lucas and agents can try a change in minutes.
    /// Only Ficha Dev has it: the real Ficha always runs on the system's time.
    var hasDebugMenu: Bool {
        switch self {
        case .dev: true
        case .real: false
        }
    }

    /// Where the app keeps its data, such as its database: a folder of its own in
    /// Application Support. It's named apart from `name`, so renaming an app never
    /// moves its cards.
    var dataFolder: URL {
        let folderName =
            switch self {
            case .dev: "Ficha Dev"
            case .real: "Ficha"
            }
        return URL.applicationSupportDirectory.appending(path: folderName, directoryHint: .isDirectory)
    }
}
