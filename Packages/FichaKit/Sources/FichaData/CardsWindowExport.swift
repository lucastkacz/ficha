import FichaCore
import Foundation

extension CardsWindowState {
    /// The Cards window's Export sheet while it's open: what it offers to
    /// export, each with how many cards it takes, and what the user chose.
    public struct Exporting: Sendable, Equatable {
        /// What the sheet offers, in its menu's order: the selected cards
        /// while the table lists some, all cards, then each deck the sidebar
        /// lists that holds a card, in its order, and each tag All Tags lists
        /// that a card has, in its order.
        public let choices: [ExportChoice]
        /// What Export writes to the file the user picks.
        public fileprivate(set) var chosen: CardsToExport

        /// The name the save panel proposes for the file.
        public enum FileName: Sendable, Equatable {
            /// A name for the selected cards.
            case selectedCards
            /// A name for all cards.
            case allCards
            /// The deck's own name, by `Deck.defaultName` for Default, for
            /// its cards, which another Ficha proposes as their tag when it
            /// imports them.
            case deck(String)
            /// The tag's own name, for the cards with it, which another
            /// Ficha proposes as their tag when it imports them.
            case tag(String)
        }

        /// What the menu offers before its first divider: the selected
        /// cards, while it offers them, and all cards.
        public var cardChoices: [ExportChoice] {
            choices.filter { $0.group == .cards }
        }

        /// What the menu offers between its dividers: each deck's cards.
        public var deckChoices: [ExportChoice] {
            choices.filter { $0.group == .deck }
        }

        /// What the menu offers after its last divider: each tag's cards.
        public var tagChoices: [ExportChoice] {
            choices.filter { $0.group == .tag }
        }

        /// The name the save panel proposes for the file of what's chosen.
        public var fileName: FileName {
            switch chosen {
            case .cards: .selectedCards
            case .all: .allCards
            case .deck(let name): .deck(name)
            case .tag(let name): .tag(name)
            }
        }

        /// How many cards Export writes.
        public var cardCount: Int {
            choices.first { $0.cards == chosen }?.cardCount ?? 0
        }

        /// Whether Export is on: while what it writes takes a card.
        public var canExport: Bool {
            cardCount > 0
        }

        /// Whether Export writes a zip, with the text file and the cards'
        /// images and sounds, rather than a text file: when a card it takes
        /// has an image or a sound.
        public var writesZip: Bool {
            choices.first { $0.cards == chosen }?.holdsFiles ?? false
        }
    }

    /// Something the Export sheet offers to export, with how many cards it
    /// takes, and whether one of them has an image or a sound, as they were
    /// when the sheet opened.
    public struct ExportChoice: Sendable, Equatable {
        public let cards: CardsToExport
        public let cardCount: Int
        public let holdsFiles: Bool

        public init(cards: CardsToExport, cardCount: Int, holdsFiles: Bool = false) {
            self.cards = cards
            self.cardCount = cardCount
            self.holdsFiles = holdsFiles
        }

        /// Which part of the menu it's in.
        fileprivate var group: Group {
            switch cards {
            case .cards, .all: .cards
            case .deck: .deck
            case .tag: .tag
            }
        }

        /// A part of the menu, between its dividers.
        fileprivate enum Group {
            /// The selected cards and all cards.
            case cards
            case deck
            case tag
        }
    }

    /// Opens the Export sheet, with what it offers counted, on what the
    /// window points at: the selected cards when several are, since one is
    /// often only the card the detail shows; else the deck or the tag the
    /// sidebar chose; else all cards. When the cards can't be read, it
    /// records why, and the sheet stays closed.
    public mutating func startExport() {
        let selected = Set(selectedRows.map(\.id))
        let offered: [CardsToExport] =
            (selected.isEmpty ? [] : [.cards(selected)]) + [.all] + decks.map { .deck($0.deck.name) }
            + tags.map { .tag($0.name) }
        var counts: [(count: Int, holdsFiles: Bool)] = []
        let isRead = perform(.export) { engine throws(EngineError) in
            counts = try engine.cardCounts(toExport: offered)
        }
        guard isRead else { return }
        let choices = zip(offered, counts).compactMap { cards, counted -> ExportChoice? in
            switch cards {
            case .deck, .tag:
                guard counted.count > 0 else { return nil }
            case .cards, .all:
                break
            }
            return ExportChoice(cards: cards, cardCount: counted.count, holdsFiles: counted.holdsFiles)
        }
        let pointedAt: CardsToExport? =
            if selected.count > 1 {
                .cards(selected)
            } else if case .cards(.deck(let deck)) = sidebarItem {
                .deck(deck)
            } else if case .cards(.tag(let tag)) = sidebarItem {
                .tag(tag)
            } else {
                nil
            }
        let chosen = choices.first { $0.cards == pointedAt }?.cards ?? .all
        exporting = Exporting(choices: choices, chosen: chosen)
    }

    /// Chooses `cards` to export, among what the sheet offers.
    public mutating func chooseCardsToExport(_ cards: CardsToExport) {
        guard exporting?.choices.contains(where: { $0.cards == cards }) == true else { return }
        exporting?.chosen = cards
    }

    /// Writes what the user chose to `file`, the one they picked in the
    /// save panel, while Export is on, and closes the sheet, or records why
    /// it couldn't, and the sheet stays open.
    public mutating func export(to file: URL) {
        guard let exporting, exporting.canExport else { return }
        let isExported = perform(.export) { engine throws(EngineError) in
            _ = try engine.export(exporting.chosen, to: file)
        }
        if isExported {
            self.exporting = nil
        }
    }

    /// Closes the Export sheet.
    public mutating func closeExport() {
        exporting = nil
    }
}
