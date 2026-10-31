import FichaCore
import Foundation
internal import GRDB

// Selective sync (ADR 0020, as ADR 0024 changes it): sync carries every card,
// or only the cards in a deck the user chose. Which it is, and which decks are
// chosen, is one choice for all the user's devices, which syncs as a deck's
// color does (the `syncChoice` row, and each deck's `chosenToSync`). A card
// syncs when every card does, or its deck, or a deck its deck sits inside, is
// chosen, Default included, so a deck made inside a chosen one syncs, and any
// other waits until the user ticks it; a card's review log entries go with
// it, and so do the captures that expand it or follow it up. Every other row
// syncs whatever the choice: captures, tags, with their changes, decks, the
// settings that decide progress and the choice itself. A tag's choice to sync,
// from before decks, decides nothing: the `tag` table keeps it for the
// conversion of Lucas's tags into decks, and its record no longer sends it.
//
// The triggers record every change, whoever writes it, the CLI too; this file
// says which of them go up. A row that starts syncing goes up whole, and one
// that stops leaves iCloud: its record stays there as one that left, holding
// nothing of its own but, for a card, its deck, so that the other devices
// tell it from a deletion, which still removes the record (`SyncedDeletions`),
// whatever order the two changes reach them in, and learn why it left. Each
// device keeps its copy of a row that left, which syncs no more until it syncs
// again, when the copies join as after a long time offline (ADR 0017). The
// record that left is our own: CloudKit deletes a record, or holds it.
//
// Under selective sync, while sync is on, a device lists only the decks that
// sync, those it holds cards of and those made on it
// (`decksListedWithRows(of:in:)`), so that it doesn't list every deck of the
// other devices empty; the Sync tab lists every deck, for the user to choose
// from.

/// The key of the field of a record that says its row left iCloud: 1, or
/// nothing in a record of a row that syncs.
private let leftKey = "left"

extension Engine {
    /// Whether only the cards in a deck the user chose sync, rather than
    /// every card.
    public func syncsOnlyChosenDecks() throws(EngineError) -> Bool {
        try read(FichaData.syncsOnlyChosenDecks(in:))
    }

    /// Has only the cards in a deck the user chose sync, or every card, as
    /// `only` says, for all the user's devices. The cards that start syncing
    /// go up whole, and those that stop leave iCloud, kept on every device.
    /// When it's so already, nothing changes.
    public func syncOnlyChosenDecks(_ only: Bool) throws(EngineError) {
        try write { db in
            try db.execute(sql: "UPDATE syncChoice SET onlyChosenTags = ?", arguments: [only])
        }
    }

    /// Chooses the deck `deck` to sync, by its whole name, or Default by
    /// `Deck.defaultName`, or stops choosing it, as `chosen` says, for all
    /// the user's devices: while only the cards in a chosen deck sync, its
    /// cards, and those of the decks inside it, also decks made inside it
    /// later, start or stop syncing, unless a deck it sits inside is chosen.
    /// Choosing deletes no card: one that stops syncing leaves iCloud, kept
    /// on every device. A deck that isn't there is made, as Change Deck makes
    /// one, and a name `makeDeck(named:)` refuses is refused. When it's so
    /// already, nothing changes, and unticking a deck never makes one.
    public func setChosenToSync(_ chosen: Bool, ofDeck deck: String) throws(EngineError) {
        let deck = try checkedDeckOrDefault(deck)
        try write { db in try changeOwnDecks([deck], in: db) { $0.chosenToSync = chosen } }
    }

    /// Every deck the user can choose to sync, as a tree, in the order a tree
    /// lists them: Default first, which can be chosen whether or not this
    /// device holds cards in it, then every deck with a row, which every
    /// device has, every deck a card here lives in, and every deck those sit
    /// inside. Each comes with whether it's chosen, whether a deck it sits
    /// inside is, and what the images and sounds of its cards here, and of
    /// those of the decks inside it, weigh, each file once, at the size Ficha
    /// keeps them, or nil when those cards have neither.
    func decksToChooseFrom() throws(EngineError) -> [DeckToChoose] {
        let (cards, own) = try read { db in (try allCards(in: db), try OwnDecks(in: db)) }
        var filesByDeck: [String: FileNames] = [:]
        for card in cards {
            for deck in TagPath.lineage(of: card.deck) {
                filesByDeck[deck, default: FileNames()].images.formUnion(card.images)
                filesByDeck[deck, default: FileNames()].sounds.formUnion(card.sounds)
            }
        }
        var sizes: [SyncedFile: Int64] = [:]
        /// What `name` weighs as Ficha keeps it, read once, or nothing when
        /// it doesn't keep it.
        func size(of name: some NameOfSyncedFile) throws(EngineError) -> Int64 {
            let file = SyncedFile(name)
            if let size = sizes[file] {
                return size
            }
            let size = name.isKept(by: self) ? try name.size(in: self) : 0
            sizes[file] = size
            return size
        }
        let decks = everyDeckName(of: own, livedInBy: cards).map(own.deck)
        var weights: [String: Int64] = [:]
        for (deck, files) in filesByDeck {
            var weight: Int64 = 0
            for image in files.images {
                weight += try size(of: image)
            }
            for sound in files.sounds {
                weight += try size(of: sound)
            }
            weights[deck] = weight > 0 ? weight : nil
        }
        let chosen = own.chosenToSync
        return deckTree(of: decks, named: \.name) { deck, title, children in
            DeckToChoose(
                deck: deck, title: title,
                isInsideChosen: TagPath.ancestors(of: deck.name).contains(where: chosen.contains),
                weight: weights[deck.name], children: children)
        }
    }

    /// Notes what syncs in the database's write `db`, as `noteWhatSyncs(in:)`
    /// says, when `everything` says so or a change that may change what syncs
    /// waits to be sent: one to a card, whose deck may have changed, to a
    /// deck, or to the choice. Otherwise only the changes of rows that
    /// neither sync nor are in iCloud stop waiting, which is quicker: a
    /// review, say.
    func noteWhatSyncs(everything: Bool) throws(EngineError) {
        try writeWithoutTelling { db in
            // A change to a card, whose deck may have changed, to a deck or to
            // the choice may change which rows sync.
            if try everything || savesWait(ofTypes: [.card, .deck, .syncChoice], in: db) {
                try FichaData.noteWhatSyncs(in: db)
            } else {
                try forgetChangesThatStayHere(in: db)
            }
        }
    }

    /// The places among the changes recorded of the rows that leave iCloud,
    /// whose records go up as ones that left, while a change to the choice
    /// waits to be sent, a deck's or whether only chosen decks sync: those
    /// wait until it went, so that a device that hears they left already
    /// knows why, as it does in any order, but sooner. Empty when no such
    /// change waits.
    func leavingWhileTheChoiceChanges() throws(EngineError) -> Set<Int64> {
        try read { db in
            guard try savesWait(ofTypes: [.deck, .syncChoice], in: db) else {
                return []
            }
            return Set(
                try SyncingTable.all.flatMap { table in
                    try Int64.fetchAll(
                        db,
                        sql: """
                            SELECT syncPending.id FROM syncPending JOIN \(table.name) AS row
                                ON row.uuid = syncPending.recordName
                            WHERE syncPending.recordType = ? AND NOT syncPending.isDeletion AND NOT (\(table.syncs))
                            """,
                        arguments: [table.type.rawValue])
                })
        }
    }
}

/// A deck the user can choose to sync, as the Sync tab lists it, in a tree
/// with the decks inside it.
public struct DeckToChoose: Sendable, Equatable, Identifiable {
    /// The deck, with whether the user chose it (`Deck.chosenToSync`), what
    /// it has of its own and what it takes from the decks it sits inside.
    public let deck: Deck
    /// What it says: its last level under its parent, or nothing for
    /// Default, which the app names in the Mac's language.
    public let title: String
    /// Whether the user chose a deck it sits inside, so it syncs whatever its
    /// own tick, which can't be unticked meanwhile.
    public let isInsideChosen: Bool
    /// What the images and sounds of its cards on this device, and of the
    /// cards of the decks inside it, weigh, in bytes, each file once, or nil
    /// when they have neither.
    public let weight: Int64?
    /// The decks right inside it, in the order a tree lists them.
    public let children: [DeckToChoose]

    public var id: String {
        deck.name
    }

    /// Whether the user chose it.
    public var isChosen: Bool {
        deck.chosenToSync
    }

    /// Whether its checkbox shows ticked, as its cards sync: it's chosen, or
    /// a deck it sits inside is.
    public var isTicked: Bool {
        isChosen || isInsideChosen
    }

    /// Whether the user can tick or untick it: unless a deck it sits inside
    /// is chosen.
    public var canChoose: Bool {
        !isInsideChosen
    }
}

extension DeckToChoose: DeckInTree {}

/// Whether only the cards in a deck the user chose sync, in `db`: the
/// `syncChoice` row's `onlyChosenTags`, named when tags were chosen, a name
/// that iCloud's record and its field's times keep too (ADR 0024).
func syncsOnlyChosenDecks(in db: Database) throws -> Bool {
    guard let only = try Bool.fetchOne(db, sql: "SELECT onlyChosenTags FROM syncChoice") else {
        throw unreadable("The database doesn't say which cards sync")
    }
    return only
}

/// What decides which cards sync, as a database held it when it was read:
/// for what a card would do once it changes, as an import's card that comes
/// in, and for which decks a device lists.
struct WhatSyncs: Sendable, Equatable {
    let onlyChosenDecks: Bool
    let chosenDecks: Set<String>

    /// What decides which cards sync in `db`, now.
    init(in db: Database) throws {
        onlyChosenDecks = try syncsOnlyChosenDecks(in: db)
        chosenDecks = Set(try String.fetchAll(db, sql: "SELECT name FROM deck WHERE chosenToSync"))
    }

    /// Whether a card in the deck `deck` syncs, as `cardSyncs(deck:)` says in
    /// a database's SQL: every card does, or `deck`, or a deck it sits
    /// inside, is chosen. The two read alike every deck's name the engine
    /// writes, cleaned up as `checkedDeckName(_:)` cleans it up, and
    /// Default's.
    func cardSyncs(inDeck deck: String) -> Bool {
        !onlyChosenDecks || !chosenDecks.isDisjoint(with: TagPath.lineage(of: deck))
    }
}

/// SQL that holds when the card whose deck is `deck` syncs: every card does,
/// or its deck, or a deck its deck sits inside, is chosen (ADR 0024), Default
/// included, which no deck sits inside. A deck sits inside a chosen one when
/// its name starts with the chosen one's and `::`, compared character by
/// character: never with LIKE, whose `_` and `%` match other characters and
/// which ignores the case of ASCII letters. Swift's twin is
/// `WhatSyncs.cardSyncs(inDeck:)`. The deletion triggers of `Schema`'s "v31
/// decks" hold a copy, which a migration keeps as it was.
func cardSyncs(deck: String) -> String {
    """
    (NOT (SELECT onlyChosenTags FROM syncChoice) OR EXISTS (
        SELECT 1 FROM deck AS chosen WHERE chosen.chosenToSync AND (chosen.name = \(deck) OR (
            chosen.name <> '\(Deck.defaultName)'
            AND substr(\(deck), 1, length(chosen.name) + 2) = chosen.name || '::'))))
    """
}

/// The decks with a row of `own`, as the `deck` table of `db` keeps it, that
/// this device lists: every one, or, under selective sync while sync is on,
/// those that sync, chosen or inside a chosen one, and those the user made
/// on this device, so that it doesn't list every deck of the other devices
/// empty (ADR 0024).
func decksListedWithRows(of own: OwnDecks, in db: Database) throws -> [String] {
    guard try isSyncOn(in: db) else {
        return own.names
    }
    let whatSyncs = try WhatSyncs(in: db)
    guard whatSyncs.onlyChosenDecks else {
        return own.names
    }
    return own.names.filter { own.madeHere.contains($0) || whatSyncs.cardSyncs(inDeck: $0) }
}

/// A table whose rows sync or not as selective sync decides, by their ID
/// unique across devices: the cards, the review log, with its card, and the
/// captures, unless they expand or follow up a card that doesn't sync.
private struct SyncingTable {
    let name: String
    let type: SyncedRow.RecordType
    /// SQL that holds when the table's row `row` syncs.
    let syncs: String

    static let cards = SyncingTable(name: "card", type: .card, syncs: cardSyncs(deck: "row.deck"))
    static let reviewLog = SyncingTable(
        name: "reviewLog", type: .reviewLogEntry,
        syncs: "EXISTS (SELECT 1 FROM card WHERE card.id = row.cardId AND \(cardSyncs(deck: "card.deck")))")
    static let captures = SyncingTable(
        name: "capture", type: .capture,
        syncs: """
            NOT EXISTS (SELECT 1 FROM card WHERE card.id IN (row.expandsCardId, row.followsUpCardId)
                AND NOT \(cardSyncs(deck: "card.deck")))
            """)
    static let all = [cards, reviewLog, captures]

    /// The table of `type`, or nil for a row that syncs whatever the choice.
    init?(_ type: SyncedRow.RecordType) {
        guard let table = Self.all.first(where: { $0.type == type }) else {
            return nil
        }
        self = table
    }

    private init(name: String, type: SyncedRow.RecordType, syncs: String) {
        self.name = name
        self.type = type
        self.syncs = syncs
    }

    /// SQL that holds when iCloud holds the record of the table's row `row`
    /// in full, as far as the device knows: it heard of it from iCloud, and
    /// not as one that left.
    var isInICloud: String {
        "EXISTS (SELECT 1 FROM syncRecord WHERE zone = '\(ICloudZone.cards.name)' AND name = row.uuid AND NOT hasLeft)"
    }

    /// SQL that holds when a change of the table's row `row` waits to be
    /// sent.
    var waits: String {
        "EXISTS (SELECT 1 FROM syncPending WHERE recordType = '\(type.rawValue)' AND recordName = row.uuid)"
    }
}

/// Whether `row` syncs, as the device's choice says now: a card, an entry of
/// the review log or a capture as selective sync decides, and any other row
/// always, as one the device doesn't hold.
func syncs(_ row: SyncedRow, in db: Database) throws -> Bool {
    guard let table = SyncingTable(row.recordType) else {
        return true
    }
    return try Bool.fetchOne(
        db, sql: "SELECT \(table.syncs) FROM \(table.name) AS row WHERE row.uuid = ?", arguments: [row.recordName])
        ?? true
}

/// Whether iCloud holds the record with this ID in full, as far as the device
/// knows: it heard of it from iCloud, and not as one that left.
func iCloudHoldsInFull(_ id: ICloudRecordID, in db: Database) throws -> Bool {
    try Bool.fetchOne(
        db, sql: "SELECT NOT hasLeft FROM syncRecord WHERE zone = ? AND name = ?", arguments: [id.zone.name, id.name])
        == true
}

/// Notes what syncs, as the choice and the cards' decks decide it now, in the
/// write `db`, while sync is on: each row that syncs, which iCloud lacks or
/// holds as one that left, waits to go up whole, as the cards, entries and
/// captures that start syncing do; each row that doesn't, which iCloud holds
/// in full, waits to go up as one that left; and the changes of the rows that
/// neither sync nor are in iCloud stop waiting, as they stay on the device.
/// A row whose change waits already goes as it is when it's sent.
func noteWhatSyncs(in db: Database) throws {
    for table in SyncingTable.all {
        let startingToSync = "(\(table.syncs)) AND NOT \(table.isInICloud)"
        let leaving = "NOT (\(table.syncs)) AND \(table.isInICloud)"
        for rows in [startingToSync, leaving] {
            try db.execute(
                sql: """
                    INSERT INTO syncPending (recordType, recordName, isDeletion)
                    SELECT '\(table.type.rawValue)', row.uuid, 0 FROM \(table.name) AS row
                    WHERE \(rows) AND NOT \(table.waits)
                    ORDER BY row.id
                    """)
        }
    }
    try forgetChangesThatStayHere(in: db)
}

/// Forgets, in the write `db`, the saves that wait to be sent of the rows that
/// neither sync nor are in iCloud in full, as far as the device knows: they
/// stay on the device. Their deletions waited only if they synced as they
/// were deleted (`Schema`'s "v26 selective sync", and "v31 decks"
/// since).
private func forgetChangesThatStayHere(in db: Database) throws {
    for table in SyncingTable.all {
        try db.execute(
            sql: """
                DELETE FROM syncPending WHERE recordType = ? AND NOT isDeletion AND recordName IN (
                    SELECT row.uuid FROM \(table.name) AS row
                    WHERE row.uuid IN (SELECT recordName FROM syncPending WHERE recordType = ?)
                        AND NOT (\(table.syncs)) AND NOT \(table.isInICloud))
                """,
            arguments: [table.type.rawValue, table.type.rawValue])
    }
}

/// Whether a save of a row of one of `types` waits to be sent.
private func savesWait(ofTypes types: [SyncedRow.RecordType], in db: Database) throws -> Bool {
    let names = types.map { "'\($0.rawValue)'" }.joined(separator: ", ")
    return try Bool.fetchOne(
        db, sql: "SELECT EXISTS (SELECT 1 FROM syncPending WHERE recordType IN (\(names)) AND NOT isDeletion)")
        == true
}

extension ICloudRecord {
    /// Whether it's the record of a row that left iCloud.
    var hasLeft: Bool {
        value(of: leftKey) == .int(1)
    }

    /// The record of the row it holds, as it syncs, which names whether it
    /// left, so that a save over one that left clears it.
    func syncing() -> ICloudRecord {
        var fields = fields
        fields[leftKey] = .some(nil)
        return ICloudRecord(id: id, type: type, fields: fields, systemFields: systemFields)
    }

    /// The record of the row it holds, as one that left iCloud: it says so,
    /// and holds nothing else but the fields named `kept`, with when each
    /// last changed. It names every field it held, with nothing, so that a
    /// save over the row's record clears them in iCloud.
    func leaving(keeping kept: [SyncedField]) -> ICloudRecord {
        let keys = Set(kept.flatMap { [$0.rawValue, $0.timeKey] })
        var fields = fields.mapValues { _ in ICloudValue?.none }
        for key in keys {
            fields[key] = .some(self.fields[key] ?? nil)
        }
        fields[leftKey] = .int(1)
        return ICloudRecord(id: id, type: type, fields: fields, systemFields: systemFields)
    }
}

/// The record `row` syncs as, as `full` holds the row now: in full while it
/// syncs, and otherwise as one that left, which keeps a card's deck, so the
/// other devices learn why it left. A row that syncs whatever the choice is
/// as `full` holds it.
func syncedOrLeft(_ full: ICloudRecord, of row: SyncedRow, in db: Database) throws -> ICloudRecord {
    guard SyncingTable(row.recordType) != nil else {
        return full
    }
    guard try syncs(row, in: db) else {
        return full.leaving(keeping: row.recordType == .card ? [.deck] : [])
    }
    return full.syncing()
}

/// Takes `record`, from iCloud, of `row`, which left iCloud: the device keeps
/// its copy of the row, if it holds one, and never makes one. A card takes
/// the record's deck when its change is the latest, as the deck that made it
/// leave, Default when the record names none.
func takeWhatLeft(_ record: ICloudRecord, of row: SyncedRow, in db: Database) throws {
    guard case .card(let uuid) = row, let own = try SyncedTable.cards.record(ofRowWith: uuid, in: db) else {
        return
    }
    try takeLatestChanges(of: [.deck], in: record, over: own, to: row, in: db) { won in
        guard won.contains(.deck) else { return }
        try db.execute(
            sql: "UPDATE card SET deck = ? WHERE uuid = ?",
            arguments: [try record.optionalText(SyncedField.deck.rawValue) ?? Deck.defaultName, uuid.uuidString])
        guard let id = try Int64.fetchOne(db, sql: "SELECT id FROM card WHERE uuid = ?", arguments: [uuid.uuidString])
        else {
            return
        }
        try SyncedTable.cards.check(id, db)
    }
}

/// The fields of the choice of what syncs that keep when they last changed,
/// each the key of its value in the choice's record too.
private let choiceFields: [SyncedField] = [.onlyChosenTags]

/// The record of the choice of what syncs, as it is now, without what iCloud
/// said of it, or nil while it never changed: every card syncs, Ficha's own
/// choice, which the device has nothing to send of.
func syncChoiceRecord(in db: Database) throws -> ICloudRecord? {
    guard try !fieldTimes(of: .syncChoice, in: db).isEmpty else {
        return nil
    }
    return try choiceRecord(holding: syncsOnlyChosenDecks(in: db), in: db)
}

/// Applies `record`, from iCloud, to the choice of what syncs: it takes it
/// when its change is the latest. A record this version of Ficha can't read
/// throws, so it waits.
func applySyncChoice(_ record: ICloudRecord, in db: Database) throws -> Bool {
    let only: Bool
    switch try record.optionalInteger(SyncedField.onlyChosenTags.rawValue) {
    case 0?: only = false
    case 1?: only = true
    default: throw unreadable("The choice of what syncs from iCloud says something else than which cards sync")
    }
    try takeLatestChanges(
        of: choiceFields, in: record, over: try choiceRecord(holding: syncsOnlyChosenDecks(in: db), in: db),
        to: .syncChoice, in: db
    ) { won in
        guard won.contains(.onlyChosenTags) else { return }
        try db.execute(sql: "UPDATE syncChoice SET onlyChosenTags = ?", arguments: [only])
    }
    return true
}

/// The record of the choice of what syncs when only chosen decks sync, or
/// not, as `only` says, with when that last changed, if it did.
private func choiceRecord(holding only: Bool, in db: Database) throws -> ICloudRecord {
    try syncedRecord(
        of: .syncChoice, holding: [SyncedField.onlyChosenTags.rawValue: .int(only ? 1 : 0)],
        andTimesOf: choiceFields, in: db)
}
