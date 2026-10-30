import FichaCore
import FichaData
import Foundation

extension CardGroup {
    /// The group's name in the sidebar.
    var title: String {
        switch self {
        case .all:
            String(
                localized: "All cards",
                comment: "An item of the Cards window's sidebar: every card but the buried ones.")
        case .new:
            String(localized: "New", comment: "An item of the Cards window's sidebar: the cards not seen yet.")
        case .due:
            String(localized: "Due", comment: "An item of the Cards window's sidebar: the cards due now.")
        case .learned:
            String(localized: "Learned", comment: "An item of the Cards window's sidebar: the learned cards.")
        case .flagged:
            String(localized: "Flagged", comment: "An item of the Cards window's sidebar: the flagged cards.")
        case .buried:
            String(localized: "Buried", comment: "An item of the Cards window's sidebar: the buried cards.")
        case .deck(let deck):
            Deck.shownName(deck)
        case .tag(let tag):
            TagPath.shown(tag)
        case .type(let type):
            type.pluralName
        case .noType:
            String(
                localized: "No Type", comment: "An item of the Cards window's sidebar: the cards that have no type.")
        }
    }

    /// The group's icon, in the sidebar and when it has no cards.
    var symbol: String {
        switch self {
        case .all: "rectangle.stack"
        case .new: "sparkles"
        case .due: "clock"
        case .learned: "checkmark.seal"
        case .flagged: "flag"
        case .buried: "eye.slash"
        case .deck: "rectangle.portrait.on.rectangle.portrait"
        case .tag: "tag"
        case .type(let type): type.symbol
        case .noType: "square.dashed"
        }
    }

    /// What the table says when the group has no cards.
    var emptyTitle: String {
        switch self {
        case .all:
            String(localized: "No cards", comment: "In the Cards window: no card that isn't buried.")
        case .new:
            String(localized: "No new cards", comment: "In the Cards window: no card waits for its first view.")
        case .due:
            String(localized: "No cards due", comment: "In the Cards window: no card is due now.")
        case .learned:
            String(localized: "No learned cards", comment: "In the Cards window: no card is learned yet.")
        case .flagged:
            String(localized: "No flagged cards", comment: "In the Cards window: no card is flagged.")
        case .buried:
            String(localized: "No buried cards", comment: "In the Cards window: no card is buried.")
        case .deck(Deck.defaultName):
            String(
                localized: "No cards in Default",
                comment:
                    "In the Cards window: no card that isn't buried lives in Default, the deck of cards with no other."
            )
        case .deck(let deck):
            String(
                localized: "No cards in \(TagPath.shown(deck))",
                comment: """
                    In the Cards window: no card that isn't buried lives in this deck, or a deck inside it, with the \
                    deck's whole name, like “Idiomas › Inglés”.
                    """)
        case .tag(let tag):
            String(
                localized: "No cards tagged \(TagPath.shown(tag))",
                comment: """
                    In the Cards window: no card that isn't buried has this tag, or a tag inside it, anymore, with \
                    the tag's whole name, like “economía › Argentina”.
                    """)
        case .type(.word):
            String(localized: "No words", comment: "In the Cards window: no word card that isn't buried.")
        case .type(.concept):
            String(localized: "No concepts", comment: "In the Cards window: no concept card that isn't buried.")
        case .type(.quote):
            String(localized: "No quotes", comment: "In the Cards window: no quote card that isn't buried.")
        case .type(.question):
            String(localized: "No questions", comment: "In the Cards window: no question card that isn't buried.")
        case .type(.user(let type)):
            String(
                localized: "No cards of the type \(type.name)",
                comment:
                    "In the Cards window: no card that isn't buried has this type of the user's own, with its name.")
        case .noType:
            String(
                localized: "No cards without a type",
                comment: "In the Cards window: every card that isn't buried has a type.")
        }
    }
}

extension Deck {
    /// Default's name, as the Mac's language says it: "Default" is the key of
    /// the String Catalog `Deck.defaultNames` reads too, so that no deck the
    /// user makes takes it.
    nonisolated static var defaultShownName: String {
        String(localized: "Default", comment: "The deck a card lives in when it has no other.")
    }

    /// The deck named `name` as the window names it on its own: its whole
    /// name, written with " › ", or Default's in the Mac's language.
    nonisolated static func shownName(_ name: String) -> String {
        name == defaultName ? defaultShownName : TagPath.shown(name)
    }
}

extension CardsWindowState.DeckRow {
    /// What its row says, in the sidebar and the Change Deck sheet: its last
    /// level, or Default's name in the Mac's language.
    var shownTitle: String {
        deck.isDefault ? Deck.defaultShownName : title
    }
}

extension InboxRow.Item {
    /// What kind it is, as the inbox's Kind column and the capture's detail
    /// say it. Each kind has a key of its own, since "Capture" is also the
    /// capture window's title, and "Flagged" the sidebar's group, which a
    /// translation may word apart.
    nonisolated var kindName: String {
        switch self {
        case .capture:
            String(
                localized: "inbox-kind.capture", defaultValue: "Capture",
                comment: "In the Cards window's inbox, the kind of a row: a capture.")
        case .expansion:
            String(
                localized: "inbox-kind.expansion", defaultValue: "Expansion",
                comment: "In the Cards window's inbox, the kind of a row: a capture attached to the card it repeats.")
        case .followUp:
            String(
                localized: "inbox-kind.follow-up", defaultValue: "Follow-up",
                comment:
                    "In the Cards window's inbox, the kind of a row: a capture asked about a card in the review panel, tied to it."
            )
        case .flaggedCard:
            String(
                localized: "inbox-kind.flagged", defaultValue: "Flagged",
                comment: "In the Cards window's inbox, the kind of a row: a flagged card.")
        }
    }
}

extension CardType {
    /// The type's name, as the Cards window shows it, and as its table sorts
    /// by it: one of the four's in the Mac's language, as the engine also
    /// knows it (`CardType.builtInNames`), and a user type's as the user
    /// wrote it.
    nonisolated var name: String {
        switch self {
        case .word: String(localized: "Word", comment: "A card type.")
        case .concept: String(localized: "Concept", comment: "A card type.")
        case .quote: String(localized: "Quote", comment: "A card type.")
        case .question: String(localized: "Question", comment: "A card type.")
        case .user(let type): type.name
        }
    }

    /// The type's name where it stands alone, as in the Type column, the
    /// detail and the type picker: a user type's emoji, when it has one,
    /// before its name.
    nonisolated var title: String {
        guard let emoji = userType?.emoji else { return name }
        return "\(emoji) \(name)"
    }

    /// The type's cards, as the Cards window's sidebar names them: a user
    /// type's by its name, as the user wrote it.
    var pluralName: String {
        switch self {
        case .word: String(localized: "Words", comment: "An item of the Cards window's sidebar: the word cards.")
        case .concept:
            String(localized: "Concepts", comment: "An item of the Cards window's sidebar: the concept cards.")
        case .quote: String(localized: "Quotes", comment: "An item of the Cards window's sidebar: the quote cards.")
        case .question:
            String(localized: "Questions", comment: "An item of the Cards window's sidebar: the question cards.")
        case .user(let type): type.name
        }
    }

    /// The type's icon, in the Cards window's sidebar, where a user type with
    /// an emoji shows the emoji instead, and one without a plain square.
    var symbol: String {
        switch self {
        case .word: "textformat"
        case .concept: "lightbulb"
        case .quote: "quote.opening"
        case .question: "questionmark.bubble"
        case .user: "square"
        }
    }
}
