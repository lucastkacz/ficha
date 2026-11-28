import FichaCore
import Foundation
import GRDB
import Testing

// For `Engine.edit(_:with:deck:bothWays:)`, an edit with a card's whole
// content, which only the tests make, and for a card's type column, which a
// test writes and reads as another device's card can leave it.
@testable import FichaData

/// Tests on editing in the Cards window: a card changes its content and keeps
/// its progress, and is fixed when it's flagged, and the window's save leaves
/// its type and its tags as they are.
struct EditingTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let settings = ReviewSettings.defaults

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
    }

    @Test("an edit changes a card's content and keeps its progress, its due time and its review log")
    func anEditKeepsTheCardsProgress() throws {
        // serendipia graduates with two goods, due a day later, and Lucas
        // edits it before it's due.
        let serendipia = try newCard("serendipia", in: engine)
        try engine.climb(serendipia, goods: 2, movingForward: time)
        let standing = try engine.standing(of: serendipia.id, with: settings.scheduler)
        let log = try engine.reviewLog()
        time.advance(by: hours(1))

        let edited = try engine.edit(
            serendipia.id,
            with: card(
                .concept, front: "serendipia", back: "Un hallazgo valioso por casualidad.", tags: ["lenguaje"],
                source: "Un podcast de etimología")
        )

        #expect(edited.type == .concept)
        #expect(edited.front == "serendipia")
        #expect(edited.back == "Un hallazgo valioso por casualidad.")
        #expect(edited.tags == ["lenguaje"])
        #expect(edited.source == "Un podcast de etimología")
        #expect(edited.createdAt == serendipia.createdAt)
        #expect(try engine.cards() == [edited])
        #expect(try engine.reviewLog() == log)
        #expect(try engine.standing(of: serendipia.id, with: settings.scheduler) == standing)
        time.move(to: try #require(standing.due))
        #expect(try engine.reviewNow(settings) == [.review(edited)])
    }

    // The Cards window (#87) has no button to unflag a card flagged by
    // mistake: Lucas saves it as it is.
    @Test(
        "editing a flagged card fixes it, even with its content unchanged: it's back where it stood in Lucas's reviews")
    func editingAFlaggedCardFixesIt() throws {
        // serendipia climbs to the second step, 4 hours, and Lucas flags it
        // before it's due.
        let serendipia = try newCard("serendipia", in: engine)
        try engine.climb(serendipia, goods: 1, movingForward: time)
        let standing = try engine.standing(of: serendipia.id, with: settings.scheduler)
        try engine.flag(serendipia.id, note: note("Falta decir de dónde viene"))
        time.advance(by: hours(1))

        let edited = try engine.edit(
            serendipia.id,
            with: card(
                serendipia.type, front: serendipia.front, back: serendipia.back, tags: serendipia.tags,
                source: serendipia.source)
        )

        #expect(edited == serendipia)
        #expect(try engine.flaggedCards().isEmpty)
        #expect(try engine.standing(of: serendipia.id, with: settings.scheduler) == standing)
        time.move(to: try #require(standing.due))
        #expect(try engine.reviewNow(settings) == [.review(edited)])
    }

    // Lucas can edit a buried card before deciding whether to unbury it.
    @Test("an edited buried card stays buried, and once unburied it's back in Lucas's reviews, fixed if it was flagged")
    func anEditedBuriedCardStaysBuried() throws {
        // serendipia and ubuntu are due on the first step, and ubuntu was
        // flagged before Lucas buried it.
        let serendipia = try newCard("serendipia", in: engine)
        let ubuntu = try newCard("ubuntu", in: engine)
        try engine.meet(serendipia)
        try engine.meet(ubuntu)
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        let buried = try engine.bury([serendipia.id, ubuntu.id])
        time.advance(by: hours(1))

        let edited = [
            try engine.edit(
                serendipia.id, with: card(.word, front: "serendipia", back: "Un hallazgo valioso por casualidad.")),
            try engine.edit(
                ubuntu.id,
                with: card(.concept, front: "ubuntu", back: "Soy porque somos: una persona lo es por las demás.")),
        ]

        #expect(edited.map(\.buriedAt) == buried.map(\.buriedAt))
        #expect(edited.map(\.flag) == [nil, nil])
        #expect(try engine.reviewNow(settings).isEmpty)
        #expect(try engine.flaggedCards().isEmpty)
        try engine.unbury([serendipia.id, ubuntu.id])
        #expect(try engine.reviewNow(settings).map(\.card.front) == ["serendipia", "ubuntu"])
        #expect(try engine.flaggedCards().isEmpty)
    }

    // iCloud's engine sends in batches, so a card's record can reach the Mac
    // before the record of its user type, "Ley", made on the iPhone: until it
    // comes, the card reads as one with no type. The window shows no types
    // or tags (#538), and its save writes neither, whatever its content says.
    @Test(
        "saving an edit in the Cards window leaves the card's type and tags as the database holds them, a user type this device doesn't hold yet included",
        .bug(id: 538))
    func savingAnEditLeavesATypeThisDeviceDoesntHold() throws {
        let ley = try #require(UUID(uuidString: "6F1A0E2C-3B7D-4C55-9E8A-2D4F1B7C9A10"))
        let mayo = try engine.create(
            card(nil, front: "Revolución de Mayo", back: "1810.", tags: ["historia::Argentina", "política"]))
        try engine.write { db in
            try db.execute(sql: "UPDATE card SET type = ? WHERE id = ?", arguments: [ley.uuidString, mayo.id])
        }
        var window = engine.openCardsWindow(with: settings.scheduler)
        window.read(with: settings.scheduler)
        window.select([mayo.id])

        window.startEditing()
        window.saveCard(
            try card(.concept, front: "Revolución de Mayo", back: "El 25 de mayo de 1810.", tags: ["efemérides"]))

        let saved = try #require(try engine.cards().first { $0.id == mayo.id })
        let typeColumn = try engine.read { db in
            try String.fetchOne(db, sql: "SELECT type FROM card WHERE id = ?", arguments: [mayo.id])
        }
        #expect(window.failure == nil)
        #expect(saved.back == "El 25 de mayo de 1810.")
        #expect(saved.type == nil)
        #expect(saved.tags == ["historia::Argentina", "política"])
        #expect(typeColumn == ley.uuidString)
    }
}
