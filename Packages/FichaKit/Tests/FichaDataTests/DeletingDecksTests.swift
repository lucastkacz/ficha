import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on deleting a deck (ADR 0024), as Anki deletes one: the deck goes
/// with the decks inside it and every card that lives in them, buried ones
/// too, with their review logs, in one write, and nothing Lucas jotted down
/// about a card is lost. Default is never deleted. They start at 9 in the
/// morning in Buenos Aires, when active hours start.
struct DeletingDecksTests {
    let time: ManualTimeSource
    let engine: Engine
    let scheduler = ReviewSettings.defaults.scheduler

    init() throws {
        let calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
    }

    // Arte::Escultura has no card, and Guernica is buried. Artes starts as
    // Arte does, and sits inside no deck.
    @Test("Delete… counts first the decks inside the deck and the cards it deletes, buried ones too, changing nothing")
    func deleteCountsFirst() throws {
        try approveInDeck("La Gioconda", deck: "Arte::Pintura", in: engine)
        let guernica = try approveInDeck("Guernica", deck: "Arte::Pintura::Óleo", in: engine)
        try approveInDeck("La Piedad", deck: "Arte", in: engine)
        try approveInDeck("fuga", deck: "Artes", in: engine)
        try engine.makeDeck(named: "Arte::Escultura")
        try engine.bury(guernica.id)

        let deletion = try engine.deletion(ofDeck: "Arte")

        #expect(deletion.deck == "Arte")
        #expect(deletion.decksInside == ["Arte::Escultura", "Arte::Pintura", "Arte::Pintura::Óleo"])
        #expect(deletion.cards == 3)
        #expect(try engine.deletion(ofDeck: "Arte::Escultura").cards == 0)
        #expect(try engine.cards().count == 4)
        #expect(
            try engine.decks().map(\.name) == [
                "Arte", "Arte::Escultura", "Arte::Pintura", "Arte::Pintura::Óleo", "Artes",
            ])
    }

    // Guernica is buried; Coliseo lives in Historia and petricor in Default.
    // La Gioconda's expansion waits in the inbox, as does a follow-up about
    // La Piedad.
    @Test(
        "deleting a deck deletes it with the decks inside it and every card in them, with their review logs, and leaves expansions and follow-ups in the inbox"
    )
    func deletingADeck() throws {
        let gioconda = try approveInDeck("La Gioconda", deck: "Arte::Pintura", in: engine)
        let guernica = try approveInDeck("Guernica", deck: "Arte::Pintura", in: engine)
        let piedad = try approveInDeck("La Piedad", deck: "Arte", in: engine)
        let coliseo = try approveInDeck("Coliseo", deck: "Historia", in: engine)
        let petricor = try approveInDeck("petricor", in: engine)
        try engine.makeDeck(named: "Arte::Escultura")
        for card in [gioconda, piedad, coliseo] {
            try engine.meet(card)
        }
        try engine.bury(guernica.id)
        let expansion = try engine.expand(text: "La Gioconda", note: "También se llama Mona Lisa", source: nil)
        let followUp = try engine.followUp(piedad.id, text: "¿Dónde está?")
        let standing = try engine.standing(of: coliseo.id, with: scheduler)

        let deletion = try engine.deleteDeck("Arte")

        #expect(deletion.cards == 3)
        #expect(try engine.decks().map(\.name) == [Deck.defaultName, "Historia"])
        #expect(try engine.cards().map(\.id) == [coliseo.id, petricor.id])
        #expect(try engine.reviewLog().map(\.cardID) == [coliseo.id])
        #expect(try engine.standing(of: coliseo.id, with: scheduler) == standing)
        let inbox = try engine.inbox()
        #expect(inbox.captures.map(\.id) == [expansion.id, followUp.id])
        #expect(inbox.captures.map(\.expandsCardID) == [nil, nil])
        #expect(inbox.captures.map(\.followsUpCardID) == [nil, nil])
    }

    @Test("deleting is refused for Default and for a deck that isn't there, deleting nothing")
    func deletingRefuses() throws {
        try approveInDeck("petricor", in: engine)

        #expect(throws: EngineError.defaultDeckStays) { try engine.deletion(ofDeck: Deck.defaultName) }
        #expect(throws: EngineError.defaultDeckStays) { try engine.deleteDeck(Deck.defaultName) }
        #expect(throws: EngineError.deckNotFound("Música")) { try engine.deleteDeck("Música") }
        #expect(try engine.cards().map(\.front) == ["petricor"])
    }
}
