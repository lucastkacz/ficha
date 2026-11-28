import FichaCore
import Foundation

extension CardsWindowState {
    /// The Cards window's Export sheet while it's open: what it offers to
    /// export, each with how many cards it takes, and what the user chose.
    public struct Exporting: Sendable, Equatable {
        /// What the sheet offers, in its menu's order: the selected cards
        /// while the grid lists some, all cards, then each deck the sidebar
        /// lists that holds a card, in its order. No tag's cards: the window
        /// shows no tags (#538).
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
        }

        /// What the menu offers before its divider: the selected cards,
        /// while it offers them, and all cards.
        public var cardChoices: [ExportChoice] {
            choices.filter { $0.group == .cards }
        }

        /// What the menu offers after its divider: each deck's cards.
        public var deckChoices: [ExportChoice] {
            choices.filter { $0.group == .deck }
        }

        /// The name the save panel proposes for the file of what's chosen.
        public var fileName: FileName {
            switch chosen {
            case .cards: .selectedCards
            case .deck(let name): .deck(name)
            // All cards, and what the engine exports beyond what the sheet
            // offers, which it never chooses: a tag's cards (#538).
            default: .allCards
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
        /// has an image or a sound, and for a deck's cards, which the engine
        /// always writes as the deck's file, a zip (#554).
        public var writesZip: Bool {
            if case .deck = chosen {
                return true
            }
            return choices.first { $0.cards == chosen }?.holdsFiles ?? false
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

        /// Which part of the menu it's in: the sheet offers no other cards
        /// than the selected ones, all cards and each deck's.
        fileprivate var group: Group {
            if case .deck = cards {
                .deck
            } else {
                .cards
            }
        }

        /// A part of the menu, on either side of its divider.
        fileprivate enum Group {
            /// The selected cards and all cards.
            case cards
            case deck
        }
    }

    /// Opens the Export sheet, with what it offers counted, on what the
    /// window points at: the selected cards when several are, since one is
    /// often only the card the detail shows; else the deck the sidebar
    /// chose; else all cards. When the cards can't be read, it records why,
    /// and the sheet stays closed.
    public mutating func startExport() {
        let selected = Set(selectedRows.map(\.id))
        let offered: [CardsToExport] =
            (selected.isEmpty ? [] : [.cards(selected)]) + [.all] + decks.map { .deck($0.deck.name) }
        var counts: [(count: Int, holdsFiles: Bool)] = []
        let isRead = perform(.export) { engine throws(EngineError) in
            counts = try engine.cardCounts(toExport: offered)
        }
        guard isRead else { return }
        let choices = zip(offered, counts).compactMap { cards, counted -> ExportChoice? in
            if case .deck = cards, counted.count == 0 {
                return nil
            }
            return ExportChoice(cards: cards, cardCount: counted.count, holdsFiles: counted.holdsFiles)
        }
        let pointedAt: CardsToExport? =
            if selected.count > 1 {
                .cards(selected)
            } else if case .cards(.deck(let deck)) = sidebarItem {
                .deck(deck)
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
            askForTheFichaDeckAskedToAdd()
        }
    }

    /// Closes the Export sheet.
    public mutating func closeExport() {
        exporting = nil
        askForTheFichaDeckAskedToAdd()
    }
}
