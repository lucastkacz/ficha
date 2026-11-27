import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on Ficha's decks as decks' files (ADR 0044, #554): each a `.ficha`
/// in the repo's `App/FichaDecks/`, which the app bundles, whose `deck.json`
/// holds its emoji and its description, in Spanish (ADR 0040), and which no
/// source writes. They start at 9 in the morning in Buenos Aires, with an
/// engine in memory. Each fails while a file it reads isn't in the repo.
struct FichaDeckFilesTests {
    let engine: Engine

    init() throws {
        let calendar = try buenosAiresCalendar()
        engine = try Engine(
            location: .inMemory, time: ManualTimeSource(now: try morning(of: 14, in: calendar)),
            ids: CountingIDSource(), calendar: calendar)
    }

    @Test(
        "each of Ficha's decks is a .ficha in the app, whose deck.json holds its emoji and its description, which the deck comes in with, and none is a zip any longer",
        .bug(id: 554), arguments: FichaDeck.allCases)
    func eachDeckIsAFichaFile(deck: FichaDeck) async throws {
        let decks = RepoText.repo.appending(path: "App/FichaDecks", directoryHint: .isDirectory)
        let file = decks.appending(path: "\(deck.fileName).ficha")
        try #require(
            FileManager.default.fileExists(atPath: file.path(percentEncoded: false)),
            "App/FichaDecks/\(deck.fileName).ficha isn't in the repo: add it, with its deck.json.")
        let names = try FileManager.default.contentsOfDirectory(atPath: decks.path(percentEncoded: false))
        let expected = ownDeckJSON(of: deck)

        try engine.addFichaDeck(try await engine.readFichaDeck(deck, at: file))
        let added = try engine.decks().first { $0.name == deck.name }

        #expect(deckJSON(inZip: file) == expected)
        #expect(added?.emoji == expected.emoji)
        #expect(added?.description == expected.description)
        #expect(names.filter { $0.hasSuffix(".zip") } == [])
    }

    // The words: the emoji of Ficha's decks, which `FichaDeck.emoji` writes in
    // the code today, and their deck.json holds once they're .ficha files:
    // 💬; 🖼, without the variation selector that follows it in 🖼️, so that
    // either spelling is found; and 💐. And the start of each one's
    // description, which deck.json alone holds, as a description written in
    // the code was built and reverted in PR #547 (#554's body). No source is
    // exempt: FichaKit's tests, which aren't sources, name them as what the
    // files hold, as this file does, and 🖼️ as any deck's emoji
    // (`DeckColorAndEmojiTests`).
    @Test(
        "FichaDeck has no emoji of its own: no Swift source writes the emoji or the description of one of Ficha's decks, which their files alone hold",
        .bug(id: 554))
    func noSourceWritesTheirEmoji() throws {
        let words = [
            "💬", "\u{1F5BC}", "💐", "40 palabras del español", "50 pinturas de 15 artistas", "30 flores y follajes",
        ]

        let found = try RepoText.lines(holding: words, in: RepoText.swiftSources())

        #expect(
            found == [],
            """
            These lines write the emoji or the description of one of Ficha's decks, which come from the deck's \
            deck.json (#554): \(found.joined(separator: ", ")). Take them out, and read them from the deck's file.
            """)
    }
}

/// What the `deck.json` of `deck`'s file holds: its emoji, as `FichaDeck.emoji`
/// wrote it, and its description, in Spanish (ADR 0040), as #554's body gives
/// it.
private func ownDeckJSON(of deck: FichaDeck) -> DeckJSON {
    switch deck {
    case .palabrasLindas:
        DeckJSON(
            emoji: "💬",
            description: """
                40 palabras del español que dan gusto: qué quieren decir y de dónde vienen.
                """)
    case .arteArgentino:
        DeckJSON(
            emoji: "\u{1F5BC}\u{FE0F}",
            description: """
                50 pinturas de 15 artistas argentinos, de 1839 a 1930, que están en museos de Buenos Aires: \
                cuál es, quién la pintó y cuándo.
                """)
    case .floresDeBuenosAires:
        DeckJSON(
            emoji: "💐",
            description: """
                30 flores y follajes de las florerías porteñas, por su foto: cómo se llaman y algo para \
                reconocerlas.
                """)
    }
}
