import Foundation

/// An Anki collection, as an Anki package holds it, in plain values whatever
/// its schema: when it was created, how it counts its days and its
/// scheduler's version, and its note types, decks, notes, cards and their
/// review history, with what Ficha reads of each. A package's
/// reader, which knows the schema, makes it, from the JSON of schema 11 or
/// the tables of schema 18, and `importReading(in:images:sounds:sha1:)`
/// makes Ficha's cards of it, the same way for both. The values follow
/// Anki's source, `rslib/src/storage/` and `rslib/src/notetype/`.
public struct AnkiCollection: Sendable, Equatable {
    /// When the collection was created, `col.crt`, in seconds since 1970:
    /// the day a review card's due day counts from.
    public let creationTime: Int64
    /// How the collection counts its days, from its configuration.
    public let daySettings: AnkiDaySettings
    /// The note types, by their ids.
    public let noteTypes: [Int64: AnkiNoteType]
    /// The decks, by their ids.
    public let decks: [Int64: AnkiDeck]
    /// The notes, by their ids.
    public let notes: [Int64: AnkiNote]
    /// The cards, in any order.
    public let cards: [AnkiCard]
    /// Every card's review history, its `revlog` table, in any order.
    public let revlog: [AnkiRevlogEntry]
    /// The version of Anki's scheduler its configuration says it's on, its
    /// `schedVer`: 2 for Anki 2.1's schedulers and later, and 1 for Anki
    /// 2.0's, which Anki takes when the configuration doesn't say
    /// (`scheduler_version` in `rslib/src/config/mod.rs`).
    public let schedulerVersion: Int

    public init(
        creationTime: Int64, daySettings: AnkiDaySettings, noteTypes: [Int64: AnkiNoteType],
        decks: [Int64: AnkiDeck], notes: [Int64: AnkiNote], cards: [AnkiCard], revlog: [AnkiRevlogEntry],
        schedulerVersion: Int
    ) {
        self.creationTime = creationTime
        self.daySettings = daySettings
        self.noteTypes = noteTypes
        self.decks = decks
        self.notes = notes
        self.cards = cards
        self.revlog = revlog
        self.schedulerVersion = schedulerVersion
    }
}

/// A note type of an Anki collection: the fields its notes have, and the
/// card templates that show them.
public struct AnkiNoteType: Sendable, Equatable {
    /// How a note type makes its cards, by the number Anki stores for it:
    /// schema 11's `type`, schema 18's `kind`.
    public enum Kind: Int, Sendable, Equatable {
        /// A card for each template, as Basic makes them.
        case standard = 0
        /// A card for each cloze number in a note's fields, all with its one
        /// template, as Cloze makes them.
        case cloze = 1
    }

    /// Its name, in the language Anki had when it was made.
    public let name: String
    public let kind: Kind
    /// The stock note type Anki made it from, as Anki 2.1.62 and later
    /// record it, `originalStockKind`: 6 is Image Occlusion, and 0 is
    /// unknown, as in note types made before.
    public let originalStockKind: Int
    /// Its fields' names, in order: a note's fields come in this order.
    public let fields: [String]
    /// Its card templates, in order: a card's template index points into it.
    public let templates: [AnkiCardTemplate]

    public init(name: String, kind: Kind, originalStockKind: Int, fields: [String], templates: [AnkiCardTemplate]) {
        self.name = name
        self.kind = kind
        self.originalStockKind = originalStockKind
        self.fields = fields
        self.templates = templates
    }

    /// Whether its cards hide parts of an image: Anki made it from its stock
    /// Image Occlusion note type, or it's the note type of Image Occlusion
    /// Enhanced, the add-on before it, which keeps each mask in a field of
    /// its own (`IO_FLDS` in the add-on's `config.py`), whatever the note
    /// type's name.
    var isImageOcclusion: Bool {
        originalStockKind == 6 || Set(fields).isSuperset(of: ["Question Mask", "Answer Mask", "Original Mask"])
    }

    /// Whether each of its notes makes a card and that card turned over, its
    /// reversed card, as Anki's stock Basic (and reversed card) does, and
    /// its Basic (optional reversed card) for a note with text in Add
    /// Reverse: a standard note type with two templates that Anki made from
    /// either, as it records from 2.1.62 on, 2 and 3; or one made before,
    /// whose stock kind is unknown, whose templates are those Anki makes for
    /// either, whatever its fields are called, as Anki names them in the
    /// language it had (ADR 0016).
    var makesReversedCards: Bool {
        guard kind == .standard, templates.count == 2 else {
            return false
        }
        switch originalStockKind {
        case 2, 3: return true
        case 0: return hasReversedStockTemplates
        default: return false
        }
    }

    /// Whether its two templates are Anki's for Basic (and reversed card),
    /// or for Basic (optional reversed card), with its own fields' names, as
    /// Anki 2.0 and later make them (`rslib/src/notetype/stock.rs`): the
    /// first asks `{{Front}}` and answers `{{FrontSide}}`, the line that
    /// marks where the answer starts, and `{{Back}}`; the second asks
    /// `{{Back}}`, or `{{#Add Reverse}}{{Back}}{{/Add Reverse}}`, and answers
    /// the same way with `{{Front}}`. Blank text between their parts doesn't
    /// count.
    private var hasReversedStockTemplates: Bool {
        guard
            let parsed = try? templates.map({ template throws(AnkiTemplateError) in
                (
                    question: try AnkiTemplate(parsing: template.question).trimmedNodes,
                    answer: try AnkiTemplate(parsing: template.answer).trimmedNodes
                )
            }),
            let front = parsed[0].question.onlyField, let back = parsed[0].answer.stockAnswersField, back != front,
            parsed[1].answer.stockAnswersField == front
        else {
            return false
        }
        if parsed[1].question.onlyField == back {
            return true
        }
        guard parsed[1].question.count == 1, case .section(_, isNegated: false, let nodes) = parsed[1].question[0]
        else {
            return false
        }
        return nodes.onlyField == back
    }
}

extension AnkiTemplate {
    /// Its nodes, without the text between them that's blank, and with the
    /// rest of their text trimmed: the lines Anki leaves around a stock
    /// template's parts don't count.
    fileprivate var trimmedNodes: [Node] {
        nodes.compactMap { node in
            guard case .text(let text) = node else {
                return node
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .text(trimmed[...])
        }
    }
}

extension [AnkiTemplate.Node] {
    /// The field these nodes show when they're that field alone, with no
    /// filter, as `{{Front}}`.
    fileprivate var onlyField: String? {
        guard count == 1, case .replacement(let field, filters: []) = self[0] else {
            return nil
        }
        return field
    }

    /// The field these nodes show when they're a stock answer of Anki's:
    /// `{{FrontSide}}`, the line that marks where the answer starts,
    /// `<hr id=answer>`, and that field alone.
    fileprivate var stockAnswersField: String? {
        guard count == 3, case .replacement("FrontSide", filters: []) = self[0], case .text(let line) = self[1],
            line == "<hr id=answer>"
        else {
            return nil
        }
        return Array(self[2...]).onlyField
    }
}

/// A card template of an Anki note type: what its cards show on the
/// question side and on the answer side, in Anki's template syntax. The
/// formats Anki's browser uses instead in its columns are left out.
public struct AnkiCardTemplate: Sendable, Equatable {
    public let name: String
    /// The question side's template, `qfmt`.
    public let question: String
    /// The answer side's template, `afmt`.
    public let answer: String

    public init(name: String, question: String, answer: String) {
        self.name = name
        self.question = question
        self.answer = answer
    }
}

/// A deck of an Anki collection. Every collection has Default, whose id is
/// 1, whatever its name.
public struct AnkiDeck: Sendable, Equatable {
    /// Its name's levels, from the top: "Medicina::Anatomía" is "Medicina"
    /// and "Anatomía".
    public let name: [String]

    public init(name: [String]) {
        self.name = name
    }
}

/// A note of an Anki collection: the fields its cards show.
public struct AnkiNote: Sendable, Equatable {
    /// The id of its note type.
    public let noteTypeID: Int64
    /// Its fields, in its note type's order, as HTML.
    public let fields: [String]
    /// Its tags, as Anki has them: each without spaces, maybe with `::`.
    public let tags: [String]

    public init(noteTypeID: Int64, fields: [String], tags: [String]) {
        self.noteTypeID = noteTypeID
        self.fields = fields
        self.tags = tags
    }

    /// Its field at `index` among its note type's: an empty one when it has
    /// fewer fields than its note type.
    func field(at index: Int) -> String {
        fields.indices.contains(index) ? fields[index] : ""
    }
}

/// A card of an Anki collection, with the columns of Anki's `cards` table
/// that say where it stands, as Anki stores them (`rslib/src/card/mod.rs`).
public struct AnkiCard: Sendable, Equatable {
    public let id: Int64
    public let noteID: Int64
    /// The deck it's in, which is a filtered deck while `originalDeckID`
    /// isn't 0.
    public let deckID: Int64
    /// Its home deck while it's in a filtered deck, `odid`, or 0.
    public let originalDeckID: Int64
    /// Its template's index in its note type, `ord`; for a cloze card, its
    /// cloze number less one.
    public let templateIndex: Int
    /// `type`: 0 new, 1 learning, 2 review, 3 relearning.
    public let type: Int
    /// `queue`: 0 new, 1 learning, 2 review, 3 learning across days, 4
    /// preview, -1 suspended, -2 and -3 buried.
    public let queue: Int
    /// `due`: a new card's position, a learning card's time in seconds since
    /// 1970, or a review card's day, counted from the collection's creation.
    public let due: Int64
    /// `ivl`: its interval, in days.
    public let interval: Int64
    /// `factor`: its ease in thousandths, such as 2500 for 250%, or 0 for a
    /// card that has none yet, as a new one.
    public let factor: Int64
    /// `odue`: its `due` in its home deck while it's in a filtered deck, or
    /// 0.
    public let originalDue: Int64
    /// `flags`: its flag's number in its lowest three bits, or 0.
    public let flags: Int

    public init(
        id: Int64, noteID: Int64, deckID: Int64, originalDeckID: Int64, templateIndex: Int, type: Int, queue: Int,
        due: Int64, interval: Int64, factor: Int64, originalDue: Int64, flags: Int
    ) {
        self.id = id
        self.noteID = noteID
        self.deckID = deckID
        self.originalDeckID = originalDeckID
        self.templateIndex = templateIndex
        self.type = type
        self.queue = queue
        self.due = due
        self.interval = interval
        self.factor = factor
        self.originalDue = originalDue
        self.flags = flags
    }

    /// Its home deck: its original deck while it's in a filtered deck, its
    /// deck otherwise.
    var homeDeckID: Int64 {
        originalDeckID != 0 ? originalDeckID : deckID
    }

    /// Whether it's new: it hasn't been studied, suspended or buried or not.
    var isNew: Bool {
        type == 0
    }

    /// Its new-card position, its `due` in its home deck: its order among
    /// new cards.
    var newPosition: Int64 {
        originalDeckID != 0 && originalDue != 0 ? originalDue : due
    }
}

/// An entry of a card's review history in an Anki collection, with the
/// columns of Anki's `revlog` table an import reads, as Anki stores them
/// (`rslib/src/revlog/mod.rs`).
public struct AnkiRevlogEntry: Sendable, Equatable {
    /// `id`: when it happened, in milliseconds since 1970.
    public let id: Int64
    /// `cid`: the card it's of.
    public let cardID: Int64
    /// `ease`: the button pressed, 1 again, 2 hard, 3 good and 4 easy, or 0
    /// for an entry no button made, as Set Due Date's, a reset's and FSRS's
    /// rescheduling. On Anki 2.0's scheduler, a card in learning steps had
    /// three buttons, so 2 was good and 3 easy there.
    public let button: Int64
    /// `ivl`: the interval it set, in days when positive, and in seconds
    /// when negative, as on a learning or relearning step.
    public let interval: Int64
    /// `factor`: the card's ease after it, in thousandths, as 2500 for 250%,
    /// or once FSRS scheduled the card, its difficulty, from 100 to 1100.
    public let factor: Int64
    /// `time`: how long the answer took, in milliseconds.
    public let milliseconds: Int64
    /// `type`: 0 learning, 1 review, 2 relearning, 3 filtered, 4 manual, 5
    /// rescheduled.
    public let kind: Int64

    public init(
        id: Int64, cardID: Int64, button: Int64, interval: Int64, factor: Int64, milliseconds: Int64, kind: Int64
    ) {
        self.id = id
        self.cardID = cardID
        self.button = button
        self.interval = interval
        self.factor = factor
        self.milliseconds = milliseconds
        self.kind = kind
    }
}
