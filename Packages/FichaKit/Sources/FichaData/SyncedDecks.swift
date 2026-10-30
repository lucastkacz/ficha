import FichaCore
import Foundation
internal import GRDB

// How a deck syncs (ADR 0017, ADR 0024): by its whole name, or Default by its
// own, whatever selective sync chooses, as a tag does, with what it has of its
// own, its switch, its color, its emoji and whether the user chose it to sync
// (ADR 0020), each of which keeps its latest change. Its record says that the
// deck exists, also while it has nothing of its own and no card lives in it,
// so a deck the user made reaches every device. A deck that two devices made
// with the same name is one deck, since its record is named after its name.
// A card names its deck in a field of its own record (`SyncedTable.cards`).

/// The keys of a deck's record.
enum DeckKey {
    /// Its whole name, exactly as cards name it, or nothing for Default.
    static let name = "name"
    // What it has of its own, each under its field's name.
    static let switchedOn = SyncedField.switchedOn.rawValue
    static let color = SyncedField.color.rawValue
    static let emoji = SyncedField.emoji.rawValue
    static let chosenToSync = SyncedField.chosenToSync.rawValue
}

/// The fields of a deck that keep when they last changed.
private let deckFields: [SyncedField] = [.switchedOn, .color, .emoji, .chosenToSync]

/// The record of the deck named `name`, as it is now, without what iCloud
/// said of it, or nil when it has no row: what it has of its own, which may
/// be nothing, and when each of those last changed.
func deckRecord(_ name: String, in db: Database) throws -> ICloudRecord? {
    guard let deck = try deckWithRow(name, in: db) else {
        return nil
    }
    return try record(of: deck, in: db)
}

/// The record of `deck`, as it is now, without what iCloud said of it.
private func record(of deck: Deck, in db: Database) throws -> ICloudRecord {
    try syncedRecord(
        of: .deck(deck.name),
        holding: [
            // Nothing for Default, whose name is empty.
            DeckKey.name: deck.isDefault ? nil : .string(deck.name),
            DeckKey.switchedOn: deck.switchedOn.map { .string($0.rawValue) },
            DeckKey.color: deck.color.map { .string($0.rawValue) },
            DeckKey.emoji: deck.emoji.map(ICloudValue.string),
            // Chosen, or nothing, as a deck that isn't holds nothing of it.
            DeckKey.chosenToSync: deck.chosenToSync ? .int(1) : nil,
        ],
        andTimesOf: deckFields, in: db)
}

/// Applies `record`, from iCloud, to the deck named `name`, which gets its
/// row when it has none: it takes each of its switch, color, emoji and
/// choice to sync whose change in the record is the latest.
func applyDeck(_ record: ICloudRecord, named name: String, in db: Database) throws -> Bool {
    let own = try FichaData.record(of: ownDeck(name, in: db), in: db)
    try takeLatestChanges(of: deckFields, in: record, over: own, to: .deck(name), in: db) { won in
        var deck = try ownDeck(name, in: db)
        if won.contains(.switchedOn) {
            deck.switchedOn = try record.optionalText(DeckKey.switchedOn).map { rawValue in
                guard let deckSwitch = DeckSwitch(rawValue: rawValue) else {
                    throw unreadable("A deck from iCloud has an unknown switch on")
                }
                return deckSwitch
            }
        }
        if won.contains(.color) {
            deck.color = try record.optionalText(DeckKey.color).map { rawValue in
                guard let color = TagColor(rawValue: rawValue) else {
                    throw unreadable("A deck from iCloud has an unknown color")
                }
                return color
            }
        }
        if won.contains(.emoji) {
            deck.emoji = try record.optionalText(DeckKey.emoji)
        }
        if won.contains(.chosenToSync) {
            switch try record.optionalInteger(DeckKey.chosenToSync) {
            case nil: deck.chosenToSync = false
            case 1?: deck.chosenToSync = true
            case _?: throw unreadable("A deck from iCloud says something else than whether it's chosen to sync")
            }
        }
        try save(deck, in: db)
    }
    return true
}

extension SyncedRow {
    /// The deck `record`, from iCloud, holds, by the name it holds, or
    /// Default when it holds none, or an error when the record isn't named
    /// after that name, as no deck's is.
    static func deck(of record: ICloudRecord) throws -> SyncedRow {
        let row = SyncedRow.deck(try record.optionalText(DeckKey.name) ?? Deck.defaultName)
        guard row.recordID == record.id else {
            throw unreadable("A deck from iCloud holds another deck's name")
        }
        return row
    }
}
