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

    // So a slip in Settings' Backups to keep loses nothing.
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
    func restoreBringsBackTheCopy() async throws {
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

    @Test("a copy from before tags of their own restores with every card where it stood, and no deck set aside")
    func copyFromBeforeTagsRestoresWithNoDeckSetAside() throws {
        let engine = try openEngine()
        try engine.setAside(deck: Deck.defaultName)
        let backups = try #require(engine.backupsFolder)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let name = "Backup 2026-01-02T120000Z.sqlite"
        try saveDatabaseBeforeTags(at: backups.appending(path: name), at: time.now)

        try engine.restore(name)

        #expect(
            try engine.cards().map(\.standing) == [
                .inReviews, .inInbox(Flag(note: "Falta un ejemplo", flaggedAt: time.now)),
                .buried(at: time.now, flag: nil),
            ])
        #expect(try engine.decks().filter(\.isSetAside).isEmpty)
    }

    @Test("a copy from before cards without a type or a capture restores with every card as it was")
    func copyFromBeforeOptionalTypesRestoresEveryCardAsItWas() throws {
        let engine = try openEngine()
        try engine.create(card(nil, front: "petricor", back: "El olor de la lluvia."))
        let backups = try #require(engine.backupsFolder)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let name = "Backup 2026-01-02T120000Z.sqlite"
        try saveDatabaseBeforeOptionalTypes(at: backups.appending(path: name), at: time.now)

        try engine.restore(name)

        try expectEveryCardAsItWasBeforeOptionalTypes(in: engine, at: time.now)
    }

    @Test(
        "a copy from before IDs unique across devices restores with every row as it was, each review with an ID of its own"
    )
    func copyFromBeforeIDsRestoresWithAnIDForEveryRow() throws {
        let engine = try openEngine()
        try engine.create(card(nil, front: "petricor", back: "El olor de la lluvia."))
        let backups = try #require(engine.backupsFolder)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let name = "Backup 2026-01-02T120000Z.sqlite"
        try saveDatabaseBeforeIDs(at: backups.appending(path: name), at: time.now)

        try engine.restore(name)

        try expectEveryRowWithAnIDAsBeforeIDs(in: engine, at: time.now)
    }

    @Test("a copy from before Ficha kept when a card was edited restores with every card never edited, until it is")
    func copyFromBeforeEditedTimesRestoresWithEveryCardNeverEdited() async throws {
        let engine = try openEngine()
        let backups = try #require(engine.backupsFolder)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let name = "Backup 2026-01-02T120000Z.sqlite"
        try saveDatabaseBeforeEditedTimes(at: backups.appending(path: name), at: time.now - days(1))

        try engine.restore(name)
        let restored = try engine.cards()
        let edited = try engine.edit(1, with: card(.word, front: "serendipia", back: "Un hallazgo por casualidad."))

        #expect(restored.map(\.front) == ["serendipia", "ubuntu"])
        #expect(restored.map(\.back) == ["Un hallazgo.", "Soy porque somos."])
        #expect(restored.map(\.editedAt) == [nil, nil])
        #expect(edited.editedAt == time.now)
    }

    @Test("a copy from before sounds on cards restores with every card as it was and no sound, until one is put")
    func copyFromBeforeSoundsRestoresWithNoSound() async throws {
        let engine = try openEngine()
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let la = try await addTone(440, to: engine)
        try engine.create(card(nil, front: "¿Qué nota es?", back: "La.", frontSound: la))
        let backups = try #require(engine.backupsFolder)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let name = "Backup 2026-01-02T120000Z.sqlite"
        try saveDatabaseBeforeSounds(at: backups.appending(path: name), at: time.now - days(1), image: bird)

        try engine.restore(name)
        let restored = try engine.cards()
        let edited = try engine.edit(
            2, with: card(.concept, front: "ubuntu", back: "Soy porque somos.", backSound: la))

        #expect(restored.map(\.front) == ["hornero", "ubuntu"])
        #expect(restored.map(\.frontImage) == [bird, nil])
        #expect(restored.allSatisfy { $0.frontSound == nil && $0.backSound == nil })
        #expect(edited.backSound == la)
    }

    @Test("a copy from before Both ways restores with every card going one way, and a backup since keeps the switch")
    func copyFromBeforeBothWaysRestoresWithEveryCardGoingOneWay() throws {
        let engine = try openEngine()
        let backups = try #require(engine.backupsFolder)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let name = "Backup 2026-01-02T120000Z.sqlite"
        try saveDatabaseBeforeBothWays(at: backups.appending(path: name), at: time.now - days(1))

        try engine.restore(name)
        let restored = try engine.cards()
        try engine.setBothWays(true, of: [2])
        let backup = try engine.backUpNow(.defaults)
        try engine.setBothWays(false, of: [2])
        time.advance(by: minutes(1))
        try engine.restore(backup.name)

        #expect(restored.map(\.front) == ["serendipia", "ubuntu"])
        #expect(restored.map(\.bothWays) == [false, false])
        #expect(try engine.cards().map(\.bothWays) == [false, true])
    }

    @Test(
        "a copy from before each answer's way restores with every entry front first, and a backup since keeps each answer's way"
    )
    func copyFromBeforeWaysRestoresWithEveryEntryFrontFirst() throws {
        let engine = try openEngine()
        let backups = try #require(engine.backupsFolder)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let name = "Backup 2026-01-02T120000Z.sqlite"
        try saveDatabaseBeforeWays(at: backups.appending(path: name), at: time.now - days(1))

        try engine.restore(name)
        let restored = try engine.reviewLog()
        let serendipia = try #require(try engine.cards().first)
        try engine.meet(serendipia, way: .backFirst)
        let backup = try engine.backUpNow(.defaults)
        try engine.takeBackAnswer(of: serendipia.id, way: .backFirst)
        time.advance(by: minutes(1))
        try engine.restore(backup.name)

        #expect(restored.map(\.way) == [.frontFirst, .frontFirst])
        #expect(try engine.reviewLog().map(\.way) == [.frontFirst, .frontFirst, .backFirst])
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

    @Test("seven backups of cards with the same images store each image once")
    func sevenBackupsStoreEachImageOnce() throws {
        let engine = try openEngine()
        let (bird, nest) = try twoImages(in: engine)
        try engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird, backImage: nest))
        try engine.create(card(nil, front: "¿De quién es este nido?", back: "Del hornero.", frontImage: nest))

        for _ in 0..<7 {
            try engine.backUpNow(.defaults)
            time.advance(by: days(1))
        }

        #expect(try engine.copies().count == 7)
        #expect(try engine.sharedImagesSize() == size(of: [bird, nest], in: engine))
    }

    @Test("deleting a card and then restoring a backup that had it brings the card back with its images")
    func restoringBringsBackADeletedCardsImages() throws {
        let engine = try openEngine()
        let (bird, nest) = try twoImages(in: engine)
        let hornero = try engine.create(
            card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird, backImage: nest))
        let images = (try engine.image(bird), try engine.image(nest))
        let backup = try engine.backUpNow(.defaults)
        try engine.delete([hornero.id])
        #expect(throws: EngineError.imagesFolder) { try engine.image(bird) }

        time.advance(by: hours(1))
        try engine.restore(backup.name)

        #expect(try engine.cards() == [hornero])
        #expect(try engine.image(bird) == images.0)
        #expect(try engine.image(nest) == images.1)
    }

    @Test("deleting old backups drops the images no remaining copy uses, and keeps the rest")
    func deletingOldBackupsDropsTheirImages() throws {
        let engine = try openEngine()
        let keepingTwo = try #require(BackupSettings(frequency: .daily, kept: 2))
        let (bird, nest) = try twoImages(in: engine)
        let hornero = try engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        let nido = try engine.create(
            card(nil, front: "¿De quién es este nido?", back: "Del hornero.", frontImage: nest))
        let (bothSizes, nestSize) = (try size(of: [bird, nest], in: engine), try size(of: [nest], in: engine))
        try engine.backUpNow(keepingTwo)
        try engine.delete([hornero.id])
        time.advance(by: days(1))
        try engine.backUpNow(keepingTwo)
        let beforePruning = try engine.sharedImagesSize()

        time.advance(by: days(1))
        let newest = try engine.backUpNow(keepingTwo)

        #expect(beforePruning == bothSizes)
        #expect(try engine.sharedImagesSize() == nestSize)
        try engine.delete([nido.id])
        try engine.restore(newest.name)
        #expect(try engine.cards() == [nido])
        #expect(try Int64(engine.image(nest).count) == nestSize)
    }

    @Test(
        "a backup from before images restores as before, letting go of the images, and undoing the restore brings them back"
    )
    func backupFromBeforeImagesRestoresAsBefore() throws {
        let engine = try openEngine()
        let (bird, nest) = try twoImages(in: engine)
        let hornero = try engine.create(
            card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird, backImage: nest))
        let images = (try engine.image(bird), try engine.image(nest))
        let backups = try #require(engine.backupsFolder)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let name = "Backup 2026-01-02T120000Z.sqlite"
        try saveDatabaseBeforeOptionalTypes(at: backups.appending(path: name), at: time.now)

        let restoration = try engine.restore(name)

        try expectEveryCardAsItWasBeforeOptionalTypes(in: engine, at: time.now)
        #expect(try engine.cards().allSatisfy { $0.frontImage == nil && $0.backImage == nil })
        #expect(throws: EngineError.imagesFolder) { try engine.image(bird) }
        time.advance(by: minutes(1))
        try engine.restore(restoration.copyBeforeRestore.name)
        #expect(try engine.cards() == [hornero])
        #expect(try engine.image(bird) == images.0)
        #expect(try engine.image(nest) == images.1)
    }

    @Test("a copy before an import keeps the images too, so restoring it brings a card deleted since back whole")
    func copyBeforeAnImportKeepsTheImages() async throws {
        let engine = try openEngine()
        let (bird, _) = try twoImages(in: engine)
        let hornero = try engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        let image = try engine.image(bird)
        let file = folder.appending(path: "pájaros.txt")
        try Data("benteveo\tUn pájaro que dice su nombre.\n".utf8).write(to: file)
        let outcome = try await engine.importCards(engine.previewImport(of: file), choosing: ImportChoices())
        let copy = try #require(outcome.copyBeforeImport)
        try engine.delete([hornero.id])

        time.advance(by: minutes(1))
        try engine.restore(copy.name)

        #expect(try engine.cards() == [hornero])
        #expect(try engine.image(bird) == image)
    }

    @Test("seven backups of cards with the same sounds store each sound once")
    func sevenBackupsStoreEachSoundOnce() async throws {
        let engine = try openEngine()
        let (la, mi) = try await twoSounds(in: engine)
        try engine.create(card(nil, front: "¿Qué nota es?", back: "La.", frontSound: la, backSound: mi))
        try engine.create(card(nil, front: "¿Y esta?", back: "Mi.", frontSound: mi))

        for _ in 0..<7 {
            try engine.backUpNow(.defaults)
            time.advance(by: days(1))
        }

        #expect(try engine.copies().count == 7)
        #expect(try engine.sharedSoundsSize() == size(of: [la, mi], in: engine))
    }

    @Test("deleting a card and then restoring a backup that had it brings the card back with its sounds")
    func restoringBringsBackADeletedCardsSounds() async throws {
        let engine = try openEngine()
        let (la, mi) = try await twoSounds(in: engine)
        let nota = try engine.create(card(nil, front: "¿Qué nota es?", back: "La.", frontSound: la, backSound: mi))
        let sounds = (try engine.sound(la), try engine.sound(mi))
        let backup = try engine.backUpNow(.defaults)
        try engine.delete([nota.id])
        #expect(throws: EngineError.soundsFolder) { try engine.sound(la) }

        time.advance(by: hours(1))
        try engine.restore(backup.name)

        #expect(try engine.cards() == [nota])
        #expect(try engine.sound(la) == sounds.0)
        #expect(try engine.sound(mi) == sounds.1)
    }

    @Test("deleting old backups drops the sounds no remaining copy uses, and keeps the rest")
    func deletingOldBackupsDropsTheirSounds() async throws {
        let engine = try openEngine()
        let keepingTwo = try #require(BackupSettings(frequency: .daily, kept: 2))
        let (la, mi) = try await twoSounds(in: engine)
        let laCard = try engine.create(card(nil, front: "¿Qué nota es?", back: "La.", frontSound: la))
        let miCard = try engine.create(card(nil, front: "¿Y esta?", back: "Mi.", backSound: mi))
        let (bothSizes, miSize) = (try size(of: [la, mi], in: engine), try size(of: [mi], in: engine))
        try engine.backUpNow(keepingTwo)
        try engine.delete([laCard.id])
        time.advance(by: days(1))
        try engine.backUpNow(keepingTwo)
        let beforePruning = try engine.sharedSoundsSize()

        time.advance(by: days(1))
        let newest = try engine.backUpNow(keepingTwo)

        #expect(beforePruning == bothSizes)
        #expect(try engine.sharedSoundsSize() == miSize)
        try engine.delete([miCard.id])
        try engine.restore(newest.name)
        #expect(try engine.cards() == [miCard])
        #expect(try Int64(engine.sound(mi).count) == miSize)
    }

    @Test("a restore lets go of the sounds only the cards it replaced used, and undoing it brings them back")
    func undoingARestoreBringsBackItsSounds() async throws {
        let engine = try openEngine()
        let ubuntu = try engine.create(card(.word, front: "ubuntu", back: "Soy porque somos."))
        let beforeSounds = try engine.backUpNow(.defaults)
        let la = try await addTone(440, to: engine)
        let nota = try engine.create(card(nil, front: "¿Qué nota es?", back: "La.", frontSound: la))
        let sound = try engine.sound(la)

        time.advance(by: hours(1))
        let restoration = try engine.restore(beforeSounds.name)
        let restored = try engine.cards()
        #expect(throws: EngineError.soundsFolder) { try engine.sound(la) }
        time.advance(by: minutes(1))
        try engine.restore(restoration.copyBeforeRestore.name)

        #expect(restored == [ubuntu])
        #expect(try engine.cards() == [ubuntu, nota])
        #expect(try engine.sound(la) == sound)
    }

    @Test("a copy before an import keeps the sounds too, so restoring it brings a card deleted since back whole")
    func copyBeforeAnImportKeepsTheSounds() async throws {
        let engine = try openEngine()
        let la = try await addTone(440, to: engine)
        let nota = try engine.create(card(nil, front: "¿Qué nota es?", back: "La.", frontSound: la))
        let sound = try engine.sound(la)
        let file = folder.appending(path: "notas.txt")
        try Data("do\tLa primera nota de la escala.\n".utf8).write(to: file)
        let outcome = try await engine.importCards(engine.previewImport(of: file), choosing: ImportChoices())
        let copy = try #require(outcome.copyBeforeImport)
        try engine.delete([nota.id])

        time.advance(by: minutes(1))
        try engine.restore(copy.name)

        #expect(try engine.cards() == [nota])
        #expect(try engine.sound(la) == sound)
    }

    @Test("a copy saved in write-ahead logging, with no log beside it, restores, and stays as it was")
    func copyInWriteAheadLoggingRestores() throws {
        let engine = try openEngine()
        let (bird, _) = try twoImages(in: engine)
        let hornero = try engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        let image = try engine.image(bird)
        let copy = try saveCopyInWriteAheadLogging(of: engine)
        let file = URL(filePath: try path(of: copy, in: engine))
        let saved = try Data(contentsOf: file)
        try engine.delete([hornero.id])

        time.advance(by: hours(1))
        try engine.restore(copy.name)

        #expect(try engine.cards() == [hornero])
        #expect(try engine.image(bird) == image)
        #expect(try Data(contentsOf: file) == saved)
        #expect(try logFiles(of: copy, in: engine).isEmpty)
    }

    @Test("a copy from an older version, in write-ahead logging with no log beside it, is restored and migrated")
    func olderCopyInWriteAheadLoggingIsMigrated() throws {
        let engine = try openEngine()
        try approveCard("ubicuo", in: engine)
        let backups = try #require(engine.backupsFolder)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let file = backups.appending(path: "Before update 2026-10-22T033656Z.sqlite")
        try saveFirstVersionDatabase(at: file, capturing: "serendipia", at: time.now)
        try leaveInWriteAheadLogging(file.path(percentEncoded: false))

        try engine.restore(file.lastPathComponent)

        #expect(try engine.inbox().captures.map(\.text) == ["serendipia"])
        let mode = try DatabaseQueue(path: folder.appending(path: "Ficha.sqlite").path(percentEncoded: false))
            .read { db in try String.fetchOne(db, sql: "PRAGMA journal_mode") }
        #expect(mode == "wal")
    }

    @Test("a copy saved in write-ahead logging, in a folder with spaces, accents and a URI's own characters, restores")
    func copyInWriteAheadLoggingRestoresFromAnyFolder() throws {
        let unusual = folder.appending(path: "José's #1 ficha 100%?", directoryHint: .isDirectory)
        let engine = try Engine(location: .folder(unusual), time: time, calendar: calendar)
        let hornero = try engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero."))
        let copy = try saveCopyInWriteAheadLogging(of: engine)
        try engine.delete([hornero.id])

        time.advance(by: hours(1))
        try engine.restore(copy.name)

        #expect(try engine.cards() == [hornero])
    }

    @Test("deleting old backups counts the files a copy in write-ahead logging uses, and drops the rest")
    func deletingOldBackupsCountsACopyInWriteAheadLogging() throws {
        let engine = try openEngine()
        let keepingOne = try #require(BackupSettings(frequency: .daily, kept: 1))
        let (bird, nest) = try twoImages(in: engine)
        let hornero = try engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        let birdSize = try size(of: [bird], in: engine)
        let copy = try saveCopyInWriteAheadLogging(of: engine)
        let nido = try engine.create(
            card(nil, front: "¿De quién es este nido?", back: "Del hornero.", frontImage: nest))
        try engine.delete([hornero.id])
        time.advance(by: days(1))
        try engine.backUpNow(keepingOne)
        try engine.delete([nido.id])

        time.advance(by: days(1))
        let newest = try engine.backUpNow(keepingOne)

        #expect(try engine.sharedImagesSize() == birdSize)
        #expect(try engine.copies().map(\.name) == [newest.name, copy.name])
        #expect(try logFiles(of: copy, in: engine).isEmpty)
    }

    @Test("deleting old backups counts the files only a copy's write-ahead log, beside it, refers to")
    func deletingOldBackupsCountsWhatACopysLogHolds() throws {
        let engine = try openEngine()
        let keepingOne = try #require(BackupSettings(frequency: .daily, kept: 1))
        let (bird, nest) = try twoImages(in: engine)
        let hornero = try engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        let nestSize = try size(of: [nest], in: engine)
        try saveCopyWhoseLogHolds(frontImage: nest, of: engine)
        try engine.delete([hornero.id])

        time.advance(by: days(1))
        try engine.backUpNow(keepingOne)
        time.advance(by: days(1))
        try engine.backUpNow(keepingOne)

        // The copy's file alone refers to the bird, and its log puts the nest
        // in the bird's place, as a restore would bring its cards back.
        #expect(try engine.sharedImagesSize() == nestSize)
    }

    @Test("a copy whose write-ahead log holds part of it restores with what the log holds, and stays as it was")
    func copyWhoseLogHoldsPartOfItRestores() throws {
        let engine = try openEngine()
        let (bird, nest) = try twoImages(in: engine)
        try engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        let image = try engine.image(nest)
        let copy = try saveCopyWhoseLogHolds(frontImage: nest, of: engine)
        let file = try path(of: copy, in: engine)
        let saved = try contents(of: [file, file + "-wal"])
        try FileManager.default.removeItem(at: folder.appending(path: "Images").appending(path: nest.rawValue))

        time.advance(by: hours(1))
        try engine.restore(copy.name)

        #expect(try engine.cards().map(\.frontImage) == [nest])
        #expect(try engine.image(nest) == image)
        #expect(try contents(of: [file, file + "-wal"]) == saved)
    }

    @Test("a copy with a write-ahead log and no index beside it is read through the log, which stays as it was")
    func copyWhoseLogHasNoIndexIsReadThroughIt() throws {
        let engine = try openEngine()
        let (bird, nest) = try twoImages(in: engine)
        try engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        let copy = try saveCopyWhoseLogHolds(frontImage: nest, of: engine)
        let file = try path(of: copy, in: engine)
        try FileManager.default.removeItem(atPath: file + "-shm")
        let saved = try contents(of: [file, file + "-wal"])

        let referred = try engine.filesTheCopiesUse(in: try #require(engine.backupsFolder))

        #expect(referred.images == [nest])
        #expect(try contents(of: [file, file + "-wal"]) == saved)
    }

    @Test(
        "a copy with a write-ahead log and no index, in a folder that can't take one, can't be read, so none is dropped"
    )
    func copyWhoseLogHasNoIndexInAFolderThatCantTakeOne() throws {
        let engine = try openEngine()
        let (bird, nest) = try twoImages(in: engine)
        try engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        let copy = try saveCopyWhoseLogHolds(frontImage: nest, of: engine)
        try FileManager.default.removeItem(atPath: try path(of: copy, in: engine) + "-shm")
        let backups = try #require(engine.backupsFolder)
        let backupsPath = backups.path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: backupsPath)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: backupsPath) }

        let error = try #require(throws: UnreadableCopy.self) {
            try engine.filesTheCopiesUse(in: backups)
        }

        #expect(error.name == copy.name)
    }

    // SQLite skips a log's frames from the damage on, with no error, so a file
    // only those frames refer to goes: a restore couldn't bring it back to
    // any card either.
    @Test(
        "a copy whose write-ahead log is damaged uses what SQLite still reads of it, which is what a restore brings back"
    )
    func copyWhoseLogIsDamaged() throws {
        let engine = try openEngine()
        let (bird, nest) = try twoImages(in: engine)
        try engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        let copy = try saveCopyWhoseLogHolds(frontImage: nest, of: engine)
        let file = try path(of: copy, in: engine)
        try FileManager.default.removeItem(atPath: file + "-shm")
        var log = try Data(contentsOf: URL(filePath: file + "-wal"))
        // The first frame's page, after the log's header and the frame's.
        log[32 + 24 + 8] ^= 0xFF
        try log.write(to: URL(filePath: file + "-wal"))

        let referred = try engine.filesTheCopiesUse(in: try #require(engine.backupsFolder))

        #expect(referred.images == [bird])
        time.advance(by: hours(1))
        try engine.restore(copy.name)
        #expect(try engine.cards().map(\.frontImage) == [bird])
    }

    @Test(
        "a copy with a rollback journal beside it, which would undo part of it, can't be read: none is dropped, and it doesn't restore"
    )
    func copyWithARollbackJournalBesideItCantBeRead() throws {
        let engine = try openEngine()
        let hornero = try engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero."))
        let copy = try saveCopyWithItsRollbackJournal(of: engine)

        let error = try #require(throws: UnreadableCopy.self) {
            try engine.filesTheCopiesUse(in: try #require(engine.backupsFolder))
        }

        #expect(error.name == copy.name)
        #expect(throws: EngineError.storage) {
            try engine.restore(copy.name)
        }
        #expect(try engine.cards() == [hornero])
    }

    @Test(
        "a copy moved to the Trash with its write-ahead log beside it no longer counts, and the other copies keep theirs"
    )
    func copyWithALogMovedToTheTrash() throws {
        let engine = try openEngine()
        let (bird, nest) = try twoImages(in: engine)
        try engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        let birdSize = try size(of: [bird], in: engine)
        let withLog = try saveCopyWhoseLogHolds(frontImage: nest, of: engine)
        time.advance(by: days(1))
        try engine.backUpNow(.defaults)

        let trashed = try engine.moveToTrash([withLog])
        // The test's copies don't stay in Lucas's Trash.
        defer {
            for file in trashed {
                try? FileManager.default.removeItem(at: file)
            }
        }

        #expect(try engine.sharedImagesSize() == birdSize)
    }

    @Test("a copy that can't be read keeps every file the copies share as old backups go, and every copy but those")
    func unreadableCopyKeepsEverySharedFileWhenBackupsGo() async throws {
        let engine = try openEngine()
        let keepingOne = try #require(BackupSettings(frequency: .daily, kept: 1))
        let (bird, nest) = try twoImages(in: engine)
        let la = try await addTone(440, to: engine)
        let hornero = try engine.create(
            card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird, backImage: nest, frontSound: la))
        let (imagesSize, soundSize) = (try size(of: [bird, nest], in: engine), try size(of: [la], in: engine))
        try engine.backUpNow(keepingOne)
        let damaged = try saveDamagedCopy(of: engine)
        try engine.delete([hornero.id])

        time.advance(by: days(1))
        let newest = try engine.backUpNow(keepingOne)

        #expect(try engine.sharedImagesSize() == imagesSize)
        #expect(try engine.sharedSoundsSize() == soundSize)
        #expect(try engine.copies().map(\.name) == [newest.name, damaged])
    }

    @Test("a copy that can't be read keeps every file the copies share as copies move to the Trash, and the rest stay")
    func unreadableCopyKeepsEverySharedFileWhenCopiesMoveToTheTrash() throws {
        let engine = try openEngine()
        let (bird, _) = try twoImages(in: engine)
        let hornero = try engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        let birdSize = try size(of: [bird], in: engine)
        let old = try engine.backUpNow(.defaults)
        try engine.delete([hornero.id])
        time.advance(by: days(1))
        let newest = try engine.backUpNow(.defaults)
        let damaged = try saveDamagedCopy(of: engine)

        let trashed = try engine.moveToTrash([old])
        // The test's copies don't stay in Lucas's Trash.
        defer {
            for file in trashed {
                try? FileManager.default.removeItem(at: file)
            }
        }

        #expect(try engine.sharedImagesSize() == birdSize)
        #expect(try engine.copies().map(\.name) == [newest.name, damaged])
    }

    @Test("what the log says about a copy that can't be read names the copy and SQLite's reason")
    func unreadableCopyIsNamedWithItsReason() throws {
        let engine = try openEngine()
        try engine.backUpNow(.defaults)
        let damaged = try saveDamagedCopy(of: engine)

        let error = try #require(throws: UnreadableCopy.self) {
            try engine.filesTheCopiesUse(in: try #require(engine.backupsFolder))
        }

        #expect(error.name == damaged)
        #expect(error.description.contains(damaged))
        #expect(error.description.contains("file is not a database"))
    }

    @Test("what the log says about a copy with a file name Ficha refuses holds no card's content")
    func unreadableCopyHoldsNoCardsContent() throws {
        let engine = try openEngine()
        try engine.create(card(nil, front: "secreto del frente", back: "secreto del dorso"))
        let copy = try engine.backUpNow(.defaults)
        let refused = "foto de la abuela.jpg"
        let queue = try DatabaseQueue(path: try path(of: copy, in: engine))
        try queue.write { db in
            try db.execute(sql: "UPDATE card SET frontImage = ?", arguments: [refused])
        }
        try queue.close()

        let error = try #require(throws: UnreadableCopy.self) {
            try engine.filesTheCopiesUse(in: try #require(engine.backupsFolder))
        }

        #expect(error.name == copy.name)
        #expect(error.description.contains("A card refers to a file"))
        #expect(!error.description.contains(refused))
        #expect(!error.description.contains("secreto"))
    }

    /// Saves a copy before an update of `engine`'s database as versions of
    /// Ficha before backups saved theirs: its file on its own, still in
    /// write-ahead logging, with no log beside it.
    private func saveCopyInWriteAheadLogging(of engine: Engine) throws -> DatabaseCopy {
        let copy = try #require(try engine.saveCopy(.beforeUpdate))
        try leaveInWriteAheadLogging(try path(of: copy, in: engine))
        return copy
    }

    /// Leaves the database in the file at `file` in write-ahead logging, with
    /// no log beside it.
    private func leaveInWriteAheadLogging(_ file: String) throws {
        let queue = try DatabaseQueue(path: file)
        try queue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        try queue.close()
        for log in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: file + log)
        }
        // Where SQLite reads the journal mode from: the file's header.
        #expect(try Data(contentsOf: URL(filePath: file))[18] == 2)
    }

    /// Saves a copy before an update of `engine`'s database with its
    /// write-ahead log beside it, whose one change, which the copy's file
    /// doesn't hold, gives every card the front image `image`, which the
    /// copies share from then on, and returns it.
    @discardableResult
    private func saveCopyWhoseLogHolds(frontImage image: ImageName, of engine: Engine) throws -> DatabaseCopy {
        let copy = try #require(try engine.saveCopy(.beforeUpdate))
        let file = try path(of: copy, in: engine)
        let backups = try #require(engine.backupsFolder)
        try engine.image(image).write(
            to: folderOfShared(ImageName.self, in: backups).appending(path: image.rawValue))
        let writing = folder.appending(path: "Copy being written.sqlite").path(percentEncoded: false)
        try FileManager.default.copyItem(atPath: file, toPath: writing)
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA wal_autocheckpoint = 0")
        }
        let queue = try DatabaseQueue(path: writing, configuration: configuration)
        try queue.write { db in
            try db.execute(sql: "UPDATE card SET frontImage = ?", arguments: [image.rawValue])
        }
        // Copied while the connection is open, since closing it moves the
        // log's change into the file.
        try FileManager.default.removeItem(atPath: file)
        for suffix in ["", "-wal", "-shm"] {
            try FileManager.default.copyItem(atPath: writing + suffix, toPath: file + suffix)
        }
        try queue.close()
        return copy
    }

    /// Saves a copy before an update of `engine`'s database as a write that
    /// never finished leaves it: part of a transaction in its file, and beside
    /// it the rollback journal that would undo that part. Returns it.
    private func saveCopyWithItsRollbackJournal(of engine: Engine) throws -> DatabaseCopy {
        let copy = try #require(try engine.saveCopy(.beforeUpdate))
        let file = try path(of: copy, in: engine)
        let writing = folder.appending(path: "Copy being written.sqlite").path(percentEncoded: false)
        try FileManager.default.copyItem(atPath: file, toPath: writing)
        let queue = try DatabaseQueue(path: writing)
        try queue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA journal_mode = DELETE")
            try db.execute(
                sql: """
                    CREATE TABLE padding AS
                    WITH RECURSIVE row(number) AS (SELECT 1 UNION ALL SELECT number + 1 FROM row WHERE number < 500)
                    SELECT zeroblob(1000) AS filler FROM row
                    """)
            try db.execute(sql: "PRAGMA cache_size = 5")
            try db.execute(sql: "PRAGMA cache_spill = 5")
            try db.inTransaction {
                // More pages than the cache holds, so they spill into the file,
                // which still opens and reads with no error: the tables it
                // lists stay, and only their rows are halfway.
                try db.execute(sql: "UPDATE padding SET filler = zeroblob(1001)")
                // Copied before the write ends, which takes the journal away.
                try FileManager.default.removeItem(atPath: file)
                for suffix in ["", "-journal"] {
                    try FileManager.default.copyItem(atPath: writing + suffix, toPath: file + suffix)
                }
                return .rollback
            }
        }
        try queue.close()
        return copy
    }

    /// What the files at `paths` hold.
    private func contents(of paths: [String]) throws -> [Data] {
        try paths.map { try Data(contentsOf: URL(filePath: $0)) }
    }

    /// Saves in the Backups folder, which is there already, a file named as a
    /// copy, which isn't a database, and returns its name.
    private func saveDamagedCopy(of engine: Engine) throws -> String {
        let name = "Before update 2026-01-02T120000Z.sqlite"
        try Data(repeating: 0x2A, count: 4096).write(to: try #require(engine.backupsFolder).appending(path: name))
        return name
    }

    /// The names of the files beside `copy` that SQLite made for it.
    private func logFiles(of copy: DatabaseCopy, in engine: Engine) throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            atPath: try #require(engine.backupsFolder).path(percentEncoded: false)
        ).filter { $0.hasPrefix(copy.name + "-") }
    }

    /// Two images of different sizes, a bird and its nest, which `engine`
    /// keeps.
    private func twoImages(in engine: Engine) throws -> (bird: ImageName, nest: ImageName) {
        (
            try engine.addImage(picture(width: 800, height: 600, red: 0.8)),
            try engine.addImage(picture(width: 300, height: 200, red: 0.3))
        )
    }

    /// What `images` weigh, each once, as `engine` keeps them.
    private func size(of images: [ImageName], in engine: Engine) throws -> Int64 {
        try images.reduce(0) { $0 + Int64(try engine.image($1).count) }
    }

    /// Two sounds of different pitches, an A and an E, which `engine` keeps.
    private func twoSounds(in engine: Engine) async throws -> (la: SoundName, mi: SoundName) {
        (try await addTone(440, to: engine), try await addTone(330, to: engine))
    }

    /// What `sounds` weigh, each once, as `engine` keeps them.
    private func size(of sounds: [SoundName], in engine: Engine) throws -> Int64 {
        try sounds.reduce(0) { $0 + Int64(try engine.sound($1).count) }
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
