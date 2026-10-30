import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on pinned tags (ADR 0022): the tags the user keeps in the Cards
/// window's sidebar, in an order of their own, which they pin, unpin and
/// move, and which keep their pin and their place when they're renamed,
/// moved or merged.
struct PinnedTagsTests {
    let engine: Engine

    init() throws {
        let calendar = try buenosAiresCalendar()
        engine = try Engine(
            location: .inMemory, time: ManualTimeSource(now: try morning(of: 14, in: calendar)), calendar: calendar)
    }

    // historia is pinned before any card carries it.
    @Test(
        "nothing is pinned at first, and pinned tags list in the order they were pinned, each with what it takes from the tags it sits inside"
    )
    func pinningAtTheEnd() throws {
        try approveCard("cepo", tags: ["economía::Argentina"])
        try approveCard("petricor", tags: ["lenguaje"])
        try engine.setColor(.green, of: "economía")
        #expect(try engine.pinnedTags().isEmpty)

        try engine.pin("lenguaje")
        try engine.pin("economía::Argentina")
        try engine.pin("historia")

        let pinned = try engine.pinnedTags()
        #expect(pinned.map(\.name) == ["lenguaje", "economía::Argentina", "historia"])
        #expect(pinned.map(\.isPinned) == [true, true, true])
        #expect(pinned.map(\.shownColor) == [nil, .green, nil])
    }

    @Test(
        "pinning a tag at an index puts it there, pinning a pinned tag at another moves it, and the others keep their order"
    )
    func pinningAtAnIndexAndMoving() throws {
        for tag in ["arte", "biología", "ciencia"] {
            try engine.pin(tag)
        }

        try engine.pin("derecho", at: 1)
        let afterPinning = try engine.pinnedTags().map(\.name)
        try engine.pin("arte", at: 2)
        let afterMovingDown = try engine.pinnedTags().map(\.name)
        try engine.pin("ciencia", at: 0)
        let afterMovingUp = try engine.pinnedTags().map(\.name)
        try engine.pin("biología")
        try engine.pin("economía", at: 99)

        #expect(afterPinning == ["arte", "derecho", "biología", "ciencia"])
        #expect(afterMovingDown == ["derecho", "biología", "arte", "ciencia"])
        #expect(afterMovingUp == ["ciencia", "derecho", "biología", "arte"])
        #expect(try engine.pinnedTags().map(\.name) == ["ciencia", "derecho", "biología", "arte", "economía"])
    }

    // economía, ciencia and arte keep the order they're given in; ciencia
    // and arte were pinned, and filosofía joins the end without an index,
    // where the pinned biología stays put.
    @Test(
        "pinning several tags at an index puts them there in their order, the pinned ones moving with them, and without an index after the others"
    )
    func pinningSeveralTags() throws {
        for tag in ["arte", "biología", "ciencia"] {
            try engine.pin(tag)
        }

        try engine.pin(["economía", "ciencia", "arte"], at: 1)
        let afterPinningAtAnIndex = try engine.pinnedTags().map(\.name)
        try engine.pin(["filosofía", "biología"])

        #expect(afterPinningAtAnIndex == ["biología", "economía", "ciencia", "arte"])
        #expect(try engine.pinnedTags().map(\.name) == ["biología", "economía", "ciencia", "arte", "filosofía"])
    }

    @Test(
        "moving pinned tags puts them at an index in their order, and a tag that isn't pinned is refused, moving none of them"
    )
    func movingPinnedTags() throws {
        for tag in ["arte", "biología", "ciencia", "derecho"] {
            try engine.pin(tag)
        }

        try engine.movePinnedTags(["derecho", "arte"], to: 1)
        let afterMoving = try engine.pinnedTags().map(\.name)

        #expect(afterMoving == ["biología", "derecho", "arte", "ciencia"])
        #expect(throws: EngineError.tagNotPinned("economía")) {
            try engine.movePinnedTags(["ciencia", "economía"], to: 0)
        }
        #expect(try engine.pinnedTags().map(\.name) == afterMoving)
    }

    // historia has nothing else of its own, and no card: it's listed only
    // while it's pinned.
    @Test("unpinning a tag takes it out of the pinned tags, and a pinned tag no card carries stays listed until then")
    func unpinning() throws {
        try approveCard("petricor", tags: ["lenguaje"])
        try engine.setColor(.blue, of: "lenguaje")
        try engine.pin("lenguaje")
        try engine.pin("historia")
        let listedWhilePinned = try engine.allTags().map(\.name)

        try engine.unpin("historia")
        try engine.unpin("lenguaje")
        try engine.unpin("ciencia")

        #expect(listedWhilePinned == ["historia", "lenguaje"])
        #expect(try engine.pinnedTags().isEmpty)
        #expect(try engine.allTags() == [CardTag(name: "lenguaje", color: .blue)])
    }

    // Each move gives one tag a key between two others, which grows as they
    // close in.
    @Test("tags pinned again and again at the same place keep the order they were put in")
    func manyPinsAtTheSamePlace() throws {
        try engine.pin("primero")
        try engine.pin("último")
        let tags = (1...60).map { "tema \($0)" }

        for tag in tags {
            try engine.pin(tag, at: 1)
        }
        for _ in 1...30 {
            try engine.pin("primero", at: 1)
            try engine.pin("primero", at: 0)
        }

        #expect(try engine.pinnedTags().map(\.name) == ["primero"] + tags.reversed() + ["último"])
    }

    @Test("a renamed or moved tag keeps its pin and its place, and so does a pinned tag inside it")
    func aRenameKeepsThePin() throws {
        try approveCard("cepo", tags: ["economía::Argentina"])
        try approveCard("petricor", tags: ["lenguaje"])
        for tag in ["lenguaje", "economía::Argentina", "historia"] {
            try engine.pin(tag)
        }

        try engine.renameTag("economía", to: "economics")
        let afterTheRename = try engine.pinnedTags().map(\.name)
        try engine.renameTag("economics::Argentina", to: "Argentina")

        #expect(afterTheRename == ["lenguaje", "economics::Argentina", "historia"])
        #expect(try engine.pinnedTags().map(\.name) == ["lenguaje", "Argentina", "historia"])
    }

    // Argentina was pinned already, and stays in its place; Roma wasn't, and
    // takes historia › Roma's.
    @Test(
        "when two tags merge, the tag is pinned if either was, in the place of the one already there when it was pinned, and of the moved one otherwise"
    )
    func aMergeKeepsAPin() throws {
        try approveCard("cepo", tags: ["economía::Argentina"])
        try approveCard("tango", tags: ["Argentina"])
        try approveCard("Coliseo", tags: ["historia::Roma"])
        try approveCard("Trastevere", tags: ["Roma"])
        for tag in ["arte", "economía::Argentina", "Argentina", "historia::Roma", "ciencia"] {
            try engine.pin(tag)
        }

        try engine.renameTag("economía::Argentina", to: "Argentina")
        try engine.renameTag("historia::Roma", to: "Roma")

        #expect(try engine.pinnedTags().map(\.name) == ["arte", "Argentina", "Roma", "ciencia"])
    }

    /// Approves a capture into one word card with this front and these
    /// tags, the way refining saves cards, and returns the card.
    @discardableResult
    private func approveCard(_ front: String, tags: [String]) throws -> Card {
        try approve(card(.word, front: front, back: "Lo que quiere decir «\(front)».", tags: tags), in: engine)
    }
}
