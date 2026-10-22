import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on Settings' Backups tab, and on the backups the app saves on its
/// own, which the tab and the menu say about, in a data folder of the test's
/// own.
final class BackupsStateTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    /// A data folder of the test's own, which the engine creates when it first opens it.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaBackupsStateTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    /// Where the copies the tests move to the Trash went, to take them out
    /// of it once each test ends.
    var trashed: [URL] = []

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 21, in: calendar))
        engine = try Engine(location: .folder(folder), time: time, calendar: calendar)
    }

    deinit {
        for file in trashed {
            try? FileManager.default.removeItem(at: file)
        }
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("the tab lists every copy, newest first, and the last backup, from when the app backed up on its own")
    func tabListsTheCopies() throws {
        var backups = engine.openBackups()
        backups.backUpIfDue(.defaults)
        time.advance(by: hours(3))
        backups.backUpNow(.defaults)
        let newest = try #require(try engine.copies().first)
        time.advance(by: hours(1))

        backups.read()

        #expect(try backups.copies?.get() == engine.copies())
        #expect(try backups.copies?.get().map(\.kind) == [.backup, .backup])
        #expect(backups.lastBackup == .saved(newest.savedAt))
        #expect(!backups.lastBackupFailed)
    }

    @Test("before any backup, the tab says there's none yet")
    func noBackupYet() {
        var backups = engine.openBackups()

        backups.read()

        #expect(backups.copies == .success([]))
        #expect(backups.lastBackup == .none)
    }

    @Test("Restore is offered for one selected copy, and Delete for one or more")
    func actionsFollowTheSelection() throws {
        var backups = engine.openBackups()
        backups.backUpNow(.defaults)
        time.advance(by: hours(1))
        backups.backUpNow(.defaults)
        let copies = try #require(try backups.copies?.get())

        let none = backups.actions
        backups.select([copies[0].id])
        let one = backups.actions
        backups.select(Set(copies.map(\.id)))
        let both = backups.actions

        #expect(none.isEmpty)
        #expect(one == [.restore, .delete])
        #expect(both == [.delete])
        #expect(backups.selectedCopies == copies)
    }

    @Test("Restore asks first, then saves a copy before a restore, which the list shows, and brings the copy back")
    func restoreAsksFirst() throws {
        var backups = engine.openBackups()
        try approveCard("serendipia", in: engine)
        backups.backUpNow(.defaults)
        let backup = try #require(try backups.copies?.get().first)
        try approveCard("ubicuo", in: engine)
        backups.select([backup.id])

        backups.askToRestore()
        let question = backups.question
        time.advance(by: minutes(1))
        backups.restore(backup)

        #expect(question == .restore(backup))
        #expect(backups.question == nil)
        #expect(try engine.cards().map(\.front) == ["serendipia"])
        #expect(try backups.copies?.get().map(\.kind) == [.beforeRestore, .backup])
        #expect(backups.failure == nil)
    }

    @Test("Delete asks first, then moves the selected copies to the Trash")
    func deleteAsksFirst() throws {
        var backups = engine.openBackups()
        backups.backUpNow(.defaults)
        time.advance(by: hours(1))
        backups.backUpNow(.defaults)
        time.advance(by: hours(1))
        backups.backUpNow(.defaults)
        let copies = try #require(try backups.copies?.get())
        backups.select([copies[0].id, copies[2].id])

        backups.askToDelete()
        let question = backups.question
        trashed += backups.delete([copies[0], copies[2]])

        #expect(question == .delete([copies[0], copies[2]]))
        #expect(backups.question == nil)
        #expect(try backups.copies?.get() == [copies[1]])
        #expect(backups.selection.isEmpty)
        #expect(trashed.count == 2)
    }

    @Test("a failed backup shows in the tab and in the menu until a backup is saved")
    func failedBackupShowsUntilOneIsSaved() throws {
        var backups = engine.openBackups()
        // A file where the Backups folder goes, so no copy can be saved.
        let backupsFolder = folder.appending(path: "Backups")
        try? FileManager.default.removeItem(at: backupsFolder)
        try Data().write(to: backupsFolder)

        backups.backUpIfDue(.defaults)
        let failed = (backups.lastBackup, backups.lastBackupFailed)
        try FileManager.default.removeItem(at: backupsFolder)
        backups.backUpNow(.defaults)

        #expect(failed.0 == .failed(.backupsFolder))
        #expect(failed.1)
        #expect(!backups.lastBackupFailed)
        #expect(backups.lastBackup == .saved(time.now))
    }

    @Test("a failed backup still shows after a check that finds none due")
    func failedBackupShowsAfterACheckWithNoneDue() throws {
        var backups = engine.openBackups()
        backups.backUpNow(.defaults)
        let backupsFolder = try #require(engine.backupsFolder).path(percentEncoded: false)
        // A Backups folder Ficha can list but not write in, so no copy can be
        // saved, and the check finds today's backup.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: backupsFolder)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: backupsFolder) }
        time.advance(by: hours(1))
        backups.backUpNow(.defaults)
        let failed = backups.lastBackupFailed

        backups.backUpIfDue(.defaults)

        #expect(failed)
        #expect(backups.lastBackupFailed)
    }

    @Test("a restore that fails says why, and the list shows the copies as they are")
    func failedRestoreSaysWhy() throws {
        var backups = engine.openBackups()
        backups.backUpNow(.defaults)
        let backup = try #require(try backups.copies?.get().first)
        try FileManager.default.removeItem(at: try #require(engine.backupsFolder).appending(path: backup.name))

        backups.restore(backup)

        #expect(backups.failure?.action == .restore)
        #expect(backups.failure?.error == .copyNotFound(backup.name))
        #expect(backups.copies == .success([]))
    }
}
