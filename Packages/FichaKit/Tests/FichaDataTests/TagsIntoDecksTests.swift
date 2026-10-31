import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on turning tags into decks (ADR 0024), which Lucas does once, with
/// the `ficha` CLI, for the tags that were his subjects before decks: each
/// tag of a list, in its order, and each tag inside it, becomes a deck of the
/// same whole name, and the cards in Default that carry one move there. They
/// start at 9 in the morning in Buenos Aires, on an engine in memory, or on a
/// database from before decks, whose tags kept their switches and choices to
/// sync.
struct TagsIntoDecksTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    /// A data folder of the test's own, for a database from before decks.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaTagsIntoDecksTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    // historia::Grecia::Atenas is the deepest of acrópolis's tags, and
    // lenguaje isn't in the list.
    @Test(
        "a tag and each tag inside it become decks of the same whole names, and each card in Default that carries one moves to the deepest one's deck and loses the tags its deck now says"
    )
    func tagsBecomeDecks() throws {
        try approveInDeck("Coliseo", tags: ["historia::Roma", "lenguaje"], in: engine)
        try approveInDeck("Partenón", tags: ["historia::Grecia", "historia"], in: engine)
        try approveInDeck("acrópolis", tags: ["historia::Grecia::Atenas", "historia::Grecia"], in: engine)
        try approveInDeck("petricor", tags: ["lenguaje"], in: engine)

        try engine.convertTagsToDecks(["historia"])

        #expect(
            try engine.decks().map(\.name) == [
                Deck.defaultName, "historia", "historia::Grecia", "historia::Grecia::Atenas", "historia::Roma",
            ])
        #expect(
            try engine.cards().map(\.deck) == [
                "historia::Roma", "historia::Grecia", "historia::Grecia::Atenas", Deck.defaultName,
            ])
        #expect(try engine.cards().map(\.tags) == [["lenguaje"], [], [], ["lenguaje"]])
        #expect(try engine.allTags().map(\.name) == ["lenguaje"])
    }

    // historia isn't in the list, so the Coliseo keeps it, and it stays a tag.
    @Test("a card loses the listed tag and the tags inside it it carries, never one above the listed tag")
    func aTagAboveTheListedOneStays() throws {
        try approveInDeck("Coliseo", tags: ["historia", "historia::Roma"], in: engine)

        try engine.convertTagsToDecks(["historia::Roma"])

        let coliseo = try #require(try engine.cards().only)
        #expect(coliseo.deck == "historia::Roma")
        #expect(coliseo.tags == ["historia"])
        #expect(try engine.allTags().map(\.name) == ["historia"])
    }

    // Martín Fierro carries two tags of the list; cepo carries two tags of
    // economía, neither inside the other; Facundo was moved to Libros before.
    @Test(
        "a card an earlier tag of the list moved out of Default keeps a later one as a tag, as does a card in another deck, and one with two tags of one tag goes to the first in tree order",
        arguments: [["literatura", "historia", "economía"], ["historia", "literatura", "economía"]])
    func theListsOrderDecides(list: [String]) throws {
        try approveInDeck("Martín Fierro", tags: ["literatura::poesía", "historia"], in: engine)
        try approveInDeck("Facundo", deck: "Libros", tags: ["historia", "literatura"], in: engine)
        try approveInDeck("cepo", tags: ["economía::Brasil", "economía::Argentina"], in: engine)
        try approveInDeck("Rosas", tags: ["historia"], in: engine)

        try engine.convertTagsToDecks(list)

        let literatureFirst = list.first == "literatura"
        #expect(
            try engine.cards().map(\.deck) == [
                literatureFirst ? "literatura::poesía" : "historia", "Libros", "economía::Argentina", "historia",
            ])
        #expect(
            try engine.cards().map(\.tags) == [
                literatureFirst ? ["historia"] : ["literatura::poesía"], ["historia", "literatura"],
                ["economía::Brasil"], [],
            ])
        #expect(
            try engine.decks().map(\.name) == [
                "economía", "economía::Argentina", "economía::Brasil", "historia", "Libros", "literatura",
                "literatura::poesía",
            ])
    }

    @Test(
        "the preview lists the decks the conversion would make, how many cards each gets, and the cards with two tags that become decks, with the deck each goes to, changing nothing"
    )
    func thePreviewChangesNothing() throws {
        let fierro = try approveInDeck("Martín Fierro", tags: ["literatura::poesía", "historia"], in: engine)
        let facundo = try approveInDeck("Facundo", tags: ["historia", "literatura"], in: engine)
        try approveInDeck("Rosas", tags: ["historia"], in: engine)
        let cepo = try approveInDeck("cepo", tags: ["economía::Brasil", "economía::Argentina"], in: engine)
        try engine.setColor(.green, of: "historia")
        let cards = try engine.cards()
        let tags = try engine.allTags()

        let preview = try engine.conversion(ofTags: ["historia", "economía"])

        #expect(preview.decks.map(\.name) == ["economía", "economía::Argentina", "economía::Brasil", "historia"])
        #expect(preview.decks.map(\.cards) == [0, 1, 0, 3])
        let twoTags = try #require(preview.cardsWithTwoTags.only)
        #expect(twoTags.id == cepo.id)
        #expect(twoTags.front == "cepo")
        #expect(twoTags.tags == ["economía::Brasil", "economía::Argentina"])
        #expect(twoTags.deck == "economía::Argentina")
        #expect(try engine.cards() == cards)
        #expect(try engine.allTags() == tags)
        #expect(try engine.decks().map(\.name) == [Deck.defaultName])
        #expect(
            try engine.conversion(ofTags: ["literatura", "historia"]).cardsWithTwoTags.map(\.id) == [
                fierro.id, facundo.id,
            ])
    }

    // Before decks, ciencia was set aside and blue, historia a priority tag
    // with an emoji, chosen to sync, and lenguaje chosen to sync; Lucas pins
    // two of them after the update. Coliseo, which historia::Roma moves
    // first, keeps lenguaje as a tag.
    @Test(
        "each tag's switch, color, emoji and choice to sync from before decks go to its deck, its row goes with its pin, and its cards stand as its deck says"
    )
    func whatATagHadGoesToItsDeck() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try saveDatabaseBeforeDecks(at: folder.appending(path: "Ficha.sqlite"), at: time.now)
        let engine = try Engine(location: .folder(folder), time: time, calendar: calendar)
        try engine.pin(["historia", "ciencia"])

        try engine.convertTagsToDecks(["ciencia", "historia", "lenguaje"])

        #expect(
            try engine.decks() == [
                Deck(name: "ciencia", switchedOn: .setAside, color: .blue),
                Deck(name: "historia", switchedOn: .priority, emoji: "📜", chosenToSync: true),
                Deck(name: "historia::Roma", inheritedEmoji: "📜"),
                Deck(name: "lenguaje", chosenToSync: true),
            ])
        #expect(try engine.cards().map(\.front) == ["Coliseo", "ADN"])
        #expect(try engine.cards().map(\.deck) == ["historia::Roma", "ciencia"])
        #expect(try engine.cards().map(\.tags) == [["lenguaje"], []])
        #expect(try engine.cards().map(\.setAsideBy) == [nil, ["ciencia"]])
        #expect(try engine.allTags() == [CardTag(name: "lenguaje")])
    }

    // Before decks, historia and lenguaje were chosen to sync and ciencia
    // wasn't; Lenguas, a deck that's there already, was chosen too.
    // historia::Roma isn't chosen itself: its cards sync as historia's do.
    @Test(
        "the preview says whether each deck it would make will be chosen to sync, as it or its tag was, so that the cards that would leave iCloud show before the run"
    )
    func thePreviewSaysWhichDecksWillBeChosenToSync() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try saveDatabaseBeforeDecks(at: folder.appending(path: "Ficha.sqlite"), at: time.now)
        let engine = try Engine(location: .folder(folder), time: time, calendar: calendar)
        try engine.setChosenToSync(true, ofDeck: "Lenguas")
        try engine.create(card(.word, front: "saudade", back: "Nostalgia.", tags: ["Lenguas"]))

        let preview = try engine.conversion(ofTags: ["ciencia", "historia", "Lenguas"])
        try engine.convertTagsToDecks(["ciencia", "historia", "Lenguas"])

        #expect(preview.decks.map(\.name) == ["ciencia", "historia", "historia::Roma", "Lenguas"])
        #expect(preview.decks.map(\.chosenToSync) == [false, true, false, true])
        #expect(try engine.decks().filter(\.chosenToSync).map(\.name) == ["historia", "Lenguas"])
    }

    // historia comes first and would convert alone, but the write is one.
    @Test("a tag whose deck would take Default's name is refused, in the preview too, and nothing changes")
    func aTagNamedLikeDefaultIsRefused() throws {
        try approveInDeck("Coliseo", tags: ["historia"], in: engine)
        try approveInDeck("pendientes", tags: ["default::pendientes"], in: engine)

        #expect(throws: EngineError.defaultDeckName("default")) {
            try engine.conversion(ofTags: ["historia", "default"])
        }
        #expect(throws: EngineError.defaultDeckName("default")) {
            try engine.convertTagsToDecks(["historia", "default"])
        }
        #expect(try engine.cards().map(\.deck) == [Deck.defaultName, Deck.defaultName])
        #expect(try engine.allTags().map(\.name) == ["default", "default::pendientes", "historia"])
    }
}
