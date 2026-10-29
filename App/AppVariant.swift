import FichaData
import Foundation

#if os(macOS)
    import Security
#endif

/// Which app this build is: Ficha Dev, for development, or the real Ficha, so
/// work in progress never touches the real Ficha or Lucas's cards. Each build
/// configuration in `project.yml` names its app, gives it its own bundle
/// identifier (and so its own preferences) and sets the flag `current` reads.
/// The `ficha` CLI compiles this file too, so the CLI built with each app
/// opens that app's cards, and so do the widget's extension, which reads
/// them, and the iPhone app, which is only Ficha Dev for now.
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

    /// The app's bundle identifier, the same as its `PRODUCT_BUNDLE_IDENTIFIER`
    /// in `project.yml`, by which the CLI asks macOS whether its app runs.
    var bundleIdentifier: String {
        switch self {
        case .dev: "com.lucastkacz.ficha.dev"
        case .real: "com.lucastkacz.ficha"
        }
    }

    /// The bundle identifier of the SVG drawer, the XPC service inside the
    /// app that draws an import's SVGs, the same as the `SVGDrawer` target's
    /// `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`, by which the app asks it.
    var svgDrawerIdentifier: String {
        "\(bundleIdentifier).svg-drawer"
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
    /// Only Ficha Dev has it, and its CLI runs on the time the menu moves too:
    /// the real Ficha and its CLI always run on the system's time.
    var hasDebugMenu: Bool {
        switch self {
        case .dev: true
        case .real: false
        }
    }

    /// Whether the app syncs its cards through the user's iCloud (ADR 0017):
    /// Ficha Dev does, in the Development environment of Ficha's container,
    /// a scratch run too, in zones of its own (`scratchName`). The real Ficha
    /// builds the same code, but keeps sync off until it holds iCloud's
    /// entitlements (#318), since CloudKit stops an app that asks for a
    /// container without them: signed with the team, it holds its App Group
    /// alone.
    var syncsThroughICloud: Bool {
        switch self {
        case .dev: true
        case .real: false
        }
    }

    /// The scratch run `FICHA_DEV_SCRATCH` names in Ficha Dev, an agent's,
    /// or nil for Ficha Dev's own data folder, and always for the real Ficha.
    /// It names the scratch folder the app opens and the zones it syncs in,
    /// "Cards-<name>…" and "Files-<name>", which Ficha Dev's own devices
    /// leave alone, so its cards never reach Ficha Dev's. A name that can't
    /// name one, with anything but letters, digits, `-` and `_`, fails.
    var scratchName: ScratchName? {
        get throws(DataFolderError) {
            switch self {
            case .dev:
                guard let name = ProcessInfo.processInfo.environment["FICHA_DEV_SCRATCH"] else {
                    return nil
                }
                guard let scratch = ScratchName(name) else {
                    throw .unusableScratchName(name)
                }
                return scratch
            case .real:
                return nil
            }
        }
    }

    /// Where the app keeps its data, such as its database: a folder of its
    /// own, named apart from `name`, so renaming an app never moves its cards.
    /// On the Mac, it's in the app's App Group's folder, which the app and its
    /// CLI share (ADR 0018), and Ficha Dev's widget too. Ficha Dev's is there
    /// unless `FICHA_DEV_SCRATCH` names a scratch folder there, so an agent's
    /// runs of the CLI stay out of Ficha Dev's cards. The real Ficha's is
    /// there once it holds the database, and in Application Support while
    /// Lucas's data waits there to move (`dataMove`), so a move that failed
    /// leaves him on his cards, never on an empty Ficha. The real Ficha's
    /// widget, signed without the team's ID until #310, isn't in its app's
    /// group, so it finds no data folder (`notSignedWithItsGroup`). On the
    /// iPhone, it's in the app's own Application Support.
    var dataFolder: URL {
        get throws(DataFolderError) {
            #if os(macOS)
                switch self {
                case .dev:
                    guard let scratch = try scratchName else {
                        return try groupDataFolder
                    }
                    // A data folder of its own, which the app doesn't hear,
                    // since the database's changes are named after its path.
                    // It has to be in the group's folder, since the CLI's
                    // sandbox lets it write nowhere else.
                    return try signedGroupFolder(named: groupName).appending(
                        path: "Scratch/\(scratch.rawValue)", directoryHint: .isDirectory)
                case .real:
                    guard let move = try dataMove else {
                        return try groupDataFolder
                    }
                    return move.source
                }
            #else
                return applicationSupportDataFolder
            #endif
        }
    }

    /// The app's data folder in Application Support, where the real Ficha
    /// kept its data before it moved into its App Group's folder, and where
    /// the iPhone app keeps it.
    private var applicationSupportDataFolder: URL {
        URL.applicationSupportDirectory.appending(path: folderName, directoryHint: .isDirectory)
    }

    #if os(macOS)
        /// The defaults of the app's App Group, which the app and its widget
        /// share, or nil where they don't: in a build not signed with it, and
        /// in the real Ficha, whose widget signs without the team's ID until
        /// #310, which leaves it out of the group its app moved into (#309),
        /// so nothing the app handed it there would reach it. So the real
        /// Ficha writes nothing in its group's defaults meanwhile.
        var groupDefaults: UserDefaults? {
            switch self {
            case .dev: signedGroup(named: groupName).flatMap(UserDefaults.init(suiteName:))
            case .real: nil
            }
        }
    #endif

    /// The name of the app's data folder.
    private var folderName: String {
        switch self {
        case .dev: "Ficha Dev"
        case .real: "Ficha"
        }
    }
}

#if os(macOS)
    extension AppVariant {
        /// The real Ficha's move of Lucas's data from Application Support's
        /// data folder into its App Group's (#309), while it waits, as
        /// FichaData's `DataMove` decides: before the last build without the
        /// sandbox ran it, or after it failed. Nil once it moved, and when
        /// there was nothing to move, as for anyone but Lucas, and for Ficha
        /// Dev, which moves nothing: its sandboxed build started empty in its
        /// group.
        var dataMove: DataMove? {
            get throws(DataFolderError) {
                guard self == .real else { return nil }
                return DataMove(waitingFrom: applicationSupportDataFolder, to: try groupDataFolder)
            }
        }

        /// The app's data folder in its App Group's folder.
        var groupDataFolder: URL {
            get throws(DataFolderError) {
                try signedGroupFolder(named: groupName).appending(path: folderName, directoryHint: .isDirectory)
            }
        }
    }
#endif

/// Why the app can't find its data folder on the Mac. The iPhone app's is
/// always there, so it never meets these.
enum DataFolderError: Error {
    /// The build isn't signed with its App Group, as one built without the
    /// team's ID isn't.
    case notSignedWithItsGroup
    /// macOS gave no folder for the App Group with this name, which the
    /// build is signed with.
    case noGroupFolder(String)
    /// `FICHA_DEV_SCRATCH` holds this, which can't name a folder.
    case unusableScratchName(String)
}

#if os(macOS)
    /// What the alert at launch says, the widget too, as why it can't read
    /// the cards, and the CLI. Those the app and the widget can show, the
    /// real Ficha's included, are translated, as every text they show is,
    /// the widget's from its own String Catalog; the CLI's main bundle has no
    /// String Catalog, which keeps them in English there. Only an agent's run
    /// of Ficha Dev or its CLI meets `unusableScratchName`, which is in
    /// English and verbatim, never translated, as Ficha Dev's debug tools'
    /// messages are (ADR 0009).
    extension DataFolderError: LocalizedError {
        var errorDescription: String? {
            switch self {
            case .notSignedWithItsGroup:
                String(
                    localized: """
                        This build isn't signed with its App Group, whose folder holds its cards. Build Ficha Dev \
                        with make run, or Ficha with make install, with your team's ID in iPhone/Local.xcconfig, as \
                        docs/development.md says.
                        """,
                    comment: """
                        An alert at launch, which only a build made by hand without the developer's team shows. The \
                        widget shows it too, under that it can't read the cards, as the real Ficha's does while it's \
                        signed without the team. make run and make install are commands, iPhone/Local.xcconfig a \
                        file and docs/development.md a document, whose names stay as they are.
                        """)
            case .noGroupFolder(let group):
                String(
                    localized: """
                        macOS gave no folder for the App Group \(group), which holds your cards. Quit the app and \
                        open it again, and if it keeps happening, report it.
                        """,
                    comment: """
                        An alert at launch, and in the widget, under that it can't read the cards. The value is the \
                        App Group's identifier, such as ABCDE12345.com.lucastkacz.ficha, which stays as it is.
                        """)
            case .unusableScratchName(let name):
                """
                FICHA_DEV_SCRATCH is “\(name)”, which can't name a scratch folder: use letters, digits, - and _ \
                alone, as in FICHA_DEV_SCRATCH=agent-304.
                """
            }
        }
    }
#endif

#if os(macOS)
    extension AppVariant {
        /// The name of the app's App Group, after the team's ID that macOS
        /// puts before it, as `FICHA_APP_GROUP` in `project.yml` names it:
        /// the app and its CLI share the group's folder, and Ficha Dev's
        /// widget too.
        fileprivate var groupName: String {
            switch self {
            case .dev: "com.lucastkacz.ficha.dev"
            case .real: "com.lucastkacz.ficha"
            }
        }

        /// Whether this process is signed for iCloud, with iCloud's
        /// entitlements: CloudKit stops a process that isn't, as #316 probed,
        /// so a build signed without them reaches no iCloud at all.
        static var isSignedForICloud: Bool {
            signedEntitlement("com.apple.developer.icloud-services") != nil
        }
    }

    /// The value of `entitlement` this process is signed with, read from its
    /// own signature, or nil when it has none, as an unsigned build hasn't.
    /// So the team's ID, which names the App Groups, is never written in the
    /// code. Reading the groups this way is our own choice: Apple documents
    /// the entitlement and the group's folder, not reading one from the other.
    func signedEntitlement(_ entitlement: String) -> CFTypeRef? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        return SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil)
    }

    /// The App Group this process is signed with whose name, after the team's
    /// ID that macOS puts before it, is `name`, or nil when it isn't signed
    /// with one.
    private func signedGroup(named name: String) -> String? {
        let groups = signedEntitlement("com.apple.security.application-groups") as? [String] ?? []
        return groups.first { $0.hasSuffix(".\(name)") }
    }

    /// The folder of the App Group this process is signed with whose name,
    /// after the team's ID that macOS puts before it, is `name`.
    private func signedGroupFolder(named name: String) throws(DataFolderError) -> URL {
        guard let group = signedGroup(named: name) else {
            throw .notSignedWithItsGroup
        }
        guard let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw .noGroupFolder(group)
        }
        return folder
    }
#endif
