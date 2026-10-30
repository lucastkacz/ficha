import FichaCore
import FichaData
import Foundation
import Testing

/// A package of each schema Anki writes: schema 11, whose configuration is
/// JSON in `col.conf`, and schema 18, which keeps each key of it in a row of
/// its `config` table.
private let schemas: [AnkiPackage.Format] = [.supportOlderAnkiVersions, .current]

/// Tests on bringing an Anki deck's progress (ADR 0013): where each card
/// stands once the import is done, on the standard ladder (1 hour, 4 hours,
/// 2 days, 5 days, 12 days, 30 days and 75 days, steps counted from 0), from
/// packages the tests write in a folder of their own, into an engine in
/// memory on a Mac in Buenos Aires, on 23 October 2026. The packages'
/// collections were created on 1 October 2026 at 4 in the morning there, so
/// Anki's day 30 is 31 October, and it starts at 4 in the morning, Anki's
/// rollover hour.
final class AnkiProgressTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let ladder = Ladder.standard
    /// A folder of the test's own, for the packages it imports.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaAnkiProgressTests-\(UUID().uuidString)",
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

    /// Imports `package`, written as `name`, with `choices`, by default
    /// bringing its progress onto the standard ladder, and returns what the
    /// import did.
    @discardableResult
    private func importPackage(
        _ package: AnkiPackage, named name: String = "Mazo.apkg",
        choosing choices: ImportChoices = ImportChoices(progress: .brought(onto: .standard))
    ) async throws -> ImportOutcome {
        let file = folder.appending(path: name)
        try package.write(to: file)
        return try await engine.importCards(engine.previewImport(of: file), choosing: choices)
    }

    /// Where the card with `front` stands on the standard ladder, the way
    /// it's said to go, front first unless it's said to go back first.
    private func standing(of front: String, way: Way = .frontFirst) throws -> LadderStanding {
        let card = try #require(try engine.cards().first { $0.front == front })
        return try engine.standing(of: card.id, way: way, on: ladder)
    }

    /// `hour` o'clock on `day` October 2026, in Buenos Aires.
    private func october(_ day: Int, at hour: Int, minute: Int = 0) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)))
    }

    @Test(
        "a card Anki reviews every 10 days lands on the 12-day step of the standard ladder, due on Anki's date",
        arguments: schemas)
    func aReviewCardLandsOnTheNearestStep(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basic, fields: ["corazón", "heart"], progress: .review(due: 30, interval: 10))
            ])

        try await importPackage(package)

        #expect(try standing(of: "corazón") == .onLadder(step: 4, due: try october(31, at: 4)))
    }

    @Test("a card that came in on a step comes back first for its first view once it goes both ways")
    func aPlacedCardComesBackFirstOnceItGoesBothWays() async throws {
        let package = AnkiPackage(
            notes: [AnkiNote(type: .basic, fields: ["corazón", "heart"], progress: .review(due: 30, interval: 10))])
        try await importPackage(package)
        let corazon = try #require(try engine.cards().first)

        let bothWays = try engine.setBothWays(true, of: [corazon.id])

        #expect(try engine.reviewNow(.defaults) == [.firstView(bothWays[0], .backFirst)])
    }

    @Test(
        "each way of a reversed note lands on the step nearest its own Anki card's interval, and a new Anki card leaves its way new",
        arguments: schemas)
    func eachWayOfAReversedNoteLandsOnItsOwnStep(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basicAndReversed, fields: ["corazón", "heart"], progress: .review(due: 30, interval: 10),
                    reversedCard: (.review(due: 26, interval: 3), .asItsTypeSays)),
                AnkiNote(
                    type: .basicOptionalReversed, fields: ["pulmón", "lung", "y"],
                    progress: .review(due: 25, interval: 400), reversedCard: (.new, .asItsTypeSays)),
            ])

        try await importPackage(package)

        #expect(try standing(of: "corazón") == .onLadder(step: 4, due: try october(31, at: 4)))
        #expect(try standing(of: "corazón", way: .backFirst) == .onLadder(step: 2, due: try october(27, at: 4)))
        #expect(try standing(of: "pulmón") == .onLadder(step: 6, due: try october(26, at: 4)))
        #expect(try standing(of: "pulmón", way: .backFirst) == .new)
        #expect(try engine.cards().map(\.bothWays) == [true, true])
    }

    @Test("a card with a 400-day interval lands on the last step, due on Anki's date", arguments: schemas)
    func aLongIntervalLandsOnTheLastStep(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basic, fields: ["fémur", "thighbone"], progress: .review(due: 25, interval: 400))
            ])

        try await importPackage(package)

        #expect(try standing(of: "fémur") == .onLadder(step: 6, due: try october(26, at: 4)))
    }

    // Anki 2.0 kept a relearning card as a review card in a learning queue,
    // which Anki relabels as relearning when it imports such a package.
    @Test("a card in learning lands on the first step, due when Anki said", arguments: schemas)
    func aLearningCardLandsOnTheFirstStep(format: AnkiPackage.Format) async throws {
        let tenPast = try october(23, at: 9, minute: 10)
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basic, fields: ["perro", "dog"],
                    progress: .learning(dueAt: Int64(tenPast.timeIntervalSince1970))),
                AnkiNote(type: .basic, fields: ["gato", "cat"], progress: .relearningAcrossDays(due: 23)),
                AnkiNote(
                    type: .basic, fields: ["casa", "house"],
                    progress: .anki20Relearning(dueAt: Int64(tenPast.timeIntervalSince1970) + 600)),
            ])

        try await importPackage(package)

        #expect(try standing(of: "perro") == .onLadder(step: 0, due: tenPast))
        #expect(try standing(of: "gato") == .onLadder(step: 0, due: try october(24, at: 4)))
        #expect(try standing(of: "casa") == .onLadder(step: 0, due: tenPast + minutes(10)))
    }

    @Test("new cards stay new, in Anki's order, and come in first", arguments: schemas)
    func newCardsStayNewInAnkisOrder(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basic, fields: ["uno", "one"], progress: .review(due: 30, interval: 10)),
                AnkiNote(type: .basic, fields: ["dos", "two"], progress: .newAt(position: 5)),
                AnkiNote(type: .basic, fields: ["tres", "three"], progress: .newAt(position: 2)),
            ])

        try await importPackage(package)

        let cards = try engine.cards()
        #expect(cards.map(\.front) == ["tres", "dos", "uno"])
        #expect(
            try cards.map { try engine.standing(of: $0.id, on: ladder) } == [
                .new, .new, .onLadder(step: 4, due: try october(31, at: 4)),
            ])
        #expect(try engine.reviewNow(.defaults).map(\.card.front) == ["tres"])
    }

    // Anki buries a card for the day on its own, as when its sibling was
    // reviewed: it comes back the next day.
    @Test(
        "a suspended card comes in buried, and unburying puts it on its step; one buried for the day comes in as usual",
        arguments: schemas)
    func aSuspendedCardComesInBuried(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basic, fields: ["riñón", "kidney"], progress: .review(due: 30, interval: 10),
                    queue: .suspended),
                AnkiNote(
                    type: .basic, fields: ["hígado", "liver"], progress: .review(due: 26, interval: 5),
                    queue: .buriedForTheDay),
                AnkiNote(type: .basic, fields: ["bazo", "spleen"], queue: .suspended),
            ])

        try await importPackage(package)
        let cards = try engine.cards()
        let kidney = try #require(cards.first { $0.front == "riñón" })

        #expect(cards.map(\.front) == ["bazo", "riñón", "hígado"])
        #expect(
            cards.map(\.standing) == [.buried(at: time.now, flag: nil), .buried(at: time.now, flag: nil), .inReviews])
        #expect(try standing(of: "hígado") == .onLadder(step: 3, due: try october(27, at: 4)))
        #expect(try standing(of: "bazo") == .new)

        try engine.unbury(kidney.id)

        #expect(try engine.cards().first { $0.id == kidney.id }?.standing == .inReviews)
        #expect(try standing(of: "riñón") == .onLadder(step: 4, due: try october(31, at: 4)))
    }

    @Test(
        "a reversed note whose reversed card alone Anki suspended comes in one way, that way's step kept, and one whose first card it suspended comes in buried",
        arguments: schemas)
    func aReversedNoteWithASuspendedCard(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basicAndReversed, fields: ["riñón", "kidney"], progress: .review(due: 30, interval: 10),
                    reversedCard: (.review(due: 26, interval: 3), .suspended)),
                AnkiNote(
                    type: .basicAndReversed, fields: ["bazo", "spleen"], progress: .review(due: 30, interval: 10),
                    queue: .suspended, reversedCard: (.review(due: 26, interval: 3), .asItsTypeSays)),
            ])

        try await importPackage(package)
        let cards = try engine.cards()
        let spleen = try #require(cards.last)

        #expect(cards.map(\.front) == ["riñón", "bazo"])
        #expect(cards.map(\.bothWays) == [false, true])
        #expect(cards.map(\.standing) == [.inReviews, .buried(at: time.now, flag: nil)])
        #expect(try standing(of: "riñón", way: .backFirst) == .onLadder(step: 2, due: try october(27, at: 4)))

        try engine.unbury(spleen.id)

        #expect(try standing(of: "bazo") == .onLadder(step: 4, due: try october(31, at: 4)))
        #expect(try standing(of: "bazo", way: .backFirst) == .onLadder(step: 2, due: try october(27, at: 4)))
    }

    @Test("with Bring progress unticked, every card comes in new, and none buried", arguments: schemas)
    func withProgressLeftOutEveryCardComesInNew(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basic, fields: ["uno", "one"], progress: .review(due: 30, interval: 10)),
                AnkiNote(type: .basic, fields: ["dos", "two"], progress: .learning(dueAt: 1_792_000_000)),
                AnkiNote(
                    type: .basic, fields: ["tres", "three"], progress: .review(due: 25, interval: 3), queue: .suspended),
                AnkiNote(
                    type: .basicAndReversed, fields: ["cuatro", "four"], progress: .review(due: 25, interval: 3),
                    reversedCard: (.review(due: 25, interval: 3), .suspended)),
            ])

        try await importPackage(package, choosing: ImportChoices(progress: .leftOut))

        let cards = try engine.cards()
        #expect(cards.count == 4)
        #expect(try cards.allSatisfy { try engine.standing(of: $0.id, on: ladder) == .new })
        #expect(cards.allSatisfy { $0.standing == .inReviews })
        #expect(cards.map(\.bothWays) == [false, false, false, true])
        #expect(try engine.reviewLog().isEmpty)
    }

    @Test("a repeated card that the import updates keeps its own step and review log, not Anki's", arguments: schemas)
    func anUpdatedCardKeepsItsOwnProgress(format: AnkiPackage.Format) async throws {
        let heart = try approve(card(.word, front: "Corazón", back: "Un órgano."), in: engine)
        try engine.climb(heart, to: 2, movingForward: time)
        let standingBefore = try engine.standing(of: heart.id, on: ladder)
        let logBefore = try engine.reviewLog()
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basic, fields: ["corazón", "El órgano que bombea la sangre."],
                    progress: .review(due: 30, interval: 75))
            ])

        let outcome = try await importPackage(package)

        #expect(outcome.updated == 1)
        #expect(try engine.cards().map(\.back) == ["El órgano que bombea la sangre."])
        #expect(try engine.standing(of: heart.id, on: ladder) == standingBefore)
        #expect(try engine.reviewLog() == logBefore)
    }

    // Anki's day 30 starts at its rollover hour on the 30th date after the
    // one the collection was created on, at its creation offset: 1 October
    // in Buenos Aires, 30 September at UTC−8, where it was 11 at night.
    // Without an offset, Anki counts in the Mac's time zone.
    @Test(
        "a review card falls due on the day Anki counts from the collection's creation, at its offset, from its rollover hour",
        arguments: schemas,
        [
            DaySettings(creationOffset: 180, rollover: nil, dueOn: 31, at: 4),
            DaySettings(creationOffset: 480, rollover: nil, dueOn: 30, at: 4),
            DaySettings(creationOffset: nil, rollover: 6, dueOn: 31, at: 6),
        ])
    func aReviewCardFallsDueOnAnkisDay(format: AnkiPackage.Format, settings: DaySettings) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [AnkiNote(type: .basic, fields: ["pulmón", "lung"], progress: .review(due: 30, interval: 12))],
            creationOffset: settings.creationOffset, rollover: settings.rollover)

        try await importPackage(package)

        #expect(
            try standing(of: "pulmón") == .onLadder(step: 4, due: try october(settings.dueOn, at: settings.hour)))
    }

    @Test(
        "the Import sheet offers Bring progress for an Anki package, ticked, with how many cards come in on a step, and unticked brings them in new",
        arguments: schemas)
    func theImportSheetOffersToBringProgress(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basic, fields: ["uno", "one"], progress: .review(due: 30, interval: 10)),
                AnkiNote(type: .basic, fields: ["dos", "two"], progress: .relearningAcrossDays(due: 24)),
                AnkiNote(type: .basic, fields: ["tres", "three"]),
                AnkiNote(type: .basic, fields: ["serendipia", "luck"], progress: .review(due: 30, interval: 10)),
            ])
        try approveCard("serendipia", in: engine)
        let packageFile = folder.appending(path: "Números.apkg")
        try package.write(to: packageFile)
        let textFile = folder.appending(path: "Números.txt")
        try Data("cuatro\tfour\n".utf8).write(to: textFile)
        var window = engine.openCardsWindow(on: ladder)
        window.startImport()

        await window.previewImportAndWait(of: textFile)
        let textFileOffers = window.importing?.offersProgress
        let textFileCardsComingIn = window.importing?.cardsComingIn
        await window.previewImportAndWait(of: packageFile)
        let importing = try #require(window.importing)
        window.chooseToBringProgress(false)
        let untickedBrings = window.importing?.bringsProgress
        let untickedCardsComingIn = window.importing?.cardsComingIn
        await window.importCardsAndWait()

        #expect(textFileOffers == false)
        #expect(textFileCardsComingIn == .new(1))
        #expect(importing.offersProgress)
        #expect(importing.bringsProgress)
        // The repeated card keeps its own progress, so it isn't counted.
        #expect(importing.cardsComingIn == .newAndPlaced(new: 1, placed: 2))
        #expect(untickedBrings == false)
        #expect(untickedCardsComingIn == .new(3))
        #expect(try engine.cards().dropFirst().map(\.front) == ["tres", "uno", "dos"])
        #expect(try engine.cards().allSatisfy { try engine.standing(of: $0.id, on: ladder) == .new })
    }

    @Test(
        "the Import sheet counts the reversed notes that come in as one card that goes both ways, but one that repeats a card of the user's, and one whose reversed card alone Anki suspended while Bring progress is ticked",
        arguments: schemas)
    func theImportSheetCountsReversedNotes(format: AnkiPackage.Format) async throws {
        try approveCard("gato", in: engine)
        let file = folder.appending(path: "Mazo.apkg")
        try AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basicAndReversed, fields: ["perro", "dog"]),
                AnkiNote(type: .basicOptionalReversed, fields: ["gato", "cat", "y"]),
                AnkiNote(type: .basicOptionalReversed, fields: ["casa", "house", ""]),
                AnkiNote(
                    type: .basicAndReversed, fields: ["riñón", "kidney"], progress: .review(due: 30, interval: 10),
                    reversedCard: (.review(due: 26, interval: 3), .suspended)),
                AnkiNote(type: .basic, fields: ["uno", "one"]),
            ]
        ).write(to: file)
        var window = engine.openCardsWindow(on: ladder)
        window.startImport()
        await window.previewImportAndWait(of: file)

        let ticked = window.importing?.notesComingInBothWays
        window.chooseToBringProgress(false)

        #expect(ticked == 1)
        #expect(window.importing?.notesComingInBothWays == 2)
    }

    @Test(
        "with Bring progress ticked, the Import sheet brings each card in on its step, on the user's ladder",
        arguments: schemas)
    func theImportSheetBringsProgressOntoTheUsersLadder(format: AnkiPackage.Format) async throws {
        // A ladder of three steps, whose last one, 10 days, is the nearest
        // to Anki's 30-day interval.
        let threeSteps = try #require(Ladder(waits: [.seconds(3_600), .seconds(86_400), .seconds(10 * 86_400)]))
        let file = folder.appending(path: "Mazo.apkg")
        try AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basic, fields: ["uno", "one"], progress: .review(due: 30, interval: 30))
            ]
        ).write(to: file)
        var window = engine.openCardsWindow(on: threeSteps)
        window.startImport()
        await window.previewImportAndWait(of: file)

        await window.importCardsAndWait()

        let uno = try #require(try engine.cards().first)
        #expect(try engine.standing(of: uno.id, on: threeSteps) == .onLadder(step: 2, due: try october(31, at: 4)))
    }

    @Test(
        "a card that came in on a step shows it in its review log, unseen until its first review, which climbs from there",
        arguments: schemas)
    func aPlacedCardShowsItsStepInItsReviewLog(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basic, fields: ["corazón", "heart"], progress: .review(due: 30, interval: 10))
            ])
        try await importPackage(package)
        let heart = try #require(try engine.cards().first)
        let importedAt = time.now

        let rowsBefore = try engine.reviewLogRows(of: heart.id, on: ladder)
        let lastSeenBefore = try engine.cardRows(in: .all, on: ladder).first?.lastSeen
        time.advance(by: days(9))
        try engine.record(
            .review(.good), of: heart.id, responseTime: .seconds(3), trigger: .reviewNow,
            settings: .defaults)

        #expect(rowsBefore.map(\.entry.kind) == [.placement(Placement(step: 4, due: try october(31, at: 4)))])
        #expect(rowsBefore.map(\.entry.answeredAt) == [importedAt])
        #expect(rowsBefore.map(\.step) == [4])
        #expect(lastSeenBefore == .some(nil))
        #expect(try engine.reviewLogRows(of: heart.id, on: ladder).map(\.step) == [4, 5])
        #expect(try engine.cardRows(in: .all, on: ladder).first?.lastSeen == time.now)
    }

    // A filtered deck keeps the card's due in its home deck aside, and
    // gives it one of its own, as when the user crams a deck.
    @Test(
        "a card in a filtered deck comes in where it stands in its home deck, into its home deck",
        arguments: schemas)
    func aCardInAFilteredDeckComesInAsInItsHomeDeck(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basic, fields: ["sístole", "systole"], deck: "Medicina",
                    progress: .review(due: 30, interval: 10),
                    filteredDeck: "Repaso para el examen")
            ])

        try await importPackage(package)

        #expect(try standing(of: "sístole") == .onLadder(step: 4, due: try october(31, at: 4)))
        #expect(try engine.cards().map(\.deck) == ["Medicina"])
    }
}

/// How a test's collection counts its days, and when its day 30 starts: on
/// `dueOn` October 2026 at `hour` o'clock, in Buenos Aires.
struct DaySettings: Sendable, CustomTestStringConvertible {
    let creationOffset: Int?
    let rollover: Int?
    let dueOn: Int
    let hour: Int

    init(creationOffset: Int?, rollover: Int?, dueOn: Int, at hour: Int) {
        self.creationOffset = creationOffset
        self.rollover = rollover
        self.dueOn = dueOn
        self.hour = hour
    }

    var testDescription: String {
        "creationOffset \(creationOffset.map(String.init) ?? "missing"), rollover \(rollover.map(String.init) ?? "missing")"
    }
}
