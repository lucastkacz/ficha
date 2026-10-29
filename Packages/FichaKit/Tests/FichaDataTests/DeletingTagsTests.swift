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
        try engine.setAside("literatura")
        try engine.setColor(.purple, of: "literatura::poesía")
        try engine.pin("literatura::poesía")
        try engine.chooseToSync("literatura", true)

        try engine.deleteTags(["literatura"])

        #expect(
            try engine.cards().map(\.tags) == [["historia"], [], ["historia"]])
        #expect(try engine.allTags() == [CardTag(name: "historia")])
        #expect(try engine.pinnedTags().isEmpty)
    }

    // literatura is set aside, and so is política; literatura::poesía and
    // argentina are chosen to sync. Martín Fierro and El Aleph come back to
    // the reviews, Ficciones stays buried and Facundo set aside by política;
    // Martín Fierro is left with no chosen tag.
    @Test(
        "Delete… counts first the tags inside, the cards that carry them, those that come back to the reviews, and those that stop syncing"
    )
    func deleteCountsFirst() throws {
        try approveCard("Martín Fierro", tags: ["literatura::poesía", "historia"])
        let ficciones = try approveCard("Ficciones", tags: ["literatura"])
        try approveCard("El Aleph", tags: ["literatura", "argentina"])
        try approveCard("Facundo", tags: ["literatura", "política"])
        try approveCard("Revolución de Mayo", tags: ["historia"])
        try engine.bury(ficciones.id)
        try engine.setAside("literatura")
        try engine.setAside("política")
        try engine.syncOnlyChosenTags(true)
        try engine.chooseToSync("literatura::poesía", true)
        try engine.chooseToSync("argentina", true)

        let deletion = try engine.deletion(of: ["literatura"])

        #expect(deletion.tags == ["literatura"])
        #expect(deletion.tagsInside == ["literatura::poesía"])
        #expect(deletion.cards == 4)
        #expect(deletion.cardsBackInReviews == 2)
        #expect(deletion.cardsThatStopSyncing == 1)
        #expect(try engine.deleteTags(["literatura"]) == deletion)
    }

    // literatura is set aside; Martín Fierro carries only a tag inside it,
    // and Ficciones carries literatura too.
    @Test(
        "deleting a tag inside a set-aside tag brings back to the reviews a card it alone set aside, as Delete… counts first"
    )
    func deletingATagInsideASetAsideTag() throws {
        try approveCard("Martín Fierro", tags: ["literatura::poesía"])
        try approveCard("Ficciones", tags: ["literatura::poesía", "literatura"])
        try engine.setAside("literatura")

        #expect(try engine.deletion(of: ["literatura::poesía"]).cardsBackInReviews == 1)

        try engine.deleteTags(["literatura::poesía"])

        #expect(try engine.card(fronted: "Martín Fierro").standing == .inReviews)
        #expect(try engine.card(fronted: "Ficciones").standing == .setAside(by: ["literatura"]))
    }

    @Test("Delete… counts no card that stops syncing while every card syncs, or while sync is off")
    func deleteCountsNoCardThatStopsSyncingWhenEveryCardSyncs() throws {
        try approveCard("Martín Fierro", tags: ["literatura"])

        #expect(try engine.deletion(of: ["literatura"]).cardsThatStopSyncing == nil)

        try engine.syncOnlyChosenTags(true)
        try engine.chooseToSync("literatura", true)
        try engine.turnSyncOff()

        #expect(try engine.deletion(of: ["literatura"]).cardsThatStopSyncing == nil)
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
        try engine.setAside("cine")

        #expect(try engine.unusedTags() == ["cine", "música", "música::tango"])

        #expect(try engine.clearUnusedTags() == ["cine", "música", "música::tango"])
        #expect(try engine.allTags().map(\.name) == ["literatura", "literatura::poesía"])
        #expect(try engine.allTags().first?.color == .purple)
        #expect(try engine.pinnedTags().isEmpty)
    }

    // música is chosen to sync, cine isn't: another device may hold a card
    // with cine, which doesn't sync. Once sync is off, every tag counts.
    @Test(
        "under selective sync, Clear Unused Tags considers only the tags chosen to sync and those inside them, and every tag while sync is off"
    )
    func clearingUnusedTagsUnderSelectiveSync() throws {
        try engine.chooseToSync("música", true)
        try engine.pin("música::tango")
        try engine.setAside("cine")
        try engine.syncOnlyChosenTags(true)

        #expect(try engine.unusedTags() == ["música", "música::tango"])

        try engine.turnSyncOff()

        #expect(try engine.unusedTags() == ["cine", "música", "música::tango"])
    }

    // Martín Fierro, Facundo and El Aleph are due, Ficciones too but buried,
    // and Rayuela is new; cine is set aside, and música has a color alone.
    @Test("each tag counts the cards it lists, those inside it too but buried ones, and those due in the reviews")
    func cardsAndDuePerTag() throws {
        let ladder = ReviewSettings.defaults.ladder
        try engine.meet(try approveCard("Martín Fierro", tags: ["literatura::poesía", "historia"]))
        let ficciones = try approveCard("Ficciones", tags: ["literatura"])
        try engine.meet(ficciones)
        try engine.bury(ficciones.id)
        try engine.meet(try approveCard("Facundo", tags: ["historia::argentina"]))
        try approveCard("Rayuela", tags: ["literatura"])
        try engine.meet(try approveCard("El Aleph", tags: ["cine"]))
        try engine.setAside("cine")
        try engine.setColor(.blue, of: "música")
        time.advance(by: hours(2))

        let counted = try engine.countedTags(on: ladder)

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
