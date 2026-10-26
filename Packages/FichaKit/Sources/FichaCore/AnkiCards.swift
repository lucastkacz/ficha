import Foundation

extension AnkiCollection {
    /// Ficha's cards of the collection's cards, as an import reads them: one
    /// for each Anki card, whose front is its question side as Anki renders
    /// it, and whose back is its answer side, from where the answer starts,
    /// both as Anki's reviewer shows them when nothing was typed in a box to
    /// type the answer in, as plain text, with each run of empty lines folded
    /// into one empty line, each with the first image it shows, as `images`
    /// finds it by its name in the package, and the first sound it plays, as
    /// `sounds` finds it, the back's among the answer side's own where the
    /// answer starts, or else above it: a side whose image or sound isn't
    /// found comes in without it, and its other images and sounds are
    /// dropped. A side that is one of Anki's formulas alone,
    /// such as `[$]x^2[/$]`, comes in as the picture Anki drew of it, found
    /// by its name, after the SHA-1 digest `sha1` gives of a text as
    /// lowercase hex, and as its LaTeX when the package lacks it or Ficha
    /// can't read it, as a formula among text does. Each proposes a tag for
    /// each level of its home deck's name, but Default's, and its note's
    /// tags, an underscore in them standing for a space, and brings where it
    /// stands in Anki, its due days as dates in `calendar`, the user's, for
    /// an import that brings progress. But the two cards of a note whose note
    /// type makes a reversed card, when both come in, make one card that
    /// goes both ways: the first card, where it comes, with the tags both
    /// propose, and where the reversed card stands for its back-first way
    /// (ADR 0016). The new cards come first, in Anki's order of new cards,
    /// then the rest by note and template. A card of an Image Occlusion note
    /// type stays out, and so do a card whose template Anki can't render and
    /// one with a side left with neither text, an image nor a sound, each
    /// with its place in that order and why. Throws when a card's note, note
    /// type, template or deck isn't in the collection, or its type isn't one
    /// Anki has, as in a damaged one.
    public func importReading(
        in calendar: Calendar, images: (String) -> ImageLookup, sounds: (String) async -> SoundLookup,
        sha1: (String) -> String
    ) async throws(AnkiCollectionProblem) -> ImportReading {
        var templates: [TemplateKey: Result<ParsedTemplates, AnkiTemplateError>] = [:]
        // Each Anki card, in the order they come in, as Ficha imports it or
        // why it stays out, with its place in that order.
        var ankiCards: [(card: AnkiCard, line: Int, outcome: Imported)] = []
        // The cards that come in of each note whose note type makes a
        // reversed card, by note and template index.
        var reversedNotes: [Int64: [Int: ImportedCard]] = [:]
        for (index, card) in self.cards.sorted(by: isImportedBefore).enumerated() {
            let line = index + 1
            switch try rendering(card, templates: &templates) {
            case .rendered(let rendered):
                let outcome = await rendered.importedCard(
                    line: line, progress: try progress(of: card, in: calendar), images: images, sounds: sounds,
                    sha1: sha1)
                if rendered.makesReversedCards, case .card(let imported) = outcome {
                    reversedNotes[card.noteID, default: [:]][card.templateIndex] = imported
                }
                ankiCards.append((card, line, outcome))
            case .leftOut(let reason):
                ankiCards.append((card, line, .leftOut(reason)))
            }
        }
        var cards: [ImportedCard] = []
        var leftOut: [LeftOutLine] = []
        for (card, line, outcome) in ankiCards {
            switch outcome {
            case .card(let imported):
                // A note's two cards come in as one, where its first card
                // comes, when both come in.
                if let note = reversedNotes[card.noteID], let first = note[0], let reversed = note[1] {
                    if card.templateIndex == 0 {
                        cards.append(first.goingBothWays(with: reversed))
                    }
                } else {
                    cards.append(imported)
                }
            case .leftOut(let reason):
                leftOut.append(LeftOutLine(line: line, reason: reason))
            }
        }
        return ImportReading(cards: cards, leftOut: leftOut)
    }

    /// `card` rendered, or why it stays out, with its template parsed once
    /// for every card in `templates`.
    private func rendering(_ card: AnkiCard, templates: inout [TemplateKey: Result<ParsedTemplates, AnkiTemplateError>])
        throws(AnkiCollectionProblem) -> Rendering
    {
        guard let note = notes[card.noteID] else {
            throw AnkiCollectionProblem("Card \(card.id) is of note \(card.noteID), which isn't there")
        }
        guard let noteType = noteTypes[note.noteTypeID] else {
            throw AnkiCollectionProblem("Note \(card.noteID) is of note type \(note.noteTypeID), which isn't there")
        }
        guard let deck = decks[card.homeDeckID] else {
            throw AnkiCollectionProblem("Card \(card.id) is in deck \(card.homeDeckID), which isn't there")
        }
        let templateIndex = noteType.kind == .cloze ? 0 : card.templateIndex
        guard noteType.templates.indices.contains(templateIndex) else {
            throw AnkiCollectionProblem("Card \(card.id) has template \(templateIndex), which its note type lacks")
        }
        // The card's number, which counts from 1: a cloze card's is the
        // number of the gap it asks for.
        let (number, overflows) = card.templateIndex.addingReportingOverflow(1)
        guard !overflows else {
            throw AnkiCollectionProblem("Card \(card.id) has template \(card.templateIndex)")
        }
        if noteType.isImageOcclusion || (noteType.kind == .cloze && note.fields.contains(where: holdsImageOcclusion)) {
            return .leftOut(.ankiImageOcclusion)
        }
        let template = noteType.templates[templateIndex]
        let key = TemplateKey(noteTypeID: note.noteTypeID, index: templateIndex)
        let parsed =
            templates[key]
            ?? Result { () throws(AnkiTemplateError) in
                ParsedTemplates(
                    question: try AnkiTemplate(parsing: template.question),
                    answer: try AnkiTemplate(parsing: template.answer))
            }
        templates[key] = parsed
        do throws(AnkiTemplateError) {
            let fields = self.fields(
                of: card, numbered: number, note: note, noteType: noteType, template: template, deck: deck)
            let question = try parsed.get().question.render(fields: fields, cardNumber: number, frontSide: nil)
            let answer = try parsed.get().answer.render(fields: fields, cardNumber: number, frontSide: question)
            let front = questionWithoutTypedAnswers(question)
            let shownAnswer = answerShowingTypedAnswers(
                answer, question: question, note: note, noteType: noteType, cardNumber: number)
            let (frontSounds, frontWithoutSounds) = soundTags(in: front)
            let (soundsOnTheBack, backWithoutSounds) = soundTags(in: back(ofAnswer: shownAnswer, question: front))
            // The answer side's own sounds, without the question's that
            // `{{FrontSide}}` shows again, which Anki plays with the
            // question (`qt/aqt/reviewer.py`, `replay_audio`): those of the
            // answer rendered with a front side without its sounds.
            let answersOwnSounds =
                frontSounds.isEmpty
                ? soundTags(in: answer).names
                : soundTags(
                    in: try parsed.get().answer.render(
                        fields: fields, cardNumber: number, frontSide: soundTags(in: question).rest)
                ).names
            // The back plays those where the answer starts, as its text and
            // image are there, or else those above it, as Japanese Core
            // 2000 plays its word and sentence.
            let backsOwnSounds = soundsOnTheBack.filter(answersOwnSounds.contains)
            return .rendered(
                RenderedAnkiCard(
                    card: card, front: frontWithoutSounds, frontSounds: frontSounds, back: backWithoutSounds,
                    backSounds: backsOwnSounds.isEmpty ? answersOwnSounds : backsOwnSounds,
                    tags: tags(of: note, inDeck: card.homeDeckID), makesReversedCards: noteType.makesReversedCards))
        } catch {
            return .leftOut(.brokenAnkiTemplate)
        }
    }

    /// The fields a template of `card`, whose number is `number`, can show,
    /// by their names: its note's, and the special fields Anki adds unless a
    /// field of the note has the same name (`rslib/src/notetype/render.rs`).
    /// A note with fewer fields than its note type has the others empty.
    private func fields(
        of card: AnkiCard, numbered number: Int, note: AnkiNote, noteType: AnkiNoteType, template: AnkiCardTemplate,
        deck: AnkiDeck
    ) -> [String: String] {
        var fields = [
            "Tags": note.tags.joined(separator: " "),
            "Type": noteType.name,
            "Deck": deck.name.joined(separator: "::"),
            "Subdeck": deck.name.last ?? "",
            "CardFlag": card.flags & 7 == 0 ? "" : "flag\(card.flags & 7)",
            "Card": template.name,
            "CardID": "\(card.id)",
            "c\(number)": "1",
        ]
        for (index, name) in noteType.fields.enumerated() {
            fields[name] = note.field(at: index)
        }
        return fields
    }

    /// The tags a card of `note` in the deck `deckID` proposes: one for each
    /// level of the deck's name, without Default's levels, whose id is 1,
    /// whatever its name, then the note's own, with an underscore standing
    /// for a space, as in a text file Anki exports. Each comes once.
    private func tags(of note: AnkiNote, inDeck deckID: Int64) -> [String] {
        var levels = decks[deckID]?.name[...] ?? []
        if let defaultDeck = decks[1], levels.starts(with: defaultDeck.name) {
            levels = levels.dropFirst(defaultDeck.name.count)
        }
        let tags = levels + note.tags.map { $0.replacingOccurrences(of: "_", with: " ") }
        return tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.uniqued()
    }
}

/// Why an Anki collection can't be read: it refers to what isn't in it, as
/// a damaged one does.
public struct AnkiCollectionProblem: Error, Equatable, CustomStringConvertible {
    public let description: String

    init(_ description: String) {
        self.description = description
    }
}

/// Whether `card` comes in before `other`: new cards first, in Anki's order
/// of new cards, then the rest by note and template.
private func isImportedBefore(_ card: AnkiCard, _ other: AnkiCard) -> Bool {
    switch (card.isNew, other.isNew) {
    case (true, false): true
    case (false, true): false
    case (true, true):
        (card.newPosition, card.noteID, card.templateIndex) < (other.newPosition, other.noteID, other.templateIndex)
    case (false, false): (card.noteID, card.templateIndex) < (other.noteID, other.templateIndex)
    }
}

/// A card template of a note type, by the note type's id and its index.
private struct TemplateKey: Hashable {
    let noteTypeID: Int64
    let index: Int
}

/// A card template's question and answer, parsed.
private struct ParsedTemplates {
    let question: AnkiTemplate
    let answer: AnkiTemplate
}

/// An Anki card rendered, or why it stays out.
private enum Rendering {
    case rendered(RenderedAnkiCard)
    case leftOut(LeftOutLine.Reason)
}

/// An Anki card as Anki shows it, before it's a Ficha card: the card, with
/// where it stands in Anki, its front and back as HTML, with their images,
/// without their sounds, which it names apart, the tags it proposes, and
/// whether its note makes a reversed card.
private struct RenderedAnkiCard {
    let card: AnkiCard
    /// The question side.
    let front: String
    /// The names of the sounds the question side plays, each once, in order.
    let frontSounds: [String]
    /// The answer side, from where the answer starts.
    let back: String
    /// The names of the sounds the answer side plays, each once, in order:
    /// its own where the answer starts, or else above it.
    let backSounds: [String]
    let tags: [String]
    /// Whether its note type makes a reversed card, so that it comes in as
    /// one card with its note's other card.
    let makesReversedCards: Bool

    /// The card as Ficha imports it, each side as plain text, with its first
    /// image as `images` finds it, or Anki's picture of its formula, named
    /// after the digest `sha1` gives, and its first sound as `sounds` finds
    /// it, and with `progress`, where it stands in Anki; or why it stays out,
    /// when a side is left with neither text, an image nor a sound.
    func importedCard(
        line: Int, progress: ImportedProgress, images: (String) -> ImageLookup, sounds: (String) async -> SoundLookup,
        sha1: (String) -> String
    ) async -> Imported {
        let front = await AnkiSide(html: front, playing: frontSounds, images: images, sounds: sounds, sha1: sha1)
        let back = await AnkiSide(html: back, playing: backSounds, images: images, sounds: sounds, sha1: sha1)
        guard
            let content = CardContent(
                type: nil, front: front.text, back: back.text, tags: [], source: nil, frontImage: front.image,
                backImage: back.image, frontSound: front.sound, backSound: back.sound)
        else {
            return .leftOut(front.reasonItsCardStaysOut ?? back.reasonItsCardStaysOut ?? .emptyAnkiSide)
        }
        // Its back is Anki's whole, with its image and its sound or none, for
        // a card it updates.
        return .card(
            ImportedCard(
                content: content, fields: [.backImage, .backSound], line: line, proposedTags: tags,
                progress: progress, hasImagesDropped: front.dropsImages || back.dropsImages,
                hasSoundsDropped: front.dropsSounds || back.dropsSounds,
                hasUnreadableSoundsLeftOut: front.leavesOutAnUnreadableSound || back.leavesOutAnUnreadableSound))
    }
}

/// An Anki card as Ficha imports it, or why it stays out.
private enum Imported {
    case card(ImportedCard)
    case leftOut(LeftOutLine.Reason)
}

extension ImportedCard {
    /// The card of an Anki note that makes a reversed card, as it comes in
    /// with `reversed`, its reversed card, as one card that goes both ways
    /// (ADR 0016): with its front and back, the tags both propose, and where
    /// each stood, its own for the front-first way and the reversed card's
    /// for the back-first way.
    fileprivate func goingBothWays(with reversed: ImportedCard) -> ImportedCard {
        ImportedCard(
            content: content, bothWays: true, fields: fields, line: line,
            proposedTags: (proposedTags + reversed.proposedTags).uniqued(), progress: progress,
            backFirstProgress: reversed.progress, hasImagesDropped: hasImagesDropped,
            hasSoundsDropped: hasSoundsDropped,
            hasUnreadableSoundsLeftOut: hasUnreadableSoundsLeftOut)
    }
}

/// The back of a card whose answer side Anki renders as `answer`, after
/// `question`: what follows the line Anki's stock templates mark the answer
/// with, `<hr id=answer>`, when it's there; otherwise the answer without
/// the question, when it starts with it, as Anki's browser shows the
/// answer; otherwise the whole answer.
private func back(ofAnswer answer: String, question: String) -> String {
    if let marker = answer.firstMatch(of: /(?i)<hr\b[^>]*?\bid\s*=\s*(?:"answer"|'answer'|answer\b)[^>]*>/) {
        return String(answer[marker.range.upperBound...])
    }
    if answer.hasPrefix(question) {
        return String(answer.dropFirst(question.count))
    }
    return answer
}
