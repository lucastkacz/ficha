import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the Cards window's tags (ADR 0021, ADR 0022): the sidebar's
/// pinned tags, which Lucas pins, unpins and drags into his own order, what
/// choosing a tag lists, and renaming a tag with Rename…, on the default
/// ladder. All Tags has tests of its own (`CardsWindowAllTagsTests`).
struct CardsWindowTagsTests {
    let engine: Engine
    let scheduler = ReviewSettings.defaults.scheduler

    init() throws {
        let calendar = try buenosAiresCalendar()
        engine = try Engine(
            location: .inMemory, time: ManualTimeSource(now: try morning(of: 14, in: calendar)), calendar: calendar)
    }

    // ciencia has no card.
    @Test("the sidebar lists the pinned tags alone, in their order, and nothing at first")
    func theSidebarListsThePinnedTags() throws {
        try approveCard("deuda", tags: ["economía::Argentina", "lenguaje"])
        try approveCard("Coliseo", tags: ["historia::Roma"])
        let before = openWindow().pinnedTags

        for tag in ["lenguaje", "economía::Argentina", "historia::Roma", "ciencia"] {
            try engine.pin(tag)
        }
        let window = openWindow()

        #expect(before.isEmpty)
        #expect(window.pinnedTags.map(\.id) == ["lenguaje", "economía::Argentina", "historia::Roma", "ciencia"])
    }

    // Every card has a type, so the Types section has no No Type, and lives
    // in Default, which the Decks section lists alone.
    @Test(
        "the sidebar lists the card groups, then Inbox, then the decks, then the pinned tags in their order and All Tags, then the card types"
    )
    func theSidebarsItemsInOrder() throws {
        try approveCard("deuda", tags: ["economía::Argentina", "lenguaje"])
        try engine.pin("lenguaje")
        try engine.pin("economía::Argentina")

        let window = openWindow()

        #expect(
            window.sidebarSections.map(\.items) == [
                [.cards(.all), .cards(.new), .cards(.due), .cards(.learned), .cards(.flagged), .cards(.buried)],
                [.inbox],
                [.cards(.deck(Deck.defaultName))],
                [.cards(.tag("lenguaje")), .cards(.tag("economía::Argentina")), .allTags],
                [.cards(.type(.word)), .cards(.type(.concept)), .cards(.type(.quote)), .cards(.type(.question))],
            ])
    }

    @Test("Pin to Sidebar in a tag's menu pins it after the others, and Unpin from Sidebar unpins it")
    func pinningFromATagsMenu() throws {
        try approveCard("deuda", tags: ["economía::Argentina", "lenguaje"])
        try engine.pin("lenguaje")
        var window = openWindow()
        let menuBefore = window.menu(for: ["economía::Argentina"])

        window.choosePin(on: ["economía::Argentina"])
        let afterPinning = window.pinnedTags.map(\.id)
        let menuAfter = window.menu(for: ["economía::Argentina"])
        window.choosePin(on: ["lenguaje"])

        #expect(menuBefore?.isPinned == false)
        #expect(afterPinning == ["lenguaje", "economía::Argentina"])
        #expect(menuAfter?.isPinned == true)
        #expect(window.pinnedTags.map(\.id) == ["economía::Argentina"])
        #expect(window.failure == nil)
    }

    @Test("dragging a pinned tag moves it where it's dropped, and a tag dragged in from All Tags is pinned there")
    func theSidebarsDrops() throws {
        for tag in ["arte", "biología", "ciencia"] {
            try approveCard(tag, tags: [tag, "derecho"])
            try engine.pin(tag)
        }
        var window = openWindow()

        window.movePinnedTags(fromOffsets: [0], toOffset: 3)
        let afterMovingDown = window.pinnedTags.map(\.id)
        window.movePinnedTags(fromOffsets: [2], toOffset: 1)
        let afterMovingUp = window.pinnedTags.map(\.id)
        let pinned = window.dragFromAllTags(["derecho"]) { $0.pinDraggedTags(at: 1) }
        let pinnedAgain = window.dragFromAllTags(["arte"]) { $0.pinDraggedTags(at: 0) }

        #expect(afterMovingDown == ["biología", "ciencia", "arte"])
        #expect(afterMovingUp == ["biología", "arte", "ciencia"])
        #expect(pinned)
        #expect(pinnedAgain)
        #expect(window.pinnedTags.map(\.id) == ["arte", "biología", "derecho", "ciencia"])
        #expect(try engine.pinnedTags().map(\.name) == ["arte", "biología", "derecho", "ciencia"])
        #expect(window.failure == nil)
    }

    // Moving the first and the third to the end, as a drag of several rows
    // would.
    @Test("dragging several pinned tags at once keeps them in their order where they're dropped")
    func movingSeveralPinnedTags() throws {
        for tag in ["arte", "biología", "ciencia", "derecho"] {
            try engine.pin(tag)
        }
        var window = openWindow()

        window.movePinnedTags(fromOffsets: [0, 2], toOffset: 4)

        #expect(window.pinnedTags.map(\.id) == ["biología", "derecho", "arte", "ciencia"])
        #expect(try engine.pinnedTags().map(\.name) == ["biología", "derecho", "arte", "ciencia"])
    }

    // With nothing pinned, the pinned tags have no row to drop between.
    @Test(
        "a tag dragged from All Tags onto All Tags… in the sidebar is pinned after the pinned tags, also when none is")
    func droppingOnAllTags() throws {
        try approveCard("arte", tags: ["arte", "biología"])
        var window = openWindow()

        let pinnedFirst = window.dragFromAllTags(["biología"]) { $0.dropDraggedTagsOnAllTags() }
        let pinnedAfter = window.dragFromAllTags(["arte"]) { $0.dropDraggedTagsOnAllTags() }

        #expect(pinnedFirst)
        #expect(pinnedAfter)
        #expect(window.pinnedTags.map(\.id) == ["biología", "arte"])
    }

    // Text dragged in from another app, or from elsewhere in Ficha, such as
    // a tag's name in a card's tags, is dropped while Lucas drags nothing
    // from All Tags.
    @Test(
        "text dragged in from elsewhere pins no tag, even one it names, among the pinned tags or on All Tags…, nor once a drag from All Tags ended"
    )
    func textDraggedFromElsewhere() throws {
        try approveCard("arte", tags: ["arte", "biología"])
        try engine.pin("arte")
        var window = openWindow()

        let amongThePinned = window.pinDraggedTags(at: 0)
        let onAllTags = window.dropDraggedTagsOnAllTags()
        window.startDraggingTags(["biología"])
        window.stopDraggingTags()
        let afterADragFromAllTags = window.dropDraggedTagsOnAllTags()

        #expect(!amongThePinned)
        #expect(!onAllTags)
        #expect(!afterADragFromAllTags)
        #expect(window.pinnedTags.map(\.id) == ["arte"])
        #expect(window.failure == nil)
    }

    // Another device unpinned arte after the window read the pinned tags.
    @Test("dragging a pinned tag that was unpinned meanwhile moves nothing, and the window says why")
    func draggingATagUnpinnedMeanwhile() throws {
        for tag in ["arte", "biología", "ciencia"] {
            try engine.pin(tag)
        }
        var window = openWindow()
        try engine.unpin("arte")

        window.movePinnedTags(fromOffsets: [0], toOffset: 3)

        #expect(window.failure?.action == .reorderPinned(tag: "arte"))
        #expect(window.failure?.error == .tagNotPinned("arte"))
        #expect(try engine.pinnedTags().map(\.name) == ["biología", "ciencia"])
    }

    @Test(
        "choosing a pinned parent lists its cards and those of the tags inside it, and choosing a tag inside it only its own"
    )
    func choosingAPinnedParentListsItsChildrensCards() throws {
        let ahorro = try approveCard("ahorro", tags: ["economía"])
        let cepo = try approveCard("cepo", tags: ["economía::Argentina"])
        let deuda = try approveCard("deuda", tags: ["economía::Argentina::deuda"])
        try approveCard("economista", tags: ["economíaX"])
        try engine.pin("economía")
        try engine.pin("economía::Argentina")
        var window = openWindow()

        window.choose(.cards(.tag(try #require(window.pinnedTags.first).id)))
        let parentsCards = window.listedCardIDs
        window.choose(.cards(.tag("economía::Argentina")))

        #expect(parentsCards == [ahorro.id, cepo.id, deuda.id])
        #expect(window.listedCardIDs == [cepo.id, deuda.id])
    }

    @Test(
        "Rename… asks for the tag's whole name, refuses a blank one or one inside itself, and OK renames it, with the sidebar following it"
    )
    func renameAsksForTheWholeName() throws {
        try approveCard("cepo", tags: ["economía::Argentina"])
        try engine.pin("economía::Argentina")
        var window = openWindow()
        window.choose(.cards(.tag("economía::Argentina")))

        window.askToRename("economía")
        #expect(window.question == .renameTag(CardTag(name: "economía")))
        #expect(window.renameEntry("economía::Argentina::economía") == .refused(.tagInsideItself("economía")))
        #expect(window.renameEntry(" :: ") == .refused(.blankTagName))
        #expect(window.renameEntry(" economics ") == .name("economics"))
        window.chooseNewName("economía::otra")
        #expect(window.question == .renameTag(CardTag(name: "economía")))
        window.chooseNewName("economics")

        #expect(window.question == nil)
        #expect(window.failure == nil)
        #expect(window.pinnedTags.map(\.id) == ["economics::Argentina"])
        #expect(window.sidebarItem == .cards(.tag("economics::Argentina")))
        window.choose(.allTags)
        #expect(window.allTagsRows?.outline == ["economics", "  Argentina"])
        #expect(try engine.cards().map(\.tags) == [["economics::Argentina"]])
    }

    /// Opens the Cards window and reads Lucas's cards, as the window does
    /// once it listens for the reasons to read them again.
    private func openWindow() -> CardsWindowState {
        var window = engine.openCardsWindow(with: scheduler)
        window.read(with: scheduler)
        return window
    }

    /// Approves a capture into one word card with this front and these
    /// tags, the way refining saves cards, and returns the card.
    @discardableResult
    private func approveCard(_ front: String, tags: [String]) throws -> Card {
        try approve(card(.word, front: front, back: "Lo que quiere decir «\(front)».", tags: tags), in: engine)
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
