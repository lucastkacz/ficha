import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on a tag's color and emoji, which Lucas picks so that subjects
/// stand apart at a glance (#206), each optional, and which the Cards
/// window shows wherever the tag shows.
struct TagColorAndEmojiTests {
    let engine: Engine
    let ladder = ReviewSettings.defaults.ladder

    init() throws {
        let calendar = try buenosAiresCalendar()
        engine = try Engine(
            location: .inMemory, time: ManualTimeSource(now: try morning(of: 14, in: calendar)), calendar: calendar)
    }

    @Test("a tag's color and emoji are stored and read back with the sidebar's tags and the table's rows")
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
        #expect(
            try engine.cardRows(in: .all, on: ladder).map(\.tags) == [[historia, argentina], [ciencia, lenguaje]])
    }

    // The menu's Prioritize submenu puts each tag's emoji before its name.
    @Test("the Prioritize submenu's read carries each tag's emoji and color, also a priority tag's")
    func thePrioritizeSubmenusReadCarriesEachTagsEmoji() throws {
        try approveCard("Revolución de Mayo", tags: ["historia", "argentina::Mayo"])
        try engine.setEmoji(Emoji("🇦🇷"), of: "argentina")
        try engine.pin("argentina::Mayo")
        try engine.togglePriority(of: "historia")
        try engine.setColor(.blue, of: "historia")
        try engine.setEmoji(Emoji("📜"), of: "historia")

        let tags = try engine.prioritizeMenu().tags
        #expect(tags.map(\.name) == ["argentina::Mayo", "historia"])
        #expect(tags.map(\.shownEmoji) == ["🇦🇷", "📜"])
        #expect(tags.map(\.shownColor) == [nil, .blue])
        #expect(tags.map(\.isPriority) == [false, true])
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
        "a colored tag that loses its last card leaves the sidebar's read, and comes back with its color and emoji when a card gets it again"
    )
    func aColoredTagThatLosesItsLastCardComesBackWithItsColorAndEmoji() throws {
        let mayo = try approveCard("Revolución de Mayo", tags: ["argentina"])
        try approveCard("serendipia", tags: [])
        try engine.setColor(.blue, of: "argentina")
        try engine.setEmoji(Emoji("🇦🇷"), of: "argentina")

        try engine.bury(mayo.id)
        #expect(try engine.allTags() == [])

        let martin = try approveCard("San Martín", tags: ["argentina"])
        let argentina = CardTag(name: "argentina", color: .blue, emoji: "🇦🇷")
        #expect(try engine.allTags() == [argentina])
        #expect(try engine.cardRows(in: .tag("argentina"), on: ladder).map(\.tags) == [[argentina]])
        #expect(try engine.cardRows(in: .tag("argentina"), on: ladder).map(\.id) == [martin.id])
    }

    /// Approves a capture into one word card with this front and these
    /// tags, the way refining saves cards, and returns the card.
    @discardableResult
    private func approveCard(_ front: String, tags: [String]) throws -> Card {
        try approve(card(.word, front: front, back: "Lo que quiere decir «\(front)».", tags: tags), in: engine)
    }
}
