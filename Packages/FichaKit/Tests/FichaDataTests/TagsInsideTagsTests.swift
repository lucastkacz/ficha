import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on tags inside tags (ADR 0021): a tag's name carries the tags it
/// sits inside, `economía::Argentina`, and what's set on a tag, set aside,
/// priority, its color and its emoji, holds for the tags inside it, with the
/// default settings. They start at 9 in the morning in Buenos Aires, when
/// active hours start.
struct TagsInsideTagsTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let settings = ReviewSettings.defaults

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    // deuda's tag comes once economía is set aside, a level further in.
    @Test("a card tagged economía::Argentina is set aside when economía is, also when its tag is made after")
    func aCardIsSetAsideWithAParentOfItsTag() throws {
        try approveCard("inflación", tags: ["economía::Argentina"])
        let petricor = try approveCard("petricor", tags: ["lenguaje"])

        try engine.setAside("economía")
        try approveCard("deuda", tags: ["economía::Argentina::deuda"])

        #expect(
            try engine.cards().map(\.standing) == [
                .setAside(by: ["economía"]), .inReviews, .setAside(by: ["economía"]),
            ])
        #expect(try engine.reviewNow(settings) == [.firstView(petricor)])
    }

    @Test("a tag inside a parent that isn't set aside can be set aside alone, and the parent's other tags stay")
    func aTagInsideAParentCanBeSetAsideAlone() throws {
        try approveCard("inflación", tags: ["economía::Argentina"])
        let comercio = try approveCard("comercio", tags: ["economía::mundial"])
        try approveCard("ahorro", tags: ["economía"])

        try engine.setAside("economía::Argentina")

        #expect(
            try engine.cards().map(\.standing) == [.setAside(by: ["economía::Argentina"]), .inReviews, .inReviews])
        #expect(try engine.reviewNow(settings) == [.firstView(comercio)])
    }

    // As a refine session or the card form might write them.
    @Test("a tag's levels lose the spaces around them, and an empty level goes, wherever a card comes from")
    func aTagsLevelsAreCleanedUp() throws {
        let inflacion = try approveCard("inflación", tags: [" economía :: Argentina ", "economía::::mundial", ":: "])

        #expect(inflacion.tags == ["economía::Argentina", "economía::mundial"])
    }

    @Test(
        "a priority parent brings the cards of the tags inside it first, and a parent set aside wins over a priority tag inside it"
    )
    func aPriorityParentBringsItsChildrensCardsFirst() throws {
        let ubuntu = try meetCard("ubuntu", tags: ["lenguaje"])
        let inflacion = try meetCard("inflación", tags: ["economía::Argentina"])
        time.advance(by: hours(1))
        #expect(try engine.reviewNow(settings) == [.review(ubuntu), .review(inflacion)])

        try engine.togglePriority(of: "economía")
        let withAPriorityParent = try engine.reviewNow(settings)
        try engine.togglePriority(of: "economía")
        try engine.togglePriority(of: "economía::Argentina")
        try engine.setAside("economía")

        #expect(withAPriorityParent == [.review(inflacion), .review(ubuntu)])
        #expect(try engine.reviewNow(settings) == [.review(ubuntu)])
        #expect(try engine.cards().map(\.standing) == [.inReviews, .setAside(by: ["economía"])])
    }

    // So that Lucas can make a parent no card carries alone a priority tag,
    // its children right after it.
    @Test("the Prioritize submenu offers each tag in reviews and the tags it sits inside, children after their parent")
    func thePrioritizeSubmenuOffersParents() throws {
        try approveCard("inflación", tags: ["economía::Argentina"])
        try approveCard("comercio", tags: ["economía::mundial", "economíaX"])
        try approveCard("ubuntu", tags: ["Lenguaje"])

        #expect(
            try engine.prioritizeMenu().tags.map(\.name) == [
                "economía", "economía::Argentina", "economía::mundial", "economíaX", "Lenguaje",
            ])
    }

    // Color and emoji are each looked up apart: Argentina keeps its own
    // emoji and shows economía's color, and deuda shows Argentina's emoji.
    @Test("a tag with no color or emoji of its own shows the nearest one's of the tags it sits inside")
    func aTagShowsItsNearestParentsColorAndEmoji() throws {
        try approveCard("deuda", tags: ["economía::Argentina::deuda", "lenguaje"])
        try engine.setColor(.green, of: "economía")
        try engine.setEmoji(Emoji("📈"), of: "economía")
        try engine.setEmoji(Emoji("🇦🇷"), of: "economía::Argentina")

        let economia = CardTag(name: "economía", color: .green, emoji: "📈")
        let argentina = CardTag(
            name: "economía::Argentina", emoji: "🇦🇷", inheritedColor: .green, inheritedEmoji: "📈")
        let deuda = CardTag(name: "economía::Argentina::deuda", inheritedColor: .green, inheritedEmoji: "🇦🇷")
        #expect(try engine.sidebarTags() == [economia, argentina, deuda, CardTag(name: "lenguaje")])
        #expect(try engine.cardRows(in: .all, on: settings.ladder).map(\.tags) == [[deuda, CardTag(name: "lenguaje")]])
        let sidebar = try engine.sidebarTags()
        #expect(sidebar.map(\.shownColor) == [.green, .green, .green, nil])
        #expect(sidebar.map(\.shownEmoji) == ["📈", "🇦🇷", "🇦🇷", nil])
    }

    @Test(
        "renaming a tag moves every card and every tag inside it to the new name, with their color, emoji, switches and choice to sync"
    )
    func renamingMovesEveryCardAndTagInside() throws {
        try approveCard("inflación", tags: ["economía::Argentina", "lenguaje"])
        try approveCard("ahorro", tags: ["economía"])
        try approveCard("deuda", tags: ["economía::Argentina::deuda"])
        try engine.setColor(.green, of: "economía")
        try engine.setEmoji(Emoji("📈"), of: "economía")
        try engine.togglePriority(of: "economía")
        try engine.setAside("economía::Argentina")
        try engine.chooseToSync("economía::Argentina", true)

        let renamed = try engine.renameTag("economía", to: " economics ")

        #expect(renamed == "economics")
        #expect(
            try engine.cards().map(\.tags) == [
                ["economics::Argentina", "lenguaje"], ["economics"], ["economics::Argentina::deuda"],
            ])
        #expect(
            try engine.cards().map(\.standing) == [
                .setAside(by: ["economics::Argentina"]), .inReviews, .setAside(by: ["economics::Argentina"]),
            ])
        #expect(
            try engine.sidebarTags() == [
                CardTag(name: "economics", switchedOn: .priority, color: .green, emoji: "📈"),
                CardTag(
                    name: "economics::Argentina", switchedOn: .setAside, chosenToSync: true, inheritedColor: .green,
                    inheritedEmoji: "📈"),
                CardTag(name: "economics::Argentina::deuda", inheritedColor: .green, inheritedEmoji: "📈"),
                CardTag(name: "lenguaje"),
            ])
    }

    // Argentina had a color of its own, and is a priority tag: it keeps them,
    // and economía::Argentina's are gone with its name, as in Anki.
    @Test(
        "renaming a tag onto a name that exists joins them, a card that carried both carries it once, and the tag already there stays as it was"
    )
    func renamingOntoANameThatExistsJoinsThem() throws {
        try approveCard("inflación", tags: ["economía::Argentina", "Argentina"])
        try approveCard("deuda", tags: ["economía::Argentina::deuda"])
        try approveCard("tango", tags: ["Argentina"])
        try engine.setColor(.blue, of: "Argentina")
        try engine.togglePriority(of: "Argentina")
        try engine.setColor(.green, of: "economía::Argentina")
        try engine.setAside("economía::Argentina")

        try engine.renameTag("economía::Argentina", to: "Argentina")

        #expect(try engine.cards().map(\.tags) == [["Argentina"], ["Argentina::deuda"], ["Argentina"]])
        #expect(try engine.cards().map(\.standing) == [.inReviews, .inReviews, .inReviews])
        #expect(
            try engine.sidebarTags() == [
                CardTag(name: "Argentina", switchedOn: .priority, color: .blue),
                CardTag(name: "Argentina::deuda", inheritedColor: .blue),
            ])
    }

    @Test(
        "joining a tag onto one only cards carry keeps that one as it was, with nothing of its own, and so for each tag inside them"
    )
    func joiningOntoATagOnlyCardsCarryKeepsIt() throws {
        try approveCard("Revolución de Mayo", tags: ["historia::Argentina", "historia::Roma"])
        try approveCard("inflación", tags: ["economía", "economía::Argentina"])
        try engine.setAside("historia")
        try engine.setColor(.red, of: "historia")
        try engine.setEmoji(Emoji("📜"), of: "historia")
        try engine.chooseToSync("historia", true)
        try engine.setColor(.green, of: "historia::Argentina")
        try engine.setColor(.purple, of: "historia::Roma")

        try engine.renameTag("historia", to: "economía")

        #expect(try engine.cards().map(\.standing) == [.inReviews, .inReviews])
        #expect(
            try engine.sidebarTags() == [
                CardTag(name: "economía"),
                CardTag(name: "economía::Argentina"),
                CardTag(name: "economía::Roma", color: .purple),
            ])
    }

    @Test("joining a tag onto one that exists only as the parent of tags inside it keeps that parent as it was")
    func joiningOntoAParentKeepsIt() throws {
        try approveCard("inflación", tags: ["economía::Argentina"])
        try approveCard("Revolución de Mayo", tags: ["historia"])
        try engine.setAside("historia")
        try engine.setEmoji(Emoji("📜"), of: "historia")

        try engine.renameTag("historia", to: "economía")

        #expect(try engine.cards().map(\.standing) == [.inReviews, .inReviews])
        #expect(
            try engine.sidebarTags() == [
                CardTag(name: "economía"),
                CardTag(name: "economía::Argentina"),
            ])
    }

    @Test("renaming a tag inside itself, or inside a tag inside it, or to a blank name is refused, and nothing changes")
    func renamingATagInsideItselfIsRefused() throws {
        try approveCard("inflación", tags: ["economía::Argentina"])
        try engine.setColor(.green, of: "economía")

        #expect(throws: EngineError.tagInsideItself("economía")) {
            try engine.renameTag("economía", to: "economía::Argentina::economía")
        }
        #expect(throws: EngineError.tagInsideItself("economía")) {
            try engine.renameTag("economía", to: "economía::otra")
        }
        #expect(throws: EngineError.blankTagName) {
            try engine.renameTag("economía", to: " :: ")
        }
        #expect(try engine.cards().map(\.tags) == [["economía::Argentina"]])
        #expect(try engine.sidebarTags().map(\.name) == ["economía", "economía::Argentina"])
    }

    // Renaming a tag to the name it has, or a tag no card carries, changes
    // nothing; a set-aside tag no card carries moves with its row.
    @Test("renaming a set-aside tag no card carries moves it, and renaming a tag to its own name changes nothing")
    func renamingASetAsideTagNoCardCarries() throws {
        try engine.setAside("historia")

        try engine.renameTag("historia", to: "historia")
        try engine.renameTag("historia", to: "ciencias sociales::historia")

        #expect(
            try engine.sidebarTags() == [CardTag(name: "ciencias sociales::historia", switchedOn: .setAside)])
    }

    /// Approves a capture into one word card with this front and these tags
    /// and meets it, then moves time a minute on, so that the cards met
    /// before it are longer overdue.
    @discardableResult
    private func meetCard(_ front: String, tags: [String]) throws -> Card {
        let card = try approveCard(front, tags: tags)
        try engine.meet(card)
        time.advance(by: minutes(1))
        return card
    }

    /// Approves a capture into one word card with this front and these
    /// tags, the way refining saves cards, and returns the card.
    @discardableResult
    private func approveCard(_ front: String, tags: [String]) throws -> Card {
        try approve(card(.word, front: front, back: "Lo que quiere decir «\(front)».", tags: tags), in: engine)
    }
}
