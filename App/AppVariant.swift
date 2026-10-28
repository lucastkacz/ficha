import Foundation

#if os(macOS)
    import Security
#endif

/// Which app this build is: Ficha Dev, for development, or the real Ficha, so
/// work in progress never touches the real Ficha or Lucas's cards. Each build
/// configuration in `project.yml` names its app, gives it its own bundle
/// identifier (and so its own preferences) and sets the flag `current` reads.
/// The `ficha` CLI compiles this file too, so the CLI built with each app
/// opens that app's cards, and so does the iPhone app, which is only Ficha
/// Dev for now.
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

    /// Where the app keeps its data, such as its database: a folder of its
    /// own, named apart from `name`, so renaming an app never moves its cards.
    /// On the Mac, Ficha Dev's is in its App Group's folder, which its sandbox
    /// and its CLI's share (ADR 0018), unless `FICHA_DEV_SCRATCH` names a
    /// scratch folder there, so an agent's runs of the CLI stay out of Ficha
    /// Dev's cards. The real Ficha's stays in Application Support until it
    /// moves into its own group (#309), and on the iPhone it's in the app's
    /// own Application Support.
    var dataFolder: URL {
        get throws(DataFolderError) {
            #if os(macOS)
                switch self {
                case .dev:
                    let group = try signedGroupFolder(named: "com.lucastkacz.ficha.dev")
                    guard let scratch = ProcessInfo.processInfo.environment["FICHA_DEV_SCRATCH"] else {
                        return group.appending(path: folderName, directoryHint: .isDirectory)
                    }
                    return try scratchFolder(named: scratch, in: group)
                case .real:
                    break
                }
            #endif
            return URL.applicationSupportDirectory.appending(path: folderName, directoryHint: .isDirectory)
        }
    }

    /// The name of the app's data folder.
    private var folderName: String {
        switch self {
        case .dev: "Ficha Dev"
        case .real: "Ficha"
        }
    }
}

/// Why Ficha Dev can't find its data folder on the Mac. Like Ficha Dev's
/// debug tools, each message is in English and verbatim, never translated
/// (ADR 0009).
enum DataFolderError: Error, LocalizedError {
    /// The build isn't signed with Ficha Dev's App Group, as one built
    /// without the team's ID isn't.
    case notSignedWithItsGroup
    /// `FICHA_DEV_SCRATCH` holds this, which can't name a folder.
    case scratchName(String)

    var errorDescription: String? {
        switch self {
        case .notSignedWithItsGroup:
            """
            This Ficha Dev isn't signed with its App Group, whose folder holds its cards. Build it with make run, \
            with your team's ID in iPhone/Local.xcconfig, as docs/development.md says.
            """
        case .scratchName(let name):
            """
            FICHA_DEV_SCRATCH is “\(name)”, which can't name a scratch folder: use letters, digits, - and _ alone, \
            as in FICHA_DEV_SCRATCH=agent-304.
            """
        }
    }
}

#if os(macOS)
    /// The value of `entitlement` this process is signed with, read from its
    /// own signature, or nil when it has none, as an unsigned build hasn't.
    /// So the team's ID, which names the App Groups, is never written in the
    /// code. Reading the groups this way is our own choice: Apple documents
    /// the entitlement and the group's folder, not reading one from the other.
    func signedEntitlement(_ entitlement: String) -> CFTypeRef? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        return SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil)
    }

    /// The folder of the App Group this process is signed with whose name,
    /// after the team's ID that macOS puts before it, is `name`.
    private func signedGroupFolder(named name: String) throws(DataFolderError) -> URL {
        let groups = signedEntitlement("com.apple.security.application-groups") as? [String] ?? []
        guard let group = groups.first(where: { $0.hasSuffix(".\(name)") }),
            let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else {
            throw .notSignedWithItsGroup
        }
        return folder
    }

    /// The scratch folder `name` in the group's folder `group`: a data folder
    /// of its own, which the app doesn't hear, since the database's changes
    /// are named after its path. It has to be in the group's folder, since
    /// the CLI's sandbox lets it write nowhere else.
    private func scratchFolder(named name: String, in group: URL) throws(DataFolderError) -> URL {
        guard !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_".contains($0)) })
        else {
            throw .scratchName(name)
        }
        return group.appending(path: "Scratch/\(name)", directoryHint: .isDirectory)
    }
#endif
