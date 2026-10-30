import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on a deck's tags in the Cards window (ADR 0024): the row above the
/// card list while the sidebar chose a deck, with each tag its cards carry
/// and how many do, the most first, the ones that fit and "+N more" for the
/// rest, and one of them chosen at a time, which narrows the list to the
/// deck's cards that carry it, on the default ladder.
struct CardsWindowDeckTagsTests {
    let engine: Engine
    let ladder = ReviewSettings.defaults.ladder

    init() throws {
        let calendar = try buenosAiresCalendar()
        engine = try Engine(
            location: .inMemory, time: ManualTimeSource(now: try morning(of: 14, in: calendar)), calendar: calendar)
    }

    @Test(
        "choosing a deck shows its tags with how many of its cards carry each, most first, and anything else shows none"
    )
    func choosingADeckShowsItsTags() throws {
        try approveInDeck("Revolución de Mayo", deck: "Historia", tags: ["argentina::Mayo", "política"], in: engine)
        try approveInDeck("Senado", deck: "Historia::Roma", tags: ["política"], in: engine)
        try approveInDeck("Gioconda", deck: "Arte", tags: ["renacimiento"], in: engine)
        try engine.setColor(.blue, of: "política")
        var window = openWindow()
        #expect(window.deckTags.isEmpty)

        window.choose(.cards(.deck("Historia")))

        #expect(window.deckTags.map(\.id) == ["política", "argentina", "argentina::Mayo"])
        #expect(window.deckTags.map(\.cards) == [2, 1, 1])
        #expect(window.deckTags.first?.tag == CardTag(name: "política", color: .blue))
        window.choose(.cards(.tag("política")))
        #expect(window.deckTags.isEmpty)
    }

    @Test(
        "a tag chosen in the row lists only the deck's cards that carry it or a tag inside it, with the search, and choosing it again lists them all"
    )
    func aChosenTagNarrowsTheDecksCards() throws {
        let mayo = try approveInDeck("Mayo", deck: "Historia", tags: ["argentina::Mayo", "política"], in: engine)
        let julio = try approveInDeck("Julio", deck: "Historia", tags: ["argentina::Independencia"], in: engine)
        let senado = try approveInDeck("Senado", deck: "Historia::Roma", tags: ["política"], in: engine)
        try approveInDeck("Gioconda", deck: "Arte", tags: ["argentina"], in: engine)
        var window = openWindow()
        window.choose(.cards(.deck("Historia")))

        window.chooseDeckTag("argentina")
        #expect(window.chosenDeckTag == "argentina")
        #expect(window.listedCardIDs == [mayo.id, julio.id])
        window.search(for: "Julio")
        #expect(window.listedCardIDs == [julio.id])
        window.search(for: "")
        window.chooseDeckTag("política")
        #expect(window.listedCardIDs == [mayo.id, senado.id])
        window.chooseDeckTag("política")

        #expect(window.chosenDeckTag == nil)
        #expect(window.listedCardIDs == [mayo.id, julio.id, senado.id])
        window.chooseDeckTag("renacimiento")
        #expect(window.chosenDeckTag == nil)
    }

    @Test("another deck, or the deck's cards losing the chosen tag, clears it, and the deck lists all its cards again")
    func theChosenTagClears() throws {
        let mayo = try approveInDeck("Mayo", deck: "Historia", tags: ["argentina"], in: engine)
        let senado = try approveInDeck("Senado", deck: "Historia", tags: ["política"], in: engine)
        try approveInDeck("Gioconda", deck: "Arte", tags: ["argentina"], in: engine)
        var window = openWindow()
        window.choose(.cards(.deck("Historia")))
        window.chooseDeckTag("argentina")

        window.choose(.cards(.deck("Arte")))
        #expect(window.chosenDeckTag == nil)
        window.choose(.cards(.deck("Historia")))
        window.chooseDeckTag("argentina")
        window.select([mayo.id])
        window.askToChangeDeck()
        window.chooseInDeckChange("Arte")
        window.changeDeck()

        #expect(window.chosenDeckTag == nil)
        #expect(window.deckTags.map(\.id) == ["política"])
        #expect(window.listedCardIDs == [senado.id])
    }

    // A pinned tag's menu in the sidebar renames it while the deck stays
    // chosen.
    @Test("a chosen tag renamed meanwhile stays chosen by its new name")
    func aChosenTagRenamedStaysChosen() throws {
        let mayo = try approveInDeck("Mayo", deck: "Historia", tags: ["argentina"], in: engine)
        try approveInDeck("Senado", deck: "Historia", tags: ["política"], in: engine)
        var window = openWindow()
        window.choose(.cards(.deck("Historia")))
        window.chooseDeckTag("argentina")

        window.askToRename("argentina")
        window.chooseNewName("patria")

        #expect(window.chosenDeckTag == "patria")
        #expect(window.listedCardIDs == [mayo.id])
    }

    // The window's width decides how many fit, which only the view knows: it
    // shows the first row that fits.
    @Test(
        "the row shows the tags that fit and lists the rest in +N more, the chosen one always shown, in the last place that fits"
    )
    func theTagsThatFitAndMore() throws {
        try approveInDeck("Mayo", deck: "Historia", tags: ["a", "b", "c", "d"], in: engine)
        try approveInDeck("Julio", deck: "Historia", tags: ["a", "b", "c"], in: engine)
        try approveInDeck("Senado", deck: "Historia", tags: ["a", "b"], in: engine)
        try approveInDeck("Cónsul", deck: "Historia", tags: ["a"], in: engine)
        var window = openWindow()
        window.choose(.cards(.deck("Historia")))

        #expect(
            window.deckTagsRows.map { $0.shown.map(\.id) } == [
                ["a", "b", "c", "d"], ["a", "b", "c"], ["a", "b"], ["a"], [],
            ])
        #expect(
            window.deckTagsRows.map { $0.more.map(\.id) } == [
                [], ["d"], ["c", "d"], ["b", "c", "d"], ["a", "b", "c", "d"],
            ])

        window.chooseDeckTag("d")

        #expect(
            window.deckTagsRows.map { $0.shown.map(\.id) } == [
                ["a", "b", "c", "d"], ["a", "b", "d"], ["a", "d"], ["d"], [],
            ])
        #expect(
            window.deckTagsRows.map { $0.more.map(\.id) } == [
                [], ["c"], ["b", "c"], ["a", "b", "c"], ["a", "b", "c", "d"],
            ])
        window.choose(.cards(.all))
        #expect(window.deckTagsRows.isEmpty)
    }

    // An Anki package can bring hundreds of tags into one deck: the view
    // tries each row until one fits, so the state offers a few rows, not
    // hundreds.
    @Test("the row offers at most 15 tags, however wide the window, and +N more lists the rest")
    func theRowOffersAtMostFifteenTags() throws {
        let tags = (1...20).map { "t\($0 < 10 ? "0" : "")\($0)" }
        try approveInDeck("Mayo", deck: "Historia", tags: tags, in: engine)
        var window = openWindow()
        window.choose(.cards(.deck("Historia")))

        #expect(window.deckTagsRows.count == 16)
        #expect(window.deckTagsRows.first?.shown.map(\.id) == Array(tags.prefix(15)))
        #expect(window.deckTagsRows.first?.more.map(\.id) == ["t16", "t17", "t18", "t19", "t20"])
        #expect(window.deckTagsRows.last?.shown.isEmpty == true)
        #expect(window.deckTagsRows.last?.more.map(\.id) == tags)

        window.chooseDeckTag("t20")

        #expect(window.deckTagsRows.first?.shown.map(\.id) == Array(tags.prefix(14)) + ["t20"])
        #expect(window.deckTagsRows.first?.more.map(\.id) == ["t15", "t16", "t17", "t18", "t19"])
    }

    private func openWindow() -> CardsWindowState {
        var window = engine.openCardsWindow(on: ladder)
        window.read(on: ladder)
        return window
    }
}

extension CardsWindowState {
    /// The ids of the cards the table lists, in the order the engine read
    /// them, or nil when it lists the inbox or couldn't read them.
    fileprivate var listedCardIDs: [Int64]? {
        guard case .success(.cards(let rows)) = listing else {
            return nil
        }
        return rows.map(\.id)
    }
}
