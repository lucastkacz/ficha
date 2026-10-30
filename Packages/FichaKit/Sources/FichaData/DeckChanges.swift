import FichaCore
import Foundation
internal import GRDB

// A rename or a deletion of a deck reaches every card on every device, those
// that don't sync included, as a tag's does (`TagChanges.swift`, ADR 0022):
// the device that makes it records it as a change to the deck, a row of the
// `deckChange` table (`Schema`'s "v31 decks"), which syncs as a record of its
// own whatever selective sync chooses, and which every device that hears of
// it applies once, in the write that takes it from iCloud. Decks have a
// record of their own rather than sharing a tag's with a kind: a version of
// Ficha that knows changes to tags but not to decks would read a deck's
// change as a tag's, and apply it to its tags, while a record of a type it
// doesn't know waits for a version that does. A device keeps the row of each
// change it made or heard of, which says it applied it, and, after it took a
// restore's cards, the IDs of those it applied in
// `deckChangeAppliedBeforeARestore`, as a tag's.
//
// A device that hears of a change applies it as an edit of its own, which
// syncs as such, to the decks' rows as the fetch left them, and to every card
// it holds that lives in the deck, or a deck inside it, synced or not, as it
// held them then: the fetch applies the changes it brings after its decks
// and before its cards (`Sync`'s `applyingRank()`). A rename moves those
// cards to the deck's new name, and the rows to their new names, each new
// row made on this device when the old one was, and a row that joins one
// there made here when either was (`moveRows(ofDeck:to:among:markingMadeHere:in:)`).
// A deletion deletes the cards that sync, as the device that made it deleted
// them, with what goes with a card another device deleted
// (`SyncedDeletions.swift`), and moves those that don't to Default, which
// the device that made it may never have held; then the rows go, with
// whether they were made here. Each field the edit changes, a card's deck or
// what a deck's row has of its own, records it as made when the change was,
// or a millisecond after it last changed, as a tag's change records it
// (`stamp(_:of:changedBy:in:)`), and an old row's record waits to be deleted,
// as the device that made it deletes it. The changes it holds that were made
// after this one, heard before it, then follow on the cards and the rows it
// changed, in the order they were made, as on the device that made them.

/// A rename or a deletion of a deck, which reaches every card that lives in
/// it or in a deck inside it, and the decks inside it.
enum DeckEdit: Sendable, Equatable {
    /// The deck `deck`, the first, renamed to the second.
    case rename(String, to: String)
    /// The deck deleted.
    case deletion(String)

    /// The deck it changes, never Default.
    var deck: String {
        switch self {
        case .rename(let deck, _), .deletion(let deck): deck
        }
    }

    /// The name it renames the deck to, or nil for a deletion.
    var newName: String? {
        switch self {
        case .rename(_, let newName): newName
        case .deletion: nil
        }
    }
}

/// A rename or a deletion of a deck, as a device records it, which syncs to
/// the user's other devices.
struct DeckChange: Sendable, Equatable {
    /// Its ID unique across devices, which its record is named by.
    let id: UUID
    let edit: DeckEdit
    /// When it was made, by the engine's time on the device that made it.
    let madeAt: Date

    /// A change read from a row of the `deckChange` table.
    init(row: Row) throws {
        let uuid: String = try row.decode(forColumn: "uuid")
        guard let id = UUID(uuidString: uuid) else {
            throw unreadable("A change to a deck isn't named by a UUID")
        }
        self.id = id
        let deck: String = try row.decode(forColumn: "deck")
        let newName: String? = try row.decode(forColumn: "newName")
        edit = newName.map { .rename(deck, to: $0) } ?? .deletion(deck)
        madeAt = try row.decode(forColumn: "madeAt")
    }
}

/// Records `edit`, made on this device in the write `db`, as a change to the
/// deck, made as the write happens; it waits to be sent to the user's other
/// devices, as the database's trigger records it.
func recordDeckChange(_ edit: DeckEdit, in db: Database) throws {
    try db.execute(
        sql: "INSERT INTO deckChange (uuid, deck, newName, madeAt) VALUES (?, ?, ?, (SELECT at FROM syncWrite))",
        arguments: [UUID().uuidString, edit.deck, edit.newName])
}

/// Takes `record`, from iCloud, of the change to a deck with this ID, in the
/// write `db`, which records no change to send: a change the device holds
/// already stays as it is, one it applied before it took a restore's cards
/// comes in again and isn't applied, and one new to it comes in and is
/// applied, as the file's header says.
func applyDeckChange(_ record: ICloudRecord, as id: UUID, in db: Database) throws -> Bool {
    let isNew = try !SyncedTable.deckChanges.holdsRow(with: id, in: db) && !wasAppliedBeforeARestore(id, in: db)
    guard try SyncedTable.deckChanges.apply(record, toRowWith: id, in: db) else {
        return false
    }
    if isNew {
        try applyHeardDeckChange(id, in: db)
    }
    return true
}

/// Whether the device applied the change to a deck with this ID before it
/// took a restore's cards (`dropEverythingThatSyncs(in:)`).
private func wasAppliedBeforeARestore(_ id: UUID, in db: Database) throws -> Bool {
    try Bool.fetchOne(
        db, sql: "SELECT EXISTS (SELECT 1 FROM deckChangeAppliedBeforeARestore WHERE uuid = ?)",
        arguments: [id.uuidString]) == true
}

/// Applies the change with this ID, which this device just heard of from
/// another, in the write `db` that took it from iCloud, which records no
/// change to send, as the file's header says, and then the changes made
/// after it, heard before it, on what it changed.
private func applyHeardDeckChange(_ id: UUID, in db: Database) throws {
    guard let row = try Row.fetchOne(db, sql: "SELECT * FROM deckChange WHERE uuid = ?", arguments: [id.uuidString])
    else {
        throw unreadable("A change to a deck that came from iCloud isn't there")
    }
    let change = try DeckChange(row: row)
    var reached = try apply(change, among: nil, in: db)
    let later = try Row.fetchAll(
        db, sql: "SELECT * FROM deckChange WHERE madeAt > ? AND uuid <> ? ORDER BY madeAt, id",
        arguments: [change.madeAt, id.uuidString]
    ).map(DeckChange.init(row:))
    for following in later where !reached.isEmpty {
        reached.formUnion(try apply(following, among: reached, in: db))
    }
}

/// What applying a change to a deck changed on this device: the ids of the
/// cards it moved, and the new names of the rows it moved.
private struct Reached {
    var cards: Set<Int64> = []
    var decks: Set<String> = []

    var isEmpty: Bool {
        cards.isEmpty && decks.isEmpty
    }

    mutating func formUnion(_ other: Reached) {
        cards.formUnion(other.cards)
        decks.formUnion(other.decks)
    }
}

/// Applies `change`, which another device made, to the cards and the rows
/// among `reached`, or to every card and row when it's nil, in the write `db`,
/// as the file's header says, and returns what it changed.
private func apply(_ change: DeckChange, among reached: Reached?, in db: Database) throws -> Reached {
    let deck = change.edit.deck
    let cards = try cardsLiving(within: deck, in: db).filter { reached?.cards.contains($0.id) ?? true }
    let rows = try String.fetchAll(db, sql: "SELECT name FROM deck").filter { name in
        TagPath.isTag(name, within: deck) && (reached?.decks.contains(name) ?? true)
    }
    var changed = Reached()
    switch change.edit {
    case .rename(_, let name):
        for card in cards {
            let newDeck = TagPath.renaming(card.deck, from: deck, to: name) ?? card.deck
            try db.execute(sql: "UPDATE card SET deck = ? WHERE id = ?", arguments: [newDeck, card.id])
            try stamp(.deck, of: card.row, changedBy: change.madeAt, in: db)
            try waitToBeSent(card.row, as: .saved, in: db)
            changed.cards.insert(card.id)
        }
        // The rows the new names had, if any, before the rows move onto
        // them; and what of the old rows changed after the change was made,
        // here while this device hadn't heard of it, which is later than
        // anything the device that made it knew, so it moves with the rename
        // also onto a deck that was there, and wins, as a later change does.
        var had: [String: Deck] = [:]
        for new in rows.compactMap({ TagPath.renaming($0, from: deck, to: name) }) {
            had[new] = try deckWithRow(new, in: db)
        }
        var changedSince: [String: (deck: Deck, times: [SyncedField: Date])] = [:]
        for old in rows {
            changedSince[old] = (
                try ownDeck(old, in: db), try fieldTimes(of: .deck(old), in: db).filter { $0.value > change.madeAt }
            )
        }
        let moved = try moveRows(ofDeck: deck, to: name, among: Set(rows), markingMadeHere: false, in: db)
        // Every old row's deletion first, so that a row that moved onto the
        // old name of another is sent as saved.
        for (old, _) in moved {
            try waitToBeSent(.deck(old), as: .deleted, in: db)
        }
        for (old, new) in moved {
            let since = changedSince[old]?.times ?? [:]
            if let oldDeck = changedSince[old]?.deck, !since.isEmpty {
                try changeOwnDecks([new], in: db) { $0.take(since.keys, of: oldDeck) }
            }
            let fields = (had[new] ?? Deck(name: new)).fieldsDiffering(from: try ownDeck(new, in: db))
            for field in fields {
                try stamp(field, of: .deck(new), changedBy: max(change.madeAt, since[field] ?? change.madeAt), in: db)
            }
            if had[new] == nil || !fields.isEmpty {
                try waitToBeSent(.deck(new), as: .saved, in: db)
            }
            changed.decks.insert(new)
        }
    case .deletion:
        let whatSyncs = try WhatSyncs(in: db)
        for card in cards {
            if whatSyncs.cardSyncs(inDeck: card.deck) {
                try deleteCard(deletedOnAnotherDevice: card.uuid, at: change.madeAt, in: db)
                if try systemFields(of: card.row.recordID, in: db) != nil {
                    try waitToBeSent(card.row, as: .deleted, in: db)
                }
            } else {
                try db.execute(sql: "UPDATE card SET deck = ? WHERE id = ?", arguments: [Deck.defaultName, card.id])
                try stamp(.deck, of: card.row, changedBy: change.madeAt, in: db)
                try waitToBeSent(card.row, as: .saved, in: db)
                changed.cards.insert(card.id)
            }
        }
        for name in rows {
            try db.execute(sql: "DELETE FROM deck WHERE name = ?", arguments: [name])
            try waitToBeSent(.deck(name), as: .deleted, in: db)
        }
    }
    return changed
}

/// A card that lives in a deck, as a change to the deck reaches it.
struct CardInDeck {
    let id: Int64
    let uuid: UUID
    /// The deck it lives in, by its whole name.
    let deck: String

    /// The row it syncs as.
    var row: SyncedRow {
        .card(uuid)
    }
}

/// Every card that lives in the deck `deck`, never Default, or in a deck
/// inside it, buried ones too, in `db`, in the order they came in. A deck
/// sits inside another when its name starts with the other's and `::`,
/// compared character by character, as `TagPath` compares them.
func cardsLiving(within deck: String, in db: Database) throws -> [CardInDeck] {
    try Row.fetchAll(
        db,
        sql: """
            SELECT id, uuid, deck FROM card
            WHERE deck = ? OR substr(deck, 1, length(?) + 2) = ? || '::'
            ORDER BY id
            """,
        arguments: [deck, deck, deck]
    ).map { row in
        let uuid: String = try row.decode(forColumn: "uuid")
        guard let id = UUID(uuidString: uuid) else {
            throw unreadable("A card isn't named by a UUID")
        }
        return CardInDeck(id: try row.decode(forColumn: "id"), uuid: id, deck: try row.decode(forColumn: "deck"))
    }
}

/// Moves the rows of the `deck` table of `deck` and the decks inside it,
/// among `rows`, or every one when it's nil, to the new name `name`, in the
/// write `db`, and returns each old name with its new one: each old row
/// goes, and a new one comes with what it had of its own, unless its new
/// name is among the decks that exist apart from the ones that move, whose
/// deck keeps exactly what it had of its own, which may be nothing, as the
/// moved row is dropped. The new row, or the one there, is made on this
/// device when `markingMadeHere` says so, as on the device that renames, or
/// when the old one was, as on one that applies another's rename, since
/// whether a deck was made here never syncs: a deck the user just moved, an
/// empty one too, stays listed under selective sync. The rows that move all
/// go first, so that a row that moves onto the old name of another, as
/// moving a deck onto the deck it sits inside can, never meets it.
@discardableResult
func moveRows(
    ofDeck deck: String, to name: String, among rows: Set<String>?, markingMadeHere: Bool, in db: Database
) throws -> [(old: String, new: String)] {
    let own = try OwnDecks(in: db)
    let existing = try decksThatExist(apartFrom: deck, in: db)
    let moving = own.names.filter { TagPath.isTag($0, within: deck) && (rows?.contains($0) ?? true) }.sorted()
    let before = try moving.map { try ownDeck($0, in: db) }
    for old in moving {
        try db.execute(sql: "DELETE FROM deck WHERE name = ?", arguments: [old])
    }
    var moved: [(old: String, new: String)] = []
    for old in before {
        guard let new = TagPath.renaming(old.name, from: deck, to: name) else {
            continue
        }
        if !existing.contains(new) {
            try save(old.named(new), in: db)
        }
        try makeRow(ofDeck: new, madeHere: markingMadeHere || own.madeHere.contains(old.name), in: db)
        moved.append((old.name, new))
    }
    return moved
}

/// The decks that exist apart from `deck` and the decks inside it, in `db`:
/// each a row of the `deck` table has, each a card lives in, and each one of
/// those sits inside, as a parent exists through the decks inside it.
func decksThatExist(apartFrom deck: String, in db: Database) throws -> Set<String> {
    let rows = try String.fetchAll(db, sql: "SELECT name FROM deck")
    let livedIn = try String.fetchAll(db, sql: "SELECT DISTINCT deck FROM card")
    return TagPath.lineages(of: (rows + livedIn).filter { !TagPath.isTag($0, within: deck) })
        .subtracting([Deck.defaultName])
}

/// Refuses `deck`, which was to be renamed, moved or deleted in `db`, when
/// it's Default, which never is, or when it isn't there: no row has it, no
/// card lives in it and no deck sits inside it.
func checkDeckToChange(_ deck: String, in db: Database) throws {
    guard deck != Deck.defaultName else {
        throw EngineError.defaultDeckStays
    }
    // Default sits inside no deck, so every other deck exists apart from it.
    guard try decksThatExist(apartFrom: Deck.defaultName, in: db).contains(deck) else {
        throw EngineError.deckNotFound(deck)
    }
}

extension Deck {
    /// The deck with what it has of its own, under the name `name`.
    fileprivate func named(_ name: String) -> Deck {
        Deck(name: name, switchedOn: switchedOn, color: color, emoji: emoji, chosenToSync: chosenToSync)
    }

    /// Takes `fields` of what `other` has of its own.
    fileprivate mutating func take(_ fields: some Sequence<SyncedField>, of other: Deck) {
        for field in fields {
            switch field {
            case .switchedOn: switchedOn = other.switchedOn
            case .color: color = other.color
            case .emoji: emoji = other.emoji
            case .chosenToSync: chosenToSync = other.chosenToSync
            default: break
            }
        }
    }

    /// The fields of a deck's own that `other`, the same deck at another
    /// time, holds otherwise, as they sync.
    fileprivate func fieldsDiffering(from other: Deck) -> [SyncedField] {
        var fields: [SyncedField] = []
        if switchedOn != other.switchedOn { fields.append(.switchedOn) }
        if color != other.color { fields.append(.color) }
        if emoji != other.emoji { fields.append(.emoji) }
        if chosenToSync != other.chosenToSync { fields.append(.chosenToSync) }
        return fields
    }
}
