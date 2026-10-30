import FichaCore
import Foundation
internal import GRDB

// Selective sync (ADR 0020): sync carries every card, or only the cards with
// a tag the user chose. Which it is, and which tags are chosen, is one choice
// for all the user's devices, which syncs as a tag's color does (the
// `syncChoice` row, and each tag's `chosenToSync`). A card syncs when every
// card does, or one of its tags, or a tag one of them sits inside, is chosen
// (ADR 0021); a card's review log entries go
// with it, and so do the captures that expand it or follow it up. Every
// other row syncs whatever the choice: captures, tags, the settings that
// decide progress and the choice itself.
//
// The triggers record every change, whoever writes it, the CLI too; this file
// says which of them go up. A row that starts syncing goes up whole, and one
// that stops leaves iCloud: its record stays there as one that left, holding
// nothing of its own but, for a card, its tags, so that the other devices
// tell it from a deletion, which still removes the record (`SyncedDeletions`),
// whatever order the two changes reach them in, and learn why it left. Each
// device keeps its copy of a row that left, which syncs no more until it syncs
// again, when the copies join as after a long time offline (ADR 0017). The
// record that left is our own: CloudKit deletes a record, or holds it.

/// The key of the field of a record that says its row left iCloud: 1, or
/// nothing in a record of a row that syncs.
private let leftKey = "left"

extension Engine {
    /// Whether only the cards with a tag the user chose sync, rather than
    /// every card.
    public func syncsOnlyChosenTags() throws(EngineError) -> Bool {
        try read(FichaData.syncsOnlyChosenTags(in:))
    }

    /// Has only the cards with a tag the user chose sync, or every card, as
    /// `only` says, for all the user's devices. The cards that start syncing
    /// go up whole, and those that stop leave iCloud, kept on every device.
    /// When it's so already, nothing changes.
    public func syncOnlyChosenTags(_ only: Bool) throws(EngineError) {
        try write { db in
            try db.execute(sql: "UPDATE syncChoice SET onlyChosenTags = ?", arguments: [only])
        }
    }

    /// Chooses `tag` to sync, or stops choosing it, as `chosen` says, for all
    /// the user's devices: while only the cards with a chosen tag sync, its
    /// cards, and those of the tags inside it, also tags made later, start or
    /// stop syncing, unless another of their tags, or a tag one of them sits
    /// inside, is chosen. When it's so already, nothing changes.
    public func chooseToSync(_ tag: String, _ chosen: Bool) throws(EngineError) {
        try write { db in
            var own = try ownTag(tag, in: db)
            guard own.chosenToSync != chosen else { return }
            own.chosenToSync = chosen
            try save(own, in: db)
        }
    }

    /// Every tag the user can choose to sync, as a tree (ADR 0021): those of
    /// every card, with every tag they sit inside, and those chosen, which
    /// stay listed while no card carries them, so the user can untick them.
    /// Each comes with whether it's chosen, whether a tag it sits inside is,
    /// and what the images and sounds of its cards and of the cards of the
    /// tags inside it weigh, each file once, at the size Ficha keeps them, or
    /// nil when those cards have neither; in the order a tree lists them.
    func tagsToChooseFrom() throws(EngineError) -> [TagToChoose] {
        let (cards, own) = try read { db in (try allCards(in: db), try OwnTags(in: db)) }
        var filesByTag: [String: FileNames] = [:]
        for card in cards {
            for tag in TagPath.lineages(of: card.tags) {
                filesByTag[tag, default: FileNames()].images.formUnion(card.images)
                filesByTag[tag, default: FileNames()].sounds.formUnion(card.sounds)
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
        /// The tag at the top of `tree`, with the tags inside it, to choose.
        func toChoose(_ tree: TagTree) throws(EngineError) -> TagToChoose {
            let files = filesByTag[tree.name] ?? FileNames()
            var weight: Int64 = 0
            for image in files.images {
                weight += try size(of: image)
            }
            for sound in files.sounds {
                weight += try size(of: sound)
            }
            var children: [TagToChoose] = []
            for child in tree.children {
                children.append(try toChoose(child))
            }
            return TagToChoose(
                name: tree.name, isChosen: own.tag(tree.name).chosenToSync,
                isInsideChosen: TagPath.ancestors(of: tree.name).contains { own.tag($0).chosenToSync },
                weight: weight > 0 ? weight : nil, children: children)
        }
        let names = Set(filesByTag.keys).union(own.chosenToSync.map(\.name))
        var trees: [TagToChoose] = []
        for tree in TagTree.forest(of: names) {
            trees.append(try toChoose(tree))
        }
        return trees
    }

    /// Notes what syncs in the database's write `db`, as `noteWhatSyncs(in:)`
    /// says, when `everything` says so or a change that may change what syncs
    /// waits to be sent: one to a card, whose tags may have changed, to a
    /// tag, or to the choice. Otherwise only the changes of rows that neither
    /// sync nor are in iCloud stop waiting, which is quicker: a review, say.
    func noteWhatSyncs(everything: Bool) throws(EngineError) {
        try writeWithoutTelling { db in
            // A change to a card, whose tags may have changed, to a tag or to
            // the choice may change which rows sync.
            if try everything || savesWait(ofTypes: [.card, .tag, .syncChoice], in: db) {
                try FichaData.noteWhatSyncs(in: db)
            } else {
                try forgetChangesThatStayHere(in: db)
            }
        }
    }

    /// The places among the changes recorded of the rows that leave iCloud,
    /// whose records go up as ones that left, while a change to the choice
    /// waits to be sent, a tag's or whether only chosen tags sync: those wait
    /// until it went, so that a device that hears they left already knows
    /// why, as it does in any order, but sooner. Empty when no such change
    /// waits.
    func leavingWhileTheChoiceChanges() throws(EngineError) -> Set<Int64> {
        try read { db in
            guard try savesWait(ofTypes: [.tag, .syncChoice], in: db) else {
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

/// A tag the user can choose to sync, as the Sync tab lists it, in a tree
/// with the tags inside it.
public struct TagToChoose: Sendable, Equatable, Identifiable {
    /// Its whole name, exactly as cards carry it.
    public let name: String
    /// Whether the user chose it.
    public let isChosen: Bool
    /// Whether the user chose a tag it sits inside, so it syncs whatever its
    /// own tick, which can't be unticked meanwhile (ADR 0021).
    public let isInsideChosen: Bool
    /// What the images and sounds of its cards, and of the cards of the tags
    /// inside it, weigh, in bytes, each file once, or nil when they have
    /// neither.
    public let weight: Int64?
    /// The tags right inside it, in the order a tree lists them.
    public let children: [TagToChoose]

    init(
        name: String, isChosen: Bool, isInsideChosen: Bool = false, weight: Int64?, children: [TagToChoose] = []
    ) {
        self.name = name
        self.isChosen = isChosen
        self.isInsideChosen = isInsideChosen
        self.weight = weight
        self.children = children
    }

    public var id: String {
        name
    }

    /// Whether its checkbox shows ticked, as its cards sync: it's chosen, or
    /// a tag it sits inside is.
    public var isTicked: Bool {
        isChosen || isInsideChosen
    }

    /// Whether the user can tick or untick it: unless a tag it sits inside
    /// is chosen.
    public var canChoose: Bool {
        !isInsideChosen
    }
}

/// Whether only the cards with a tag the user chose sync, in `db`.
func syncsOnlyChosenTags(in db: Database) throws -> Bool {
    guard let only = try Bool.fetchOne(db, sql: "SELECT onlyChosenTags FROM syncChoice") else {
        throw unreadable("The database doesn't say which cards sync")
    }
    return only
}

/// What decides which cards sync, as a database held it when it was read:
/// for what a card would do once it changes, as an import's card that comes
/// in.
struct WhatSyncs: Sendable, Equatable {
    let onlyChosenTags: Bool
    let chosenTags: Set<String>

    /// What decides which cards sync in `db`, now.
    init(in db: Database) throws {
        onlyChosenTags = try syncsOnlyChosenTags(in: db)
        chosenTags = Set(try String.fetchAll(db, sql: "SELECT name FROM tag WHERE chosenToSync"))
    }

    private init(onlyChosenTags: Bool, chosenTags: Set<String>) {
        self.onlyChosenTags = onlyChosenTags
        self.chosenTags = chosenTags
    }

    /// What would decide which cards sync with only `chosenTags` chosen, as
    /// after some of them are deleted.
    func choosing(_ chosenTags: Set<String>) -> WhatSyncs {
        WhatSyncs(onlyChosenTags: onlyChosenTags, chosenTags: chosenTags)
    }

    /// Whether a card with the tags `tags` syncs, as `cardSyncs(tags:)` says
    /// in a database's SQL of every tag written as `TagPath.normalized(_:)`
    /// writes it, as every tag a card gets now is. A tag a card kept from
    /// before tags sat inside tags (ADR 0021) can differ: one with an empty
    /// level, or with spaces around one, sits inside no tag here, as All
    /// Tags lists it, and in SQL inside the tag its name starts with
    /// before a `::`; and one with an accent written apart from its letter
    /// is the same name as the accented letter's here, and another in SQL.
    func cardSyncs(tagged tags: [String]) -> Bool {
        !onlyChosenTags || !chosenTags.isDisjoint(with: TagPath.lineages(of: tags))
    }
}

/// SQL that holds when the card whose tags are the JSON array `tags` syncs:
/// every card does, or one of its tags, or a tag one of them sits inside, is
/// chosen (ADR 0021). A tag sits inside a chosen one when its name starts with
/// the chosen one's and `::`, compared character by character: never with
/// LIKE, whose `_` and `%` match other characters and which ignores the case
/// of ASCII letters. Swift's twin, `WhatSyncs.cardSyncs(tagged:)`, says where
/// the two differ. The deletion triggers of `Schema`'s "v27 tags inside
/// tags" hold a copy, which a migration keeps as it was.
func cardSyncs(tags: String) -> String {
    """
    (NOT (SELECT onlyChosenTags FROM syncChoice) OR EXISTS (
        SELECT 1 FROM json_each(\(tags)) AS cardTag JOIN tag ON tag.chosenToSync AND (tag.name = cardTag.value
            OR substr(cardTag.value, 1, length(tag.name) + 2) = tag.name || '::')))
    """
}

/// A table whose rows sync or not as selective sync decides, by their ID
/// unique across devices: the cards, the review log, with its card, and the
/// captures, unless they expand or follow up a card that doesn't sync.
private struct SyncingTable {
    let name: String
    let type: SyncedRow.RecordType
    /// SQL that holds when the table's row `row` syncs.
    let syncs: String

    static let cards = SyncingTable(name: "card", type: .card, syncs: cardSyncs(tags: "row.tags"))
    static let reviewLog = SyncingTable(
        name: "reviewLog", type: .reviewLogEntry,
        syncs: "EXISTS (SELECT 1 FROM card WHERE card.id = row.cardId AND \(cardSyncs(tags: "card.tags")))")
    static let captures = SyncingTable(
        name: "capture", type: .capture,
        syncs: """
            NOT EXISTS (SELECT 1 FROM card WHERE card.id IN (row.expandsCardId, row.followsUpCardId)
                AND NOT \(cardSyncs(tags: "card.tags")))
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

/// Notes what syncs, as the choice and the cards' tags decide it now, in the
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
/// were deleted (`Schema`'s "v26 selective sync", and "v27 tags inside tags"
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
/// syncs, and otherwise as one that left, which keeps a card's tags, so the
/// other devices learn why it left. A row that syncs whatever the choice is
/// as `full` holds it.
func syncedOrLeft(_ full: ICloudRecord, of row: SyncedRow, in db: Database) throws -> ICloudRecord {
    guard SyncingTable(row.recordType) != nil else {
        return full
    }
    guard try syncs(row, in: db) else {
        return full.leaving(keeping: row.recordType == .card ? [.tags] : [])
    }
    return full.syncing()
}

/// Takes `record`, from iCloud, of `row`, which left iCloud: the device keeps
/// its copy of the row, if it holds one, and never makes one. A card takes
/// the record's tags when theirs is the latest change, as the tags that made
/// it leave.
func takeWhatLeft(_ record: ICloudRecord, of row: SyncedRow, in db: Database) throws {
    guard case .card(let uuid) = row, let own = try SyncedTable.cards.record(ofRowWith: uuid, in: db) else {
        return
    }
    try takeLatestChanges(of: [.tags], in: record, over: own, to: row, in: db) { won in
        guard won.contains(.tags) else { return }
        try db.execute(
            sql: "UPDATE card SET tags = ? WHERE uuid = ?",
            arguments: [try record.text(SyncedField.tags.rawValue), uuid.uuidString])
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
    return try choiceRecord(holding: syncsOnlyChosenTags(in: db), in: db)
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
        of: choiceFields, in: record, over: try choiceRecord(holding: syncsOnlyChosenTags(in: db), in: db),
        to: .syncChoice, in: db
    ) { won in
        guard won.contains(.onlyChosenTags) else { return }
        try db.execute(sql: "UPDATE syncChoice SET onlyChosenTags = ?", arguments: [only])
    }
    return true
}

/// The record of the choice of what syncs when only chosen tags sync, or
/// not, as `only` says, with when that last changed, if it did.
private func choiceRecord(holding only: Bool, in db: Database) throws -> ICloudRecord {
    try syncedRecord(
        of: .syncChoice, holding: [SyncedField.onlyChosenTags.rawValue: .int(only ? 1 : 0)],
        andTimesOf: choiceFields, in: db)
}
