import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on All Tags in the Cards window (ADR 0022): every tag as a tree,
/// with its cards and due cards, sorted by a column, narrowed by a search,
/// several tags selected and acted on at once from one menu, Delete… and
/// Clear Unused Tags with their questions, the drops onto a tag and between
/// rows, and a tag's cards listed in All Tags' place, with Back, on the
/// default scheduler.
struct CardsWindowAllTagsTests {
    let time: ManualTimeSource
    let engine: Engine
    let scheduler = ReviewSettings.defaults.scheduler

    init() throws {
        let calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
    }

    // arte::barroco and geografía have a color, filosofía an emoji,
    // historia is pinned, ciencia and música have emoji, and no card
    // carries them; a buried card carries política, which lists no card.
    // deuda and arancel are due, and Coliseo is due but in a set-aside deck.
    @Test(
        "All Tags lists every tag as a tree, alphabetical per level, each with its cards and due cards, none of a set-aside deck's due"
    )
    func allTagsListsEveryTag() throws {
        let deuda = try approveCard("deuda", tags: ["economía::Argentina::deuda", "lenguaje"])
        let arancel = try approveCard("arancel", tags: ["economía::mundial"])
        let coliseo = try approveCard("Coliseo", tags: ["literatura::Roma"])
        try approveCard("cepo", tags: ["economía::Argentina"])
        try engine.bury(try approveCard("Cabildo abierto", tags: ["política"]).id)
        for card in [deuda, arancel, coliseo] {
            try engine.meet(card)
        }
        time.advance(by: hours(1))
        try engine.changeDeck(of: [coliseo.id], to: "Literatura")
        try engine.setAside(deck: "Literatura")
        try engine.setEmoji(Emoji("🔭"), of: "ciencia")
        try engine.pin("historia")
        try engine.setColor(.blue, of: "arte::barroco")
        try engine.setEmoji(Emoji("🦉"), of: "filosofía")
        try engine.setColor(.green, of: "geografía")
        try engine.setEmoji(Emoji("🎵"), of: "música")
        var window = openWindow()

        window.choose(.allTags)

        let rows = try #require(window.allTagsRows)
        #expect(
            rows.outline == [
                "arte", "  barroco", "ciencia", "economía", "  Argentina", "    deuda", "  mundial", "filosofía",
                "geografía", "historia", "lenguaje", "literatura", "  Roma", "música", "política",
            ])
        #expect(
            rows.counted == [
                "arte 0/0", "barroco 0/0", "ciencia 0/0", "economía 3/2", "Argentina 2/1", "deuda 1/1",
                "mundial 1/1", "filosofía 0/0", "geografía 0/0", "historia 0/0", "lenguaje 1/1", "literatura 1/0",
                "Roma 1/0", "música 0/0", "política 0/0",
            ])
        #expect(window.sidebarItem == .allTags)
        #expect(window.detail == .allTags(selected: []))
        #expect(window.actions.isEmpty)
    }

    // arte has two due cards, economía one and three cards in all, so Due
    // and Cards put them in different orders; ciencia and economía tie on
    // Pinned, and stay alphabetical.
    @Test("a click on a column's title sorts each level of the tree by it, either way, alphabetically between ties")
    func sortingByAColumn() throws {
        let barroco = try approveCard("Las meninas", tags: ["arte::barroco"])
        let gotico = try approveCard("Notre-Dame", tags: ["arte::gótico"])
        try approveCard("La Gioconda", tags: ["arte::renacimiento"])
        let cepo = try approveCard("cepo", tags: ["economía::Argentina"])
        try approveCard("arancel", tags: ["economía::mundial"])
        try approveCard("deuda", tags: ["economía::Argentina"])
        try approveCard("átomo", tags: ["ciencia"])
        for card in [barroco, gotico, cepo] {
            try engine.meet(card)
        }
        time.advance(by: hours(1))
        try engine.pin("economía")
        try engine.pin("ciencia")
        var window = openWindow()
        window.choose(.allTags)
        let alphabetical = window.allTagsRows?.outline

        window.sortAllTags(by: .due, ascending: false)
        let mostDueFirst = window.allTagsRows?.counted
        window.sortAllTags(by: .cards, ascending: true)
        let fewestCardsFirst = window.allTagsRows?.counted
        window.sortAllTags(by: .pinned, ascending: false)
        let pinnedFirst = window.allTagsRows?.outline
        window.sortAllTags(by: .tag, ascending: false)

        #expect(
            alphabetical == [
                "arte", "  barroco", "  gótico", "  renacimiento", "ciencia", "economía", "  Argentina", "  mundial",
            ])
        #expect(
            mostDueFirst == [
                "arte 3/2", "barroco 1/1", "gótico 1/1", "renacimiento 1/0", "economía 3/1", "Argentina 2/1",
                "mundial 1/0", "ciencia 1/0",
            ])
        #expect(
            fewestCardsFirst == [
                "ciencia 1/0", "arte 3/2", "barroco 1/1", "gótico 1/1", "renacimiento 1/0", "economía 3/1",
                "mundial 1/0", "Argentina 2/1",
            ])
        #expect(
            pinnedFirst == [
                "ciencia", "economía", "  Argentina", "  mundial", "arte", "  barroco", "  gótico", "  renacimiento",
            ])
        #expect(
            window.allTagsRows?.outline == [
                "economía", "  mundial", "  Argentina", "ciencia", "arte", "  renacimiento", "  gótico", "  barroco",
            ])
        #expect(window.allTagsSort == CardsWindowState.AllTagsSort(column: .tag, isAscending: false))
        #expect(CardsWindowState.AllTagsColumn.allCases.filter(\.sortsDescendingFirst) == [.cards, .due, .pinned])
    }

    // The search's "arg" is in Argentina and in historia's argentina, and
    // in no parent's own name.
    @Test(
        "the search keeps each tag whose name mentions it with the tags it sits inside, every parent open until Lucas closes one"
    )
    func searchingKeepsEachMatchWithItsParents() throws {
        try approveCard("cepo", tags: ["economía::Argentina::cepo", "economía::mundial"])
        try approveCard("Cabildo", tags: ["historia::argentina", "lenguaje"])
        var window = openWindow()
        window.choose(.allTags)
        let closedAtFirst = ["economía", "economía::Argentina", "historia"].filter(window.isOpen)

        window.search(for: "arg")
        let found = window.allTagsRows?.outline
        let openWhileSearching = ["economía", "economía::Argentina", "historia"].filter(window.isOpen)
        window.setOpen(false, "historia")
        let afterClosingOne = ["economía", "historia"].filter(window.isOpen)
        window.search(for: "")

        #expect(closedAtFirst == [])
        #expect(found == ["economía", "  Argentina", "historia", "  argentina"])
        #expect(openWhileSearching == ["economía", "economía::Argentina", "historia"])
        #expect(afterClosingOne == ["economía"])
        #expect(
            window.allTagsRows?.outline == [
                "economía", "  Argentina", "    cepo", "  mundial", "historia", "  argentina", "lenguaje",
            ])
        #expect(["economía", "historia"].filter(window.isOpen) == [])
    }

    @Test("the parents Lucas opens stay open while the window is, after he chooses another group and All Tags again")
    func openParentsStayOpen() throws {
        try approveCard("cepo", tags: ["economía::Argentina::cepo", "historia::argentina"])
        var window = openWindow()
        window.choose(.allTags)

        window.setOpen(true, "economía")
        window.setOpen(true, "economía::Argentina")
        window.setOpen(true, "historia")
        window.setOpen(false, "historia")
        window.choose(.cards(.due))
        window.choose(.allTags)

        #expect(
            ["economía", "economía::Argentina", "historia"].filter(window.isOpen) == [
                "economía", "economía::Argentina",
            ])
    }

    // historia and lenguaje are pinned and blue; filosofía isn't pinned.
    @Test(
        "a tag's menu acts on every selected tag when it's opened on one of them, with Rename… and Emoji… off, and on that tag alone otherwise"
    )
    func theMenuForSeveralTags() throws {
        try approveCard("ubuntu", tags: ["filosofía", "historia", "lenguaje"])
        try engine.pin(["historia", "lenguaje"])
        try engine.setColor(.blue, of: ["historia", "lenguaje"])
        var window = openWindow()
        window.choose(.allTags)

        window.selectTags(["historia", "lenguaje"])
        let actedOnSelected = window.tagsActedOn(clicking: "lenguaje")
        let actedOnOther = window.tagsActedOn(clicking: "filosofía")
        let both = try #require(window.menu(for: actedOnSelected))
        let lenguaje = try #require(window.menu(for: ["lenguaje"]))
        let mixed = try #require(window.menu(for: ["filosofía", "lenguaje"]))

        #expect(actedOnSelected == ["historia", "lenguaje"])
        #expect(actedOnOther == ["filosofía"])
        #expect(both.isPinned && !both.isForOneTag)
        #expect(both.colorItems.filter(\.isTicked).map(\.color) == [.blue])
        #expect(lenguaje.isForOneTag && lenguaje.isPinned)
        #expect(!mixed.isPinned)
        #expect(mixed.colorItems.filter(\.isTicked).isEmpty)
        #expect(window.detail == .allTags(selected: try engine.allTags().filter { $0.name != "filosofía" }))
    }

    @Test("choosing an item of the menu for several tags pins and colors them all at once")
    func choosingForSeveralTags() throws {
        try approveCard("ubuntu", tags: ["arte", "filosofía", "historia", "lenguaje"])
        try engine.pin("historia")
        var window = openWindow()
        window.choose(.allTags)
        let several = ["lenguaje", "filosofía", "historia"]

        window.choosePin(on: several)
        let pinned = window.pinnedTags.map(\.id)
        window.choosePin(on: several)
        let unpinned = window.pinnedTags.map(\.id)
        window.chooseColor(.green, on: ["arte", "lenguaje"])

        #expect(pinned == ["historia", "filosofía", "lenguaje"])
        #expect(unpinned == [])
        #expect(try engine.allTags().filter { $0.color == .green }.map(\.name) == ["arte", "lenguaje"])
        #expect(window.failure == nil)
    }

    // A tag only labels its cards (ADR 0024): Set Aside and Prioritize are
    // a deck's, so All Tags has no columns for them.
    @Test("All Tags' columns are the tag, Cards, Due and Pinned, whose checkbox pins and unpins its tag")
    func thePinnedCheckbox() throws {
        try approveCard("ubuntu", tags: ["filosofía", "historia"])
        var window = openWindow()
        window.choose(.allTags)

        window.tickPinned(true, on: "historia")
        let afterTicking = window.pinnedTags.map(\.id)
        window.tickPinned(false, on: "historia")

        #expect(CardsWindowState.AllTagsColumn.allCases == [.tag, .cards, .due, .pinned])
        #expect(afterTicking == ["historia"])
        #expect(window.pinnedTags.isEmpty)
        #expect(try engine.allTags() == [CardTag(name: "filosofía"), CardTag(name: "historia")])
        #expect(window.failure == nil)
    }

    // Martín Fierro and El Aleph carry literatura or a tag inside it.
    // historia stays.
    @Test(
        "Delete… on the selected tags asks first, with the cards that lose them and the tags inside, and OK deletes them"
    )
    func deleteAsksFirst() throws {
        try approveCard("Martín Fierro", tags: ["literatura::poesía", "historia"])
        try approveCard("El Aleph", tags: ["literatura"])
        try approveCard("Facundo", tags: ["política", "historia"])
        var window = openWindow()
        window.choose(.allTags)
        let offeredWithNothingSelected = window.tagActions

        window.selectTags(["literatura", "política"])
        let offered = window.tagActions
        window.askToDeleteSelectedTags()
        let question = window.question
        window.cancelQuestion()
        window.askToDeleteTags(window.tagsActedOn(clicking: "literatura"))
        guard case .deleteTags(let deletion)? = window.question else {
            Issue.record("Delete… asked nothing")
            return
        }
        window.deleteTags(deletion)

        #expect(offeredWithNothingSelected == [])
        #expect(offered == [.delete])
        #expect(question == .deleteTags(deletion))
        #expect(deletion.tags == ["literatura", "política"])
        #expect(deletion.tagsInside == ["literatura::poesía"])
        #expect(deletion.cards == 3)
        #expect(window.question == nil)
        #expect(window.failure == nil)
        #expect(window.allTagsRows?.outline == ["historia"])
        #expect(window.selectedTags.isEmpty)
        #expect(try engine.cards().map(\.tags) == [["historia"], [], ["historia"]])
    }

    // ciencia has a color with no card, música is pinned, and geografía has
    // an emoji inside lenguaje, which a card carries.
    @Test(
        "Clear Unused Tags… is offered while some tag has no card, asks first with how many, and OK deletes them"
    )
    func clearUnusedTagsAsksFirst() throws {
        try approveCard("ubuntu", tags: ["lenguaje"])
        try engine.setColor(.red, of: "ciencia")
        try engine.pin("música")
        try engine.setEmoji(Emoji("🗺️"), of: "lenguaje::geografía")
        var window = openWindow()
        window.choose(.allTags)
        let offered = window.tagActions

        window.askToClearUnusedTags()
        let question = window.question
        window.clearUnusedTags()

        #expect(offered == [.clearUnused])
        #expect(question == .clearUnusedTags(["ciencia", "lenguaje::geografía", "música"]))
        #expect(window.question == nil)
        #expect(window.allTagsRows?.outline == ["lenguaje"])
        #expect(window.pinnedTags.isEmpty)
        #expect(window.tagActions == [])
    }

    @Test(
        "tags dropped onto a tag go inside it, and between rows to that level or the top, selected where they land, with their parent open"
    )
    func droppingOntoATagAndBetweenRows() throws {
        try approveCard("tango", tags: ["Argentina", "música"])
        try approveCard("ahorro", tags: ["economía"])
        try approveCard("arancel", tags: ["economía::mundial::comercio", "economía::mundial"])
        try engine.pin("Argentina")
        var window = openWindow()
        window.choose(.allTags)

        let movedInside = window.dragFromAllTags(["Argentina", "música"]) { $0.dropDraggedTags(into: "economía") }
        let afterMovingInside = window.allTagsRows?.outline
        let selectedAfterIt = window.selectedTags
        let openAfterIt = window.isOpen("economía")
        let movedToALevel = window.dragFromAllTags(["economía::mundial::comercio"]) {
            $0.dropDraggedTags(into: "economía")
        }
        let movedToTheTop = window.dragFromAllTags(["economía::música", "economía::mundial"]) {
            $0.dropDraggedTags(into: nil)
        }

        #expect(movedInside)
        #expect(afterMovingInside == ["economía", "  Argentina", "  mundial", "    comercio", "  música"])
        #expect(selectedAfterIt == ["economía::Argentina", "economía::música"])
        #expect(openAfterIt)
        #expect(movedToALevel)
        #expect(movedToTheTop)
        #expect(window.allTagsRows?.outline == ["economía", "  Argentina", "  comercio", "mundial", "música"])
        #expect(window.selectedTags == ["música", "mundial"])
        #expect(window.pinnedTags.map(\.id) == ["economía::Argentina"])
        #expect(window.failure == nil)
        #expect(
            try engine.cards().map(\.tags) == [
                ["economía::Argentina", "música"], ["economía"], ["economía::comercio", "mundial"],
            ])
    }

    // economía::mundial and economía::Argentina already sit right inside
    // economía. Text dragged in from another app, or from elsewhere in
    // Ficha, such as a tag's name in a card's tags, is dropped while Lucas
    // drags nothing from All Tags.
    @Test(
        "a drop onto a dragged tag, or a tag inside one, is refused, as is one that moves nothing, of a word that isn't a tag, or of text dragged in from elsewhere"
    )
    func refusedDrops() throws {
        try approveCard("ahorro", tags: ["economía::Argentina", "economía::mundial::comercio", "historia"])
        var window = openWindow()
        window.choose(.allTags)

        let refused = [
            window.canDrop(["economía"], into: "economía"),
            window.canDrop(["historia", "economía"], into: "economía::mundial"),
            window.canDrop(["economía::mundial"], into: "economía::mundial::comercio"),
            window.canDrop(["economía::mundial", "economía::Argentina"], into: "economía"),
            window.canDrop(["historia"], into: nil),
            window.canDrop(["una palabra"], into: "economía"),
            window.canDrop(["historia"], into: "una palabra"),
            window.canDropDraggedTags(into: "economía::mundial::comercio"),
        ]
        let dropped = window.dragFromAllTags(["historia", "economía"]) {
            $0.dropDraggedTags(into: "economía::mundial")
        }
        let droppedFromElsewhere = window.dropDraggedTags(into: "economía::mundial::comercio")

        #expect(refused == [false, false, false, false, false, false, false, false])
        #expect(window.canDrop(["historia"], into: "economía::mundial::comercio"))
        #expect(!dropped)
        #expect(!droppedFromElsewhere)
        #expect(window.failure == nil)
        #expect(try engine.cards().map(\.tags) == [["economía::Argentina", "economía::mundial::comercio", "historia"]])
    }

    // A tag inside another dragged tag moves along with it.
    @Test("dragging a tag along with one it sits inside moves it with its parent, not out of it")
    func draggingATagWithItsParent() throws {
        try approveCard("cepo", tags: ["economía::Argentina::cepo", "historia"])
        var window = openWindow()
        window.choose(.allTags)

        _ = window.dragFromAllTags(["economía", "economía::Argentina::cepo"]) { $0.dropDraggedTags(into: "historia") }

        #expect(window.allTagsRows?.outline == ["historia", "  economía", "    Argentina", "      cepo"])
        #expect(window.selectedTags == ["historia::economía"])
    }

    @Test(
        "double-clicking a tag lists its cards in All Tags' place, with its name as the title, and Back returns to All Tags as it was left"
    )
    func aTagsCardsAndBack() throws {
        let cepo = try approveCard("cepo", tags: ["economía::Argentina"])
        let arancel = try approveCard("arancel", tags: ["economía::mundial"])
        try approveCard("Cabildo", tags: ["historia::argentina"])
        var window = openWindow()
        window.choose(.allTags)
        window.sortAllTags(by: .cards, ascending: false)
        window.search(for: "arg")
        window.setOpen(false, "historia")
        window.selectTags(["economía::Argentina"])
        let canGoBackBefore = window.canGoBack

        window.showCardsOfSelectedTag()
        let listed = window.listedCardIDs
        let searchWhileListed = window.search
        let shown = window.shownTag
        let canGoBack = window.canGoBack
        window.search(for: "cep")
        window.goBack()

        #expect(!canGoBackBefore)
        #expect(listed == [cepo.id])
        #expect(searchWhileListed == "")
        #expect(shown == CardTag(name: "economía::Argentina"))
        #expect(canGoBack)
        #expect(window.sidebarItem == .allTags)
        #expect(window.search == "arg")
        #expect(window.allTagsSort == CardsWindowState.AllTagsSort(column: .cards, isAscending: false))
        #expect(window.selectedTags == ["economía::Argentina"])
        #expect(["economía", "historia"].filter(window.isOpen) == ["economía"])
        #expect(window.allTagsRows?.outline == ["economía", "  Argentina", "historia", "  argentina"])
        #expect(window.shownTag == nil)
        #expect(!window.canGoBack)
        window.showCards(of: "economía")
        #expect(window.listedCardIDs == [cepo.id, arancel.id])
        window.choose(.allTags)
        #expect(window.shownTag == nil)
        #expect(window.allTagsRows != nil)
    }

    @Test("Return lists the cards of the one tag selected, and nothing while several are, nor while none is")
    func returnListsTheOneSelectedTagsCards() throws {
        try approveCard("cepo", tags: ["economía", "historia"])
        var window = openWindow()
        window.choose(.allTags)

        window.selectTags(["economía", "historia"])
        let offeredForSeveral = window.tagActions
        window.showCardsOfSelectedTag()
        let afterSeveral = window.shownTag
        window.selectTags(["historia"])
        let offeredForOne = window.tagActions
        window.showCardsOfSelectedTag()

        #expect(offeredForSeveral == [.delete])
        #expect(afterSeveral == nil)
        #expect(offeredForOne == [.delete, .showCards])
        #expect(window.shownTag == CardTag(name: "historia"))
    }

    // Unpinned, the tag has no row in the sidebar, so the sidebar shows All
    // Tags…, where the tag is now.
    @Test(
        "unpinning the tag the sidebar chose keeps its cards listed, as All Tags lists a tag's, and Back goes to All Tags with it selected"
    )
    func unpinningTheChosenTag() throws {
        let cepo = try approveCard("cepo", tags: ["economía::Argentina"])
        try engine.pin("economía::Argentina")
        var window = openWindow()
        window.choose(.cards(.tag("economía::Argentina")))

        window.choosePin(on: ["economía::Argentina"])
        let listed = window.listedCardIDs
        let sidebarItem = window.sidebarItem
        window.goBack()

        #expect(listed == [cepo.id])
        #expect(sidebarItem == .allTags)
        #expect(window.pinnedTags.isEmpty)
        #expect(window.detail == .allTags(selected: [CardTag(name: "economía::Argentina")]))
        #expect(window.isOpen("economía"))
    }

    // Another device, or the CLI, deletes it meanwhile.
    @Test("All Tags lists its tree again when the tag whose cards it lists is gone")
    func aShownTagThatsGone() throws {
        try approveCard("cepo", tags: ["economía"])
        var window = openWindow()
        window.choose(.allTags)
        window.showCards(of: "economía")

        try engine.deleteTags(["economía"])
        window.read(with: scheduler)

        #expect(window.shownTag == nil)
        #expect(window.allTagsRows?.outline == [])
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

extension [CardsWindowState.AllTagsRow] {
    /// The rows of these tags and the tags inside them, as All Tags shows
    /// them with every parent open: each its title, two spaces in for each
    /// level it's in.
    var outline: [String] {
        flatMap { row in [row.title] + row.children.outline.map { "  " + $0 } }
    }

    /// These rows and the rows inside them, in the order they're listed.
    var flattened: [CardsWindowState.AllTagsRow] {
        flatMap { [$0] + $0.children.flattened }
    }

    /// Each row's title with its Cards and Due columns, as "economía 3/1",
    /// in the order they're listed.
    var counted: [String] {
        flattened.map { "\($0.title) \($0.counts.cards)/\($0.counts.due)" }
    }
}

extension CardsWindowState {
    /// Drags the tags named `names` from All Tags, as Lucas starts dragging
    /// their rows, drops them with `drop`, and lets go of them: whether the
    /// drop took them.
    mutating func dragFromAllTags(_ names: [String], _ drop: (inout Self) -> Bool) -> Bool {
        startDraggingTags(names)
        defer { stopDraggingTags() }
        return drop(&self)
    }

    /// Whether All Tags would take the tags named `names`, dragged from it,
    /// dropped inside the tag named `parent`, or at the top when it's nil.
    func canDrop(_ names: [String], into parent: String?) -> Bool {
        var window = self
        window.startDraggingTags(names)
        return window.canDropDraggedTags(into: parent)
    }

    /// The ids of the cards the table lists, in the order the engine read
    /// them, or nil when it lists the inbox, All Tags' tree, or couldn't
    /// read them.
    fileprivate var listedCardIDs: [Int64]? {
        guard case .success(.cards(let rows)) = listing else {
            return nil
        }
        return rows.map(\.id)
    }

    /// What All Tags lists, while the window lists it.
    var allTagsRows: [AllTagsRow]? {
        guard case .success(.allTags(let rows)) = listing else {
            return nil
        }
        return rows
    }
}
