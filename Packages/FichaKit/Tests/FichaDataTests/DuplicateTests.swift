import FichaCore
import Foundation
import Testing

@testable import FichaData

/// Tests on the duplicate rule, by which the Cards window's form warns of a
/// front that repeats a card's, and `ficha add` refuses one.
struct DuplicateTests {
    let time = ManualTimeSource(now: Date(timeIntervalSince1970: 1_760_000_000))

    @Test(
        "a front that repeats a card's, ignoring case, accents and surrounding spaces, repeats that card",
        .bug(id: 540))
    func repeatingACardsFrontIsADuplicate() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let card = try newCard("Pensamiento crítico", in: engine)

        let fronts = try engine.frontsInUse()

        #expect(fronts.cardID(repeatedBy: "  pensamiento CRITICO\n") == card.id)
        #expect(fronts.cardID(repeatedBy: "serendipia") == nil)
    }

    // In Spanish, ñ is a letter of its own, not an n with an accent.
    @Test("words that differ only in ñ and n aren't duplicates", .bug(id: 540))
    func eñeIsALetterOfItsOwn() throws {
        let engine = try Engine(location: .inMemory, time: time)
        try newCard("año", in: engine)

        #expect(try engine.frontsInUse().cardID(repeatedBy: "ano") == nil)
    }

    // A chemistry deck brings "H₂O", and someone types "H2O". A raised minus
    // comes from a "-" or a "−", the minus sign.
    @Test(
        "words that differ only in superscripts and subscripts, or in a minus sign, are duplicates", .bug(id: 540))
    func superscriptsAndSubscriptsDontKeepFrontsApart() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let water = try newCard("H₂O", in: engine)
        let sulfate = try newCard("SO42-", in: engine)
        let inverse = try newCard("x−1", in: engine)

        let fronts = try engine.frontsInUse()

        #expect(fronts.cardID(repeatedBy: "h2o") == water.id)
        #expect(fronts.cardID(repeatedBy: "SO₄²⁻") == sulfate.id)
        #expect(fronts.cardID(repeatedBy: "x⁻¹") == inverse.id)
    }

    // The form's warning names one card, and points to it.
    @Test("a front that repeats two cards' repeats the first that came in", .bug(id: 540))
    func theFirstCardCounts() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let first = try newCard("Serendipia", in: engine)
        try newCard("serendipia", in: engine)

        #expect(try engine.frontsInUse().cardID(repeatedBy: "SERENDIPIA") == first.id)
    }

    @Test("flagged and buried cards count as repeated too")
    func flaggedAndBuriedCardsCount() throws {
        let engine = try Engine(location: .inMemory, time: time)
        let flagged = try newCard("serendipia", in: engine)
        let buried = try newCard("ubuntu", in: engine)
        try engine.flag(flagged.id, note: note("El dorso es confuso"))
        try engine.bury(buried.id)

        let fronts = try engine.frontsInUse()

        #expect(fronts.cardID(repeatedBy: "serendipia") == flagged.id)
        #expect(fronts.cardID(repeatedBy: "ubuntu") == buried.id)
    }
}
