import FichaCore
import FichaData
import Foundation
import Testing

// For the JSON `ficha approve` reads, which the CLI's commands decode before
// they open the engine.
@testable import FichaCLI

/// Tests on what the `ficha` CLI reads from a refine session, as the JSON on
/// `ficha approve`'s standard input, and as the engine then takes it, in
/// memory.
struct CardInputTests {
    // Before card types of the user's own (#365), "Fármaco" failed to decode.
    @Test(
        "a card's type comes in by its name, one of the four's raw value or a type of the user's own, which approving it makes"
    )
    func aCardsTypeComesInByItsName() async throws {
        let engine = try Engine(location: .inMemory, time: ManualTimeSource(now: Date(timeIntervalSince1970: 0)))
        guard case .saved(let capture) = try engine.capture(text: "farmacología", note: nil, source: nil) else {
            Issue.record("The capture wasn't saved.")
            return
        }
        let input = Data(
            """
            [
              {"type": "Fármaco", "front": "ibuprofeno", "back": "Un antiinflamatorio.", "tags": [], "source": null},
              {"type": "quote", "front": "La dosis hace el veneno.", "back": "Paracelso.", "tags": [], "source": null},
              {"type": null, "front": "AINE", "back": "Antiinflamatorio no esteroideo.", "tags": [], "source": null}
            ]
            """.utf8)

        let drafts = try cards(in: input)
        let approved = try await engine.approve(capture.id, into: drafts)

        #expect(drafts.map(\.type) == ["Fármaco", "quote", nil])
        let drug = try #require(try engine.userTypes().first)
        #expect(drug.name == "Fármaco")
        #expect(approved.map(\.type) == [CardType.user(drug), .quote, nil])
    }

    // Medicina::Farmacología isn't there yet; the second card names no deck,
    // and the third names Default by its name in `ficha cards`.
    @Test("each approved card goes to the deck it names, made if it isn't there, or to Default when it names none")
    func anApprovedCardGoesToItsDeck() async throws {
        let engine = try Engine(location: .inMemory, time: ManualTimeSource(now: Date(timeIntervalSince1970: 0)))
        let capture = try newCapture("farmacología", in: engine)
        let input = Data(
            """
            [
              {"type": "word", "front": "ibuprofeno", "back": "Un antiinflamatorio.", "tags": [], "source": null,
               "deck": " Medicina :: Farmacología "},
              {"type": "word", "front": "AINE", "back": "Antiinflamatorio no esteroideo.", "tags": [], "source": null},
              {"type": "word", "front": "dosis", "back": "Cuánto se toma.", "tags": [], "source": null, "deck": ""}
            ]
            """.utf8)

        let approved = try await engine.approve(capture.id, into: cards(in: input))

        #expect(approved.map(\.deck) == ["Medicina::Farmacología", Deck.defaultName, Deck.defaultName])
        #expect(try engine.decks().map(\.name) == [Deck.defaultName, "Medicina", "Medicina::Farmacología"])
    }

    // ibuprofeno lives in Medicina; the fix moves it, and the expansion,
    // which names no deck, leaves it where the fix put it.
    @Test(
        "`ficha fix` and `ficha approve-expansion` move a card to the deck the card names, and keep its own when it names none"
    )
    func aFixedOrExpandedCardKeepsOrChangesItsDeck() async throws {
        let engine = try Engine(location: .inMemory, time: ManualTimeSource(now: Date(timeIntervalSince1970: 0)))
        let capture = try newCapture("ibuprofeno", in: engine)
        let content = try #require(
            CardContent(type: .word, front: "ibuprofeno", back: "Un analgésico.", tags: [], source: nil))
        let ibuprofeno = try #require(try engine.approve(capture.id, into: [content], deck: "Medicina").first)
        try engine.flag(ibuprofeno.id, note: try #require(FlagNote("Es un antiinflamatorio")))
        let fixed = Data(
            """
            {"type": "word", "front": "ibuprofeno", "back": "Un antiinflamatorio.", "tags": [], "source": null,
             "deck": "Medicina::Farmacología"}
            """.utf8)
        let expanded = Data(
            """
            {"type": "word", "front": "ibuprofeno", "back": "Un antiinflamatorio y analgésico.", "tags": [],
             "source": null}
            """.utf8)

        let afterFix = try await engine.fix(ibuprofeno.id, with: card(in: fixed, as: .fixedCard))
        let expansion = try engine.expand(text: "ibuprofeno", note: "También calma el dolor", source: nil)
        let afterExpansion = try await engine.approveExpansion(
            expansion.id, into: card(in: expanded, as: .expandedCard))

        #expect(afterFix.deck == "Medicina::Farmacología")
        #expect(afterExpansion.deck == "Medicina::Farmacología")
        #expect(afterExpansion.back == "Un antiinflamatorio y analgésico.")
    }

    @Test("a card whose deck is null is refused, saying where, as any field of the wrong kind is")
    func aNullDeckIsRefused() throws {
        let input = Data(
            """
            [{"type": "word", "front": "AINE", "back": "Antiinflamatorio.", "tags": [], "source": null, "deck": null}]
            """.utf8)

        #expect(throws: CardsInputError.self) { try cards(in: input) }
    }

    /// Saves a capture of `text` in `engine`'s inbox, which repeats nothing,
    /// and returns it.
    private func newCapture(_ text: String, in engine: Engine) throws -> Capture {
        guard case .saved(let capture) = try engine.capture(text: text, note: nil, source: nil) else {
            throw EngineError.emptyCapture
        }
        return capture
    }
}
