import FichaCore
import FichaData
import Foundation
import Testing

/// A package of each schema Anki writes: schema 11, whose cards and revlog
/// sit beside its configuration's JSON, and schema 18.
private let schemas: [AnkiPackage.Format] = [.supportOlderAnkiVersions, .current]

/// Tests on bringing Anki's reviews of a card with its progress (#409), with
/// their ratings and intervals, which FSRS goes over, and a placement where
/// Anki's due date differs from what they set. From
/// packages the tests write in a folder of their own, into an engine in
/// memory on a Mac in Buenos Aires, on 23 October 2026 at 9 in the morning.
/// The packages' collections were created on 1 October 2026 at 4 in the
/// morning there, so Anki's day 30 is 31 October, from 4 in the morning,
/// Anki's rollover hour, to 4 in the morning the next day.
final class AnkiReviewsTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let scheduler = ReviewSettings.defaults.scheduler
    /// A folder of the test's own, for the packages it imports.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaAnkiReviewsTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 23, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Imports `package` with `choices`, by default bringing its progress.
    private func importPackage(
        _ package: AnkiPackage, choosing choices: ImportChoices = ImportChoices(progress: .brought)
    ) async throws {
        let file = folder.appending(path: "Mazo.apkg")
        try package.write(to: file)
        try await engine.importCards(engine.previewImport(of: file), choosing: choices)
    }

    /// The card with `front`.
    private func card(_ front: String) throws -> Card {
        try #require(try engine.cards().first { $0.front == front })
    }

    /// The stage and due time of the card with `front`, the way it's said to
    /// go, front first unless it's said to go back first, with `scheduler`,
    /// the default settings unless it's said, or nil while it's new.
    private func standing(of front: String, way: Way = .frontFirst, with scheduler: Scheduler? = nil) throws
        -> StageAndDue?
    {
        try engine.standing(of: card(front).id, way: way, with: scheduler ?? self.scheduler).stageAndDue
    }

    /// The review log of the card with `front`, the way it's said to go,
    /// front first unless it's said to go back first, as a test compares it.
    private func log(of front: String, way: Way = .frontFirst) throws -> [ReviewLogEntry] {
        let card = try card(front)
        return try engine.reviewLog().filter { $0.cardID == card.id && $0.way == way }.map(\.withoutIDs)
    }

    /// `hour` o'clock on `day` October 2026, in Buenos Aires.
    private func october(_ day: Int, at hour: Int, minute: Int = 0) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)))
    }

    /// The review an import brings of the card with the id `cardID`, the way
    /// it's said to go, front first unless it's said to go back first, rated
    /// `rating` at `answeredAt`, keeping `interval`, as Anki's 6 seconds to
    /// answer: with no trigger, since no appearance brought it.
    private func imported(
        _ rating: Rating, of cardID: Int64, way: Way = .frontFirst, at answeredAt: Date, keeping interval: Duration
    ) -> ReviewLogEntry {
        ReviewLogEntry(
            cardID: cardID, way: way, kind: .review(rating), answeredAt: answeredAt, responseTime: .seconds(6),
            trigger: nil, interval: interval)
    }

    @Test(
        "a card's reviews come in with Anki's ratings and intervals, due when Anki had it due, whatever the user's settings",
        arguments: schemas)
    func reviewsComeInWithTheirRatingsAndIntervals(format: AnkiPackage.Format) async throws {
        let revlog = [
            AnkiRevlogEntry(at: try october(2, at: 10), button: 3, interval: -600, kind: .learning),
            AnkiRevlogEntry(at: try october(2, at: 10, minute: 10), button: 3, interval: 1, kind: .learning),
            AnkiRevlogEntry(at: try october(3, at: 10, minute: 15), button: 2, interval: 2, kind: .review),
            AnkiRevlogEntry(at: try october(5, at: 10, minute: 20), button: 1, interval: -600, kind: .review),
            AnkiRevlogEntry(at: try october(5, at: 10, minute: 30), button: 3, interval: 1, kind: .relearning),
            AnkiRevlogEntry(at: try october(6, at: 10, minute: 40), button: 4, interval: 25, kind: .review),
        ]
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basic, fields: ["corazón", "heart"], progress: .review(due: 30, interval: 25),
                    revlog: revlog)
            ])
        let otherSettings = try #require(
            Scheduler(
                learningSteps: [.seconds(minutes(10))], relearningSteps: [], desiredRetention: 0.8,
                longestIntervalInDays: 365,
                parameters: []))

        try await importPackage(package)

        let heart = try card("corazón").id
        #expect(
            try log(of: "corazón") == [
                imported(.good, of: heart, at: try october(2, at: 10), keeping: .seconds(minutes(10))),
                imported(.good, of: heart, at: try october(2, at: 10, minute: 10), keeping: .seconds(days(1))),
                imported(.hard, of: heart, at: try october(3, at: 10, minute: 15), keeping: .seconds(days(2))),
                imported(.again, of: heart, at: try october(5, at: 10, minute: 20), keeping: .seconds(minutes(10))),
                imported(.good, of: heart, at: try october(5, at: 10, minute: 30), keeping: .seconds(days(1))),
                imported(.easy, of: heart, at: try october(6, at: 10, minute: 40), keeping: .seconds(days(25))),
            ])
        #expect(try standing(of: "corazón") == graduated(due: try october(31, at: 10, minute: 40)))
        #expect(try standing(of: "corazón", with: otherSettings) == graduated(due: try october(31, at: 10, minute: 40)))
    }

    // Set Due Date with "20!" sets the interval too. FSRS's rescheduling and
    // a reset write an entry with no button as well; cramming in a filtered
    // deck with rescheduling off writes one with an ease of 0.
    @Test(
        "Anki's manual entries, resets and cramming stay out, and the due date and interval Set Due Date gave are kept",
        arguments: schemas)
    func manualEntriesStayOut(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basic, fields: ["riñón", "kidney"], progress: .review(due: 25, interval: 20),
                    revlog: [
                        AnkiRevlogEntry(at: try october(2, at: 10), button: 3, interval: -600, kind: .learning),
                        AnkiRevlogEntry(
                            at: try october(2, at: 10, minute: 10), button: 3, interval: 1, kind: .learning),
                        AnkiRevlogEntry(
                            at: try october(3, at: 9), button: 3, interval: -600, factor: 0, kind: .filtered),
                        AnkiRevlogEntry(at: try october(3, at: 11), button: 3, interval: 4, kind: .review),
                        AnkiRevlogEntry(at: try october(5, at: 12), button: 0, interval: 6, kind: .rescheduled),
                        AnkiRevlogEntry(at: try october(5, at: 12, minute: 5), button: 0, interval: 20, kind: .manual),
                    ]),
                AnkiNote(
                    type: .basic, fields: ["bazo", "spleen"], progress: .review(due: 22, interval: 12),
                    revlog: [
                        AnkiRevlogEntry(at: try october(2, at: 11), button: 3, interval: -600, kind: .learning),
                        AnkiRevlogEntry(
                            at: try october(2, at: 11, minute: 10), button: 3, interval: 1, kind: .learning),
                        AnkiRevlogEntry(at: try october(3, at: 10), button: 3, interval: 3, kind: .review),
                        AnkiRevlogEntry(at: try october(4, at: 8), button: 0, interval: 0, factor: 0, kind: .manual),
                        AnkiRevlogEntry(at: try october(10, at: 10), button: 1, interval: -60, kind: .learning),
                        AnkiRevlogEntry(
                            at: try october(10, at: 10, minute: 1), button: 3, interval: -600, kind: .learning),
                        AnkiRevlogEntry(
                            at: try october(10, at: 10, minute: 11), button: 3, interval: 1, kind: .learning),
                        AnkiRevlogEntry(
                            at: try october(11, at: 10, minute: 30), button: 3, interval: 12, kind: .review),
                    ]),
            ])

        try await importPackage(package)

        let kidney = try card("riñón").id
        let spleen = try card("bazo").id
        #expect(
            try log(of: "riñón") == [
                imported(.good, of: kidney, at: try october(2, at: 10), keeping: .seconds(minutes(10))),
                imported(.good, of: kidney, at: try october(2, at: 10, minute: 10), keeping: .seconds(days(1))),
                imported(.good, of: kidney, at: try october(3, at: 11), keeping: .seconds(days(4))),
                ReviewLogEntry(
                    placing: kidney,
                    on: Placement(interval: .seconds(days(20)), due: try october(26, at: 4), ease: 2.5), at: time.now),
            ])
        #expect(try standing(of: "riñón") == graduated(due: try october(26, at: 4)))
        #expect(
            try log(of: "bazo") == [
                imported(.again, of: spleen, at: try october(10, at: 10), keeping: .seconds(minutes(1))),
                imported(.good, of: spleen, at: try october(10, at: 10, minute: 1), keeping: .seconds(minutes(10))),
                imported(.good, of: spleen, at: try october(10, at: 10, minute: 11), keeping: .seconds(days(1))),
                imported(.good, of: spleen, at: try october(11, at: 10, minute: 30), keeping: .seconds(days(12))),
            ])
        #expect(try standing(of: "bazo") == graduated(due: try october(23, at: 10, minute: 30)))
    }

    // Anki's learning steps here are its default, 1 and 10 minutes. Its
    // scheduler before v3 put a card on a learning step due a few minutes
    // after the step's wait, which its revlog doesn't keep.
    @Test(
        "a card Anki was learning or relearning goes on with its steps, due when Anki had it due", arguments: schemas)
    func aLearningCardGoesOnWithItsSteps(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basic, fields: ["perro", "dog"],
                    progress: .learning(dueAt: Int64(try october(23, at: 9, minute: 3).timeIntervalSince1970)),
                    revlog: [
                        AnkiRevlogEntry(
                            at: try october(23, at: 8, minute: 52), button: 1, interval: -60, kind: .learning),
                        AnkiRevlogEntry(
                            at: try october(23, at: 8, minute: 53), button: 3, interval: -600, kind: .learning),
                    ]),
                AnkiNote(
                    type: .basic, fields: ["casa", "house"],
                    progress: .learning(dueAt: Int64(try october(23, at: 9, minute: 4).timeIntervalSince1970)),
                    revlog: [
                        AnkiRevlogEntry(
                            at: try october(23, at: 8, minute: 50), button: 3, interval: -600, kind: .learning)
                    ]),
                AnkiNote(
                    type: .basic, fields: ["gato", "cat"],
                    progress: .relearning(dueAt: Int64(try october(23, at: 9, minute: 5).timeIntervalSince1970)),
                    revlog: [
                        AnkiRevlogEntry(at: try october(20, at: 10), button: 3, interval: -600, kind: .learning),
                        AnkiRevlogEntry(
                            at: try october(20, at: 10, minute: 10), button: 3, interval: 1, kind: .learning),
                        AnkiRevlogEntry(at: try october(21, at: 10), button: 3, interval: 2, kind: .review),
                        AnkiRevlogEntry(
                            at: try october(23, at: 8, minute: 55), button: 1, interval: -600, kind: .review),
                    ]),
            ])

        try await importPackage(package)
        let dog = try card("perro")
        let house = try card("casa").id
        let stoodAtTheImport = try ["perro", "casa", "gato"].map { try standing(of: $0) }
        time.move(to: try october(23, at: 9, minute: 3))
        try engine.review(dog, .hard)

        #expect(
            try log(of: "casa") == [
                imported(.good, of: house, at: try october(23, at: 8, minute: 50), keeping: .seconds(minutes(10))),
                ReviewLogEntry(
                    placing: house,
                    on: Placement(interval: .seconds(minutes(10)), due: try october(23, at: 9, minute: 4)),
                    at: try october(23, at: 9)),
            ])
        #expect(
            stoodAtTheImport == [
                learning(step: 1, due: try october(23, at: 9, minute: 3)),
                learning(step: 1, due: try october(23, at: 9, minute: 4)),
                relearning(step: 0, due: try october(23, at: 9, minute: 5)),
            ])
        // Hard repeats the step it's on, Ficha's second, of 4 hours.
        #expect(try standing(of: "perro") == learning(step: 1, due: try october(23, at: 13, minute: 3)))
    }

    @Test("Anki's reviews of a reversed card come in as its back-first way's", arguments: schemas)
    func ankisReviewsOfAReversedCardComeInAsItsBackFirstWays(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basicAndReversed, fields: ["corazón", "heart"], progress: .review(due: 29, interval: 10),
                    reversedCard: (.review(due: 25, interval: 5), .asItsTypeSays),
                    revlog: [
                        AnkiRevlogEntry(at: try october(2, at: 10), button: 3, interval: -600, kind: .learning),
                        AnkiRevlogEntry(
                            at: try october(2, at: 10, minute: 10), button: 3, interval: 1, kind: .learning),
                        AnkiRevlogEntry(at: try october(20, at: 10), button: 3, interval: 10, kind: .review),
                    ],
                    reversedCardRevlog: [
                        AnkiRevlogEntry(at: try october(2, at: 12), button: 3, interval: -600, kind: .learning),
                        AnkiRevlogEntry(
                            at: try october(2, at: 12, minute: 10), button: 4, interval: 4, kind: .learning),
                        AnkiRevlogEntry(at: try october(21, at: 12), button: 3, interval: 5, kind: .review),
                    ])
            ])

        try await importPackage(package)

        let heart = try card("corazón").id
        #expect(
            try log(of: "corazón", way: .backFirst) == [
                imported(.good, of: heart, way: .backFirst, at: try october(2, at: 12), keeping: .seconds(minutes(10))),
                imported(
                    .easy, of: heart, way: .backFirst, at: try october(2, at: 12, minute: 10),
                    keeping: .seconds(days(4))),
                imported(.good, of: heart, way: .backFirst, at: try october(21, at: 12), keeping: .seconds(days(5))),
            ])
        #expect(try standing(of: "corazón", way: .backFirst) == graduated(due: try october(26, at: 12)))
        #expect(
            try log(of: "corazón").map(\.answeredAt) == [
                try october(2, at: 10), try october(2, at: 10, minute: 10), try october(20, at: 10),
            ])
        #expect(try standing(of: "corazón") == graduated(due: try october(30, at: 10)))
    }

    // fsrs-rs's `test_memory_from_sm2`, at v6.6.2, starts a card of 10 days
    // and an ease of 250%, at Anki's historical retention of 90%, with a
    // stability of 10 days and a difficulty of 6.9140563.
    @Test(
        "a card without Anki's reviews is placed with Anki's interval and due date, its memory started from its interval and ease",
        arguments: schemas)
    func aCardWithoutAnkisReviewsIsPlaced(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [AnkiNote(type: .basic, fields: ["fémur", "thighbone"], progress: .review(due: 30, interval: 10))])

        try await importPackage(package)

        let femur = try card("fémur").id
        let memory = try #require(try engine.standing(of: femur, with: scheduler).memory)
        #expect(
            try log(of: "fémur") == [
                ReviewLogEntry(
                    placing: femur,
                    on: Placement(interval: .seconds(days(10)), due: try october(31, at: 4), ease: 2.5), at: time.now)
            ])
        #expect(try standing(of: "fémur") == graduated(due: try october(31, at: 4)))
        #expect(abs(memory.stability - 10) < 1e-4)
        #expect(abs(memory.difficulty - 6.9140563) < 1e-4)
        #expect(memory.lastReview == (try october(21, at: 4)))
    }

    // Anki keeps a card's reviews without its learning steps when it was set
    // due by hand before it was ever learned, or its first reviews are
    // gone: its FSRS starts the card from the first review it holds.
    @Test(
        "Anki's reviews without the card's learning steps start from the interval and ease the first of them set, as Anki's FSRS does",
        arguments: schemas)
    func reviewsWithoutTheLearningStepsStartFromTheFirst(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basic, fields: ["pulmón", "lung"], progress: .review(due: 26, interval: 15),
                    revlog: [
                        AnkiRevlogEntry(at: try october(1, at: 9), button: 0, interval: 3, kind: .manual),
                        AnkiRevlogEntry(
                            at: try october(2, at: 10), button: 3, interval: 5, factor: 2300, kind: .review),
                        AnkiRevlogEntry(at: try october(12, at: 10), button: 3, interval: 15, kind: .review),
                    ])
            ])

        try await importPackage(package)

        let lung = try card("pulmón").id
        #expect(
            try log(of: "pulmón") == [
                ReviewLogEntry(
                    placing: lung,
                    on: Placement(interval: .seconds(days(5)), due: try october(7, at: 10), ease: 2.3),
                    at: try october(2, at: 10)),
                imported(.good, of: lung, at: try october(12, at: 10), keeping: .seconds(days(15))),
            ])
        #expect(try standing(of: "pulmón") == graduated(due: try october(27, at: 10)))
    }

    // Anki 2.0's scheduler gave a card in learning steps three buttons:
    // again, good and easy.
    @Test(
        "a learning step's second and third buttons come in as good and easy from Anki 2.0's scheduler, which a package that doesn't say is on, and as hard and good from Anki 2.1's",
        arguments: [nil, 1, 2])
    func learningButtonsComeInAsTheirSchedulerGaveThem(schedulerVersion: Int?) async throws {
        let package = AnkiPackage(
            format: .anki20,
            notes: [
                AnkiNote(
                    type: .basic, fields: ["hueso", "bone"], progress: .review(due: 14, interval: 9),
                    revlog: [
                        AnkiRevlogEntry(at: try october(2, at: 10), button: 2, interval: -600, kind: .learning),
                        AnkiRevlogEntry(
                            at: try october(2, at: 10, minute: 10), button: 3, interval: 4, kind: .learning),
                        AnkiRevlogEntry(at: try october(6, at: 10), button: 3, interval: 9, kind: .review),
                    ])
            ], schedulerVersion: schedulerVersion)

        try await importPackage(package)

        let ratings = try log(of: "hueso").compactMap { entry -> Rating? in
            guard case .review(let rating) = entry.kind else { return nil }
            return rating
        }
        #expect(ratings == (schedulerVersion == 2 ? [.hard, .good, .good] : [.good, .easy, .good]))
        #expect(try standing(of: "hueso") == graduated(due: try october(15, at: 10)))
    }

    // Anki's scheduler versions are 1 and 2, which its v3 scheduler keeps,
    // and the types of its revlog's entries 0 to 5.
    @Test(
        "a package whose scheduler version, or the type of an entry Anki logged of a card, is one Anki doesn't have can't be read",
        arguments: schemas)
    func aPackageWithAnUnknownSchedulerOrEntryTypeCantBeRead(format: AnkiPackage.Format) async throws {
        let reviewed = [
            AnkiRevlogEntry(at: try october(2, at: 10), button: 3, interval: -600, kind: .learning),
            AnkiRevlogEntry(at: try october(2, at: 10, minute: 10), button: 3, interval: 1, kind: .learning),
        ]
        let unknownVersion = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basic, fields: ["uno", "one"], progress: .review(due: 30, interval: 1), revlog: reviewed)
            ], schedulerVersion: 3)
        let unknownType = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basic, fields: ["dos", "two"], progress: .review(due: 30, interval: 1),
                    revlog: reviewed + [
                        AnkiRevlogEntry(at: try october(3, at: 10), button: 3, interval: 1, kind: .unknown)
                    ])
            ])

        for (name, package) in [("Versión.apkg", unknownVersion), ("Tipo.apkg", unknownType)] {
            let file = folder.appending(path: name)
            try package.write(to: file)
            await #expect(throws: EngineError.unreadableFile(name, .unreadableAnkiPackage)) {
                try await engine.previewImport(of: file)
            }
        }
    }

    // Anki's learning steps here are 10 minutes and a day, unfuzzed. Its
    // schedulers before v3 logged the day's step in seconds, -86,400; v3
    // logs a step that waits past the start of Anki's next day in days, 1
    // here, as it logs a graduation.
    @Test(
        "a learning step of whole days, which Ficha's steps can't last, comes in as Ficha's step, due on Anki's day, logged in seconds or in days",
        arguments: schemas, [-86_400, 1])
    func aLearningStepOfADayComesInAsFichasStep(format: AnkiPackage.Format, loggedInterval: Int) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basic, fields: ["sístole", "systole"], progress: .learningAcrossDays(due: 22),
                    revlog: [
                        AnkiRevlogEntry(at: try october(22, at: 10), button: 1, interval: -600, kind: .learning),
                        AnkiRevlogEntry(
                            at: try october(22, at: 10, minute: 10), button: 3, interval: loggedInterval,
                            kind: .learning),
                    ])
            ])

        try await importPackage(package)

        let systole = try card("sístole").id
        #expect(
            try log(of: "sístole") == [
                imported(.again, of: systole, at: try october(22, at: 10), keeping: .seconds(minutes(10))),
                imported(.good, of: systole, at: try october(22, at: 10, minute: 10), keeping: .seconds(hours(4))),
                ReviewLogEntry(
                    placing: systole, on: Placement(interval: .seconds(hours(4)), due: try october(23, at: 4)),
                    at: time.now),
            ])
        #expect(try standing(of: "sístole") == learning(step: 1, due: try october(23, at: 4)))
    }

    // Anki's learning steps here are Ficha's, an hour and 4 hours, and its
    // relearning step 4 hours. Anki's next day starts at 4 in the morning,
    // so from 1 o'clock or half past either 4 hours waits past it, which
    // Anki's v3 scheduler logs as a day.
    @Test(
        "a step that waits past the start of Anki's next day, which Anki logs as a day, comes in as Ficha's step",
        arguments: schemas)
    func aStepPastAnkisNextDayComesInAsFichasStep(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basic, fields: ["perro", "dog"], progress: .learningAcrossDays(due: 22),
                    revlog: [
                        AnkiRevlogEntry(
                            at: try october(22, at: 23, minute: 50), button: 1, interval: -3_600, kind: .learning),
                        AnkiRevlogEntry(at: try october(23, at: 1), button: 3, interval: 1, kind: .learning),
                    ]),
                AnkiNote(
                    type: .basic, fields: ["gato", "cat"], progress: .relearningAcrossDays(due: 22),
                    revlog: [
                        AnkiRevlogEntry(at: try october(20, at: 10), button: 3, interval: -600, kind: .learning),
                        AnkiRevlogEntry(
                            at: try october(20, at: 10, minute: 10), button: 3, interval: 1, kind: .learning),
                        AnkiRevlogEntry(at: try october(21, at: 10), button: 3, interval: 1, kind: .review),
                        AnkiRevlogEntry(
                            at: try october(23, at: 1, minute: 30), button: 1, interval: 1, kind: .review),
                    ]),
            ])

        try await importPackage(package)

        let dog = try card("perro").id
        let cat = try card("gato").id
        #expect(
            try log(of: "perro") == [
                imported(.again, of: dog, at: try october(22, at: 23, minute: 50), keeping: .seconds(hours(1))),
                imported(.good, of: dog, at: try october(23, at: 1), keeping: .seconds(hours(4))),
            ])
        #expect(try standing(of: "perro") == learning(step: 1, due: try october(23, at: 5)))
        // Ficha's relearning step is an hour, so the cat is placed due when
        // Anki had it due, on that step.
        #expect(
            try log(of: "gato").suffix(2) == [
                imported(.again, of: cat, at: try october(23, at: 1, minute: 30), keeping: .seconds(hours(1))),
                ReviewLogEntry(
                    placing: cat, on: Placement(interval: .seconds(hours(1)), due: try october(23, at: 4)),
                    at: time.now),
            ])
        #expect(try standing(of: "gato") == relearning(step: 0, due: try october(23, at: 4)))
    }

    // Anki's learning steps here are 1, 10 and 60 minutes, and its relearning
    // steps 10 and 60 minutes, one more than Ficha's each. The last of each
    // waits past 4 in the morning, the start of Anki's next day, so Anki's v3
    // scheduler logs it as a day, and Ficha's replay, which gives such a step
    // the interval its own steps give it, graduates the card: Ficha has no
    // step past its last.
    @Test(
        "a card Anki had on a step past Ficha's last comes in on Ficha's last learning step, or its last relearning step once it lapsed, due when Anki had it due",
        arguments: schemas)
    func aStepPastFichasLastComesInAsItsLastStep(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basic, fields: ["hígado", "liver"], progress: .learningAcrossDays(due: 22),
                    revlog: [
                        AnkiRevlogEntry(at: try october(23, at: 3), button: 1, interval: -60, kind: .learning),
                        AnkiRevlogEntry(
                            at: try october(23, at: 3, minute: 1), button: 3, interval: -600, kind: .learning),
                        AnkiRevlogEntry(
                            at: try october(23, at: 3, minute: 11), button: 3, interval: 1, kind: .learning),
                    ]),
                AnkiNote(
                    type: .basic, fields: ["páncreas", "pancreas"], progress: .relearningAcrossDays(due: 22),
                    revlog: [
                        AnkiRevlogEntry(at: try october(20, at: 10), button: 3, interval: -600, kind: .learning),
                        AnkiRevlogEntry(
                            at: try october(20, at: 10, minute: 10), button: 3, interval: 1, kind: .learning),
                        AnkiRevlogEntry(at: try october(21, at: 10), button: 3, interval: 2, kind: .review),
                        AnkiRevlogEntry(
                            at: try october(23, at: 3, minute: 2), button: 1, interval: -600, kind: .review),
                        AnkiRevlogEntry(
                            at: try october(23, at: 3, minute: 12), button: 3, interval: 1, kind: .relearning),
                    ]),
            ])

        try await importPackage(package)

        let liver = try card("hígado").id
        let pancreas = try card("páncreas").id
        let intervalColumns = try engine.cardRows(in: .all, with: scheduler).map(\.frontFirst.intervalColumn)
        #expect(
            try log(of: "hígado").last
                == ReviewLogEntry(
                    placing: liver, on: Placement(interval: .seconds(hours(4)), due: try october(23, at: 4)),
                    at: time.now))
        #expect(try standing(of: "hígado") == learning(step: 1, due: try october(23, at: 4)))
        #expect(
            try log(of: "páncreas").last
                == ReviewLogEntry(
                    placing: pancreas, on: Placement(interval: .seconds(hours(1)), due: try october(23, at: 4)),
                    at: time.now))
        #expect(try standing(of: "páncreas") == relearning(step: 0, due: try october(23, at: 4)))
        #expect(intervalColumns == [.learning(.seconds(hours(4))), .interval(.seconds(hours(1)))])
    }

    // Anki's learning steps here are 10 minutes and a day, as in Anki's v3
    // scheduler, which logs the day's step in days.
    @Test(
        "an again on a learning step of a day isn't a lapse, which Forgotten often would count",
        arguments: schemas)
    func anAgainOnAStepOfADayIsntALapse(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basic, fields: ["riñón", "kidney"], progress: .review(due: 22, interval: 3),
                    revlog: [
                        AnkiRevlogEntry(at: try october(18, at: 10), button: 3, interval: 1, kind: .learning),
                        AnkiRevlogEntry(at: try october(19, at: 10), button: 1, interval: -600, kind: .learning),
                        AnkiRevlogEntry(
                            at: try october(19, at: 10, minute: 10), button: 3, interval: 1, kind: .learning),
                        AnkiRevlogEntry(at: try october(20, at: 10), button: 3, interval: 3, kind: .learning),
                    ])
            ])

        try await importPackage(package)

        let kidney = try card("riñón").id
        #expect(
            try log(of: "riñón") == [
                imported(.good, of: kidney, at: try october(18, at: 10), keeping: .seconds(hours(4))),
                imported(.again, of: kidney, at: try october(19, at: 10), keeping: .seconds(minutes(10))),
                imported(.good, of: kidney, at: try october(19, at: 10, minute: 10), keeping: .seconds(hours(4))),
                imported(.good, of: kidney, at: try october(20, at: 10), keeping: .seconds(days(3))),
            ])
        #expect(try scheduler.lapses(after: engine.reviewLog()).isEmpty)
        #expect(try standing(of: "riñón") == graduated(due: try october(23, at: 10)))
    }

    @Test(
        "a package without progress, an import that leaves progress out, and a card Anki reset to new bring cards new",
        arguments: schemas)
    func cardsWithoutProgressComeInNew(format: AnkiPackage.Format) async throws {
        let shared = AnkiPackage(format: format, notes: [AnkiNote(type: .basic, fields: ["uno", "one"])])
        let reviewed = [
            AnkiRevlogEntry(at: try october(2, at: 10), button: 3, interval: -600, kind: .learning),
            AnkiRevlogEntry(at: try october(2, at: 10, minute: 10), button: 3, interval: 1, kind: .learning),
        ]
        let ownDeck = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basic, fields: ["dos", "two"], progress: .review(due: 30, interval: 1), revlog: reviewed)
            ])
        let reset = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basic, fields: ["tres", "three"],
                    revlog: reviewed + [
                        AnkiRevlogEntry(at: try october(3, at: 8), button: 0, interval: 0, factor: 0, kind: .manual)
                    ])
            ])

        try await importPackage(shared)
        try await importPackage(ownDeck, choosing: ImportChoices(progress: .leftOut))
        try await importPackage(reset)

        #expect(try engine.cards().map(\.front) == ["uno", "dos", "tres"])
        #expect(try engine.cards().allSatisfy { try engine.standing(of: $0.id, with: scheduler) == .new })
        #expect(try engine.reviewLog().isEmpty)
    }
}
