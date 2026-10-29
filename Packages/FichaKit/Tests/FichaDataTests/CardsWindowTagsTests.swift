import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the Cards window's tags, which sit inside tags (ADR 0021): its
/// sidebar's Tags section, a tree of the tags that aren't set aside, and its
/// Set Aside section, what choosing a tag lists, and renaming and moving a
/// tag with Rename… and the drops, on the default ladder.
struct CardsWindowTagsTests {
    let engine: Engine
    let ladder = ReviewSettings.defaults.ladder

    init() throws {
        let calendar = try buenosAiresCalendar()
        engine = try Engine(
            location: .inMemory, time: ManualTimeSource(now: try morning(of: 14, in: calendar)), calendar: calendar)
    }

    // ciencia is set aside with no card, and stays listed so that Lucas can
    // undo it.
    @Test(
        "the sidebar lists the tags that aren't set aside as a tree, and the set-aside ones in Set Aside, one inside a tag that isn't by its whole path"
    )
    func theSidebarsTreeAndItsSetAsideSection() throws {
        try approveCard("deuda", tags: ["economía::Argentina::deuda", "lenguaje"])
        try approveCard("arancel", tags: ["economía::mundial"])
        try approveCard("Coliseo", tags: ["historia::Roma"])
        try engine.setAside("economía::Argentina")
        try engine.setAside("historia")
        try engine.setAside("ciencia")

        let window = openWindow()

        #expect(window.tagsSection.outline == ["economía", "  mundial", "lenguaje"])
        #expect(
            window.setAsideSection.outline == ["ciencia", "economía › Argentina", "  deuda", "historia", "  Roma"])
        #expect(window.setAsideSection[1].children.map(\.tag.name) == ["economía::Argentina::deuda"])
        #expect(window.tags.map(\.name).contains("economía::Argentina::deuda"))
    }

    @Test(
        "choosing a parent lists its cards and those of the tags inside it, and choosing a tag inside it only its own")
    func choosingAParentListsItsChildrensCards() throws {
        let ahorro = try approveCard("ahorro", tags: ["economía"])
        let cepo = try approveCard("cepo", tags: ["economía::Argentina"])
        let deuda = try approveCard("deuda", tags: ["economía::Argentina::deuda"])
        try approveCard("economista", tags: ["economíaX"])
        var window = openWindow()

        window.choose(.cards(.tag("economía")))
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
        var window = openWindow()
        window.choose(.cards(.tag("economía::Argentina")))

        window.askToRename("economía")
        #expect(window.question == .rename(CardTag(name: "economía")))
        #expect(window.renameEntry("economía::Argentina::economía") == .refused(.tagInsideItself("economía")))
        #expect(window.renameEntry(" :: ") == .refused(.blankTagName))
        #expect(window.renameEntry(" economics ") == .name("economics"))
        window.chooseNewName("economía::otra")
        #expect(window.question == .rename(CardTag(name: "economía")))
        window.chooseNewName("economics")

        #expect(window.question == nil)
        #expect(window.failure == nil)
        #expect(window.tagsSection.outline == ["economics", "  Argentina"])
        #expect(window.sidebarItem == .cards(.tag("economics::Argentina")))
        #expect(try engine.cards().map(\.tags) == [["economics::Argentina"]])
    }

    @Test(
        "dropping a tag on another moves it inside, dropping it on the Tags title takes it to the top, and a drop inside itself is refused"
    )
    func theDrops() throws {
        try approveCard("tango", tags: ["Argentina"])
        try approveCard("ahorro", tags: ["economía"])
        try approveCard("arancel", tags: ["economía::mundial::comercio"])
        var window = openWindow()

        let movedInside = window.drop("Argentina", onto: "economía")
        let outlineAfterIt = window.tagsSection.outline
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
        #expect(window.tagsSection.outline == ["economía", "  Argentina", "mundial", "  comercio"])
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

extension [CardsWindowState.SidebarTag] {
    /// The rows of these tags and the tags inside them, as the sidebar shows
    /// them open: each its title, two spaces in for each level it's in.
    fileprivate var outline: [String] {
        flatMap { tag in [tag.title] + tag.children.outline.map { "  " + $0 } }
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
