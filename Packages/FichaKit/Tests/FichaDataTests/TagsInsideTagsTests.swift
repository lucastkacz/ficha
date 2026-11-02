import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on tags inside tags (ADR 0021): a tag's name carries the tags it
/// sits inside, `economía::Argentina`, and a tag's color and emoji show on the
/// tags inside it that have none, with the default settings. They start at 9 in the morning in Buenos Aires, when
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

    // As a refine session or the card form might write them.
    @Test("a tag's levels lose the spaces around them, and an empty level goes, wherever a card comes from")
    func aTagsLevelsAreCleanedUp() throws {
        let inflacion = try approveCard("inflación", tags: [" economía :: Argentina ", "economía::::mundial", ":: "])

        #expect(inflacion.tags == ["economía::Argentina", "economía::mundial"])
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
        #expect(try engine.allTags() == [economia, argentina, deuda, CardTag(name: "lenguaje")])
        #expect(
            try engine.cardRows(in: .all, with: settings.scheduler).map(\.tags) == [[deuda, CardTag(name: "lenguaje")]])
        let allTags = try engine.allTags()
        #expect(allTags.map(\.shownColor) == [.green, .green, .green, nil])
        #expect(allTags.map(\.shownEmoji) == ["📈", "🇦🇷", "🇦🇷", nil])
    }

    @Test(
        "renaming a tag moves every card and every tag inside it to the new name, with their color, emoji and pin"
    )
    func renamingMovesEveryCardAndTagInside() throws {
        try approveCard("inflación", tags: ["economía::Argentina", "lenguaje"])
        try approveCard("ahorro", tags: ["economía"])
        try approveCard("deuda", tags: ["economía::Argentina::deuda"])
        try engine.setColor(.green, of: "economía")
        try engine.setEmoji(Emoji("📈"), of: "economía")
        try engine.pin("economía::Argentina")

        let renamed = try engine.renameTag("economía", to: " economics ")

        #expect(renamed == "economics")
        #expect(
            try engine.cards().map(\.tags) == [
                ["economics::Argentina", "lenguaje"], ["economics"], ["economics::Argentina::deuda"],
            ])
        let tags = try engine.allTags()
        let pin = try #require(tags.first { $0.name == "economics::Argentina" }?.pin)
        #expect(
            tags == [
                CardTag(name: "economics", color: .green, emoji: "📈"),
                CardTag(
                    name: "economics::Argentina", pin: pin, inheritedColor: .green,
                    inheritedEmoji: "📈"),
                CardTag(name: "economics::Argentina::deuda", inheritedColor: .green, inheritedEmoji: "📈"),
                CardTag(name: "lenguaje"),
            ])
    }

    // Argentina had a color of its own: it keeps it, and economía::Argentina's
    // color and emoji are gone with its name, as in Anki.
    @Test(
        "renaming a tag onto a name that exists joins them, a card that carried both carries it once, and the tag already there stays as it was"
    )
    func renamingOntoANameThatExistsJoinsThem() throws {
        try approveCard("inflación", tags: ["economía::Argentina", "Argentina"])
        try approveCard("deuda", tags: ["economía::Argentina::deuda"])
        try approveCard("tango", tags: ["Argentina"])
        try engine.setColor(.blue, of: "Argentina")
        try engine.setColor(.green, of: "economía::Argentina")
        try engine.setEmoji(Emoji("🧉"), of: "economía::Argentina")

        try engine.renameTag("economía::Argentina", to: "Argentina")

        #expect(try engine.cards().map(\.tags) == [["Argentina"], ["Argentina::deuda"], ["Argentina"]])
        #expect(
            try engine.allTags() == [
                CardTag(name: "Argentina", color: .blue),
                CardTag(name: "Argentina::deuda", inheritedColor: .blue),
            ])
    }

    @Test(
        "joining a tag onto one only cards carry keeps that one as it was, with nothing of its own, and so for each tag inside them"
    )
    func joiningOntoATagOnlyCardsCarryKeepsIt() throws {
        try approveCard("Revolución de Mayo", tags: ["historia::Argentina", "historia::Roma"])
        try approveCard("inflación", tags: ["economía", "economía::Argentina"])
        try engine.setColor(.red, of: "historia")
        try engine.setEmoji(Emoji("📜"), of: "historia")
        try engine.setColor(.green, of: "historia::Argentina")
        try engine.setColor(.purple, of: "historia::Roma")

        try engine.renameTag("historia", to: "economía")

        #expect(
            try engine.allTags() == [
                CardTag(name: "economía"),
                CardTag(name: "economía::Argentina"),
                CardTag(name: "economía::Roma", color: .purple),
            ])
    }

    @Test("joining a tag onto one that exists only as the parent of tags inside it keeps that parent as it was")
    func joiningOntoAParentKeepsIt() throws {
        try approveCard("inflación", tags: ["economía::Argentina"])
        try approveCard("Revolución de Mayo", tags: ["historia"])
        try engine.setEmoji(Emoji("📜"), of: "historia")

        try engine.renameTag("historia", to: "economía")

        #expect(try engine.cards().map(\.tags) == [["economía::Argentina"], ["economía"]])
        #expect(
            try engine.allTags() == [
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
        #expect(try engine.allTags().map(\.name) == ["economía", "economía::Argentina"])
    }

    // Renaming a tag to the name it has changes nothing; a tag with a color
    // and no card moves with its row.
    @Test("renaming a tag no card carries moves it with its color, and renaming a tag to its own name changes nothing")
    func renamingATagNoCardCarries() throws {
        try engine.setColor(.red, of: "historia")

        try engine.renameTag("historia", to: "historia")
        try engine.renameTag("historia", to: "ciencias sociales::historia")

        #expect(
            try engine.allTags() == [
                CardTag(name: "ciencias sociales"), CardTag(name: "ciencias sociales::historia", color: .red),
            ])
    }

    /// Approves a capture into one word card with this front and these
    /// tags, the way refining saves cards, and returns the card.
    @discardableResult
    private func approveCard(_ front: String, tags: [String]) throws -> Card {
        try approve(card(.word, front: front, back: "Lo que quiere decir «\(front)».", tags: tags), in: engine)
    }
}
