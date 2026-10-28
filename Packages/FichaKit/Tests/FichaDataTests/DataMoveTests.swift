import FichaCore
import Foundation
import GRDB
import Testing

@testable import FichaData

/// Tests on Lucas's data move into the App Group's folder (ADR 0018): a data
/// folder copied into another, in a scratch folder of the test's own that
/// stands for Application Support and the group's folder.
final class DataMoveTests {
    let time = ManualTimeSource(now: Date(timeIntervalSince1970: 1_760_000_000))
    /// The test's own scratch folder, which holds both data folders.
    let scratch = URL.temporaryDirectory.appending(
        path: "FichaDataMoveTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    /// The data folder the data moves from, as Application Support's.
    let source: URL
    /// The data folder it moves to, as the one in the group's folder.
    let target: URL

    init() {
        source = scratch.appending(path: "Application Support/Ficha", directoryHint: .isDirectory)
        target = scratch.appending(path: "Group/Ficha", directoryHint: .isDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: scratch)
    }

    @Test("a move waits while the old data folder holds a database and the new one holds none, until it ran")
    func aMoveWaitsUntilItRan() throws {
        #expect(DataMove(waitingFrom: source, to: target) == nil)
        let engine = try Engine(location: .folder(source), time: time)
        try engine.newCapture("serendipia")

        try #require(DataMove(waitingFrom: source, to: target)).run()

        #expect(DataMove(waitingFrom: source, to: target) == nil)
    }

    @Test("a data move brings the cards, their review logs, images, sounds and backups, as they were")
    func theMoveBringsEverything() async throws {
        let engine = try Engine(location: .folder(source), time: time)
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let la = try await addTone(440, to: engine)
        let hornero = try approve(
            card(
                .word, front: "hornero", back: "Un pájaro que hace su nido de barro.", frontImage: bird, backSound: la),
            in: engine)
        try engine.climb(hornero, to: 2, movingForward: time)
        try approveCard("serendipia", in: engine)
        try engine.newCapture("¿Por qué el cielo es azul?", source: "Una charla")
        let backup = try engine.backUpNow(.defaults)
        let before = try filesAsTheyAre(in: source)

        try #require(DataMove(waitingFrom: source, to: target)).run()

        let moved = try Engine(location: .folder(target), time: time)
        #expect(try moved.cards() == engine.cards())
        #expect(try moved.reviewLog() == engine.reviewLog())
        #expect(try moved.inbox().captures == engine.inbox().captures)
        #expect(try moved.image(bird) == engine.image(bird))
        #expect(try moved.sound(la) == engine.sound(la))
        #expect(try moved.copies() == [backup])
        #expect(try filesAsTheyAre(in: source) == before)
    }

    // As the CLI may, in a refine session, while the app launches and moves.
    @Test(
        """
        a move made while another engine writes holds together, but fails rather than miss a write, and the next \
        one brings every capture
        """)
    func aMoveWhileAnotherEngineWrites() async throws {
        let engine = try Engine(location: .folder(source), time: time)
        for word in ["serendipia", "ojalá", "sobremesa"] {
            try engine.newCapture(word)
        }
        // Each capture the writer saves, as it saves it, to a reader waiting
        // for one: one saved while none waits is dropped.
        let (saves, saved) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(0))
        let writing = Task.detached {
            defer { saved.finish() }
            var count = 0
            while !Task.isCancelled {
                try engine.newCapture("palabra \(count)")
                count += 1
                saved.yield()
            }
            return count
        }
        var nextSave = saves.makeAsyncIterator()
        await nextSave.next()

        let staged = try #require(DataMove(waitingFrom: source, to: target)).stage()
        // A capture saved once the move copied the database, before it gives
        // the new folder its name.
        await nextSave.next()
        writing.cancel()
        let savedWhileMoving = try await writing.value

        #expect(try #require(staged.moved.rows["capture"]) > 3)
        #expect(throws: DataMoveError.sourceChanged(source)) {
            try staged.finish()
        }
        #expect(try inGroupFolder() == [])
        try #require(DataMove(waitingFrom: source, to: target)).run()
        let captures = try Engine(location: .folder(target), time: time).inbox().captures.map(\.text)
        #expect(try captures == engine.inbox().captures.map(\.text))
        #expect(captures.count == 3 + savedWhileMoving)
    }

    @Test(
        "a broken file leaves the new folder's place empty, and the old data folder as it was",
        arguments: [BrokenFile.database, .image])
    func aBrokenFileMovesNothing(_ broken: BrokenFile) throws {
        do {
            let engine = try Engine(location: .folder(source), time: time)
            let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
            try approve(card(.word, front: "hornero", back: "Un pájaro.", frontImage: bird), in: engine)
        }
        try broken.breakIt(in: source)
        let before = try filesAsTheyAre(in: source)
        let move = try #require(DataMove(waitingFrom: source, to: target))

        #expect(throws: DataMoveError.self) {
            try move.run()
        }

        #expect(try inGroupFolder() == [])
        #expect(try filesAsTheyAre(in: source) == before)
    }

    @Test("a move first removes the hidden folder that a move the app was killed in left")
    func aMoveRemovesWhatAKilledOneLeft() throws {
        let engine = try Engine(location: .folder(source), time: time)
        try engine.newCapture("serendipia")
        // Killed before the move gave its hidden folder the new folder's name.
        _ = try #require(DataMove(waitingFrom: source, to: target)).stage()

        try #require(DataMove(waitingFrom: source, to: target)).run()

        #expect(try inGroupFolder() == [target.lastPathComponent])
    }

    @Test("the preferences file carries every setting the last build kept into the sandboxed app's preferences")
    func thePreferencesFileCarriesEverySetting() throws {
        let lastBuild = try preferences(named: "last-build")
        for (key, value) in everySetting {
            lastBuild.defaults.set(value, forKey: key)
        }
        let file = try preferencesFile()

        try file.write(lastBuild.domain, from: lastBuild.defaults)
        let sandboxed = try preferences(named: "sandboxed")
        let readIn = try file.readIn(to: sandboxed.defaults)

        #expect(readIn)
        for (key, value) in everySetting {
            #expect(sandboxed.defaults.object(forKey: key) as? NSObject == value as? NSObject, "\(key)")
        }
    }

    @Test("the sandboxed app reads the preferences file in at the first launch that finds it, and never again")
    func thePreferencesFileIsReadInOnce() throws {
        let lastBuild = try preferences(named: "last-build")
        lastBuild.defaults.set(5, forKey: "CardsPerAppearance")
        let file = try preferencesFile()
        try file.write(lastBuild.domain, from: lastBuild.defaults)
        let sandboxed = try preferences(named: "sandboxed")
        try file.readIn(to: sandboxed.defaults)

        sandboxed.defaults.set(2, forKey: "CardsPerAppearance")
        lastBuild.defaults.set(7, forKey: "CardsPerAppearance")
        try file.write(lastBuild.domain, from: lastBuild.defaults)
        let readInAgain = try file.readIn(to: sandboxed.defaults)

        #expect(!readInAgain)
        #expect(sandboxed.defaults.integer(forKey: "CardsPerAppearance") == 2)
    }

    // As when the sandboxed app launches before the move ran.
    @Test("a preferences file that isn't there yet is read in once it is")
    func aMissingPreferencesFileIsReadInLater() throws {
        let file = try preferencesFile()
        let sandboxed = try preferences(named: "sandboxed")
        let readInBeforeTheFile = try file.readIn(to: sandboxed.defaults)

        let lastBuild = try preferences(named: "last-build")
        lastBuild.defaults.set(5, forKey: "CardsPerAppearance")
        try file.write(lastBuild.domain, from: lastBuild.defaults)
        let readIn = try file.readIn(to: sandboxed.defaults)

        #expect(!readInBeforeTheFile)
        #expect(readIn)
        #expect(sandboxed.defaults.integer(forKey: "CardsPerAppearance") == 5)
    }

    /// What the folder that stands for the group's holds, by name, hidden
    /// items too.
    private func inGroupFolder() throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            atPath: target.deletingLastPathComponent().path(percentEncoded: false))
    }

    /// The preferences file in the data folder the data moves to, once the
    /// move made the folder.
    private func preferencesFile() throws -> PreferencesFile {
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return PreferencesFile(in: target)
    }

    /// A preferences domain of the test's own, which stands for an app's,
    /// named `name`. Its name is a path in the scratch folder, where macOS
    /// keeps its file, as `man defaults` says of a domain named by a path,
    /// so it goes with the folder, and never lands in the Mac's Preferences
    /// folder: a suite named by a path is our own.
    private func preferences(named name: String) throws -> (domain: String, defaults: UserDefaults) {
        let domain = scratch.appending(path: "Preferences/\(name)").path(percentEncoded: false)
        return (domain, try #require(UserDefaults(suiteName: domain)))
    }

    /// Every file in `folder`, by its path in it, with what it holds, or nil
    /// when it can't be read, but SQLite's shared-memory index of the
    /// write-ahead log, which a reader may write to without changing the
    /// database.
    private func filesAsTheyAre(in folder: URL) throws -> [String: Data?] {
        let files = try #require(FileManager.default.subpaths(atPath: folder.path(percentEncoded: false)))
        var contents: [String: Data?] = [:]
        for path in files where !path.hasSuffix("-shm") {
            let file = folder.appending(path: path)
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            contents[path] = .some(try? Data(contentsOf: file))
        }
        return contents
    }
}

/// A file in a data folder that a test breaks before moving it.
enum BrokenFile {
    /// The database's file, whose pages past the first, which names the
    /// tables, hold garbage.
    case database
    /// An image, which can't be read.
    case image

    /// Breaks the file in the data folder `folder`, whose engine is closed.
    func breakIt(in folder: URL) throws {
        switch self {
        case .database:
            let database = databaseFile(in: folder)
            // Every page into the database's file, out of its write-ahead log.
            try DatabaseQueue(path: database.path(percentEncoded: false)).writeWithoutTransaction { db in
                try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
            }
            let file = try FileHandle(forUpdating: database)
            let size = try file.seekToEnd()
            try file.seek(toOffset: 4096)
            try file.write(contentsOf: Data(repeating: 0xA5, count: Int(size) - 4096))
            try file.close()
        case .image:
            let images = folder.appending(path: "Images")
            let image = try #require(
                try FileManager.default.contentsOfDirectory(atPath: images.path(percentEncoded: false)).first)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0], ofItemAtPath: images.appending(path: image).path(percentEncoded: false))
        }
    }
}

/// Every setting the real Ficha keeps in its preferences, by its name there,
/// with a value Lucas could have left, of the kind the app stores. That
/// includes the three that decide a card's progress, which versions before
/// #315 kept there, and which the app moves into the database from its
/// preferences while the database holds none. A dictionary of any values
/// isn't `Sendable`, so each use makes its own.
var everySetting: [String: Any] {
    [
        "LadderMinutes": [10, 1_440, 4_320, 10_080],
        "CardsPerAppearance": 3,
        "NewCardsPerDay": 8,
        "LookAheadMinutes": 30,
        "ActiveHours": [8, 23],
        "SeparationMinutes": 90,
        "WaitAfterWakingMinutes": 5,
        "WaitAfterSuppressionMinutes": 10,
        "SuppressionsThatApply": ["camera", "fullScreen"],
        "AutoCloseMinutes": 3,
        "FocusMode": "afterIdle",
        "IdleBeforeTakingKeyboardSeconds": 45,
        "ForgottenOftenAfter": 4,
        "BackupFrequency": "weekly",
        "BackupsKept": 12,
        "ShowsDueCount": true,
        "CaptureShortcut": ["key": "k", "keyCode": 40, "modifiers": ["control", "option"]] as [String: Any],
        "StartsAtLoginIsSetUp": true,
        "SettingsTab": "backups",
        "CardsSortOrder": Data(#"[{"column":"front","ascending":true}]"#.utf8),
        "CardsColumns": Data(#"{"front":{"width":240}}"#.utf8),
    ]
}
