import FichaCore
import Foundation
internal import GRDB

// How a tag syncs (ADR 0017): by its name, whatever selective sync chooses,
// with what it has of its own, its color, its emoji and its pin, with its
// place among the pinned tags (ADR 0022), each of which keeps its latest
// change. A tag that two devices made with the same name is one tag, since
// its record is named after its name. The switch and the choice to sync it
// had before decks took them (ADR 0024) stay on each device for the
// conversion of Lucas's tags into decks, and don't sync: a record that still
// holds one, from a device before decks, leaves this device's as it is.

/// The keys of a tag's record.
enum TagKey {
    /// Its name, exactly as cards carry it.
    static let name = "name"
    // What it has of its own, each under its field's name.
    static let color = SyncedField.color.rawValue
    static let emoji = SyncedField.emoji.rawValue
    static let pin = SyncedField.pin.rawValue
}

/// The fields of a tag that keep when they last changed.
private let tagFields: [SyncedField] = [.color, .emoji, .pin]

/// The record of the tag named `name`, as it is now, without what iCloud
/// said of it: what it has of its own, which may be nothing, and when each
/// of those last changed.
func tagRecord(_ name: String, in db: Database) throws -> ICloudRecord {
    let tag = try ownTag(name, in: db)
    return try syncedRecord(
        of: .tag(name),
        holding: [
            TagKey.name: .string(name),
            TagKey.color: tag.color.map { .string($0.rawValue) },
            TagKey.emoji: tag.emoji.map(ICloudValue.string),
            TagKey.pin: tag.pin.map { .string($0.key) },
        ],
        andTimesOf: tagFields, in: db)
}

/// Applies `record`, from iCloud, to the tag named `name`: it takes each of
/// its color, emoji and pin whose change in the record is the latest. A tag
/// left with nothing of its own is just a name.
func applyTag(_ record: ICloudRecord, named name: String, in db: Database) throws -> Bool {
    try takeLatestChanges(of: tagFields, in: record, over: try tagRecord(name, in: db), to: .tag(name), in: db) {
        won in
        var tag = try ownTag(name, in: db)
        if won.contains(.color) {
            tag.color = try record.optionalText(TagKey.color).map { name in
                guard let color = TagColor(rawValue: name) else {
                    throw unreadable("A tag from iCloud has an unknown color")
                }
                return color
            }
        }
        if won.contains(.emoji) {
            tag.emoji = try record.optionalText(TagKey.emoji)
        }
        if won.contains(.pin) {
            tag.pin = try record.optionalText(TagKey.pin).map { key in
                guard let pin = PinPosition(key: key) else {
                    throw unreadable("A tag from iCloud has a pin that isn't a place among the pinned tags")
                }
                return pin
            }
        }
        try save(tag, in: db)
    }
    return true
}
