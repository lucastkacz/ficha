import FichaData
import Foundation

/// The real Ficha's move into its App Group's folder, which its sandbox and
/// its CLI's share (ADR 0018, #309). The last build without the sandbox
/// copies Lucas's data there from Application Support as it launches, works
/// from there, and keeps all its preferences in a file there, which the
/// sandboxed Ficha reads in at its first launch, where its preferences are
/// its own. Ficha Dev moves nothing. FichaData logs what the copy and the
/// preferences file did, and why they failed.
enum MoveIntoGroup {
    /// Keeps the preferences file up to date as a preference changes, once
    /// it started.
    private static var preferencesObserver: (any NSObjectProtocol)?

    /// The real Ficha's data folder, once its move did what it does as the
    /// app launches, before the app opens its cards and reads its settings.
    /// Without the sandbox, it copies Lucas's data while it waits in
    /// Application Support; when the copy fails, the app works from there
    /// meanwhile, and the next launch tries again. In the sandbox, it reads
    /// the preferences file in at the first launch, before the settings that
    /// decide a card's progress move from the preferences into the database
    /// (#315), so Lucas's move in.
    static func dataFolderAtLaunch() throws(DataFolderError) -> URL {
        let real = AppVariant.real
        guard !runsInItsSandbox else {
            let dataFolder = try real.dataFolder
            _ = try? PreferencesFile(in: dataFolder).readIn(to: .standard)
            return dataFolder
        }
        if let move = try real.dataWaitingToMove {
            _ = try? copyDataFolder(from: move.from, to: move.to)
        }
        return try real.dataFolder
    }

    /// Writes all the preferences to the file in `dataFolder`, the real
    /// Ficha's, and again whenever one changes, for the sandboxed Ficha, while
    /// the last build without the sandbox works from its App Group's folder.
    /// The sandboxed Ficha writes none, and nor does the last build while it
    /// works from Application Support, until its data moved.
    static func keepPreferencesFile(in dataFolder: URL) {
        guard !runsInItsSandbox, dataFolder == (try? AppVariant.real.groupDataFolder) else { return }
        let file = PreferencesFile(in: dataFolder)
        let domain = AppVariant.real.bundleIdentifier
        try? file.write(domain, from: .standard)
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { _ in
            try? file.write(domain, from: .standard)
        }
    }

    /// Whether this process runs in its App Sandbox, as the sandboxed Ficha
    /// does, by its signature.
    private static var runsInItsSandbox: Bool {
        signedEntitlement("com.apple.security.app-sandbox") as? Bool == true
    }
}
