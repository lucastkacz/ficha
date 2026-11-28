import FichaCore
import FichaData
import Foundation
import Testing
import ZIPFoundation

/// Tests on a deck's file, a `.ficha` (ADR 0044, #554): a zip that holds the
/// deck's cards, their pictures, and `deck.json`, with the deck's emoji and
/// description, but never the user's progress, which the engine writes from
/// a deck, reads back, and brings in as Add Deck… brings in one of Ficha's
/// decks. They start at 9 in the morning in Buenos Aires, with engines in
/// memory, and files in a folder of the test's own.
final class DeckFileTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    /// A folder of the test's own, for the files it writes and reads.
    let folder = URL.temporaryDirectory.appending(
        path: "DeckFileTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    // The user's Pinturas has an emoji, a description, a painting by its
    // picture alone, one that goes both ways and one with its source, and
    // they met the first; Palabras has no emoji, description or picture; and
    // Historia is in neither file. Another Ficha, with no cards, reads both
    // files back.
    @Test(
        "a deck written as a .ficha, a zip whose deck.json holds its emoji and description, with pictures or none, reads back in another Ficha with the same cards, pictures, emoji and description, and none of its progress",
        .bug(id: 554))
    func aDeckReadsBackAsItWasWritten() async throws {
        let description = "Pinturas argentinas del siglo XIX, que están en museos de Buenos Aires."
        let siesta = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let met = try engine.create(
            card(nil, front: "", back: "La siesta, de Pueyrredón, 1865.", frontImage: siesta), deck: "Pinturas")
        try engine.create(
            card(nil, front: "Sin pan y sin trabajo", back: "Ernesto de la Cárcova, 1894."), deck: "Pinturas",
            bothWays: true)
        try engine.create(
            card(nil, front: "La vuelta del malón", back: "Ángel Della Valle, 1892.", source: "bellasartes.gob.ar"),
            deck: "Pinturas")
        try engine.create(card(nil, front: "cachivache", back: "Una cosa vieja que sirve de poco."), deck: "Palabras")
        try engine.create(card(nil, front: "Revolución de Mayo", back: "1810."), deck: "Historia")
        try engine.setEmoji(Emoji("🎨"), ofDeck: "Pinturas")
        try engine.setDescription(description, ofDeck: "Pinturas")
        try engine.meet(met)
        let written = try engine.cards().filter { $0.deck != "Historia" }
        let pinturas = folder.appending(path: "Pinturas.ficha")
        let palabras = folder.appending(path: "Palabras.ficha")

        try engine.export(.deck("Pinturas"), to: pinturas)
        try engine.export(.deck("Palabras"), to: palabras)
        let other = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
        for file in [pinturas, palabras] {
            try other.addDeck(try await other.readDeckFile(at: file))
        }
        let read = try other.cards()
        let decks = try other.decks()

        #expect(deckJSON(inZip: pinturas) == DeckJSON(emoji: "🎨", description: description))
        #expect(deckJSON(inZip: palabras) == DeckJSON(emoji: nil, description: nil))
        #expect(read.map(content(of:)) == written.map(content(of:)))
        #expect(read.map(\.deck) == written.map(\.deck))
        #expect(read.map(\.bothWays) == written.map(\.bothWays))
        #expect(try other.image(siesta) == engine.image(siesta))
        #expect(decks.map(\.name) == ["Palabras", "Pinturas"])
        #expect(decks.map(\.emoji) == [nil, "🎨"])
        #expect(decks.map(\.description) == [nil, description])
        #expect(try other.reviewLog() == [])
    }

    // The user has Pinturas, with an emoji, a description or none, and two
    // paintings, and met the first. A friend's Pinturas, written by another
    // Ficha, has an emoji and a description of its own, the same two
    // paintings, the first with a longer back, and one more.
    @Test(
        "a .ficha of a deck the user has adds only the cards it lacks, without a tag, and leaves the cards it repeats, their progress, and the deck's emoji and description, or its lack of one, as they were",
        .bug(id: 554), arguments: ["Las que vi en el museo.", nil])
    func aDeckTheUserHasTakesOnlyTheCardsItLacks(description: String?) async throws {
        let siesta = try engine.create(
            card(nil, front: "La siesta", back: "Prilidiano Pueyrredón, 1865."), deck: "Pinturas")
        try engine.create(
            card(nil, front: "Sin pan y sin trabajo", back: "Ernesto de la Cárcova, 1894."), deck: "Pinturas")
        try engine.setEmoji(Emoji("🎨"), ofDeck: "Pinturas")
        try engine.setDescription(description, ofDeck: "Pinturas")
        try engine.meet(siesta)
        let cardsBefore = try engine.cards()
        let logBefore = try engine.reviewLog()
        let friend = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
        try friend.create(
            card(nil, front: "La siesta", back: "Prilidiano Pueyrredón, 1865. Museo Nacional de Bellas Artes."),
            deck: "Pinturas")
        try friend.create(
            card(nil, front: "Sin pan y sin trabajo", back: "Ernesto de la Cárcova, 1894."), deck: "Pinturas")
        try friend.create(card(nil, front: "La vuelta del malón", back: "Ángel Della Valle, 1892."), deck: "Pinturas")
        try friend.setEmoji(Emoji("🌄"), ofDeck: "Pinturas")
        try friend.setDescription("Pinturas argentinas del siglo XIX.", ofDeck: "Pinturas")
        let file = folder.appending(path: "Pinturas.ficha")
        try friend.export(.deck("Pinturas"), to: file)

        let added = try engine.addDeck(try await engine.readDeckFile(at: file))
        let cards = try engine.cards()
        let pinturas = try engine.decks().first { $0.name == "Pinturas" }

        #expect(added.added == 1)
        #expect(Array(cards.prefix(2)) == cardsBefore)
        #expect(cards.dropFirst(2).map(\.front) == ["La vuelta del malón"])
        #expect(cards.dropFirst(2).map(\.deck) == ["Pinturas"])
        #expect(cards.dropFirst(2).map(\.tags) == [[]])
        #expect(try engine.reviewLog() == logBefore)
        #expect(pinturas?.emoji == "🎨")
        #expect(pinturas?.description == description)
    }
}

/// What a deck's file's `deck.json` holds, as the tests read it: the deck's
/// emoji and description, each nil when the deck has none.
struct DeckJSON: Decodable, Equatable {
    let emoji: String?
    let description: String?
}

/// What the `deck.json` at the top of the zip `file` holds, or nil when
/// `file` isn't a zip, holds no `deck.json`, or holds one that isn't JSON
/// with an emoji and a description, each a text or nothing.
func deckJSON(inZip file: URL) -> DeckJSON? {
    guard let archive = try? Archive(url: file, accessMode: .read, pathEncoding: nil),
        let entry = archive["deck.json"]
    else {
        return nil
    }
    var data = Data()
    guard (try? archive.extract(entry) { chunk in data.append(chunk) }) != nil else {
        return nil
    }
    return try? JSONDecoder().decode(DeckJSON.self, from: data)
}
