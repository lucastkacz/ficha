import Foundation
import GRDB
import ZIPFoundation

// Small Anki packages a test describes, written as Anki writes them, so that
// no binary file is checked in. The shapes come from Anki's source, as the
// spec's research cites it: the tables of `rslib/src/storage/schema11.sql`,
// and the members of `rslib/src/import_export/package/`. A package holds
// only what a reader needs, which isn't enough for Anki itself to open it.

/// An Anki package a test describes: its notes, each with its note type, its
/// deck and its tags, and which Anki wrote it.
struct AnkiPackage {
    /// Which Anki wrote a package, which sets its members.
    enum Format {
        /// Anki 2.0: `collection.anki2`, without `meta`.
        case anki20
        /// Anki 2.1 before 2.1.50, with scheduling on the v2 scheduler:
        /// `collection.anki21`, beside a placeholder `collection.anki2`,
        /// without `meta`.
        case anki21
        /// Current Anki with "Support older Anki versions" ticked: `meta`
        /// at version 2, `collection.anki21`, and the placeholder.
        case supportOlderAnkiVersions
        /// Current Anki by default: `meta` at version 3, a zstd-compressed
        /// `collection.anki21b`, and the placeholder. Its collection here is
        /// a zstd frame's magic number and nothing else.
        case current
    }

    var format = Format.supportOlderAnkiVersions
    var notes: [AnkiNote]
    /// `creationOffset` in the collection's configuration: the UTC offset
    /// it was created at, in minutes west of UTC, Buenos Aires's by default,
    /// or nil to leave it out, as Anki 2.0 did.
    var creationOffset: Int? = 180
    /// `rollover` in the collection's configuration: the hour Anki's day
    /// starts at, or nil to leave it out, as current Anki's packages do.
    var rollover: Int? = nil

    /// Writes the package to `file`, as a zip, as Anki does.
    func write(to file: URL) throws {
        let collection = try collectionData()
        let placeholder = try AnkiPackage(format: .anki20, notes: [.placeholder]).collectionData()
        let media = Data("{}".utf8)
        let members: [(String, Data)] =
            switch format {
            case .anki20:
                [("collection.anki2", collection), ("media", media)]
            case .anki21:
                [("collection.anki21", collection), ("collection.anki2", placeholder), ("media", media)]
            case .supportOlderAnkiVersions:
                [
                    ("meta", Data([0x08, 0x02])), ("collection.anki21", collection),
                    ("collection.anki2", placeholder), ("media", media),
                ]
            case .current:
                [
                    ("meta", Data([0x08, 0x03])), ("collection.anki21b", Data([0x28, 0xB5, 0x2F, 0xFD])),
                    ("collection.anki2", placeholder), ("media", Data([0x28, 0xB5, 0x2F, 0xFD])),
                ]
            }
        try? FileManager.default.removeItem(at: file)
        let archive = try Archive(url: file, accessMode: .create, pathEncoding: nil)
        for (path, data) in members {
            try archive.addEntry(
                with: path, type: .file, uncompressedSize: Int64(data.count),
                compressionMethod: path == "meta" ? .none : .deflate
            ) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
    }

    /// The package's collection, a SQLite database at schema 11, as the
    /// bytes of its file.
    private func collectionData() throws -> Data {
        let folder = URL.temporaryDirectory.appending(
            path: "FichaAnkiPackage-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "collection.anki2")
        let queue = try DatabaseQueue(path: file.path(percentEncoded: false))
        try queue.write { db in
            try db.execute(sql: schema11)
            try db.execute(
                sql: "INSERT INTO col VALUES (1, ?, 0, 0, 11, 0, 0, 0, ?, ?, ?, '{}', '{}')",
                arguments: [creationTime, try json(confJSON), try json(noteTypesJSON), try json(decksJSON)])
            var nextPosition = 1
            for (index, note) in notes.enumerated() {
                let noteID = Int64(1_700_000_000_000 + index)
                try db.execute(
                    sql: "INSERT INTO notes VALUES (?, ?, ?, 0, 0, ?, ?, '', 0, 0, '')",
                    arguments: [
                        noteID, "guid\(index)", noteTypeID(of: note.type),
                        note.tags.isEmpty ? "" : " \(note.tags.joined(separator: " ")) ",
                        note.fields.joined(separator: "\u{1F}"),
                    ])
                let position: Int
                if case .newAt(let given) = note.progress {
                    position = given
                } else {
                    position = nextPosition
                    nextPosition += 1
                }
                for ordinal in note.cardOrdinals {
                    let columns = note.progress.columns(position: position)
                    var (queue, due) = (columns.queue, columns.due)
                    switch note.queue {
                    case .asItsTypeSays: break
                    case .suspended: queue = -1
                    case .buriedForTheDay: queue = -2
                    }
                    // A filtered deck keeps the card's home deck and its due
                    // in `odid` and `odue`, and gives it a position of its
                    // own, below zero, as rescheduling filtered decks do.
                    var (deck, originalDeck, originalDue) = (deckID(of: note.deck), Int64(0), Int64(0))
                    if let filteredDeck = note.filteredDeck {
                        (deck, originalDeck, originalDue) = (deckID(of: filteredDeck), deck, due)
                        due = -100_000 + Int64(index)
                    }
                    try db.execute(
                        sql: "INSERT INTO cards VALUES (?, ?, ?, ?, 0, 0, ?, ?, ?, ?, 2500, 0, 0, 0, ?, ?, 0, '')",
                        arguments: [
                            noteID * 10 + Int64(ordinal), noteID, deck, ordinal, columns.type, queue, due,
                            columns.interval, originalDue, originalDeck,
                        ])
                }
            }
        }
        try queue.close()
        return try Data(contentsOf: file)
    }

    /// When the collection was created, `col.crt`: 1 October 2026 at 4 in
    /// the morning in Buenos Aires.
    private var creationTime: Int64 {
        1_790_838_000
    }

    /// The note types the notes have, each once, in the order they first
    /// come.
    private var noteTypes: [AnkiNoteType] {
        notes.map(\.type).reduce(into: []) { types, type in
            if !types.contains(type) {
                types.append(type)
            }
        }
    }

    /// The id of `type` in the collection.
    private func noteTypeID(of type: AnkiNoteType) -> Int64 {
        Int64(1_600_000_000_000 + (noteTypes.firstIndex(of: type) ?? 0))
    }

    /// The decks' names, the notes' and their parents', each once, in the
    /// order they first come, after Default, which every collection has,
    /// and then the filtered decks'.
    private var deckNames: [String] {
        notes.flatMap { note in
            let parts = note.deck.components(separatedBy: "::")
            return parts.indices.map { parts[...$0].joined(separator: "::") }
        }
        .reduce(into: ["Default"]) { names, name in
            if !names.contains(name) {
                names.append(name)
            }
        } + filteredDeckNames
    }

    /// The filtered decks' names, each once, in the order they first come.
    private var filteredDeckNames: [String] {
        notes.compactMap(\.filteredDeck).reduce(into: []) { names, name in
            if !names.contains(name) {
                names.append(name)
            }
        }
    }

    /// `col.conf`, with what a reader needs: the scheduler's version, and
    /// how the collection counts its days.
    private var confJSON: [String: Any] {
        var conf: [String: Any] = ["schedVer": 2]
        conf["creationOffset"] = creationOffset
        conf["rollover"] = rollover
        return conf
    }

    /// The id of the deck named `name`: Default's is 1, as in every
    /// collection.
    private func deckID(of name: String) -> Int64 {
        guard let index = deckNames.firstIndex(of: name), index > 0 else {
            return 1
        }
        return Int64(1_500_000_000_000 + index)
    }

    /// `col.models`: each note type by its id, as Anki 2.1 writes it.
    private var noteTypesJSON: [String: Any] {
        Dictionary(
            uniqueKeysWithValues: noteTypes.map { type in
                var model: [String: Any] = [
                    "id": noteTypeID(of: type), "name": type.name, "type": type.isCloze ? 1 : 0, "sortf": 0,
                    "css": ".card { font-family: arial; }",
                    "flds": type.fields.enumerated().map { ["name": $1, "ord": $0] },
                    "tmpls": type.templates.enumerated().map { index, template in
                        [
                            "name": template.name, "ord": index, "qfmt": template.question,
                            "afmt": template.answer, "bqfmt": "", "bafmt": "", "did": NSNull(),
                        ]
                    },
                ]
                if type.originalStockKind != 0 {
                    model["originalStockKind"] = type.originalStockKind
                }
                return ("\(noteTypeID(of: type))", model)
            })
    }

    /// `col.decks`: each deck by its id.
    private var decksJSON: [String: Any] {
        Dictionary(
            uniqueKeysWithValues: deckNames.map { name in
                let id = deckID(of: name)
                let isFiltered = filteredDeckNames.contains(name)
                return ("\(id)", ["id": id, "name": name, "dyn": isFiltered ? 1 : 0] as [String: Any])
            })
    }

    /// `object` as JSON text.
    private func json(_ object: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }
}

/// A note of a test's Anki package.
struct AnkiNote {
    /// How a note's cards stand in Anki, as its `cards` table says it
    /// (`rslib/src/card/mod.rs`).
    enum Progress {
        /// New, at the next new-card position, in the notes' order.
        case new
        /// New, at this new-card position.
        case newAt(position: Int)
        /// In review, due on this day, counted from the collection's
        /// creation, with this interval in days.
        case review(due: Int, interval: Int)
        /// Being learned, due at this time, in seconds since 1970.
        case learning(dueAt: Int64)
        /// Being relearned after a lapse, with steps of a day or more, due on
        /// this day, counted from the collection's creation.
        case relearningAcrossDays(due: Int)
        /// Being relearned after a lapse, due at this time, in seconds since
        /// 1970, as Anki 2.0's scheduler kept it: a review card in the
        /// learning queue.
        case anki20Relearning(dueAt: Int64)

        /// Its `type`, `queue`, `due` and `ivl`, with `position` as a new
        /// card's position.
        func columns(position: Int) -> (type: Int, queue: Int, due: Int64, interval: Int) {
            switch self {
            case .new, .newAt: (0, 0, Int64(position), 0)
            case .review(let due, let interval): (2, 2, Int64(due), interval)
            case .learning(let dueAt): (1, 1, dueAt, 0)
            case .relearningAcrossDays(let due): (3, 3, Int64(due), 1)
            case .anki20Relearning(let dueAt): (2, 1, dueAt, 1)
            }
        }
    }

    /// Whether a note's cards are suspended or buried, which Anki says in
    /// their queue.
    enum Queue {
        /// The queue its progress gives it.
        case asItsTypeSays
        /// Suspended, until the user unsuspends it.
        case suspended
        /// Buried until the next day.
        case buriedForTheDay
    }

    var type: AnkiNoteType
    var fields: [String]
    var tags: [String] = []
    /// Its cards' deck, with `::` between levels: their home deck while
    /// they're in a filtered deck.
    var deck = "Default"
    var progress = Progress.new
    var queue = Queue.asItsTypeSays
    /// The filtered deck its cards were moved to, or nil.
    var filteredDeck: String? = nil

    /// The template index, from 0, of each card the note has, as Anki makes
    /// them: one for each template of a standard note type, and one for each
    /// cloze number its fields hold for a cloze one, its number less one.
    var cardOrdinals: [Int] {
        guard type.isCloze else {
            return Array(type.templates.indices)
        }
        let numbers = fields.flatMap { field in
            field.matches(of: /\{\{c(\d+)::/).compactMap { Int($0.output.1) }
        }
        return Set(numbers).sorted().map { $0 - 1 }
    }

    /// The note current Anki leaves in `collection.anki2`, beside a newer
    /// collection, for an older Anki to show.
    static let placeholder = AnkiNote(
        type: .basic,
        fields: [
            "Please update to the latest Anki version, then import the .colpkg/.apkg file again.",
            "This package was made by a newer Anki.",
        ])
}

/// A note type of a test's Anki package: its fields, by their names, and its
/// card templates.
struct AnkiNoteType: Hashable {
    var name: String
    var isCloze = false
    /// Anki's `originalStockKind`, which note types made by Anki 2.1.62 and
    /// later have: 6 for Image Occlusion, 0 when it's not written.
    var originalStockKind = 0
    var fields: [String]
    var templates: [AnkiCardTemplate]

    /// Anki's Basic.
    static let basic = AnkiNoteType(
        name: "Basic", originalStockKind: 1, fields: ["Front", "Back"],
        templates: [AnkiCardTemplate(name: "Card 1", question: "{{Front}}", answer: basicAnswer("{{Back}}"))])

    /// Anki's Basic (and reversed card).
    static let basicAndReversed = AnkiNoteType(
        name: "Basic (and reversed card)", originalStockKind: 2, fields: ["Front", "Back"],
        templates: [
            AnkiCardTemplate(name: "Card 1", question: "{{Front}}", answer: basicAnswer("{{Back}}")),
            AnkiCardTemplate(name: "Card 2", question: "{{Back}}", answer: basicAnswer("{{Front}}")),
        ])

    /// Anki's Cloze.
    static let cloze = AnkiNoteType(
        name: "Cloze", isCloze: true, originalStockKind: 5, fields: ["Text", "Back Extra"],
        templates: [
            AnkiCardTemplate(name: "Cloze", question: "{{cloze:Text}}", answer: "{{cloze:Text}}<br>\n{{Back Extra}}")
        ])

    /// Anki's Image Occlusion, with its template cut short: the cloze, the
    /// image, and a script.
    static let imageOcclusion = AnkiNoteType(
        name: "Image Occlusion", isCloze: true, originalStockKind: 6,
        fields: ["Occlusion", "Image", "Header", "Back Extra", "Comments"],
        templates: [
            AnkiCardTemplate(
                name: "Image Occlusion",
                question: """
                    {{#Header}}<div>{{Header}}</div>{{/Header}}
                    <div style="display: none">{{cloze:Occlusion}}</div>
                    <div id="image-occlusion-container">{{Image}}<canvas id="image-occlusion-canvas"></canvas></div>
                    <script>try { anki.imageOcclusion.setup(); } catch (exc) { }</script>
                    """,
                answer: """
                    {{#Header}}<div>{{Header}}</div>{{/Header}}
                    <div style="display: none">{{cloze:Occlusion}}</div>
                    <div id="image-occlusion-container">{{Image}}<canvas id="image-occlusion-canvas"></canvas></div>
                    <script>try { anki.imageOcclusion.setup(); } catch (exc) { }</script>
                    {{#Back Extra}}<div>{{Back Extra}}</div>{{/Back Extra}}
                    """)
        ])

    /// A stock answer of Anki's: the question, the line that marks where
    /// the answer starts, and `back`.
    private static func basicAnswer(_ back: String) -> String {
        "{{FrontSide}}\n\n<hr id=answer>\n\n\(back)"
    }
}

/// A card template of a test's note type: its name, and its question and
/// answer, in Anki's template syntax.
struct AnkiCardTemplate: Hashable {
    var name: String
    var question: String
    var answer: String
}

/// Schema 11's tables a reader needs, from Anki's `schema11.sql`.
private let schema11 = """
    CREATE TABLE col (id integer PRIMARY KEY, crt integer NOT NULL, mod integer NOT NULL, scm integer NOT NULL,
      ver integer NOT NULL, dty integer NOT NULL, usn integer NOT NULL, ls integer NOT NULL, conf text NOT NULL,
      models text NOT NULL, decks text NOT NULL, dconf text NOT NULL, tags text NOT NULL);
    CREATE TABLE notes (id integer PRIMARY KEY, guid text NOT NULL, mid integer NOT NULL, mod integer NOT NULL,
      usn integer NOT NULL, tags text NOT NULL, flds text NOT NULL, sfld integer NOT NULL, csum integer NOT NULL,
      flags integer NOT NULL, data text NOT NULL);
    CREATE TABLE cards (id integer PRIMARY KEY, nid integer NOT NULL, did integer NOT NULL, ord integer NOT NULL,
      mod integer NOT NULL, usn integer NOT NULL, type integer NOT NULL, queue integer NOT NULL, due integer NOT NULL,
      ivl integer NOT NULL, factor integer NOT NULL, reps integer NOT NULL, lapses integer NOT NULL,
      left integer NOT NULL, odue integer NOT NULL, odid integer NOT NULL, flags integer NOT NULL, data text NOT NULL);
    """
