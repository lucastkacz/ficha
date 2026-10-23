import FichaCore
import Foundation
internal import GRDB

/// What importing a file would do, as the engine read it, before anything
/// changes: the cards that come in, in the file's order, how many of them
/// repeat the user's cards, the lines it left out, and the tags it proposes
/// for every card.
public struct ImportPreview: Sendable, Equatable {
    /// The file's name, as Finder shows it.
    public let fileName: String
    /// The cards the file holds, in its order.
    let cards: [ImportedCard]
    /// The images the cards refer to, as they came in with the file, which
    /// Ficha keeps once they're imported.
    let images: [ImageName: CardImage]
    /// The lines that make no card, with why, in the file's order.
    public let leftOut: [LeftOutLine]
    /// The tags the import proposes to add to every card, on top of each
    /// card's own: for a text file, its name without its extension.
    public let proposedTags: [String]
    /// How many of the file's cards repeat one of the user's, by the
    /// duplicate rule, as the user's cards were when the file was read.
    public let repeatedCount: Int

    /// How many cards the file holds.
    public var cardCount: Int {
        cards.count
    }

    /// How many of the file's cards are new: those that repeat none of the
    /// user's.
    public var newCount: Int {
        cards.count - repeatedCount
    }
}

/// What the user chooses before an import.
public struct ImportChoices: Sendable, Equatable {
    /// What happens to a card of the file that repeats one of the user's.
    public enum RepeatedCards: Sendable, Equatable {
        /// The user's card takes everything the file gives it but its front,
        /// and keeps its step and review log, as an edit does.
        case update
        /// The user's card stays as it is, and the file's doesn't come in.
        case skip
    }

    /// The name each tag the preview proposes goes on the cards with, by the
    /// proposed name: another one, or a blank one, which leaves the tag out.
    /// A proposed tag that isn't here goes on the cards as it's proposed.
    public var tagNames: [String: String]
    public var repeatedCards: RepeatedCards

    /// The choices an import starts with: every proposed tag as it's
    /// proposed, and the repeated cards updated.
    public init(tagNames: [String: String] = [:], repeatedCards: RepeatedCards = .update) {
        self.tagNames = tagNames
        self.repeatedCards = repeatedCards
    }
}

/// What an import did.
public struct ImportOutcome: Sendable, Equatable {
    /// How many cards came in, as new.
    public let added: Int
    /// How many of the user's cards the file updated.
    public let updated: Int
    /// How many of the file's cards repeated one of the user's and were
    /// skipped.
    public let skipped: Int
    /// The copy before the import, which restoring undoes it, or nil when
    /// nothing came in or changed, or the engine is in memory.
    public let copyBeforeImport: DatabaseCopy?

    public init(added: Int, updated: Int, skipped: Int, copyBeforeImport: DatabaseCopy?) {
        self.added = added
        self.updated = updated
        self.skipped = skipped
        self.copyBeforeImport = copyBeforeImport
    }
}

extension Engine {
    /// Reads the file of cards at `file`, a text file or a zip with a text
    /// file and its cards' images, and says what importing it would do,
    /// without changing anything.
    public func previewImport(of file: URL) throws(EngineError) -> ImportPreview {
        let name = file.lastPathComponent
        let data: Data
        do {
            // A file the user chose in an open panel, in an app with a
            // sandbox; outside one, there's nothing to start.
            let isAccessing = file.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    file.stopAccessingSecurityScopedResource()
                }
            }
            data = try Data(contentsOf: file)
        } catch {
            logger.error("Couldn't read a file to import: \(String(describing: error))")
            throw .unreadableFile(name, .cannotOpen)
        }
        let reading: ImportReading
        var images: [ImageName: CardImage] = [:]
        do throws(CardsFileProblem) {
            if isZip(data) {
                (reading, images) = try readZipOfCards(data)
            } else {
                reading = try CardsTextFile.read(data)
            }
        } catch {
            throw .unreadableFile(name, error)
        }
        let tag = file.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return try preview(reading, of: name, proposing: tag.isEmpty ? [] : [tag], images: images)
    }

    /// What importing `reading`, read from the file named `fileName`, would
    /// do, with `tags` proposed for every card, whatever reader read it.
    /// `images` are the images that came in with the file, of which the
    /// preview holds those its cards refer to, until they're imported.
    func preview(
        _ reading: ImportReading, of fileName: String, proposing tags: [String],
        images: [ImageName: CardImage] = [:]
    ) throws(EngineError) -> ImportPreview {
        let repeated = try read { db in try repeatedCards(of: reading.cards, in: db) }
        let referred = Set(reading.cards.flatMap { [$0.content.frontImage, $0.content.backImage].compactMap(\.self) })
        return ImportPreview(
            fileName: fileName, cards: reading.cards, images: images.filter { referred.contains($0.key) },
            leftOut: reading.leftOut, proposedTags: tags, repeatedCount: repeated.count { $0 != nil })
    }

    /// Imports the cards `preview` read, as the user chose: each card that
    /// repeats none of the user's comes in as new, in the file's order, so
    /// new cards come up for their first view in that order; each one that
    /// repeats a card of the user's updates it or is skipped. Every card that
    /// comes in or is updated gets the proposed tags, as the user named them.
    /// Which cards repeat the user's is worked out again as their cards are
    /// now. Before it changes anything, it saves a copy before an import,
    /// which restoring undoes the import; an import that changes nothing
    /// saves none. The images that came with the file are kept with the
    /// cards that refer to them, and an image an updated card no longer
    /// refers to goes once no card uses it. Returns what it did.
    @discardableResult
    public func importCards(_ preview: ImportPreview, choosing choices: ImportChoices) throws(EngineError)
        -> ImportOutcome
    {
        let addedTags = preview.proposedTags.map {
            (choices.tagNames[$0] ?? $0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let repeatedCount = try read { db in try repeatedCards(of: preview.cards, in: db) }.count { $0 != nil }
        let skippedCount = choices.repeatedCards == .skip ? repeatedCount : 0
        guard preview.cards.count > skippedCount else {
            return ImportOutcome(added: 0, updated: 0, skipped: skippedCount, copyBeforeImport: nil)
        }
        let copy = try copyBeforeImport()
        let importedAt = time.now
        // The images that came in, kept before the cards that refer to them,
        // and those of them no card uses removed again after, such as a
        // skipped card's, or all of them when the cards can't be written.
        let comingIn = Set(preview.images.keys)
        var (added, updated, skipped) = (0, 0, 0)
        var letGo = Set<ImageName>()
        do throws(EngineError) {
            for image in preview.images.values {
                try keepImage(image)
            }
            (added, updated, skipped, letGo) = try write { db in
                var (added, updated, skipped, letGo) = (0, 0, 0, Set<ImageName>())
                for (card, repeated) in zip(preview.cards, try repeatedCards(of: preview.cards, in: db)) {
                    switch (repeated, choices.repeatedCards) {
                    case (nil, _):
                        try insertCard(try card.content(adding: addedTags), capturedAs: nil, at: importedAt, in: db)
                        added += 1
                    case (let repeated?, .update):
                        let updatedCard = try replaceContent(
                            of: repeated.id, with: try card.update(of: repeated, adding: addedTags), in: db)
                        letGo.formUnion(repeated.images.subtracting(updatedCard.images))
                        updated += 1
                    case (_?, .skip):
                        skipped += 1
                    }
                }
                return (added, updated, skipped, letGo)
            }
        } catch {
            removeImagesNoCardUses(among: comingIn)
            throw error
        }
        removeImagesNoCardUses(among: comingIn.union(letGo))
        return ImportOutcome(added: added, updated: updated, skipped: skipped, copyBeforeImport: copy)
    }

    /// Saves a copy before an import in the Backups folder, and returns it,
    /// or nil for an engine in memory, which keeps no copies.
    private func copyBeforeImport() throws(EngineError) -> DatabaseCopy? {
        guard let backupsFolder else {
            return nil
        }
        return try saveCopy(of: database, as: .beforeImport, at: time.now, in: backupsFolder)
    }
}

extension ImportedCard {
    /// The card as it comes in, as new, with its images and `tags` added to
    /// its own.
    fileprivate func content(adding tags: [String]) throws -> CardContent {
        try checked(
            CardContent(
                type: content.type, front: content.front, back: content.back, tags: content.tags.adding(tags),
                source: content.source, frontImage: content.frontImage, backImage: content.backImage))
    }

    /// What `card`, the user's card it repeats, holds once it's updated: its
    /// own front, with its image, the back and every field the file gives,
    /// the back's image among them, its own fields that the file doesn't,
    /// and `tags` added to its tags.
    fileprivate func update(of card: Card, adding tags: [String]) throws -> CardContent {
        try checked(
            CardContent(
                type: fields.contains(.type) ? content.type : card.type,
                front: card.front,
                back: content.back,
                tags: (fields.contains(.tags) ? content.tags : card.tags).adding(tags),
                source: fields.contains(.source) ? content.source : card.source,
                frontImage: card.frontImage,
                backImage: fields.contains(.backImage) ? content.backImage : card.backImage))
    }

    /// `content`, which a front and a back already checked make, or an error
    /// when the check refuses it, which it never does.
    private func checked(_ content: CardContent?) throws -> CardContent {
        guard let content else {
            throw unreadable("The card on line \(line) has a blank front or back after its import")
        }
        return content
    }
}

extension [String] {
    /// These tags, then those of `tags` they don't hold yet, in order.
    fileprivate func adding(_ tags: [String]) -> [String] {
        tags.reduce(into: self) { all, tag in
            if !all.contains(tag) {
                all.append(tag)
            }
        }
    }
}

/// For each card in `cards`, in order, the user's card it repeats by the
/// duplicate rule, or nil when it repeats none. Each of the user's cards is
/// repeated by one card of the file at most, the first that repeats it, so
/// that importing a file again repeats it whole, two cards of it with the
/// same front included. A front without text, which holds only an image,
/// repeats none, as in the Cards window's form.
func repeatedCards(of cards: [ImportedCard], in db: Database) throws -> [Card?] {
    var cardsByFront = Dictionary(grouping: try allCards(in: db)) { duplicateKey($0.front) }
    return cards.map { card in
        let key = duplicateKey(card.content.front)
        guard !CardContent.isBlank(card.content.front), let repeated = cardsByFront[key]?.first else {
            return nil
        }
        cardsByFront[key]?.removeFirst()
        return repeated
    }
}
