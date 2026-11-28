import FichaCore
import Foundation
internal import GRDB

// The engine's import, which brings in a deck's `.ficha` alone (ADR 0041,
// ADR 0044, `DeckFile.swift`): what its text file of cards and its images
// and sounds would do, read before anything changes, and the cards that
// come in, skipping those that repeat the user's.

/// What importing a deck's `.ficha` would do, as the engine read it, before
/// anything changes: the cards that come in, in the file's order, with the
/// images and sounds they refer to, and the lines it left out.
struct ImportPreview: Sendable, Equatable {
    /// The file's name, as Finder shows it.
    let fileName: String
    /// The cards the file holds, in its order.
    let cards: [ImportedCard]
    /// The images the cards refer to, as they came in with the file, which
    /// Ficha keeps once they're imported.
    let images: [ImageName: CardImage]
    /// The sounds the cards refer to, as the images.
    let sounds: [SoundName: CardSound]
    /// The lines that make no card, with why, in the file's order.
    let leftOut: [LeftOutLine]

    /// How many cards the file holds.
    var cardCount: Int {
        cards.count
    }
}

/// What an import did.
public struct ImportOutcome: Sendable, Equatable {
    /// How many cards came in, as new.
    public let added: Int
    /// How many of the file's cards repeated one of the user's and were
    /// skipped.
    public let skipped: Int
    /// The copy before the import, which restoring undoes it, or nil when
    /// nothing came in, or the engine is in memory.
    public let copyBeforeImport: DatabaseCopy?

    public init(added: Int, skipped: Int, copyBeforeImport: DatabaseCopy?) {
        self.added = added
        self.skipped = skipped
        self.copyBeforeImport = copyBeforeImport
    }
}

extension Engine {
    /// What importing `fileReading`, read from the file named `fileName`,
    /// would do: in a file that doesn't name its Type column, a card whose
    /// type is neither one of the four nor a user type the user has stays out
    /// (`ImportReading.typeColumnIsNamed`). `images` and `sounds` are the
    /// files that came in with the file, of which the preview holds those its
    /// cards refer to, until they're imported.
    func preview(
        _ fileReading: ImportReading, of fileName: String, images: [ImageName: CardImage] = [:],
        sounds: [SoundName: CardSound] = [:]
    ) throws(EngineError) -> ImportPreview {
        let reading = try read { db in fileReading.leavingOutUnknownTypes(knowing: try CardTypesByName(in: db)) }
        let referredImages = Set(reading.cards.flatMap(\.content.images))
        let referredSounds = Set(reading.cards.flatMap(\.content.sounds))
        return ImportPreview(
            fileName: fileName, cards: reading.cards, images: images.filter { referredImages.contains($0.key) },
            sounds: sounds.filter { referredSounds.contains($0.key) }, leftOut: reading.leftOut)
    }

    /// Imports the cards `preview` read: each card that repeats none of the
    /// user's comes in as new, in the file's order, so new cards come up for
    /// their first review in that order, and each one that repeats a card of
    /// the user's is skipped, leaving theirs as it is. A card goes both ways
    /// as the file says, and comes into the deck it names, or Default for
    /// none, which the import makes when the user doesn't have it. Its tags
    /// that repeat each other as duplicates are compared, such as “banderas”
    /// and “Banderas”, come in as one. A card's type is the one its name
    /// stands for, one of the four or a user type, which the import makes,
    /// with no emoji, when the user has none by that name. Which cards repeat
    /// the user's is worked out again as their cards are now. Before it
    /// changes anything, it saves a copy before an import, which restoring
    /// undoes the import; an import that adds nothing saves none. The images
    /// and sounds that came with the file are kept with the cards that refer
    /// to them. Returns what it did. Refuses a deck's name that
    /// `Engine.makeDeck(named:)` refuses, changing nothing.
    @discardableResult
    func importCards(_ preview: ImportPreview) throws(EngineError) -> ImportOutcome {
        // The deck each deck the cards name comes in under, by the name, ""
        // for none, each checked before anything changes.
        var decks: [String: String] = [:]
        for proposed in Set(preview.cards.map(\.deck)) {
            decks[proposed ?? ""] = try deckComingIn(proposed: proposed)
        }
        let skippedCount = try read { db in try repeatedCards(of: preview.cards, in: db) }.count { $0 != nil }
        guard preview.cards.count > skippedCount else {
            return ImportOutcome(added: 0, skipped: skippedCount, copyBeforeImport: nil)
        }
        let copy = try saveCopy(.beforeImport)
        let importedAt = time.now
        // The images and sounds that came in, kept before the cards that
        // refer to them, and those of them no card uses removed again after,
        // such as a skipped card's, or all of them when the cards can't be
        // written.
        let held = HeldFiles(images: Array(preview.images.values), sounds: Array(preview.sounds.values))
        let (added, skipped) = try keeping(held) { () throws(EngineError) in
            try write { db in
                var (added, skipped) = (0, 0)
                var types = try CardTypesByName(in: db)
                for (card, repeated) in zip(preview.cards, try repeatedCards(of: preview.cards, in: db)) {
                    guard repeated == nil else {
                        skipped += 1
                        continue
                    }
                    guard let deck = decks[card.deck ?? ""] else {
                        throw unreadable("The card on line \(card.line) proposes a deck the import didn't check")
                    }
                    let type = try types.type(named: card.typeName, savingIn: db)
                    try insertCard(
                        try card.content(as: type), deck: deck, bothWays: card.bothWays, at: importedAt, in: db)
                    added += 1
                }
                return (added, skipped)
            }
        }
        removeFilesNoCardUses(images: Set(preview.images.keys), sounds: Set(preview.sounds.keys))
        return ImportOutcome(added: added, skipped: skipped, copyBeforeImport: copy)
    }
}

/// The deck a card of a deck's file that names `proposed`, or nil for none,
/// comes into new, by its whole name, cleaned up as `Engine.makeDeck(named:)`
/// cleans it up, or Default for none. An error for a name the import
/// refuses, which it refuses before it brings any card.
func deckComingIn(proposed: String?) throws(EngineError) -> String {
    guard let proposed else {
        return Deck.defaultName
    }
    return try checkedDeckName(proposed)
}

extension ImportedCard {
    /// The card as it comes in, as new, of `type`, the one its type's name
    /// stands for, with its images and sounds, and its tags each once, as
    /// duplicates are compared, so “banderas” and “Banderas” are one (#229),
    /// spelled as the first of them.
    fileprivate func content(as type: CardType?) throws -> CardContent {
        guard
            let made = CardContent(
                type: type, front: content.front, back: content.back,
                tags: content.tags.uniqued(on: duplicateKey), source: content.source,
                frontImage: content.frontImage, backImage: content.backImage, frontSound: content.frontSound,
                backSound: content.backSound)
        else {
            throw unreadable("The card on line \(line) has a blank front or back after its import")
        }
        return made
    }
}

extension ImportReading {
    /// The reading of a text file with each card's deck without its top
    /// levels while they're one of the names Default goes by
    /// (`Deck.isOneOfDefaultNames(_:)`), as Anki writes its Default, and a
    /// deck inside it, in a text file, and with no deck when that leaves no
    /// level: so that “Default” stands for Default, and “Default::Viejas” for
    /// “Viejas”.
    func outsideDefault() -> ImportReading {
        ImportReading(
            cards: cards.map { card in
                var levels = TagPath.levels(of: card.deck ?? "")[...]
                while let top = levels.first, Deck.isOneOfDefaultNames(top) {
                    levels = levels.dropFirst()
                }
                return ImportedCard(
                    content: card.content, typeName: card.typeName, bothWays: card.bothWays, line: card.line,
                    deck: TagPath.normalized(levels.joined(separator: TagPath.separator)))
            },
            leftOut: leftOut, typeColumnIsNamed: typeColumnIsNamed)
    }

    /// The reading with each card whose type names neither one of the four
    /// nor a user type `types` knows left out, saying why, when the file
    /// doesn't name its Type column (`typeColumnIsNamed`), its lines left
    /// out in the file's order.
    fileprivate func leavingOutUnknownTypes(knowing types: CardTypesByName) -> ImportReading {
        guard !typeColumnIsNamed else {
            return self
        }
        var kept: [ImportedCard] = []
        var leftOut = leftOut
        for card in cards {
            if let name = card.typeName, types.existingType(named: name) == nil {
                leftOut.append(LeftOutLine(line: card.line, reason: .unknownType(name)))
            } else {
                kept.append(card)
            }
        }
        return ImportReading(cards: kept, leftOut: leftOut.sorted { $0.line < $1.line }, typeColumnIsNamed: false)
    }
}

/// For each card in `cards`, in order, the user's card it repeats by the
/// duplicate rule, or nil when it repeats none. An import's rule compares a
/// front's image too: two fronts repeat when their texts do, and their
/// images, when both have one, are the same image. So a front with only an
/// image repeats one with only that image, and fronts with one caption,
/// such as a deck's "? · Location" over each country's map, repeat by their
/// images. Each of the user's cards is repeated by one card of the file at
/// most, so that importing a file again repeats it whole, two cards of it
/// with the same front included. The file's cards find theirs in the order
/// of `FrontImageMatch`, each way across the whole file and in its order:
/// so a card whose front lacks an image doesn't take the card a later one
/// has the very image of. A front with neither text nor an image, which
/// holds only a sound, repeats none.
func repeatedCards(of cards: [ImportedCard], in db: Database) throws -> [Card?] {
    var cardsByFront = Dictionary(grouping: try allCards(in: db)) { duplicateKey($0.front) }
    var repeated = [Card?](repeating: nil, count: cards.count)
    for match in FrontImageMatch.allCases {
        for (index, card) in cards.enumerated() where repeated[index] == nil {
            let (front, image) = (card.content.front, card.content.frontImage)
            let key = duplicateKey(front)
            guard !CardContent.isBlank(front, image: image, sound: nil),
                let found = cardsByFront[key]?.firstIndex(where: {
                    match.matches(image, $0.frontImage, frontHasText: !CardContent.isBlank(front))
                })
            else {
                continue
            }
            repeated[index] = cardsByFront[key]?.remove(at: found)
        }
    }
    return repeated
}

/// The cards of `preview` that importing it would bring in new at `now`, out
/// of the cards in `db`, as `Engine.importCards(_:)` adds them: those that
/// repeat none of the user's, in their order, each with the deck it comes
/// into and whether it goes both ways. How fast? counts a deck's `.ficha` by
/// them, before it comes in (#458, #554).
func cardsComingIn(_ preview: ImportPreview, at now: Date, in db: Database) throws -> [CardComingIn] {
    var coming: [CardComingIn] = []
    for (card, repeated) in zip(preview.cards, try repeatedCards(of: preview.cards, in: db)) where repeated == nil {
        coming.append(
            CardComingIn(deck: try deckComingIn(proposed: card.deck), bothWays: card.bothWays, createdAt: now))
    }
    return coming
}

/// The ways an imported front repeats one of the user's fronts with the same
/// text, in the order an import tries them.
private enum FrontImageMatch: CaseIterable {
    /// Both fronts have the same image, or neither has one.
    case sameImage
    /// Only one of the two fronts has an image, and they have text.
    case imageOnOneSide

    func matches(_ image: ImageName?, _ other: ImageName?, frontHasText: Bool) -> Bool {
        switch self {
        case .sameImage: image == other
        case .imageOnOneSide: frontHasText && (image == nil) != (other == nil)
        }
    }
}
