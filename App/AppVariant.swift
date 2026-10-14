import Foundation

/// Which app this build is. Debug builds, which `make run` opens, are Ficha Dev:
/// a separate app, so work in progress never touches the real Ficha or Lucas's
/// cards. Release builds, which `make install` puts in /Applications, are the
/// real Ficha. Each app's name and bundle identifier come from `project.yml`, and
/// the bundle identifier also keeps each app's preferences apart.
enum AppVariant {
    case dev
    case real

    /// The app this build is.
    static var current: AppVariant {
        #if DEBUG
            return .dev
        #else
            return .real
        #endif
    }

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

    /// Where the app keeps its data, such as its database: a folder of its own in
    /// Application Support. It's named apart from `name`, so renaming an app never
    /// moves its cards.
    var dataFolder: URL {
        let folder =
            switch self {
            case .dev: "Ficha Dev"
            case .real: "Ficha"
            }
        return URL.applicationSupportDirectory.appending(path: folder, directoryHint: .isDirectory)
    }
}
