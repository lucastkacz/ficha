import FichaCore
import Foundation

extension CardsWindowState {
    /// The Cards window's Export sheet while it's open: what it offers to
    /// export, each with how many cards it takes, and what the user chose.
    public struct Exporting: Sendable, Equatable {
        /// What the sheet offers, in its menu's order: the selected cards
        /// while the table lists some, all cards, and then each tag the
        /// sidebar lists that a card has, in its order.
        public let choices: [ExportChoice]
        /// What Export writes to the file the user picks.
        public fileprivate(set) var chosen: CardsToExport

        /// The name the save panel proposes for the file.
        public enum FileName: Sendable, Equatable {
            /// A name for the selected cards.
            case selectedCards
            /// A name for all cards.
            case allCards
            /// The tag's own name, for the cards with it, which another
            /// Ficha proposes as their tag when it imports them.
            case tag(String)
        }

        /// What the menu offers before its divider: the selected cards,
        /// while it offers them, and all cards.
        public var cardChoices: [ExportChoice] {
            choices.filter { !$0.isTag }
        }

        /// What the menu offers after its divider: each tag's cards.
        public var tagChoices: [ExportChoice] {
            choices.filter(\.isTag)
        }

        /// The name the save panel proposes for the file of what's chosen.
        public var fileName: FileName {
            switch chosen {
            case .cards: .selectedCards
            case .all: .allCards
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
        /// images, rather than a text file: when a card it takes has an
        /// image.
        public var writesZip: Bool {
            choices.first { $0.cards == chosen }?.holdsImages ?? false
        }
    }

    /// Something the Export sheet offers to export, with how many cards it
    /// takes, and whether one of them has an image, as they were when the
    /// sheet opened.
    public struct ExportChoice: Sendable, Equatable {
        public let cards: CardsToExport
        public let cardCount: Int
        public let holdsImages: Bool

        public init(cards: CardsToExport, cardCount: Int, holdsImages: Bool = false) {
            self.cards = cards
            self.cardCount = cardCount
            self.holdsImages = holdsImages
        }

        /// Whether it's a tag's cards.
        fileprivate var isTag: Bool {
            if case .tag = cards {
                return true
            }
            return false
        }
    }

    /// Opens the Export sheet, with what it offers counted, on what the
    /// window points at: the selected cards when several are, since one is
    /// often only the card the detail shows; else the tag the sidebar chose;
    /// else all cards. When the cards can't be read, it records why, and the
    /// sheet stays closed.
    public mutating func startExport() {
        let selected = Set(selectedRows.map(\.id))
        let offered: [CardsToExport] =
            (selected.isEmpty ? [] : [.cards(selected)]) + [.all] + tags.map { .tag($0.name) }
        var counts: [(count: Int, holdsImages: Bool)] = []
        let isRead = perform(.export) { engine throws(EngineError) in
            counts = try engine.cardCounts(toExport: offered)
        }
        guard isRead else { return }
        let choices = zip(offered, counts).compactMap { cards, counted -> ExportChoice? in
            if case .tag = cards, counted.count == 0 {
                return nil
            }
            return ExportChoice(cards: cards, cardCount: counted.count, holdsImages: counted.holdsImages)
        }
        let pointedAt: CardsToExport? =
            if selected.count > 1 {
                .cards(selected)
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
