import FichaCore
import Foundation
import GRDB
import Testing

// For the backups' files, which a test changes as a newer or an older
// version of Ficha would have left them.
@testable import FichaData

/// Tests on the copies of the database the engine saves in its Backups
/// folder, in a data folder of the test's own, on a Mac in Buenos Aires.
final class BackupTests {
    let calendar: Calendar
    let time: ManualTimeSource
    /// A data folder of the test's own, which the engine creates when it first opens it.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaBackupTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 21, in: calendar))
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// The engine on the test's data folder, as the app opens it.
    private func openEngine() throws -> Engine {
        try Engine(location: .folder(folder), time: time, calendar: calendar)
    }

    @Test("every day by default, the first open in a day saves a backup, and no other one is saved later that day")
    func dailyBackups() throws {
        let engine = try openEngine()

        let first = try engine.backUpIfDue(.defaults)
        time.advance(by: hours(14))
        let laterThatDay = try engine.backUpIfDue(.defaults)
        time.advance(by: hours(1))
        let nextDay = try engine.backUpIfDue(.defaults)

        #expect(first?.kind == .backup)
        #expect(laterThatDay == nil)
        #expect(nextDay?.kind == .backup)
        #expect(try engine.copies().map(\.savedAt) == [time.now, try morning(of: 21, in: calendar)])
    }

    @Test("every hour, the first open in an hour saves a backup, and no other one is saved later that hour")
    func hourlyBackups() throws {
        let engine = try openEngine()
        let settings = try #require(BackupSettings(frequency: .hourly, kept: 7))

        let first = try engine.backUpIfDue(settings)
        time.advance(by: minutes(59))
        let laterThatHour = try engine.backUpIfDue(settings)
        time.advance(by: minutes(1))
        let nextHour = try engine.backUpIfDue(settings)

        #expect(first != nil)
        #expect(laterThatHour == nil)
        #expect(nextHour != nil)
    }

    // 21 October 2026 is a Wednesday.
    @Test("every week, the first open in a week of the Mac's calendar saves a backup, and no other one that week")
    func weeklyBackups() throws {
        var weeksFromMonday = calendar
        weeksFromMonday.firstWeekday = 2
        let engine = try Engine(location: .folder(folder), time: time, calendar: weeksFromMonday)
        let settings = try #require(BackupSettings(frequency: .weekly, kept: 7))

        let first = try engine.backUpIfDue(settings)
        time.move(to: try morning(of: 25, in: calendar))
        let sunday = try engine.backUpIfDue(settings)
        time.move(to: try morning(of: 26, in: calendar))
        let monday = try engine.backUpIfDue(settings)

        #expect(first != nil)
        #expect(sunday == nil)
        #expect(monday != nil)
    }

    @Test("a Back Up Now in a day counts as its backup")
    func backUpNowCountsAsTheDaysBackup() throws {
        let engine = try openEngine()

        let now = try engine.backUpNow(.defaults)
        time.advance(by: hours(2))
        let onItsOwn = try engine.backUpIfDue(.defaults)

        #expect(now.kind == .backup)
        #expect(onItsOwn == nil)
        #expect(try engine.copies() == [now])
    }

    @Test("after more backups than the number kept, the newest ones remain, as many as kept")
    func newestBackupsRemain() throws {
        let engine = try openEngine()
        let settings = try #require(BackupSettings(frequency: .daily, kept: 3))

        var saved: [DatabaseCopy] = []
        for _ in 0..<5 {
            saved.append(try #require(try engine.backUpIfDue(settings)))
            time.advance(by: days(1))
        }

        #expect(try engine.copies() == saved.suffix(3).reversed())
    }

    // So a slip on Settings' stepper loses nothing.
    @Test("lowering the number kept deletes nothing until the next backup")
    func loweringTheNumberKeptWaitsForTheNextBackup() throws {
        let engine = try openEngine()
        var saved: [DatabaseCopy] = []
        for day in 21...25 {
            time.move(to: try morning(of: day, in: calendar))
            saved.append(try #require(try engine.backUpIfDue(.defaults)))
        }
        let fewer = try #require(BackupSettings(frequency: .daily, kept: 2))

        time.advance(by: hours(1))
        let laterThatDay = try engine.backUpIfDue(fewer)
        let afterLowering = try engine.copies()
        time.move(to: try morning(of: 26, in: calendar))
        let next = try #require(try engine.backUpIfDue(fewer))

        #expect(laterThatDay == nil)
        #expect(afterLowering == saved.reversed())
        #expect(try engine.copies() == [next, saved[4]])
    }

    @Test("two backups saved in the same second each keep a name of their own")
    func backupsInTheSameSecond() throws {
        let engine = try openEngine()

        let first = try engine.backUpNow(.defaults)
        let second = try engine.backUpNow(.defaults)

        #expect(first.name == "Backup 2026-10-21T120000Z.sqlite")
        #expect(second.name == "Backup 2026-10-21T120000Z 2.sqlite")
        #expect(try engine.copies() == [second, first])
    }

    @Test("a restore saves a copy before a restore, and the database then holds the copy's cards, review log and inbox")
    func restoreBringsBackTheCopy() throws {
        let engine = try openEngine()
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.meet(serendipia)
        try engine.newCapture("efímero")
        let backup = try engine.backUpNow(.defaults)
        let before = try Snapshot(of: engine)
        time.advance(by: hours(1))
        try engine.review(serendipia, .good)
        try approveCard("ubicuo", in: engine)
        try engine.newCapture("¿Por qué el cielo es azul?")
        let after = try Snapshot(of: engine)

        let restoration = try engine.restore(backup.name)

        #expect(restoration.restored == backup)
        #expect(restoration.copyBeforeRestore.kind == .beforeRestore)
        #expect(try engine.copies() == [restoration.copyBeforeRestore, backup])
        #expect(try Snapshot(of: engine) == before)
        #expect(before != after)

        time.advance(by: minutes(1))
        try engine.restore(restoration.copyBeforeRestore.name)

        #expect(try Snapshot(of: engine) == after)
    }

    // The CLI and the app each open an engine on the database, and the
    // restore never swaps its file under them.
    @Test(
        "another engine on the database reads the restored cards, and hears that it changed",
        .timeLimit(.minutes(1))
    )
    func anotherEngineReadsTheRestoredCards() async throws {
        let app = try openEngine()
        let cli = try openEngine()
        try approveCard("serendipia", in: app)
        let backup = try app.backUpNow(.defaults)
        try approveCard("ubicuo", in: app)
        var changes = cli.changes().makeAsyncIterator()

        try app.restore(backup.name)

        #expect(await changes.next() != nil)
        #expect(try cli.cards().map(\.front) == ["serendipia"])
    }

    @Test("after a restore, the database is still in write-ahead logging, as the app and the CLI share it")
    func restoreKeepsWriteAheadLogging() throws {
        let engine = try openEngine()
        let backup = try engine.backUpNow(.defaults)

        try engine.restore(backup.name)

        let mode = try DatabaseQueue(path: folder.appending(path: "Ficha.sqlite").path(percentEncoded: false))
            .read { db in try String.fetchOne(db, sql: "PRAGMA journal_mode") }
        #expect(mode == "wal")
    }

    @Test("copies before an update and before a restore are neither counted nor pruned")
    func otherCopiesAreNeitherCountedNorPruned() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try saveFirstVersionDatabase(at: folder.appending(path: "Ficha.sqlite"), capturing: "serendipia", at: time.now)
        let engine = try openEngine()
        let keepingOne = try #require(BackupSettings(frequency: .daily, kept: 1))
        let first = try #require(try engine.backUpIfDue(keepingOne))
        time.move(to: try morning(of: 22, in: calendar))
        let restoration = try engine.restore(first.name)

        time.advance(by: minutes(1))
        let second = try engine.backUpIfDue(keepingOne)

        #expect(second != nil)
        #expect(try engine.copies().map(\.kind) == [.backup, .beforeRestore, .beforeUpdate])
        #expect(try engine.copies().first == second)
        #expect(try engine.copies().contains(restoration.copyBeforeRestore))
    }

    @Test("a copy that a newer version of Ficha migrated is refused, and nothing changes")
    func copyFromANewerVersionIsRefused() throws {
        let engine = try openEngine()
        try approveCard("serendipia", in: engine)
        let backup = try engine.backUpNow(.defaults)
        var newerFicha = DatabaseMigrator()
        newerFicha.registerMigration("a migration from a newer Ficha") { _ in }
        try newerFicha.migrate(DatabaseQueue(path: try path(of: backup, in: engine)))
        try approveCard("ubicuo", in: engine)

        #expect(throws: EngineError.copyMigratedByNewerVersion(backup.name)) {
            try engine.restore(backup.name)
        }
        #expect(try engine.cards().map(\.front) == ["serendipia", "ubicuo"])
        #expect(try engine.copies().map(\.name) == [backup.name])
    }

    @Test("a copy from an older version of Ficha is restored and migrated, with its copy before an update")
    func copyFromAnOlderVersionIsMigrated() throws {
        let engine = try openEngine()
        try approveCard("ubicuo", in: engine)
        let backups = try #require(engine.backupsFolder)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let name = "Backup 2026-01-02T120000Z.sqlite"
        try saveFirstVersionDatabase(at: backups.appending(path: name), capturing: "serendipia", at: time.now)

        try engine.restore(name)

        #expect(try engine.inbox().captures.map(\.text) == ["serendipia"])
        #expect(try engine.cards().isEmpty)
        // The copy before the restore and the one before the update are
        // saved in the same second.
        #expect(Set(try engine.copies().map(\.kind)) == [.beforeRestore, .beforeUpdate, .backup])
        #expect(try engine.copies().count == 3)
    }

    @Test("a copy that isn't in the Backups folder can't be restored")
    func missingCopyIsRefused() throws {
        let engine = try openEngine()

        #expect(throws: EngineError.copyNotFound("Backup 2026-01-02T120000Z.sqlite")) {
            try engine.restore("Backup 2026-01-02T120000Z.sqlite")
        }
    }

    @Test("copies moved to the Trash leave the Backups folder for the Trash, where they can be brought back from")
    func copiesMoveToTheTrash() throws {
        let engine = try openEngine()
        let first = try engine.backUpNow(.defaults)
        time.advance(by: hours(1))
        let second = try engine.backUpNow(.defaults)
        time.advance(by: hours(1))
        let third = try engine.backUpNow(.defaults)

        let trashed = try engine.moveToTrash([first, third])
        // The test's copies don't stay in Lucas's Trash.
        defer {
            for file in trashed {
                try? FileManager.default.removeItem(at: file)
            }
        }

        #expect(try engine.copies() == [second])
        #expect(trashed.count == 2)
        #expect(trashed.allSatisfy { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) })
    }

    /// The path of `copy`'s file.
    private func path(of copy: DatabaseCopy, in engine: Engine) throws -> String {
        try #require(engine.backupsFolder).appending(path: copy.name).path(percentEncoded: false)
    }
}

/// What a restore brings back: the cards, the review log and the inbox.
private struct Snapshot: Equatable {
    let cards: [Card]
    let reviewLog: [ReviewLogEntry]
    let inbox: [Capture]

    init(of engine: Engine) throws {
        cards = try engine.cards()
        reviewLog = try engine.reviewLog()
        inbox = try engine.inbox().captures
    }
}
