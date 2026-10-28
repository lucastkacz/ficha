import FichaCore
import FichaData
import Foundation
import GRDB
import Testing

/// Tests on the move of Lucas's data into the App Group's folder (ADR 0018):
/// a data folder copied into another, in a scratch folder of the test's own
/// that stands for Application Support and the group's folder.
final class DataMoveTests {
    let time = ManualTimeSource(now: Date(timeIntervalSince1970: 1_760_000_000))
    /// The test's own scratch folder, which holds both data folders.
    let scratch = URL.temporaryDirectory.appending(
        path: "FichaDataMoveTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    /// The data folder the copy is made from, as Application Support's.
    let source: URL
    /// The data folder the copy goes to, as the one in the group's folder.
    let target: URL

    init() {
        source = scratch.appending(path: "Application Support/Ficha", directoryHint: .isDirectory)
        target = scratch.appending(path: "Group/Ficha", directoryHint: .isDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: scratch)
    }

    @Test("a data folder's copy holds its cards, their review logs, images, sounds and backups, as they were")
    func theCopyHoldsEverything() async throws {
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

        try copyDataFolder(from: source, to: target)

        let copy = try Engine(location: .folder(target), time: time)
        #expect(try copy.cards() == engine.cards())
        #expect(try copy.reviewLog() == engine.reviewLog())
        #expect(try copy.inbox().captures == engine.inbox().captures)
        #expect(try copy.image(bird) == engine.image(bird))
        #expect(try copy.sound(la) == engine.sound(la))
        #expect(try copy.copies() == [backup])
        #expect(try filesAsTheyAre(in: source) == before)
    }

    // As the CLI may, in a refine session, while the app launches and copies.
    @Test("a copy made while another engine writes holds together, with the captures saved before it began")
    func aCopyWhileAnotherEngineWrites() async throws {
        let engine = try Engine(location: .folder(source), time: time)
        for word in ["serendipia", "ojalá", "sobremesa"] {
            try engine.newCapture(word)
        }
        let (started, start) = AsyncStream.makeStream(of: Void.self)
        let writing = Task.detached {
            var saved = 0
            while !Task.isCancelled {
                try engine.newCapture("palabra \(saved)")
                saved += 1
                start.yield()
            }
            return saved
        }
        for await _ in started {
            break
        }

        let copied = try copyDataFolder(from: source, to: target)
        writing.cancel()
        let savedWhileCopying = try await writing.value

        let captures = try Engine(location: .folder(target), time: time).inbox().captures.map(\.text)
        let saved = try engine.inbox().captures.map(\.text)
        #expect(captures.count > 3)
        #expect(Array(saved.prefix(captures.count)) == captures)
        #expect(copied.rows["capture"] == captures.count)
        #expect(saved.count == 3 + savedWhileCopying)
    }

    @Test(
        "a broken file leaves the copy's folder empty, and the data folder as it was",
        arguments: [BrokenFile.database, .image])
    func aBrokenFileLeavesNoCopy(_ broken: BrokenFile) throws {
        do {
            let engine = try Engine(location: .folder(source), time: time)
            let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
            try approve(card(.word, front: "hornero", back: "Un pájaro.", frontImage: bird), in: engine)
        }
        try broken.breakIt(in: source)
        let before = try filesAsTheyAre(in: source)

        #expect(throws: DataFolderCopyError.self) {
            try copyDataFolder(from: source, to: target)
        }

        let group = target.deletingLastPathComponent()
        #expect(try FileManager.default.contentsOfDirectory(atPath: group.path(percentEncoded: false)) == [])
        #expect(try filesAsTheyAre(in: source) == before)
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

    @Test("the sandboxed app reads the preferences file in at its first launch, and never again")
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

    /// The preferences file in the data folder the copy goes to, once the
    /// copy made the folder.
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

/// A file in a data folder that a test breaks before copying it.
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
            let database = folder.appending(path: "Ficha.sqlite")
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
