import FichaCore
import Foundation
internal import GRDB
internal import ZIPFoundation

/// What importing a file would do, as the engine read it, before anything
/// changes: the cards that come in, in the file's order, how many of them
/// repeat the user's cards, the lines it left out, and the tags it proposes.
public struct ImportPreview: Sendable, Equatable {
    /// What kind of file an import reads.
    public enum Kind: Sendable, Equatable {
        /// A text file of cards, or a zip with one and its cards' images and
        /// sounds.
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
    /// The sounds the cards refer to, as the images.
    let sounds: [SoundName: CardSound]
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
    /// How many of the file's cards that repeat none of the user's are made
    /// of two of its cards, one for each way, and come in going both ways
    /// with an import that leaves progress out: an Anki package's notes that
    /// make a reversed card (ADR 0016).
    public let reversedNoteCount: Int
    /// How many of those come in going both ways with an import that brings
    /// progress: all but those whose reversed card alone Anki suspended,
    /// which come in one way.
    public let reversedNoteCountBringingProgress: Int

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

    /// How many of the file's cards come in without some of the sounds the
    /// file gives them: an Anki package's cards with more than one sound on
    /// a side, which bring the first.
    public var cardsWithSoundsDropped: Int {
        cards.count(where: \.hasSoundsDropped)
    }

    /// How many of the file's cards come in without a sound the file gives
    /// them that Ficha can't read: an Anki package's cards whose side holds
    /// something else too.
    public var cardsWithUnreadableSoundsLeftOut: Int {
        cards.count(where: \.hasUnreadableSoundsLeftOut)
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
    /// A tag of the file's that it repeats as duplicates are compared, such
    /// as “banderas” for “Banderas”, takes its name, but a user's card that
    /// the import updates keeps its own.
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
    /// file and its cards' images and sounds, or an Anki package, and says
    /// what importing it would do, without changing anything. A zip's files
    /// are read as they're needed, so that a big one takes no more memory
    /// than a few of its files: one at a time, and an Anki package's sounds
    /// as many at once as the Mac has cores, since they're converted as they
    /// come in. It takes a while for a big file, so the app calls it away
    /// from the main actor.
    public func previewImport(of file: URL) async throws(EngineError) -> ImportPreview {
        let name = file.lastPathComponent
        // A file the user chose in an open panel, in an app with a sandbox,
        // held until it's read; outside one, there's nothing to start.
        let isAccessing = file.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                file.stopAccessingSecurityScopedResource()
            }
        }
        var reading: ImportReading
        var images: [ImageName: CardImage] = [:]
        var sounds: [SoundName: CardSound] = [:]
        let kind: ImportPreview.Kind
        do throws(CardsFileProblem) {
            if let archive = try zipArchive(at: file) {
                if isAnkiPackage(archive) {
                    (reading, images, sounds) = try await readAnkiPackage(
                        archive, in: calendar, drawingSVGsWith: newSVGDrawer?())
                    kind = .ankiPackage
                } else {
                    (reading, images, sounds) = try await readZipOfCards(archive, drawingSVGsWith: newSVGDrawer?())
                    kind = .cardsFile
                }
            } else if file.pathExtension.lowercased() == "apkg" {
                throw .unreadableAnkiPackage
            } else {
                reading = try await CardsTextFile.read(try fileContents(of: file))
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
        return try preview(reading, of: name, kind: kind, images: images, sounds: sounds)
    }

    /// What importing `reading`, read from the file named `fileName`, would
    /// do, whatever reader read it, with the tags each card proposes.
    /// `images` and `sounds` are the files that came in with the file, of
    /// which the preview holds those its cards refer to, until they're
    /// imported.
    func preview(
        _ reading: ImportReading, of fileName: String, kind: ImportPreview.Kind, images: [ImageName: CardImage] = [:],
        sounds: [SoundName: CardSound] = [:]
    ) throws(EngineError) -> ImportPreview {
        let repeated = try read { db in try repeatedCards(of: reading.cards, in: db) }
        let referredImages = Set(reading.cards.flatMap(\.content.images))
        let referredSounds = Set(reading.cards.flatMap(\.content.sounds))
        let proposedTags = reading.cards.flatMap(\.proposedTags).uniqued()
        let placedCount = zip(reading.cards, repeated).count { card, repeated in
            switch (card.progress?.stage, repeated) {
            case (.learning?, nil), (.review?, nil): true
            case (.new?, _), (nil, _), (_, _?): false
            }
        }
        // A card made of two, one for each way, has the second's progress.
        let newReversedNotes = zip(reading.cards, repeated).filter { card, repeated in
            repeated == nil && card.backFirstProgress != nil
        }.map(\.0)
        return ImportPreview(
            fileName: fileName, kind: kind, cards: reading.cards,
            images: images.filter { referredImages.contains($0.key) },
            sounds: sounds.filter { referredSounds.contains($0.key) }, leftOut: reading.leftOut,
            proposedTags: proposedTags, repeatedCount: repeated.count { $0 != nil },
            placedCount: placedCount,
            reversedNoteCount: newReversedNotes.count { $0.goesBothWays(bringingProgress: false) },
            reversedNoteCountBringingProgress: newReversedNotes.count { $0.goesBothWays(bringingProgress: true) })
    }

    /// Imports the cards `preview` read, as the user chose: each card that
    /// repeats none of the user's comes in as new, in the file's order, so
    /// new cards come up for their first view in that order; each one that
    /// repeats a card of the user's updates it or is skipped. A card goes
    /// both ways as the file says, and an updated one keeps its own Both ways
    /// when the file says nothing of it. Every card that comes in or is
    /// updated gets the tags it proposes, as the user named them, and its
    /// tags that repeat each other as duplicates are compared, such as
    /// “banderas” and “Banderas”, come in as one.
    /// Which cards repeat the user's is worked out again as their cards are
    /// now. Before it changes anything, it saves a copy before an import,
    /// which restoring undoes the import; an import that changes nothing
    /// saves none. The images and sounds that came with the file are kept
    /// with the cards that refer to them, and an image or a sound an updated
    /// card no longer refers to goes once no card uses it. Returns what it
    /// did.
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
        // The images and sounds that came in, kept before the cards that
        // refer to them, and those of them no card uses removed again after,
        // such as a skipped card's, or all of them when the cards can't be
        // written.
        let held = HeldFiles(images: Array(preview.images.values), sounds: Array(preview.sounds.values))
        let (added, updated, skipped, letGo) = try keeping(held) { () throws(EngineError) in
            try write { db in
                var (added, updated, skipped) = (0, 0, 0)
                var letGo = (images: Set<ImageName>(), sounds: Set<SoundName>())
                for (card, repeated) in zip(preview.cards, try repeatedCards(of: preview.cards, in: db)) {
                    switch (repeated, choices.repeatedCards) {
                    case (nil, _):
                        let cardID = try insertCard(
                            try card.content(adding: addedTags(card)),
                            bothWays: card.goesBothWays(bringingProgress: choices.bringsProgress), capturedAs: nil,
                            at: importedAt, in: db)
                        if case .brought(let ladder) = choices.progress {
                            try bring(card, to: cardID, onto: ladder, at: importedAt, in: db)
                        }
                        added += 1
                    case (let repeated?, .update):
                        let updatedCard = try replaceContent(
                            of: repeated.id, with: try card.update(of: repeated, adding: addedTags(card)),
                            at: importedAt, in: db)
                        if card.fields.contains(.bothWays) {
                            _ = try setBothWays(card.bothWays, of: repeated.id, in: db)
                        }
                        letGo.images.formUnion(repeated.images.subtracting(updatedCard.images))
                        letGo.sounds.formUnion(repeated.sounds.subtracting(updatedCard.sounds))
                        updated += 1
                    case (_?, .skip):
                        skipped += 1
                    }
                }
                return (added, updated, skipped, letGo)
            }
        }
        removeFilesNoCardUses(
            images: Set(preview.images.keys).union(letGo.images), sounds: Set(preview.sounds.keys).union(letGo.sounds))
        return ImportOutcome(added: added, updated: updated, skipped: skipped, copyBeforeImport: copy)
    }

    /// Gives the card with the id `cardID`, which is coming in new to Ficha
    /// at `importedAt` as `card`, the progress it brings from the app it
    /// comes from: for each of its ways, a placement on `ladder`, the first
    /// entry of that way's review log, unless it's new there; and a burial
    /// when it was suspended there, as its front-first way says.
    private func bring(
        _ card: ImportedCard, to cardID: Int64, onto ladder: Ladder, at importedAt: Date, in db: Database
    ) throws {
        for (way, progress) in [(Way.frontFirst, card.progress), (.backFirst, card.backFirstProgress)] {
            if let placement = progress.flatMap({ ladder.placement(of: $0.stage) }) {
                try place(cardID, way: way, on: placement, at: importedAt, in: db)
            }
        }
        if card.progress?.isSuspended == true {
            _ = try bury(cardID, at: importedAt, in: db)
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

extension ImportChoices {
    /// Whether the cards bring where they stood in the app the file comes
    /// from.
    var bringsProgress: Bool {
        if case .brought = progress { true } else { false }
    }
}

extension ImportedCard {
    /// Whether the card goes both ways as it comes in new, by an import that
    /// brings progress or not: as the file says, but one way when the
    /// import brings progress and the app the file comes from suspended its
    /// back-first way alone, as Anki suspends a note's reversed card, whose
    /// step it keeps (ADR 0016). Its front-first way suspended, it comes in
    /// buried, both ways.
    func goesBothWays(bringingProgress: Bool) -> Bool {
        guard bringingProgress, backFirstProgress?.isSuspended == true else {
            return bothWays
        }
        return bothWays && progress?.isSuspended == true
    }

    /// The card as it comes in, as new, with its images, its sounds and
    /// `tags` added to its own, as `importedTags` joins them.
    fileprivate func content(adding tags: [String]) throws -> CardContent {
        try checked(
            CardContent(
                type: content.type, front: content.front, back: content.back,
                tags: importedTags(content.tags, adding: tags),
                source: content.source, frontImage: content.frontImage, backImage: content.backImage,
                frontSound: content.frontSound, backSound: content.backSound))
    }

    /// What `card`, the user's card it repeats, holds once it's updated: its
    /// own front, with its image and its sound, the back and every field the
    /// file gives, the back's image and sound among them, its own fields that
    /// the file doesn't, and `tags` added to its tags, as `importedTags` joins
    /// them, spelled as the card has them. Both ways isn't what a card holds:
    /// the import sets it apart.
    fileprivate func update(of card: Card, adding tags: [String]) throws -> CardContent {
        try checked(
            CardContent(
                type: fields.contains(.type) ? content.type : card.type,
                front: card.front,
                back: content.back,
                tags: importedTags(fields.contains(.tags) ? content.tags : card.tags, adding: tags, keeping: card.tags),
                source: fields.contains(.source) ? content.source : card.source,
                frontImage: card.frontImage,
                backImage: fields.contains(.backImage) ? content.backImage : card.backImage,
                frontSound: card.frontSound,
                backSound: fields.contains(.backSound) ? content.backSound : card.backSound))
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

/// The tags an imported card gets: `own`, the file's for it or the user's
/// card's, then `proposed`, the import's as the user named them, each once
/// as duplicates are compared, so “banderas” and “Banderas” are one (#229).
/// A tag spelled several ways takes the spelling of `kept`, the tags of the
/// user's card it updates, or else of `proposed`, the name the user saw in
/// the Import sheet, or else its first.
private func importedTags(_ own: [String], adding proposed: [String], keeping kept: [String] = []) -> [String] {
    var spellings: [String: String] = [:]
    for tag in kept + proposed where spellings[duplicateKey(tag)] == nil {
        spellings[duplicateKey(tag)] = tag
    }
    return (own + proposed).map { spellings[duplicateKey($0)] ?? $0 }.uniqued(on: duplicateKey)
}

extension ImportReading {
    /// The reading with `tags` proposed for every card, on top of what it
    /// proposes.
    fileprivate func proposing(_ tags: [String]) -> ImportReading {
        ImportReading(
            cards: cards.map { card in
                ImportedCard(
                    content: card.content, bothWays: card.bothWays, fields: card.fields, line: card.line,
                    proposedTags: (card.proposedTags + tags).uniqued(), progress: card.progress,
                    backFirstProgress: card.backFirstProgress, hasImagesDropped: card.hasImagesDropped,
                    hasSoundsDropped: card.hasSoundsDropped, hasUnreadableSoundsLeftOut: card.hasUnreadableSoundsLeftOut
                )
            },
            leftOut: leftOut)
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
