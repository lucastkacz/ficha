import FichaCore
import Foundation
internal import GRDB

/// What importing a file would do, as the engine read it, before anything
/// changes: the cards that come in, in the file's order, how many of them
/// repeat the user's cards, the lines it left out, and the tags it proposes.
public struct ImportPreview: Sendable, Equatable {
    /// What kind of file an import reads.
    public enum Kind: Sendable, Equatable {
        /// A text file of cards, or a zip with one and its cards' images.
        case cardsFile
        /// An Anki package, with Anki's decks.
        case ankiPackage
    }

    /// The file's name, as Finder shows it.
    public let fileName: String
    public let kind: Kind
    /// The cards the file holds, in its order.
    let cards: [ImportedCard]
    /// The images the cards refer to, as they came in with the file, which
    /// Ficha keeps once they're imported.
    let images: [ImageName: CardImage]
    /// The lines that make no card, with why, in the file's order: for an
    /// Anki package, its cards that make none.
    public let leftOut: [LeftOutLine]
    /// The tags the import proposes to add to its cards, on top of each
    /// card's own, each once, in the order they first come: for a text
    /// file, its name without its extension, for every card; for an Anki
    /// package, the levels of each card's deck and its note's tags, for the
    /// cards that have them.
    public let proposedTags: [String]
    /// How many of the file's cards repeat one of the user's, by the
    /// duplicate rule, as the user's cards were when the file was read.
    public let repeatedCount: Int
    /// How many of the file's cards that repeat none of the user's an
    /// import that brings progress puts on a step: an Anki package's cards
    /// that Anki was reviewing or learning (ADR 0013).
    public let placedCount: Int

    /// How many of the file's lines, or an Anki package's cards, stay out
    /// for a reason.
    public struct LeftOutCount: Sendable, Equatable {
        public let reason: LeftOutLine.Reason
        public let count: Int

        public init(reason: LeftOutLine.Reason, count: Int) {
            self.reason = reason
            self.count = count
        }
    }

    /// How many lines stay out for each reason, in the order each reason
    /// first comes: as the preview of an Anki package lists its cards that
    /// stay out, whose places in the package say nothing to the user.
    public var leftOutCounts: [LeftOutCount] {
        leftOut.reduce(into: []) { counts, line in
            if let index = counts.firstIndex(where: { $0.reason == line.reason }) {
                counts[index] = LeftOutCount(reason: line.reason, count: counts[index].count + 1)
            } else {
                counts.append(LeftOutCount(reason: line.reason, count: 1))
            }
        }
    }

    /// How many cards the file holds.
    public var cardCount: Int {
        cards.count
    }

    /// How many of the file's cards are new: those that repeat none of the
    /// user's.
    public var newCount: Int {
        cards.count - repeatedCount
    }

    /// How many of the file's cards come in without some of the images the
    /// file gives them: an Anki package's cards with more than one image on
    /// a side, which bring the first.
    public var cardsWithImagesDropped: Int {
        cards.count(where: \.hasImagesDropped)
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

    /// Whether the cards bring where they stood in the app the file comes
    /// from, as an Anki package's do (ADR 0013).
    public enum Progress: Sendable, Equatable {
        /// Every card comes in new, and in the user's reviews.
        case leftOut
        /// Each card that comes in new to Ficha comes in where it stood:
        /// one in review on the step of `ladder`, the user's, nearest its
        /// interval, one being learned on the first step, both due when they
        /// were due there, and a new one new; a suspended one comes in
        /// buried. A card of the user's that a repeated card updates keeps
        /// its own progress.
        case brought(onto: Ladder)
    }

    /// The name each tag the preview proposes goes on the cards with, by the
    /// proposed name: another one, or a blank one, which leaves the tag out.
    /// A proposed tag that isn't here goes on the cards as it's proposed.
    public var tagNames: [String: String]
    public var repeatedCards: RepeatedCards
    public var progress: Progress

    /// The choices an import starts with in the engine: every proposed tag
    /// as it's proposed, the repeated cards updated, and progress left out.
    /// The Import sheet starts with progress brought for an Anki package.
    public init(
        tagNames: [String: String] = [:], repeatedCards: RepeatedCards = .update, progress: Progress = .leftOut
    ) {
        self.tagNames = tagNames
        self.repeatedCards = repeatedCards
        self.progress = progress
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
    /// Reads the file of cards at `file`, a text file, a zip with a text
    /// file and its cards' images, or an Anki package, and says what
    /// importing it would do, without changing anything.
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
        var reading: ImportReading
        var images: [ImageName: CardImage] = [:]
        let kind: ImportPreview.Kind
        do throws(CardsFileProblem) {
            if isZip(data) && isAnkiPackage(data) {
                (reading, images) = try readAnkiPackage(data, in: calendar)
                kind = .ankiPackage
            } else if isZip(data) {
                (reading, images) = try readZipOfCards(data)
                kind = .cardsFile
            } else if file.pathExtension.lowercased() == "apkg" {
                throw .unreadableAnkiPackage
            } else {
                reading = try CardsTextFile.read(data)
                kind = .cardsFile
            }
        } catch {
            throw .unreadableFile(name, error)
        }
        if kind == .cardsFile {
            // Every card of a text file gets a tag named after the file.
            let tag = file.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            reading = reading.proposing(tag.isEmpty ? [] : [tag])
        }
        return try preview(reading, of: name, kind: kind, images: images)
    }

    /// What importing `reading`, read from the file named `fileName`, would
    /// do, whatever reader read it, with the tags each card proposes.
    /// `images` are the images that came in with the file, of which the
    /// preview holds those its cards refer to, until they're imported.
    func preview(
        _ reading: ImportReading, of fileName: String, kind: ImportPreview.Kind, images: [ImageName: CardImage] = [:]
    ) throws(EngineError) -> ImportPreview {
        let repeated = try read { db in try repeatedCards(of: reading.cards, in: db) }
        let referred = Set(reading.cards.flatMap { [$0.content.frontImage, $0.content.backImage].compactMap(\.self) })
        var proposedTags: [String] = []
        var seen = Set<String>()
        for tag in reading.cards.flatMap(\.proposedTags) where seen.insert(tag).inserted {
            proposedTags.append(tag)
        }
        let placedCount = zip(reading.cards, repeated).count { card, repeated in
            switch (card.progress?.stage, repeated) {
            case (.learning?, nil), (.review?, nil): true
            case (.new?, _), (nil, _), (_, _?): false
            }
        }
        return ImportPreview(
            fileName: fileName, kind: kind, cards: reading.cards, images: images.filter { referred.contains($0.key) },
            leftOut: reading.leftOut, proposedTags: proposedTags, repeatedCount: repeated.count { $0 != nil },
            placedCount: placedCount)
    }

    /// Imports the cards `preview` read, as the user chose: each card that
    /// repeats none of the user's comes in as new, in the file's order, so
    /// new cards come up for their first view in that order; each one that
    /// repeats a card of the user's updates it or is skipped. Every card that
    /// comes in or is updated gets the tags it proposes, as the user named
    /// them.
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
        /// The tags `card` proposes, as the user named them.
        func addedTags(_ card: ImportedCard) -> [String] {
            card.proposedTags.map { (choices.tagNames[$0] ?? $0).trimmingCharacters(in: .whitespacesAndNewlines) }
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
                        let cardID = try insertCard(
                            try card.content(adding: addedTags(card)), capturedAs: nil, at: importedAt, in: db)
                        if case .brought(let ladder) = choices.progress, let progress = card.progress {
                            try bring(progress, to: cardID, onto: ladder, at: importedAt, in: db)
                        }
                        added += 1
                    case (let repeated?, .update):
                        let updatedCard = try replaceContent(
                            of: repeated.id, with: try card.update(of: repeated, adding: addedTags(card)), in: db)
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

    /// Gives the card with the id `cardID`, which is coming in new to Ficha
    /// at `importedAt`, the progress it brings from the app it comes from:
    /// a placement on `ladder`, the first entry of its review log, unless
    /// it's new there, and a burial when it was suspended there.
    private func bring(
        _ progress: ImportedProgress, to cardID: Int64, onto ladder: Ladder, at importedAt: Date, in db: Database
    ) throws {
        if let (step, due) = ladder.placement(of: progress.stage) {
            try place(cardID, on: step, dueAt: due, at: importedAt, in: db)
        }
        if progress.isSuspended {
            _ = try updateCard(cardID, setting: "buriedAt = ?", to: [importedAt], in: db)
        }
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

extension ImportReading {
    /// The reading with `tags` proposed for every card, on top of what it
    /// proposes.
    fileprivate func proposing(_ tags: [String]) -> ImportReading {
        ImportReading(
            cards: cards.map { card in
                ImportedCard(
                    content: card.content, fields: card.fields, line: card.line,
                    proposedTags: card.proposedTags.adding(tags), progress: card.progress,
                    hasImagesDropped: card.hasImagesDropped)
            },
            leftOut: leftOut)
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
