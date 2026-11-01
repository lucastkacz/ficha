import CryptoKit
import Foundation
import GRDB
import ZIPFoundation
import libzstd

// Small Anki packages a test describes, written as Anki writes them, so that
// no binary file is checked in. The shapes come from Anki's source, as the
// spec's research cites it: the tables of `rslib/src/storage/schema11.sql`
// and of the upgrades to schema 18 (`rslib/src/storage/upgrades/`), the
// protobuf messages of `proto/anki/`, and the members of
// `rslib/src/import_export/package/`. A package holds only what a reader
// needs, which isn't enough for Anki itself to open it.

/// An Anki package a test describes: its notes, each with its note type, its
/// deck and its tags, its media files, and which Anki wrote it.
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
        /// Current Anki by default: `meta` at version 3, and
        /// `collection.anki21b`, a database at schema 18, beside the
        /// placeholder. The collection, the media list, in protobuf, and each
        /// media file are compressed with zstd.
        case current
    }

    var format = Format.supportOlderAnkiVersions
    var notes: [AnkiNote]
    /// Its media files, by the names the notes' fields refer to them by.
    var media: [String: Data] = [:]
    /// The names of media files its media list names but whose members it
    /// lacks, as in a damaged package.
    var mediaMissingFromTheZip: Set<String> = []
    /// The names of media files whose members hold bytes zstd can't
    /// decompress, as in a damaged package of current Anki's default
    /// format; in another format, they hold the file as it is.
    var damagedMedia: Set<String> = []
    /// `creationOffset` in the collection's configuration: the UTC offset
    /// it was created at, in minutes west of UTC, Buenos Aires's by default,
    /// or nil to leave it out, as Anki 2.0 did.
    var creationOffset: Int? = 180
    /// `rollover` in the collection's configuration: the hour Anki's day
    /// starts at, or nil to leave it out, as current Anki's packages do.
    var rollover: Int? = nil
    /// `schedVer` in the collection's configuration: the version of Anki's
    /// scheduler that reviewed its cards, 2 for Anki 2.1's and later, 1 for
    /// Anki 2.0's, or nil to leave it out, as Anki 2.0 did, which Anki reads
    /// as 1.
    var schedulerVersion: Int? = 2

    /// Writes the package to `file`, as a zip, as Anki does: `meta`, the
    /// collection, the placeholder, each media file, and the media list.
    func write(to file: URL) throws {
        let collection = try collectionData()
        let placeholder = try AnkiPackage(format: .anki20, notes: [.placeholder]).collectionData()
        let media = try format == .current ? currentMedia : legacyMedia
        let members: [(String, Data)] =
            switch format {
            case .anki20:
                [("collection.anki2", collection)] + media
            case .anki21:
                [("collection.anki21", collection), ("collection.anki2", placeholder)] + media
            case .supportOlderAnkiVersions:
                [("meta", Data([0x08, 0x02])), ("collection.anki21", collection), ("collection.anki2", placeholder)]
                    + media
            case .current:
                [
                    ("meta", Data([0x08, 0x03])), ("collection.anki21b", try zstdStreamed(collection)),
                    ("collection.anki2", placeholder),
                ] + media
            }
        try? FileManager.default.removeItem(at: file)
        let archive = try Archive(url: file, accessMode: .create, pathEncoding: nil)
        for (path, data) in members {
            try archive.addEntry(
                with: path, type: .file, uncompressedSize: Int64(data.count),
                compressionMethod: path == "meta" || format == .current ? .none : .deflate
            ) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
    }

    /// The media files' names, in the order their members are numbered.
    private var mediaNames: [String] {
        media.keys.sorted()
    }

    /// The media members of a package older than current Anki's default:
    /// each file as it is, named by its number, and the list, JSON that maps
    /// each number to the file's name.
    private var legacyMedia: [(String, Data)] {
        get throws {
            let files = mediaNames.enumerated().filter { !mediaMissingFromTheZip.contains($1) }.map {
                ("\($0)", media[$1] ?? Data())
            }
            let list = Dictionary(uniqueKeysWithValues: mediaNames.enumerated().map { ("\($0)", $1) })
            return files + [("media", Data(try json(list).utf8))]
        }
    }

    /// The media members of a package current Anki exports by default: each
    /// file compressed, named by its number, and the list, a protobuf
    /// `MediaEntries` whose entries are in the numbers' order, compressed.
    private var currentMedia: [(String, Data)] {
        get throws {
            let files = try mediaNames.enumerated().filter { !mediaMissingFromTheZip.contains($1) }.map {
                position, name in
                let data = media[name] ?? Data()
                return ("\(position)", damagedMedia.contains(name) ? Data("no es zstd".utf8) : try zstdStreamed(data))
            }
            // MediaEntries { repeated MediaEntry entries = 1; }, and
            // MediaEntry { string name = 1; uint32 size = 2; bytes sha1 = 3; }
            // (`proto/anki/import_export.proto`).
            let list = mediaNames.map { name in
                let data = media[name] ?? Data()
                let entry =
                    protobufField(1, Data(name.utf8)) + protobufField(2, varint: UInt64(data.count))
                    + protobufField(3, Data(Insecure.SHA1.hash(data: data)))
                return protobufField(1, entry)
            }
            return files + [("media", try zstdStreamed(list.reduce(Data(), +)))]
        }
    }

    /// The package's collection, a SQLite database at schema 18 for current
    /// Anki's default format and at schema 11 otherwise, as the bytes of its
    /// file.
    private func collectionData() throws -> Data {
        let folder = URL.temporaryDirectory.appending(
            path: "FichaAnkiPackage-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "collection.anki2")
        var configuration = Configuration()
        let isSchema18 = format == .current
        configuration.prepareDatabase { db in
            // Schema 18's names sort with a collation Anki registers on its
            // connections; and Anki leaves the file in WAL mode.
            db.add(collation: unicase)
            if isSchema18 {
                try db.execute(sql: "PRAGMA journal_mode = WAL")
            }
        }
        let queue = try DatabaseQueue(path: file.path(percentEncoded: false), configuration: configuration)
        try queue.write { db in
            if isSchema18 {
                try writeSchema18NoteTypesAndDecks(in: db)
            } else {
                try db.execute(sql: schema11)
                try db.execute(
                    sql: "INSERT INTO col VALUES (1, ?, 0, 0, 11, 0, 0, 0, ?, ?, ?, '{}', '{}')",
                    arguments: [creationTime, try json(confJSON), try json(noteTypesJSON), try json(decksJSON)])
            }
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
                    let (progress, cardQueue) = (ordinal == 1 ? note.reversedCard : nil) ?? (note.progress, note.queue)
                    let columns = progress.columns(position: position)
                    var (queue, due) = (columns.queue, columns.due)
                    switch cardQueue {
                    case .asItsTypeSays: break
                    case .suspended: queue = -1
                    case .buriedForTheDay: queue = -2
                    }
                    // A filtered deck keeps the card's home deck and its due
                    // in `odid` and `odue`, and gives it a position of its
                    // own, below zero, as rescheduling filtered decks do.
                    let homeDeck = (ordinal == 1 ? note.reversedCardDeck : nil) ?? note.deck
                    var (deck, originalDeck, originalDue) = (deckID(of: homeDeck), Int64(0), Int64(0))
                    if let filteredDeck = note.filteredDeck {
                        (deck, originalDeck, originalDue) = (deckID(of: filteredDeck), deck, due)
                        due = -100_000 + Int64(index)
                    }
                    // Wrapping, for a damaged template index.
                    let cardID = noteID * 10 &+ Int64(ordinal)
                    try db.execute(
                        sql: "INSERT INTO cards VALUES (?, ?, ?, ?, 0, 0, ?, ?, ?, ?, 2500, 0, 0, 0, ?, ?, 0, '')",
                        arguments: [
                            cardID, noteID, deck, ordinal, columns.type, queue, due, columns.interval, originalDue,
                            originalDeck,
                        ])
                    for entry in ordinal == 1 ? note.reversedCardHistory : note.history {
                        try db.execute(
                            sql: "INSERT INTO revlog VALUES (?, ?, 0, ?, ?, 0, ?, ?, ?)",
                            arguments: [
                                Int64((entry.at.timeIntervalSince1970 * 1000).rounded()), cardID, entry.button,
                                entry.interval, entry.factor, entry.milliseconds, entry.kind.rawValue,
                            ])
                    }
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

    /// The decks' names, the notes' and their reversed cards', and their
    /// parents', each once, in the order they first come, after Default,
    /// which every collection has, and then the filtered decks'.
    private var deckNames: [String] {
        notes.flatMap { note in
            [note.deck] + [note.reversedCardDeck].compactMap(\.self)
        }
        .flatMap { deck in
            let parts = deck.components(separatedBy: "::")
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

    /// The collection's configuration, with what a reader needs: the
    /// scheduler's version, and how the collection counts its days. Schema
    /// 11 keeps it in `col.conf`, and schema 18 a row for each key in its
    /// `config` table.
    private var confJSON: [String: Int] {
        var conf: [String: Int] = [:]
        conf["schedVer"] = schedulerVersion
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

    /// Makes schema 18's tables in `db`, and writes the `col` row, the
    /// configuration, the note types, with their fields and templates, and
    /// the decks, as Anki keeps them there: in tables, with protobuf blobs,
    /// rather than as JSON in `col`.
    private func writeSchema18NoteTypesAndDecks(in db: Database) throws {
        try db.execute(sql: schema18)
        try db.execute(
            sql: "INSERT INTO col VALUES (1, ?, 0, 0, 18, 0, 0, 0, '', '', '', '', '')", arguments: [creationTime])
        // Each key's value is JSON, as bytes (`rslib/src/storage/config/`).
        for (key, value) in confJSON.sorted(by: { $0.key < $1.key }) {
            try db.execute(sql: "INSERT INTO config VALUES (?, 0, 0, ?)", arguments: [key, Data("\(value)".utf8)])
        }
        for type in noteTypes {
            let id = noteTypeID(of: type)
            // Notetype.Config: kind = 1 (0 normal, left out, or 1 cloze),
            // css = 3, original_stock_kind = 9 (`proto/anki/notetypes.proto`).
            var config = protobufField(3, Data(".card { font-family: arial; }".utf8))
            if type.isCloze {
                config = protobufField(1, varint: 1) + config
            }
            if type.originalStockKind != 0 {
                config += protobufField(9, varint: UInt64(type.originalStockKind))
            }
            try db.execute(sql: "INSERT INTO notetypes VALUES (?, ?, 0, 0, ?)", arguments: [id, type.name, config])
            for (ordinal, field) in type.fields.enumerated() {
                try db.execute(sql: "INSERT INTO fields VALUES (?, ?, ?, X'')", arguments: [id, ordinal, field])
            }
            for (ordinal, template) in type.templates.enumerated() {
                // Template.Config: q_format = 1, a_format = 2.
                let config =
                    protobufField(1, Data(template.question.utf8)) + protobufField(2, Data(template.answer.utf8))
                try db.execute(
                    sql: "INSERT INTO templates VALUES (?, ?, ?, 0, 0, ?)",
                    arguments: [id, ordinal, template.name, config])
            }
        }
        for name in deckNames {
            // A name with U+001F between its levels, where schema 11 has
            // `::` (`rslib/src/decks/name.rs`), and a Deck.KindContainer that
            // holds an empty Normal, field 1.
            try db.execute(
                sql: "INSERT INTO decks VALUES (?, ?, 0, 0, X'', X'0A00')",
                arguments: [deckID(of: name), name.replacingOccurrences(of: "::", with: "\u{1F}")])
        }
    }
}

/// Anki's `unicase` collation, which it registers on each connection to a
/// collection, and schema 18 declares its names with: a comparison that
/// ignores case.
private let unicase = DatabaseCollation("unicase") { $0.compare($1, options: .caseInsensitive) }

/// The protobuf field `number` holding `value`, length-delimited, as a
/// string, bytes or a message are.
private func protobufField(_ number: UInt64, _ value: Data) -> Data {
    varintBytes(number << 3 | 2) + varintBytes(UInt64(value.count)) + value
}

/// The protobuf field `number` holding `varint`, as an integer, an enum or
/// a bool is.
private func protobufField(_ number: UInt64, varint: UInt64) -> Data {
    varintBytes(number << 3) + varintBytes(varint)
}

/// `value` as a protobuf varint: seven bits a byte, the lowest first, each
/// byte but the last with its top bit set.
private func varintBytes(_ value: UInt64) -> Data {
    var bytes = Data()
    var rest = value
    while rest >= 0x80 {
        bytes.append(UInt8(rest & 0x7F) | 0x80)
        rest >>= 7
    }
    bytes.append(UInt8(rest))
    return bytes
}

/// `data` compressed with zstd as Anki compresses a package's members, with
/// zstd's default level: fed to a stream, then ended, so that the frame
/// doesn't say how large `data` is, as a frame compressed in one go does
/// (`colpkg/export.rs`, `zstd_copy`). A reader that sizes its buffer from
/// the frame would fail on Anki's packages, and so on these.
private func zstdStreamed(_ data: Data) throws -> Data {
    guard let context = ZSTD_createCCtx() else {
        throw ZstdHelperError(description: "zstd couldn't start compressing")
    }
    defer { ZSTD_freeCCtx(context) }
    var compressed = Data()
    var buffer = [UInt8](repeating: 0, count: ZSTD_CStreamOutSize())
    try data.withUnsafeBytes { source in
        var input = ZSTD_inBuffer(src: source.baseAddress, size: source.count, pos: 0)
        // Every byte goes in first, and the frame ends with nothing more.
        for directive in [ZSTD_e_continue, ZSTD_e_end] {
            var left = 0
            repeat {
                left = buffer.withUnsafeMutableBytes { out in
                    var output = ZSTD_outBuffer(dst: out.baseAddress, size: out.count, pos: 0)
                    let left = ZSTD_compressStream2(context, &output, &input, directive)
                    compressed.append(contentsOf: out[..<output.pos])
                    return left
                }
                guard ZSTD_isError(left) == 0 else {
                    throw ZstdHelperError(description: String(cString: ZSTD_getErrorName(left)))
                }
            } while directive == ZSTD_e_continue ? input.pos < input.size : left != 0
        }
    }
    let size = compressed.withUnsafeBytes { ZSTD_getFrameContentSize($0.baseAddress, $0.count) }
    guard size == ZSTD_CONTENTSIZE_UNKNOWN else {
        throw ZstdHelperError(description: "A streamed zstd frame says its size, \(size), unlike Anki's")
    }
    return compressed
}

/// Why the helper couldn't compress a member.
private struct ZstdHelperError: Error, CustomStringConvertible {
    let description: String
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
        /// Being learned, with steps of a day or more, due on this day,
        /// counted from the collection's creation.
        case learningAcrossDays(due: Int)
        /// Being relearned after a lapse, due at this time, in seconds since
        /// 1970, with the interval it graduates with, a day.
        case relearning(dueAt: Int64)
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
            case .learningAcrossDays(let due): (1, 3, Int64(due), 0)
            case .relearning(let dueAt): (3, 1, dueAt, 1)
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
    /// The home deck of its reversed card, its second template's, in place
    /// of `deck`, or nil when it's in `deck`, as Anki lets a card move to a
    /// deck apart from its note's other cards.
    var reversedCardDeck: String? = nil
    var progress = Progress.new
    var queue = Queue.asItsTypeSays
    /// How its reversed card, its second template's, stands in Anki, in
    /// place of `progress` and `queue`, or nil when it stands as its first
    /// card does.
    var reversedCard: (progress: Progress, queue: Queue)? = nil
    /// Its cards' review history in Anki, each card's rows of the `revlog`
    /// table, but its reversed card's, its second template's.
    var history: [AnkiRevlogEntry] = []
    /// Its reversed card's review history in Anki.
    var reversedCardHistory: [AnkiRevlogEntry] = []
    /// The filtered deck its cards were moved to, or nil.
    var filteredDeck: String? = nil
    /// The template index of the note's one card, in place of those Anki
    /// gives its cards, as in a damaged package, or nil.
    var damagedTemplateIndex: Int? = nil

    /// The template index, from 0, of each card the note has, as Anki makes
    /// them: one for each template of a standard note type, but one whose
    /// question opens with a section on a field the note leaves empty, as
    /// the reversed card of Basic (optional reversed card) without text in
    /// Add Reverse, which would show nothing; and one for each cloze number
    /// its fields hold for a cloze one, its number less one.
    var cardOrdinals: [Int] {
        if let damagedTemplateIndex {
            return [damagedTemplateIndex]
        }
        guard type.isCloze else {
            return type.templates.indices.filter { index in
                guard let section = type.templates[index].question.firstMatch(of: /^\{\{#([^}]+)\}\}/),
                    let field = type.fields.firstIndex(of: String(section.output.1))
                else {
                    return true
                }
                return fields.indices.contains(field) && !fields[field].isEmpty
            }
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

/// An entry of a card's review history in a test's Anki package, a row of
/// its `revlog` table, as Anki writes it (`rslib/src/revlog/mod.rs`).
struct AnkiRevlogEntry {
    /// What the entry records, its `type`.
    enum Kind: Int {
        /// A review of a card in its learning steps.
        case learning = 0
        /// A review of a card in review.
        case review = 1
        /// A review of a card in its relearning steps, after a lapse.
        case relearning = 2
        /// A review in a filtered deck: of a card not due yet, or, with
        /// rescheduling off and an ease of 0, cramming, which changes
        /// nothing.
        case filtered = 3
        /// Set Due Date, or, with an ease of 0, a reset to new.
        case manual = 4
        /// FSRS rescheduling the card as its settings changed.
        case rescheduled = 5
        /// A type Anki doesn't write, as in a damaged package.
        case unknown = 6
    }

    /// When it happened: its `id`, in milliseconds since 1970, which Anki
    /// keeps unique across the collection's cards.
    var at: Date
    /// The button pressed, `ease`: 1 again, 2 hard, 3 good, 4 easy, or 0
    /// for an entry no button made.
    var button: Int
    /// The interval it set, `ivl`: in days when positive, in seconds when
    /// negative, as on a learning step.
    var interval: Int
    /// The card's ease after it, `factor`, in thousandths.
    var factor = 2500
    /// How long the answer took, `time`, in milliseconds.
    var milliseconds = 6000
    var kind: Kind
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

    /// Anki's Basic (optional reversed card), whose reversed card Anki makes
    /// only for a note with text in Add Reverse.
    static let basicOptionalReversed = AnkiNoteType(
        name: "Basic (optional reversed card)", originalStockKind: 3, fields: ["Front", "Back", "Add Reverse"],
        templates: [
            AnkiCardTemplate(name: "Card 1", question: "{{Front}}", answer: basicAnswer("{{Back}}")),
            AnkiCardTemplate(
                name: "Card 2", question: "{{#Add Reverse}}{{Back}}{{/Add Reverse}}", answer: basicAnswer("{{Front}}")),
        ])

    /// A note type of someone's own whose notes make two cards, the word's
    /// and the meaning's, the second with the example on its back: without
    /// it, its templates would be Anki's for Basic (and reversed card).
    static let wordAndMeaning = AnkiNoteType(
        name: "Palabra y significado", fields: ["Palabra", "Significado", "Ejemplo"],
        templates: [
            AnkiCardTemplate(name: "Significado", question: "{{Palabra}}", answer: basicAnswer("{{Significado}}")),
            AnkiCardTemplate(
                name: "Palabra", question: "{{Significado}}", answer: basicAnswer("{{Palabra}}<br>{{Ejemplo}}")),
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

    /// The note type of Image Occlusion Enhanced, the add-on Anki users had
    /// before Anki's own Image Occlusion: an ordinary note type, which keeps
    /// the image and each mask, an SVG, in fields of its own (`config.py`'s
    /// `IO_MODEL_NAME` and `IO_FLDS`), with its template cut short.
    static let imageOcclusionEnhanced = AnkiNoteType(
        name: "Image Occlusion Enhanced",
        fields: [
            "ID (hidden)", "Header", "Image", "Question Mask", "Footer", "Remarks", "Sources", "Extra 1", "Extra 2",
            "Answer Mask", "Original Mask",
        ],
        templates: [
            AnkiCardTemplate(
                name: "IO Card",
                question: """
                    {{#Image}}
                    <div id="io-header">{{Header}}</div>
                    <div id="io-wrapper">
                      <div id="io-overlay">{{Question Mask}}</div>
                      <div id="io-original">{{Image}}</div>
                    </div>
                    <div id="io-footer">{{Footer}}</div>
                    {{/Image}}
                    """,
                answer: """
                    {{#Image}}
                    <div id="io-header">{{Header}}</div>
                    <div id="io-wrapper">
                      <div id="io-overlay">{{Answer Mask}}</div>
                      <div id="io-original">{{Image}}</div>
                    </div>
                    {{#Remarks}}<div id="io-extra">{{Remarks}}</div>{{/Remarks}}
                    {{/Image}}
                    """)
        ])

    /// The note type as one made before Anki 2.1.62 has it, which doesn't
    /// record the stock note type Anki made it from.
    var madeBeforeStockKinds: AnkiNoteType {
        var type = self
        type.originalStockKind = 0
        return type
    }

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
    CREATE TABLE revlog (id integer PRIMARY KEY, cid integer NOT NULL, usn integer NOT NULL, ease integer NOT NULL,
      ivl integer NOT NULL, lastIvl integer NOT NULL, factor integer NOT NULL, time integer NOT NULL,
      type integer NOT NULL);
    """

/// Schema 18's tables a reader needs: schema 11's, and those the upgrades
/// add (`schema14_upgrade.sql`, `schema15_upgrade.sql`), with their names'
/// collation and the indexes on them, as Anki makes them.
private let schema18 =
    schema11 + """
        CREATE TABLE notetypes (id integer NOT NULL PRIMARY KEY, name text NOT NULL COLLATE unicase,
          mtime_secs integer NOT NULL, usn integer NOT NULL, config blob NOT NULL);
        CREATE UNIQUE INDEX idx_notetypes_name ON notetypes (name);
        CREATE TABLE fields (ntid integer NOT NULL, ord integer NOT NULL, name text NOT NULL COLLATE unicase,
          config blob NOT NULL, PRIMARY KEY (ntid, ord)) WITHOUT ROWID;
        CREATE UNIQUE INDEX idx_fields_name_ntid ON fields (name, ntid);
        CREATE TABLE templates (ntid integer NOT NULL, ord integer NOT NULL, name text NOT NULL COLLATE unicase,
          mtime_secs integer NOT NULL, usn integer NOT NULL, config blob NOT NULL, PRIMARY KEY (ntid, ord)) WITHOUT ROWID;
        CREATE UNIQUE INDEX idx_templates_name_ntid ON templates (name, ntid);
        CREATE TABLE decks (id integer PRIMARY KEY NOT NULL, name text NOT NULL COLLATE unicase,
          mtime_secs integer NOT NULL, usn integer NOT NULL, common blob NOT NULL, kind blob NOT NULL);
        CREATE UNIQUE INDEX idx_decks_name ON decks (name);
        CREATE TABLE config (KEY text NOT NULL PRIMARY KEY, usn integer NOT NULL, mtime_secs integer NOT NULL,
          val blob NOT NULL) WITHOUT ROWID;
        """
