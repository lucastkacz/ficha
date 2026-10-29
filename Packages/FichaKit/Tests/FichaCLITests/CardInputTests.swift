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
}
