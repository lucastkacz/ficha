import ArgumentParser
import FichaData
import Foundation

/// `ficha restore`: lists the copies Ficha saved in its Backups folder, or
/// brings one back, as Restore does in Settings' Backups tab.
struct RestoreCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "restore",
        abstract: "List the copies of your cards Ficha saved, or bring one back and print what it restored.",
        discussion: """
            With no copy, it prints every copy in Ficha's Backups folder, newest first, each with its "kind" \
            (backup, beforeUpdate, beforeRestore or beforeImport), when it was saved in "savedAt", its "size" in bytes, and the \
            "name" to restore it by. With a copy's name, it first saves everything as it is now in a copy before a \
            restore, then brings the copy back, and prints both: restoring the copy before the restore undoes it. \
            It won't restore while the app runs: quit the app first.
            """
    )

    @Argument(help: "The name of the copy to restore, as `ficha restore` lists it.")
    var copy: String?

    func run(on engine: Engine) throws -> any Encodable {
        guard let copy else {
            return try engine.copies()
        }
        return try engine.restore(copy)
    }
}

/// A restore that wasn't run because the app the CLI belongs to runs, and
/// would go on with Lucas's cards as they were before it. Its message says to
/// quit the app first.
struct AppIsRunningError: LocalizedError {
    /// The app's name.
    let appName: String

    var errorDescription: String? {
        """
        \(appName) is running, so its cards can't be restored from here, and nothing changed. Quit \(appName) \
        from its menu and run the command again, or restore the copy from \(appName)'s Settings, in Backups.
        """
    }
}
