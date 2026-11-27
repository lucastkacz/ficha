import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on Share Deck…, among a deck's actions in the Cards window (ADR
/// 0044, #557): the window's state writes the deck's `.ficha`, named after
/// the deck, which the app hands to macOS's Share menu. They start at 9 in
/// the morning in Buenos Aires, with engines in memory.
struct ShareDeckTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let scheduler = ReviewSettings.defaults.scheduler

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
    }

    // The user's Pinturas argentinas has an emoji, a description, a painting
    // by its picture alone and one that goes both ways; Historia stays out.
    // Another Ficha, with no cards, reads the file back.
    @Test(
        "Share Deck… hands the Share menu one .ficha named after the deck, which reads back in another Ficha as that deck, with its cards, pictures, emoji and description",
        .bug(id: 557))
    func shareDeckHandsOneFichaFile() async throws {
        let name = "Pinturas argentinas"
        let description = "Pinturas argentinas del siglo XIX, que están en museos de Buenos Aires."
        let siesta = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        try engine.create(
            card(nil, front: "", back: "La siesta, de Prilidiano Pueyrredón, 1865.", frontImage: siesta), deck: name)
        try engine.create(
            card(nil, front: "Sin pan y sin trabajo", back: "Ernesto de la Cárcova, 1894."), deck: name,
            bothWays: true)
        try engine.create(card(nil, front: "Revolución de Mayo", back: "1810."), deck: "Historia")
        try engine.setEmoji(Emoji("🎨"), ofDeck: name)
        try engine.setDescription(description, ofDeck: name)
        let shared = try engine.cards().filter { $0.deck == name }
        var window = engine.openCardsWindow(with: scheduler)
        window.read(with: scheduler)

        let handed = window.shareDeck(name)

        let file = try #require(handed, "Share Deck… handed the Share menu no file.")
        defer { try? FileManager.default.removeItem(at: file) }
        let other = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
        try other.addDeck(try await other.readDeckFile(at: file))
        let read = try other.cards()
        let decks = try other.decks()
        #expect(file.lastPathComponent == "\(name).ficha")
        #expect(window.failure == nil)
        #expect(read.map(content(of:)) == shared.map(content(of:)))
        #expect(read.map(\.deck) == shared.map(\.deck))
        #expect(read.map(\.bothWays) == shared.map(\.bothWays))
        #expect(try other.image(siesta) == engine.image(siesta))
        #expect(decks.map(\.name) == [name])
        #expect(decks.map(\.emoji) == ["🎨"])
        #expect(decks.map(\.description) == [description])
    }
}
