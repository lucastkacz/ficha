import FichaCore
import FichaData
import SwiftUI

extension CardGroup {
    /// The group's name in the sidebar. Every card and the flagged ones,
    /// which the engine counts, are groups the sidebar never offers (#536),
    /// so the app names neither.
    var title: String {
        switch self {
        case .all, .flagged:
            ""
        case .deck(let deck):
            Deck.shownName(deck)
        }
    }

    /// The group's icon, in the sidebar and when it has no cards.
    var symbol: String {
        switch self {
        case .all: "rectangle.stack"
        case .flagged: "flag"
        case .deck: "rectangle.portrait.on.rectangle.portrait"
        }
    }

    /// What the grid's place says when the group has no cards: nothing for
    /// the groups the sidebar never offers.
    var emptyTitle: String {
        switch self {
        case .all, .flagged:
            ""
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
        }
    }
}

extension Deck {
    /// "Default", the key of the app's String Catalog by which
    /// `Deck.shownName(_:)`, in FichaData, names Default as the app shows
    /// it: Xcode fills the catalog from the app's own sources alone,
    /// never from a package's, so this line puts the key there. Nothing
    /// reads it.
    private static let defaultNameInCatalog = String(
        localized: "Default", comment: "The deck a card lives in when it has no other.")
}

/// A deck, as the app names and draws it where it stands alone, in a menu,
/// the sidebar or the bar above the grid: its emoji before its name, and its
/// group's symbol, filled and tinted with its color, each its own or else
/// that of the decks it sits inside.
protocol GroupWithLook {
    /// The cards it groups, as the sidebar names them and draws their
    /// symbol.
    var group: CardGroup { get }
    /// The color it shows: its own, or else that of the nearest it sits
    /// inside that has one.
    var shownColor: TagColor? { get }
    /// The emoji it shows, found the same way.
    var shownEmoji: String? { get }
}

extension GroupWithLook {
    /// How it's named where it stands alone, as in a menu: its emoji, when it
    /// shows one, before its whole name, written with " › ", as in
    /// "Idiomas › Inglés" or "🏛 Historia › Roma", or before Default's name
    /// as the app shows it.
    var title: String {
        title(shown: group.title)
    }

    /// How it's named when `shown` names it, as in a tree, by its last
    /// level: its emoji, when it shows one, before `shown`.
    func title(shown: String) -> String {
        shownEmoji.map { "\($0) \(shown)" } ?? shown
    }

    /// The SF Symbol drawn before its name, in the sidebar, the Change Deck
    /// sheet and the bar above the grid: its group's,
    /// filled while it shows a color, or outlined while it shows none.
    var symbolName: String {
        shownColor == nil ? group.symbol : "\(group.symbol).fill"
    }

    /// Its symbol (`symbolName`), tinted with the color it shows, for
    /// SwiftUI.
    @ViewBuilder var symbol: some View {
        if let color = shownColor {
            Image(systemName: symbolName).foregroundStyle(color.color)
        } else {
            Image(systemName: symbolName)
        }
    }
}

extension Deck: GroupWithLook {
    var group: CardGroup {
        .deck(name)
    }
}

extension DeckInTree {
    /// What it says in a tree of decks, in the sidebar, the Change Deck sheet,
    /// the menu bar's Prioritize submenu and the Sync tab: its emoji, its own
    /// or else the decks' it sits inside, when it shows one, before its last
    /// level, or before Default's name as the app shows it.
    var shownTitle: String {
        deck.title(shown: deck.isDefault ? Deck.shownName(deck.name) : title)
    }
}

extension InboxRow.Item {
    /// What kind it is, as the inbox's Kind column and the capture's detail
    /// say it.
    nonisolated var kindName: String {
        switch self {
        case .capture: InboxKind.capture.name
        case .expansion: InboxKind.expansion.name
        case .followUp: InboxKind.followUp.name
        case .flaggedCard: InboxKind.flagged.name
        }
    }
}

/// The kinds of the inbox's rows, whose names the Kind column's width fits.
nonisolated enum InboxKind: CaseIterable {
    case capture
    case expansion
    case followUp
    case flagged

    /// The kind's name. Each has a key of its own, since "Capture" is also
    /// the capture window's title, and "Flagged" the flag icon's label beside
    /// a flagged card, which a translation may word apart.
    var name: String {
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
        case .flagged:
            String(
                localized: "inbox-kind.flagged", defaultValue: "Flagged",
                comment: "In the Cards window's inbox, the kind of a row: a flagged card.")
        }
    }
}
