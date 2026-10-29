import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the Cards window's tags (ADR 0021, ADR 0022): the sidebar's
/// pinned tags, which Lucas pins, unpins and drags into his own order, All
/// Tags, with every tag as a tree and the set-aside ones in its Set Aside
/// section, what choosing a tag lists, and renaming and moving a tag with
/// Rename… and the drops in All Tags, on the default ladder.
struct CardsWindowTagsTests {
    let engine: Engine
    let ladder = ReviewSettings.defaults.ladder

    init() throws {
        let calendar = try buenosAiresCalendar()
        engine = try Engine(
            location: .inMemory, time: ManualTimeSource(now: try morning(of: 14, in: calendar)), calendar: calendar)
    }

    // historia::Roma sits inside a set-aside tag, and ciencia is set aside
    // with no card.
    @Test(
        "the sidebar lists the pinned tags alone, in their order, each by its whole path, a set-aside one grayed, and nothing at first"
    )
    func theSidebarListsThePinnedTags() throws {
        try approveCard("deuda", tags: ["economía::Argentina", "lenguaje"])
        try approveCard("Coliseo", tags: ["historia::Roma"])
        try engine.setAside("historia")
        try engine.setAside("ciencia")
        let before = openWindow().pinnedTags

        for tag in ["lenguaje", "economía::Argentina", "historia::Roma", "ciencia"] {
            try engine.pin(tag)
        }
        let window = openWindow()

        #expect(before.isEmpty)
        #expect(window.pinnedTags.map(\.title) == ["lenguaje", "economía › Argentina", "historia › Roma", "ciencia"])
        #expect(window.pinnedTags.grayed == ["historia › Roma", "ciencia"])
        #expect(window.pinnedTags.map(\.children) == [[], [], [], []])
    }

    // Every card has a type, so the Types section has no No Type.
    @Test(
        "the sidebar lists the card groups, then Inbox, then the pinned tags in their order and All Tags, then the card types"
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
                [.cards(.tag("lenguaje")), .cards(.tag("economía::Argentina")), .allTags],
                [.cards(.type(.word)), .cards(.type(.concept)), .cards(.type(.quote)), .cards(.type(.question))],
            ])
    }

    @Test("Pin to Sidebar in a tag's menu pins it after the others, and Unpin from Sidebar unpins it")
    func pinningFromATagsMenu() throws {
        try approveCard("deuda", tags: ["economía::Argentina", "lenguaje"])
        try engine.pin("lenguaje")
        var window = openWindow()
        let menuBefore = window.menu(for: "economía::Argentina")

        window.choosePin(on: "economía::Argentina")
        let afterPinning = window.pinnedTags.map(\.id)
        let menuAfter = window.menu(for: "economía::Argentina")
        window.choosePin(on: "lenguaje")

        #expect(menuBefore?.isPinned == false)
        #expect(afterPinning == ["lenguaje", "economía::Argentina"])
        #expect(menuAfter?.isPinned == true)
        #expect(window.pinnedTags.map(\.id) == ["economía::Argentina"])
        #expect(window.failure == nil)
    }

    @Test(
        "dragging a pinned tag moves it where it's dropped, and a tag dragged in from All Tags is pinned there, but a word that isn't a tag is refused"
    )
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
        let pinned = window.pinDroppedTags(["derecho"], at: 1)
        let pinnedAgain = window.pinDroppedTags(["arte"], at: 0)
        let refused = window.pinDroppedTags(["una palabra"], at: 0)

        #expect(afterMovingDown == ["biología", "ciencia", "arte"])
        #expect(afterMovingUp == ["biología", "arte", "ciencia"])
        #expect(pinned)
        #expect(pinnedAgain)
        #expect(!refused)
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
        "a tag dropped on All Tags… in the sidebar is pinned after the pinned tags, also when none is, but a word that isn't a tag is refused"
    )
    func droppingOnAllTags() throws {
        try approveCard("arte", tags: ["arte", "biología"])
        var window = openWindow()

        let pinnedFirst = window.dropOnAllTags("biología")
        let pinnedAfter = window.dropOnAllTags("arte")
        let refused = window.dropOnAllTags("una palabra")

        #expect(pinnedFirst)
        #expect(pinnedAfter)
        #expect(!refused)
        #expect(window.pinnedTags.map(\.id) == ["biología", "arte"])
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

    // No card carries ciencia, historia, arte › barroco, filosofía, geografía
    // or música, each listed for what it has of its own, and only a buried
    // card carries política. The Set Aside section holds the set-aside tags,
    // so none is grayed.
    @Test(
        "All Tags lists every tag as a tree, those of buried cards and those no card carries too, and the set-aside ones in its Set Aside section, ungrayed, one inside a tag that isn't by its whole path"
    )
    func allTagsListsEveryTag() throws {
        try approveCard("deuda", tags: ["economía::Argentina::deuda", "lenguaje"])
        try approveCard("arancel", tags: ["economía::mundial"])
        try approveCard("Coliseo", tags: ["literatura::Roma"])
        try engine.bury(try approveCard("Cabildo abierto", tags: ["política"]).id)
        try engine.setAside("economía::Argentina")
        try engine.setAside("literatura")
        try engine.setAside("ciencia")
        try engine.pin("historia")
        try engine.pin("economía::mundial")
        try engine.setColor(.blue, of: "arte::barroco")
        try engine.togglePriority(of: "filosofía")
        try engine.chooseToSync("geografía", true)
        try engine.setEmoji(Emoji("🎵"), of: "música")
        var window = openWindow()

        window.choose(.allTags)

        let allTags = try #require(window.allTagsListing)
        #expect(
            allTags.tree.outline == [
                "arte", "  barroco", "economía", "  mundial", "filosofía", "geografía", "historia", "lenguaje",
                "música",
                "política",
            ])
        #expect(
            allTags.setAside.outline == ["ciencia", "economía › Argentina", "  deuda", "literatura", "  Roma"])
        #expect(allTags.setAside[1].children.map(\.tag.name) == ["economía::Argentina::deuda"])
        #expect(allTags.tree.grayed + allTags.setAside.grayed == [])
        #expect(window.sidebarItem == .allTags)
        #expect(window.detail == .allTags)
        #expect(window.actions.isEmpty)
    }

    @Test("All Tags… in the menu bar's Prioritize submenu chooses All Tags, but not while a card is edited")
    func allTagsFromTheMenuBar() throws {
        let cepo = try approveCard("cepo", tags: ["economía::Argentina"])
        var window = openWindow()
        window.select([cepo.id])
        window.startEditing()

        window.showAllTags()
        let whileEditing = window.sidebarItem
        window.cancelEditing()
        window.showAllTags()

        #expect(whileEditing == .cards(.all))
        #expect(window.sidebarItem == .allTags)
        #expect(window.allTagsListing?.tree.outline == ["economía", "  Argentina"])
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
        #expect(window.pinnedTags.map(\.title) == ["economics › Argentina"])
        #expect(window.sidebarItem == .cards(.tag("economics::Argentina")))
        window.choose(.allTags)
        #expect(window.allTagsListing?.tree.outline == ["economics", "  Argentina"])
        #expect(try engine.cards().map(\.tags) == [["economics::Argentina"]])
    }

    @Test(
        "in All Tags, dropping a tag on another moves it inside, dropping it on the Tags title takes it to the top, and a drop inside itself is refused"
    )
    func allTagsDrops() throws {
        try approveCard("tango", tags: ["Argentina"])
        try approveCard("ahorro", tags: ["economía"])
        try approveCard("arancel", tags: ["economía::mundial::comercio"])
        var window = openWindow()
        window.choose(.allTags)

        let movedInside = window.drop("Argentina", onto: "economía")
        let outlineAfterIt = window.allTagsListing?.tree.outline
        let refused = [
            window.drop("economía", onto: "economía::mundial"), window.drop("economía", onto: "economía"),
            window.drop("economía::Argentina", onto: "economía"), window.drop("una palabra", onto: "economía"),
        ]
        let movedToTheTop = window.dropOnTagsTitle("economía::mundial")
        let refusedAtTheTop = window.dropOnTagsTitle("economía")

        #expect(movedInside)
        #expect(outlineAfterIt == ["economía", "  Argentina", "  mundial", "    comercio"])
        #expect(refused == [false, false, false, false])
        #expect(movedToTheTop)
        #expect(!refusedAtTheTop)
        #expect(window.allTagsListing?.tree.outline == ["economía", "  Argentina", "mundial", "  comercio"])
        #expect(window.failure == nil)
        #expect(try engine.cards().map(\.tags) == [["economía::Argentina"], ["economía"], ["mundial::comercio"]])
    }

    /// Opens the Cards window and reads Lucas's cards, as the window does
    /// once it listens for the reasons to read them again.
    private func openWindow() -> CardsWindowState {
        var window = engine.openCardsWindow(on: ladder)
        window.read(on: ladder)
        return window
    }

    /// Approves a capture into one word card with this front and these
    /// tags, the way refining saves cards, and returns the card.
    @discardableResult
    private func approveCard(_ front: String, tags: [String]) throws -> Card {
        try approve(card(.word, front: front, back: "Lo que quiere decir «\(front)».", tags: tags), in: engine)
    }
}

extension [CardsWindowState.ListedTag] {
    /// The rows of these tags and the tags inside them, as All Tags shows
    /// them open: each its title, two spaces in for each level it's in.
    var outline: [String] {
        flatMap { tag in [tag.title] + tag.children.outline.map { "  " + $0 } }
    }

    /// The titles of the grayed rows among these tags and the tags inside
    /// them, in the order they're listed.
    var grayed: [String] {
        flatMap { tag in (tag.isGrayed ? [tag.title] : []) + tag.children.grayed }
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

    /// What All Tags lists, its tree and its Set Aside section, while the
    /// window lists it.
    var allTagsListing: (tree: [ListedTag], setAside: [ListedTag])? {
        guard case .success(.allTags(let tree, let setAside)) = listing else {
            return nil
        }
        return (tree, setAside)
    }
}
