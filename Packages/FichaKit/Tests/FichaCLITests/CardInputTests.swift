import FichaCore
import FichaData
import Foundation
import Testing

// For the JSON `ficha add` and `ficha fix` read, which the CLI's commands
// decode before they open the engine.
@testable import FichaCLI

/// Tests on what the `ficha` CLI reads from an agent, as the JSON on the
/// standard input of `ficha add` and `ficha fix`, and as the engine then
/// takes it, in memory.
struct CardInputTests {
    // Before card types of the user's own (#365), "Fármaco" failed to decode.
    @Test(
        "a card's type comes in by its name, one of the four's raw value or a type of the user's own, which adding it makes",
        .bug(id: 540))
    func aCardsTypeComesInByItsName() async throws {
        let engine = try Engine(location: .inMemory, time: ManualTimeSource(now: Date(timeIntervalSince1970: 0)))
        let input = Data(
            """
            [
              {"type": "Fármaco", "front": "ibuprofeno", "back": "Un antiinflamatorio.", "tags": [], "source": null},
              {"type": "quote", "front": "La dosis hace el veneno.", "back": "Paracelso.", "tags": [], "source": null},
              {"type": null, "front": "AINE", "back": "Antiinflamatorio no esteroideo.", "tags": [], "source": null}
            ]
            """.utf8)

        let drafts = try cards(in: input, as: .addedCards)
        let result = try await engine.add(drafts)

        let added = try engine.cards()
        #expect(result == .added(added))
        #expect(drafts.map(\.type) == ["Fármaco", "quote", nil])
        let drug = try #require(try engine.userTypes().first)
        #expect(drug.name == "Fármaco")
        #expect(added.map(\.type) == [CardType.user(drug), .quote, nil])
    }

    // Medicina::Farmacología isn't there yet; the second card names no deck,
    // and the third names Default by its name in `ficha cards`.
    @Test(
        "each added card goes to the deck it names, made if it isn't there, or to Default when it names none",
        .bug(id: 540))
    func anAddedCardGoesToItsDeck() async throws {
        let engine = try Engine(location: .inMemory, time: ManualTimeSource(now: Date(timeIntervalSince1970: 0)))
        let input = Data(
            """
            [
              {"type": "word", "front": "ibuprofeno", "back": "Un antiinflamatorio.", "tags": [], "source": null,
               "deck": " Medicina :: Farmacología "},
              {"type": "word", "front": "AINE", "back": "Antiinflamatorio no esteroideo.", "tags": [], "source": null},
              {"type": "word", "front": "dosis", "back": "Cuánto se toma.", "tags": [], "source": null, "deck": ""}
            ]
            """.utf8)

        let result = try await engine.add(cards(in: input, as: .addedCards))

        let added = try engine.cards()
        #expect(result == .added(added))
        #expect(added.map(\.deck) == ["Medicina::Farmacología", Deck.defaultName, Deck.defaultName])
        #expect(try engine.decks().map(\.name) == [Deck.defaultName, "Medicina", "Medicina::Farmacología"])
    }

    // ibuprofeno lives in Medicina; the first fix moves it, and the second,
    // which names no deck, leaves it where the first put it.
    @Test(
        "`ficha fix` moves a card to the deck the card names, and keeps its own when it names none", .bug(id: 540))
    func aFixedCardKeepsOrChangesItsDeck() async throws {
        let engine = try Engine(location: .inMemory, time: ManualTimeSource(now: Date(timeIntervalSince1970: 0)))
        let content = try #require(
            CardContent(type: .word, front: "ibuprofeno", back: "Un analgésico.", tags: [], source: nil))
        let ibuprofeno = try engine.create(content, deck: "Medicina")
        try engine.flag(ibuprofeno.id, note: try #require(FlagNote("Es un antiinflamatorio")))
        let moved = Data(
            """
            {"type": "word", "front": "ibuprofeno", "back": "Un antiinflamatorio.", "tags": [], "source": null,
             "deck": "Medicina::Farmacología"}
            """.utf8)
        let kept = Data(
            """
            {"type": "word", "front": "ibuprofeno", "back": "Un antiinflamatorio y analgésico.", "tags": [],
             "source": null}
            """.utf8)

        let afterFirstFix = try await engine.fix(ibuprofeno.id, with: card(in: moved, as: .fixedCard))
        try engine.flag(ibuprofeno.id, note: try #require(FlagNote("También calma el dolor")))
        let afterSecondFix = try await engine.fix(ibuprofeno.id, with: card(in: kept, as: .fixedCard))

        #expect(afterFirstFix.deck == "Medicina::Farmacología")
        #expect(afterSecondFix.deck == "Medicina::Farmacología")
        #expect(afterSecondFix.back == "Un antiinflamatorio y analgésico.")
    }

    @Test("a card whose deck is null is refused, saying where, as any field of the wrong kind is")
    func aNullDeckIsRefused() throws {
        let input = Data(
            """
            [{"type": "word", "front": "AINE", "back": "Antiinflamatorio.", "tags": [], "source": null, "deck": null}]
            """.utf8)

        #expect(throws: CardsInputError.self) { try cards(in: input, as: .addedCards) }
    }
}
