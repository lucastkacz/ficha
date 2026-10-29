import FichaData
import Foundation

/// Lucas's data move into the real Ficha's App Group's folder, which its
/// sandbox and its CLI's share (ADR 0018, #309). The last build without the
/// sandbox runs it as it launches, from Application Support, works from
/// there, and keeps all its preferences in a file there, which the sandboxed
/// Ficha reads in at the first launch that finds it, where its preferences
/// are its own. Ficha Dev moves nothing. FichaData logs what the move and
/// the preferences file did, and why they failed.
enum MoveIntoGroup {
    /// Keeps the preferences file up to date as a preference changes, once
    /// it started.
    private static var preferencesObserver: (any NSObjectProtocol)?

    /// The real Ficha's data folder, once its move did what it does as the
    /// app launches, before the app opens its cards and reads its settings.
    /// Without the sandbox, it moves Lucas's data while it waits in
    /// Application Support; when the move fails, the app works from there
    /// meanwhile, and the next launch tries again. In the sandbox, it reads
    /// the preferences file in at the first launch that finds it, before the
    /// settings that decide a card's progress move from the preferences into
    /// the database (#315), so Lucas's move in.
    static func dataFolderAtLaunch() throws(DataFolderError) -> URL {
        let real = AppVariant.real
        guard !runsInItsSandbox else {
            let dataFolder = try real.dataFolder
            // On purpose: FichaData logs why it couldn't read the file in,
            // and the next launch tries again.
            _ = try? PreferencesFile(in: dataFolder).readIn(to: .standard)
            return dataFolder
        }
        if let move = try real.dataMove {
            // On purpose: FichaData logs why the move failed, and the app
            // then works from the old folder, which `dataFolder` names while
            // the move waits, until the next launch tries again.
            _ = try? move.run()
        }
        return try real.dataFolder
    }

    /// Writes all the preferences to the file in `dataFolder`, the real
    /// Ficha's, and again whenever one changes, for the sandboxed Ficha, while
    /// the last build without the sandbox works from its App Group's folder.
    /// The sandboxed Ficha writes none, and nor does the last build while it
    /// works from Application Support, until its data moved.
    static func keepPreferencesFile(in dataFolder: URL) {
        // A group's folder that can't be found isn't `dataFolder`, which the
        // app opened, so there's nothing to write.
        guard !runsInItsSandbox, dataFolder == (try? AppVariant.real.groupDataFolder) else { return }
        let file = PreferencesFile(in: dataFolder)
        let domain = AppVariant.real.bundleIdentifier
        // On purpose, here and as a preference changes: FichaData logs why
        // the file couldn't be written, and the next change writes it again.
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
