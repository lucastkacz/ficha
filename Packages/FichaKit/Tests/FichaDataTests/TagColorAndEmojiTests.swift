import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the tags the database keeps, listed as `ficha tags` lists them,
/// and on a tag's color and emoji, which Lucas picked so that subjects stood
/// apart at a glance (#206), each optional: the database keeps them, and the
/// `ficha` CLI sets and lists them, since tags left the app's face (#538).
struct TagColorAndEmojiTests {
    let engine: Engine

    init() throws {
        let calendar = try buenosAiresCalendar()
        engine = try Engine(
            location: .inMemory, time: ManualTimeSource(now: try morning(of: 14, in: calendar)), calendar: calendar)
    }

    // `ficha tags` lists the tags of `countedTags(with:)`, which are those
    // `allTags()` lists.
    @Test("every tag of the cards is listed, buried ones too, once each, alphabetically")
    func everyTagOfTheCardsIsListed() throws {
        try approveCard("Ubuntu", tags: ["lenguaje", "filosofía"])
        try approveCard("Eudaimonía", tags: ["ética", "filosofía"])
        let mercantilismo = try approveCard("Mercantilismo", tags: ["economía", "historia"])
        try engine.bury(mercantilismo.id)
        try approveCard("serendipia", tags: [])

        #expect(try engine.allTags().map(\.name) == ["economía", "ética", "filosofía", "historia", "lenguaje"])
    }

    @Test("a tag's color and emoji are stored and read back with every tag")
    func aTagsColorAndEmojiAreStoredAndReadBack() throws {
        try approveCard("Revolución de Mayo", tags: ["historia", "argentina"])
        try approveCard("fotosíntesis", tags: ["ciencia", "lenguaje"])

        try engine.setColor(.green, of: "ciencia")
        try engine.setEmoji(Emoji("🇦🇷"), of: "argentina")
        try engine.setColor(.blue, of: "historia")
        try engine.setEmoji(Emoji("📜"), of: "historia")

        let argentina = CardTag(name: "argentina", emoji: "🇦🇷")
        let ciencia = CardTag(name: "ciencia", color: .green)
        let historia = CardTag(name: "historia", color: .blue, emoji: "📜")
        let lenguaje = CardTag(name: "lenguaje")
        #expect(try engine.allTags() == [argentina, ciencia, historia, lenguaje])
    }

    // The `tag` table refuses a row with nothing in it, so removing both
    // fails unless the row goes.
    @Test("removing both from a tag with nothing else deletes its row, and removing one keeps the other")
    func removingBothFromATagWithNothingElseDeletesItsRow() throws {
        try approveCard("fotosíntesis", tags: ["ciencia"])
        try engine.setColor(.green, of: "ciencia")
        try engine.setEmoji(Emoji("🔬"), of: "ciencia")

        try engine.setColor(nil, of: "ciencia")
        #expect(try engine.allTags() == [CardTag(name: "ciencia", emoji: "🔬")])
        try engine.setEmoji(nil, of: "ciencia")
        #expect(try engine.allTags() == [CardTag(name: "ciencia")])
        try engine.setEmoji(nil, of: "ciencia")
        #expect(try engine.allTags() == [CardTag(name: "ciencia")])
    }

    @Test(
        "an emoji that isn't one emoji, such as a word, two emoji or a letter, is refused",
        arguments: ["argentina", "🇦🇷🇺🇾", "a", "7", "❤", "", " "])
    func anEmojiThatIsntOneEmojiIsRefused(_ emoji: String) throws {
        try approveCard("Revolución de Mayo", tags: ["argentina"])
        try engine.setEmoji(Emoji("🇦🇷"), of: "argentina")

        #expect(throws: EngineError.notOneEmoji) {
            try engine.setEmoji(Emoji(emoji), of: "argentina")
        }
        #expect(try engine.allTags() == [CardTag(name: "argentina", emoji: "🇦🇷")])
    }

    // A flag, a skin tone with a profession, joined by U+200D, an emoji asked
    // for with U+FE0F, a keycap, a text-default emoji with a skin tone and no
    // U+FE0F, as the Mac's emoji picker inserts ☝🏽 and ✌🏾, and one with
    // spaces around it.
    @Test(
        "one emoji is taken however many scalars it has, without the spaces around it",
        arguments: [
            ("🇦🇷", "🇦🇷"), ("👩🏽‍🔬", "👩🏽‍🔬"), ("❤️", "❤️"), ("1️⃣", "1️⃣"), ("\u{261D}\u{1F3FD}", "\u{261D}\u{1F3FD}"),
            ("\u{270C}\u{1F3FE}", "\u{270C}\u{1F3FE}"), ("👍🏽", "👍🏽"), (" 📜\n", "📜"),
        ])
    func oneEmojiIsTakenHoweverManyScalarsItHas(_ emoji: String, _ stored: String) throws {
        try approveCard("Revolución de Mayo", tags: ["argentina"])

        try engine.setEmoji(Emoji(emoji), of: "argentina")

        #expect(try engine.allTags() == [CardTag(name: "argentina", emoji: stored)])
    }

    @Test(
        "a colored tag that loses its last card stays listed with its color and emoji, which it keeps once a card gets it again"
    )
    func aColoredTagThatLosesItsLastCardKeepsItsColorAndEmoji() throws {
        let mayo = try approveCard("Revolución de Mayo", tags: ["argentina"])
        try approveCard("serendipia", tags: [])
        try engine.setColor(.blue, of: "argentina")
        try engine.setEmoji(Emoji("🇦🇷"), of: "argentina")
        let argentina = CardTag(name: "argentina", color: .blue, emoji: "🇦🇷")

        try engine.delete([mayo.id])
        #expect(try engine.allTags() == [argentina])

        let martin = try approveCard("San Martín", tags: ["argentina"])
        #expect(try engine.allTags() == [argentina])
        #expect(try engine.cards().filter { $0.tags == ["argentina"] }.map(\.id) == [martin.id])
    }

    /// Approves a capture into one word card with this front and these
    /// tags, the way refining saves cards, and returns the card.
    @discardableResult
    private func approveCard(_ front: String, tags: [String]) throws -> Card {
        try approve(card(.word, front: front, back: "Lo que quiere decir «\(front)».", tags: tags), in: engine)
    }
}
