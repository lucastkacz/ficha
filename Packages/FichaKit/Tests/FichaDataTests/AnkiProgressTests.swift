import FichaCore
import FichaData
import Foundation
import Testing

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
    ) throws -> ImportOutcome {
        let file = folder.appending(path: name)
        try package.write(to: file)
        return try engine.importCards(engine.previewImport(of: file), choosing: choices)
    }

    /// Where the card with `front` stands on the standard ladder.
    private func standing(of front: String) throws -> LadderStanding {
        let card = try #require(try engine.cards().first { $0.front == front })
        return try engine.standing(of: card.id, on: ladder)
    }

    /// `hour` o'clock on `day` October 2026, in Buenos Aires.
    private func october(_ day: Int, at hour: Int, minute: Int = 0) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)))
    }

    @Test("a card Anki reviews every 10 days lands on the 12-day step of the standard ladder, due on Anki's date")
    func aReviewCardLandsOnTheNearestStep() throws {
        let package = AnkiPackage(notes: [
            AnkiNote(type: .basic, fields: ["corazón", "heart"], progress: .review(due: 30, interval: 10))
        ])

        try importPackage(package)

        #expect(try standing(of: "corazón") == .onLadder(step: 4, due: try october(31, at: 4)))
    }

    @Test("a card with a 400-day interval lands on the last step, due on Anki's date")
    func aLongIntervalLandsOnTheLastStep() throws {
        let package = AnkiPackage(notes: [
            AnkiNote(type: .basic, fields: ["fémur", "thighbone"], progress: .review(due: 25, interval: 400))
        ])

        try importPackage(package)

        #expect(try standing(of: "fémur") == .onLadder(step: 6, due: try october(26, at: 4)))
    }

    // Anki 2.0 kept a relearning card as a review card in a learning queue,
    // which Anki relabels as relearning when it imports such a package.
    @Test("a card in learning lands on the first step, due when Anki said")
    func aLearningCardLandsOnTheFirstStep() throws {
        let tenPast = try october(23, at: 9, minute: 10)
        let package = AnkiPackage(notes: [
            AnkiNote(
                type: .basic, fields: ["perro", "dog"],
                progress: .learning(dueAt: Int64(tenPast.timeIntervalSince1970))),
            AnkiNote(type: .basic, fields: ["gato", "cat"], progress: .relearningAcrossDays(due: 23)),
            AnkiNote(
                type: .basic, fields: ["casa", "house"],
                progress: .anki20Relearning(dueAt: Int64(tenPast.timeIntervalSince1970) + 600)),
        ])

        try importPackage(package)

        #expect(try standing(of: "perro") == .onLadder(step: 0, due: tenPast))
        #expect(try standing(of: "gato") == .onLadder(step: 0, due: try october(24, at: 4)))
        #expect(try standing(of: "casa") == .onLadder(step: 0, due: tenPast + minutes(10)))
    }

    @Test("new cards stay new, in Anki's order, and come in first")
    func newCardsStayNewInAnkisOrder() throws {
        let package = AnkiPackage(notes: [
            AnkiNote(type: .basic, fields: ["uno", "one"], progress: .review(due: 30, interval: 10)),
            AnkiNote(type: .basic, fields: ["dos", "two"], progress: .newAt(position: 5)),
            AnkiNote(type: .basic, fields: ["tres", "three"], progress: .newAt(position: 2)),
        ])

        try importPackage(package)

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
        "a suspended card comes in buried, and unburying puts it on its step; one buried for the day comes in as usual")
    func aSuspendedCardComesInBuried() throws {
        let package = AnkiPackage(notes: [
            AnkiNote(
                type: .basic, fields: ["riñón", "kidney"], progress: .review(due: 30, interval: 10),
                queue: .suspended),
            AnkiNote(
                type: .basic, fields: ["hígado", "liver"], progress: .review(due: 26, interval: 5),
                queue: .buriedForTheDay),
            AnkiNote(type: .basic, fields: ["bazo", "spleen"], queue: .suspended),
        ])

        try importPackage(package)
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

    @Test("with Bring progress unticked, every card comes in new, and none buried")
    func withProgressLeftOutEveryCardComesInNew() throws {
        let package = AnkiPackage(notes: [
            AnkiNote(type: .basic, fields: ["uno", "one"], progress: .review(due: 30, interval: 10)),
            AnkiNote(type: .basic, fields: ["dos", "two"], progress: .learning(dueAt: 1_792_000_000)),
            AnkiNote(
                type: .basic, fields: ["tres", "three"], progress: .review(due: 25, interval: 3), queue: .suspended),
        ])

        try importPackage(package, choosing: ImportChoices(progress: .leftOut))

        let cards = try engine.cards()
        #expect(cards.count == 3)
        #expect(try cards.allSatisfy { try engine.standing(of: $0.id, on: ladder) == .new })
        #expect(cards.allSatisfy { $0.standing == .inReviews })
        #expect(try engine.reviewLog().isEmpty)
    }

    @Test("a repeated card that the import updates keeps its own step and review log, not Anki's")
    func anUpdatedCardKeepsItsOwnProgress() throws {
        let heart = try approve(card(.word, front: "Corazón", back: "Un órgano."), in: engine)
        try engine.climb(heart, to: 2, movingForward: time)
        let standingBefore = try engine.standing(of: heart.id, on: ladder)
        let logBefore = try engine.reviewLog()
        let package = AnkiPackage(notes: [
            AnkiNote(
                type: .basic, fields: ["corazón", "El órgano que bombea la sangre."],
                progress: .review(due: 30, interval: 75))
        ])

        let outcome = try importPackage(package)

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
        arguments: [
            (creationOffset: 180, rollover: nil, dueOn: 31, at: 4),
            (creationOffset: 480, rollover: nil, dueOn: 30, at: 4),
            (creationOffset: nil, rollover: 6, dueOn: 31, at: 6),
        ] as [(creationOffset: Int?, rollover: Int?, dueOn: Int, at: Int)])
    func aReviewCardFallsDueOnAnkisDay(creationOffset: Int?, rollover: Int?, dueOn day: Int, at hour: Int) throws {
        let package = AnkiPackage(
            notes: [AnkiNote(type: .basic, fields: ["pulmón", "lung"], progress: .review(due: 30, interval: 12))],
            creationOffset: creationOffset, rollover: rollover)

        try importPackage(package)

        #expect(try standing(of: "pulmón") == .onLadder(step: 4, due: try october(day, at: hour)))
    }

    @Test(
        "the Import sheet offers Bring progress for an Anki package, ticked, with how many cards come in on a step, and unticked brings them in new"
    )
    func theImportSheetOffersToBringProgress() throws {
        let package = AnkiPackage(notes: [
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

        window.previewImport(of: textFile)
        let textFileOffers = window.importing?.offersProgress
        window.previewImport(of: packageFile)
        let importing = try #require(window.importing)
        window.chooseToBringProgress(false)
        let untickedBrings = window.importing?.bringsProgress
        window.importCards()

        #expect(textFileOffers == false)
        #expect(importing.offersProgress)
        #expect(importing.bringsProgress)
        // The repeated card keeps its own progress, so it isn't counted.
        #expect(importing.preview?.placedCount == 2)
        #expect(untickedBrings == false)
        #expect(try engine.cards().dropFirst().map(\.front) == ["tres", "uno", "dos"])
        #expect(try engine.cards().allSatisfy { try engine.standing(of: $0.id, on: ladder) == .new })
    }

    @Test("with Bring progress ticked, the Import sheet brings each card in on its step, on the user's ladder")
    func theImportSheetBringsProgressOntoTheUsersLadder() throws {
        // A ladder of three steps, whose last one, 10 days, is the nearest
        // to Anki's 30-day interval.
        let threeSteps = try #require(Ladder(waits: [.seconds(3_600), .seconds(86_400), .seconds(10 * 86_400)]))
        let file = folder.appending(path: "Mazo.apkg")
        try AnkiPackage(notes: [
            AnkiNote(type: .basic, fields: ["uno", "one"], progress: .review(due: 30, interval: 30))
        ]).write(to: file)
        var window = engine.openCardsWindow(on: threeSteps)
        window.startImport()
        window.previewImport(of: file)

        window.importCards()

        let uno = try #require(try engine.cards().first)
        #expect(try engine.standing(of: uno.id, on: threeSteps) == .onLadder(step: 2, due: try october(31, at: 4)))
    }

    // A filtered deck keeps the card's due in its home deck aside, and
    // gives it one of its own, as when the user crams a deck.
    @Test("a card in a filtered deck comes in where it stands in its home deck, with its home deck's tags")
    func aCardInAFilteredDeckComesInAsInItsHomeDeck() throws {
        let package = AnkiPackage(notes: [
            AnkiNote(
                type: .basic, fields: ["sístole", "systole"], deck: "Medicina",
                progress: .review(due: 30, interval: 10),
                filteredDeck: "Repaso para el examen")
        ])

        try importPackage(package)

        #expect(try standing(of: "sístole") == .onLadder(step: 4, due: try october(31, at: 4)))
        #expect(try engine.cards().map(\.tags) == [["Medicina"]])
    }
}
