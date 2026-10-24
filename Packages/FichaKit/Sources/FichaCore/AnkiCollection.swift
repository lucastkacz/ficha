import Foundation

/// An Anki collection, as an Anki package holds it, in plain values whatever
/// its schema: when it was created and how it counts its days, and its note
/// types, decks, notes and cards, with what Ficha reads of each. A package's
/// reader, which knows the schema, makes it, from the JSON of schema 11 or
/// the tables of schema 18, and `importReading(in:images:)` makes Ficha's
/// cards of it, the same way for both. The values follow Anki's source,
/// `rslib/src/storage/` and `rslib/src/notetype/`.
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

    public init(
        creationTime: Int64, daySettings: AnkiDaySettings, noteTypes: [Int64: AnkiNoteType],
        decks: [Int64: AnkiDeck], notes: [Int64: AnkiNote], cards: [AnkiCard]
    ) {
        self.creationTime = creationTime
        self.daySettings = daySettings
        self.noteTypes = noteTypes
        self.decks = decks
        self.notes = notes
        self.cards = cards
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
    /// `odue`: its `due` in its home deck while it's in a filtered deck, or
    /// 0.
    public let originalDue: Int64
    /// `flags`: its flag's number in its lowest three bits, or 0.
    public let flags: Int

    public init(
        id: Int64, noteID: Int64, deckID: Int64, originalDeckID: Int64, templateIndex: Int, type: Int, queue: Int,
        due: Int64, interval: Int64, originalDue: Int64, flags: Int
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
