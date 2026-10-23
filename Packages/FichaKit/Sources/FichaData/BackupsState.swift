import FichaCore
import Foundation

/// Settings' Backups tab, and the backups the app saves on its own, which
/// the tab and the menu say about, for as long as the app runs: what the tab
/// lists, the copies in the Backups folder, newest first, what Lucas selected
/// and so what the tab offers, Restore for one copy and Delete for any, what
/// it asks before it acts, and what couldn't be done. It also keeps why the
/// last attempt to back up failed, on its own or with Back Up Now, until a
/// backup is saved, which the tab says, and the menu with "Last backup
/// failed". It reads the copies again after each thing it does, and when the
/// tab asks.
public struct BackupsState: Sendable {
    /// What Lucas can do with the selected copies.
    public enum Action: Sendable, Hashable {
        /// Restore the copy, asking first.
        case restore
        /// Move the copies to the Trash, asking first.
        case delete
    }

    /// What the tab asks before it acts, until Lucas confirms or cancels.
    public enum Question: Sendable, Equatable {
        /// Whether to restore this copy, in place of everything as it is
        /// now, which a copy before a restore keeps.
        case restore(DatabaseCopy)
        /// Whether to move these copies to the Trash.
        case delete([DatabaseCopy])
    }

    /// The last backup, as the tab says it.
    public enum LastBackup: Sendable, Equatable {
        /// No backup was saved yet.
        case none
        /// The newest backup was saved then.
        case saved(Date)
        /// The last attempt to back up failed, for this reason.
        case failed(EngineError)
    }

    /// What Lucas did in the tab that couldn't be done, and why, which the
    /// tab says until he closes it.
    public struct Failure: Sendable, Equatable {
        /// What he did.
        public let action: FailedAction
        /// Why the engine couldn't do it.
        public let error: EngineError
    }

    /// What Lucas did that couldn't be done.
    public enum FailedAction: Sendable, Equatable {
        /// He restored a copy.
        case restore
        /// He moved this many copies to the Trash.
        case delete(copyCount: Int)
    }

    /// The Backups folder, which the tab shows, or nil for an engine in
    /// memory.
    public let folder: URL?
    /// The copies in the Backups folder, newest first, or why they couldn't
    /// be read: nil until they're first read.
    public private(set) var copies: Result<[DatabaseCopy], EngineError>?
    /// The copies Lucas selected, which can include copies the list no
    /// longer has: the actions take only those it has.
    public private(set) var selection: Set<DatabaseCopy.ID> = []
    /// What the tab asks before it acts, while it asks.
    public private(set) var question: Question?
    /// What Lucas did that couldn't be done, while the tab says so.
    public private(set) var failure: Failure?
    /// Why the last attempt to back up failed, until a backup is saved.
    private var lastAttemptFailure: EngineError?
    /// What the images the copies share weigh, in bytes, as last read.
    private var imagesSize: Int64 = 0
    private let engine: Engine

    init(engine: Engine) {
        self.engine = engine
        folder = engine.backupsFolder
    }

    /// The selected copies the list has, newest first.
    public var selectedCopies: [DatabaseCopy] {
        guard case .success(let copies) = copies else {
            return []
        }
        return copies.filter { selection.contains($0.id) }
    }

    /// What Lucas can do with the selected copies: restore one, and move any
    /// number to the Trash.
    public var actions: Set<Action> {
        switch selectedCopies.count {
        case 0: []
        case 1: [.restore, .delete]
        default: [.delete]
        }
    }

    /// The last backup: why the last attempt failed, when it did, or when the
    /// newest backup was saved.
    public var lastBackup: LastBackup {
        if let lastAttemptFailure {
            return .failed(lastAttemptFailure)
        }
        guard case .success(let copies) = copies, let newest = copies.first(where: { $0.kind == .backup }) else {
            return .none
        }
        return .saved(newest.savedAt)
    }

    /// Whether the last attempt to back up failed, which the menu says until
    /// a backup is saved.
    public var lastBackupFailed: Bool {
        lastAttemptFailure != nil
    }

    /// What the copies the list has weigh in all, in bytes: their databases,
    /// without the images they share.
    public var totalSize: Int64 {
        guard case .success(let copies) = copies else {
            return 0
        }
        return copies.reduce(0) { $0 + $1.size }
    }

    /// What the images the copies share weigh, in bytes, each once however
    /// many copies refer to it, which the tab says beside what the copies
    /// weigh; or nil while they share none, and the tab says nothing about
    /// images.
    public var sharedImagesSize: Int64? {
        guard case .success = copies, imagesSize > 0 else {
            return nil
        }
        return imagesSize
    }

    /// Reads the copies in the Backups folder again, as they are now, and
    /// what the images they share weigh. When either can't be read, the tab
    /// says why in place of the copies.
    public mutating func read() {
        do throws(EngineError) {
            let read = try engine.copies()
            imagesSize = try engine.sharedImagesSize()
            copies = .success(read)
        } catch {
            imagesSize = 0
            copies = .failure(error)
        }
    }

    /// Saves a backup when one is due, as `settings` say, and lets the oldest
    /// beyond the number kept go: the app asks as it launches and as time
    /// passes. A backup that fails is logged, and the tab and the menu say so
    /// until one is saved.
    public mutating func backUpIfDue(_ settings: BackupSettings) {
        backUp { engine throws(EngineError) in try engine.backUpIfDue(settings) }
    }

    /// Saves a backup now, Back Up Now, which is the backup of its hour, day
    /// or week, and lets the oldest beyond the number `settings` keep go. One
    /// that fails is said as a backup that failed on its own.
    public mutating func backUpNow(_ settings: BackupSettings) {
        backUp { engine throws(EngineError) in try engine.backUpNow(settings) }
    }

    /// Selects the copies in `selection`.
    public mutating func select(_ selection: Set<DatabaseCopy.ID>) {
        self.selection = selection
    }

    /// Asks whether to restore the selected copy, while Restore is offered.
    public mutating func askToRestore() {
        guard actions.contains(.restore), let copy = selectedCopies.first else { return }
        question = .restore(copy)
    }

    /// Restores `copy`, which the tab asked about and Lucas confirmed, after
    /// saving everything as it is now in a copy before a restore, which the
    /// list then shows, or records why it couldn't. The dialog that asked
    /// hands `copy` back, since SwiftUI may close it, which drops the
    /// question, before its button acts.
    public mutating func restore(_ copy: DatabaseCopy) {
        question = nil
        do throws(EngineError) {
            try engine.restore(copy.name)
        } catch {
            failure = Failure(action: .restore, error: error)
        }
        read()
    }

    /// Asks whether to move the selected copies to the Trash, while Delete is
    /// offered.
    public mutating func askToDelete() {
        guard actions.contains(.delete) else { return }
        question = .delete(selectedCopies)
    }

    /// Moves `copies`, which the tab asked about and Lucas confirmed, to the
    /// Trash, where he can bring them back from, or records why it couldn't,
    /// and returns where each one went. The dialog hands `copies` back, as
    /// Restore's hands its copy.
    @discardableResult
    public mutating func delete(_ copies: [DatabaseCopy]) -> [URL] {
        question = nil
        var trashed: [URL] = []
        do throws(EngineError) {
            trashed = try engine.moveToTrash(copies)
        } catch {
            failure = Failure(action: .delete(copyCount: copies.count), error: error)
        }
        selection.subtract(copies.map(\.id))
        read()
        return trashed
    }

    /// Drops what the tab asks, which Lucas cancelled.
    public mutating func cancelQuestion() {
        question = nil
    }

    /// Clears what failed, once the tab said so and Lucas closed it.
    public mutating func dismissFailure() {
        failure = nil
    }

    /// Backs up with `work`, noting whether it failed, and reads the copies
    /// again. A failure stays until a backup is saved, not only tried: a
    /// check that finds none due doesn't clear it.
    private mutating func backUp(_ work: (Engine) throws(EngineError) -> DatabaseCopy?) {
        do throws(EngineError) {
            if try work(engine) != nil {
                lastAttemptFailure = nil
            }
        } catch {
            lastAttemptFailure = error
        }
        read()
    }
}

extension Engine {
    /// The Backups tab's state, and the backups the app saves on its own,
    /// before the copies are read.
    public func openBackups() -> BackupsState {
        BackupsState(engine: self)
    }
}
