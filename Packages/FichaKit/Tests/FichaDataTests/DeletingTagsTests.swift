import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on deleting tags (ADR 0022): a tag deleted, with every tag inside
/// it, comes off every card that carries it, and its rows go, while every
/// card stays; what Delete…'s question counts first; Clear Unused Tags,
/// which deletes the tags no card carries; and each tag's counts, which All
/// Tags shows beside them (`TagCounts.swift`). They start at 9 in the morning
/// in Buenos Aires, with the default settings.
struct DeletingTagsTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test(
        "deleting a tag takes it, and every tag inside it, off every card, buried ones too, removes their rows, and deletes no card"
    )
    func deletingATag() throws {
        try approveCard("Martín Fierro", tags: ["literatura::poesía", "historia"])
        let ficciones = try approveCard("Ficciones", tags: ["literatura"])
        try approveCard("Revolución de Mayo", tags: ["historia"])
        try engine.bury(ficciones.id)
        try engine.setColor(.purple, of: "literatura::poesía")
        try engine.pin("literatura::poesía")

        try engine.deleteTags(["literatura"])

        #expect(
            try engine.cards().map(\.tags) == [["historia"], [], ["historia"]])
        #expect(try engine.allTags() == [CardTag(name: "historia")])
        #expect(try engine.pinnedTags().isEmpty)
    }

    // Only the cards in Borges sync, chosen, and Martín Fierro's tags change
    // nothing of it; Ficciones is buried.
    @Test("Delete… counts first the tags inside and the cards that carry them, under selective sync too")
    func deleteCountsFirst() throws {
        try approveCard("Martín Fierro", tags: ["literatura::poesía", "historia"])
        let ficciones = try approveCard("Ficciones", tags: ["literatura"])
        try approveInDeck("El Aleph", deck: "Borges", tags: ["literatura", "argentina"], in: engine)
        try approveCard("Facundo", tags: ["literatura", "política"])
        try approveCard("Revolución de Mayo", tags: ["historia"])
        try engine.bury(ficciones.id)
        try engine.syncOnlyChosenDecks(true)
        try engine.setChosenToSync(true, ofDeck: "Borges")

        let deletion = try engine.deletion(of: ["literatura"])

        #expect(deletion.tags == ["literatura"])
        #expect(deletion.tagsInside == ["literatura::poesía"])
        #expect(deletion.cards == 4)
        #expect(try engine.deleteTags(["literatura"]) == deletion)
    }

    @Test("deleting a tag with a tag inside it among those chosen deletes each once, the tag inside it with it")
    func deletingATagAndATagInsideIt() throws {
        try approveCard("Martín Fierro", tags: ["literatura::poesía::gauchesca", "historia"])

        let deletion = try engine.deleteTags(["literatura::poesía", "literatura", "literatura"])

        #expect(deletion.tags == ["literatura::poesía", "literatura"])
        #expect(deletion.tagsInside == ["literatura::poesía::gauchesca"])
        #expect(try engine.cards().map(\.tags) == [["historia"]])
    }

    // literatura has a color, and a card carries a tag inside it; música,
    // música::tango and cine have something of their own and no card.
    @Test("Clear Unused Tags deletes each tag with a row of its own that no card carries, nor a tag inside it")
    func clearingUnusedTags() throws {
        try approveCard("Martín Fierro", tags: ["literatura::poesía"])
        try engine.setColor(.purple, of: "literatura")
        try engine.setColor(.blue, of: "música")
        try engine.pin("música::tango")
        try engine.setEmoji(Emoji("🎬"), of: "cine")

        #expect(try engine.unusedTags() == ["cine", "música", "música::tango"])

        #expect(try engine.clearUnusedTags() == ["cine", "música", "música::tango"])
        #expect(try engine.allTags().map(\.name) == ["literatura", "literatura::poesía"])
        #expect(try engine.allTags().first?.color == .purple)
        #expect(try engine.pinnedTags().isEmpty)
    }

    // Only the cards in Música sync, chosen; Martín Fierro, which carries
    // literatura, doesn't. Another device's cards keep their tags, which
    // Clear Unused Tags never changes (`SelectiveSyncTests`).
    @Test("under selective sync, Clear Unused Tags considers every tag no card here carries, whatever syncs")
    func clearingUnusedTagsUnderSelectiveSync() throws {
        try approveCard("Martín Fierro", tags: ["literatura"])
        try engine.setColor(.purple, of: "literatura")
        try engine.pin("música::tango")
        try engine.setEmoji(Emoji("🎬"), of: "cine")
        try engine.syncOnlyChosenDecks(true)
        try engine.setChosenToSync(true, ofDeck: "Música")

        #expect(try engine.unusedTags() == ["cine", "música::tango"])
    }

    // Martín Fierro, Facundo and El Aleph are due, Ficciones too but buried,
    // and Rayuela is new; El Aleph lives in a set-aside deck, and música has
    // a color alone.
    @Test("each tag counts the cards it lists, those inside it too but buried ones, and those due in the reviews")
    func cardsAndDuePerTag() throws {
        let scheduler = ReviewSettings.defaults.scheduler
        try engine.meet(try approveCard("Martín Fierro", tags: ["literatura::poesía", "historia"]))
        let ficciones = try approveCard("Ficciones", tags: ["literatura"])
        try engine.meet(ficciones)
        try engine.bury(ficciones.id)
        try engine.meet(try approveCard("Facundo", tags: ["historia::argentina"]))
        try approveCard("Rayuela", tags: ["literatura"])
        let aleph = try approveCard("El Aleph", tags: ["cine"])
        try engine.meet(aleph)
        try engine.changeDeck(of: [aleph.id], to: "Borges")
        try engine.setAside(deck: "Borges")
        try engine.setColor(.blue, of: "música")
        time.advance(by: hours(2))

        let counted = try engine.countedTags(with: scheduler)

        #expect(counted.map(\.tag) == (try engine.allTags()))
        #expect(
            counted.map { "\($0.tag.name) \($0.counts.cards)/\($0.counts.due)" } == [
                "cine 1/0", "historia 2/2", "historia::argentina 1/1", "literatura 2/1", "literatura::poesía 1/1",
                "música 0/0",
            ])
    }

    @discardableResult
    private func approveCard(_ front: String, tags: [String]) throws -> Card {
        try approve(card(.word, front: front, back: "Lo que quiere decir «\(front)».", tags: tags), in: engine)
    }
}
