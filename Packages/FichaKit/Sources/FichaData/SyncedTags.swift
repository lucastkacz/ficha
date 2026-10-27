import FichaCore
import Foundation
internal import GRDB

// How a tag syncs (ADR 0017): by its name, with what it has of its own, its
// switch, its color and its emoji, each of which keeps its latest change. A
// tag that two devices made with the same name is one tag, since its record
// is named after its name.

/// The keys of a tag's record.
enum TagKey {
    /// Its name, exactly as cards carry it.
    static let name = "name"
    // What it has of its own, each under its field's name.
    static let switchedOn = SyncedField.switchedOn.rawValue
    static let color = SyncedField.color.rawValue
    static let emoji = SyncedField.emoji.rawValue
}

/// The fields of a tag that keep when they last changed.
private let tagFields: [SyncedField] = [.switchedOn, .color, .emoji]

/// The record of the tag named `name`, as it is now, without what iCloud
/// said of it: what it has of its own, which may be nothing, and when each
/// of those last changed.
func tagRecord(_ name: String, in db: Database) throws -> ICloudRecord {
    let tag = try ownTag(name, in: db)
    let times = try fieldTimes(of: .tag(name), in: db)
    var fields: [String: ICloudValue?] = [
        TagKey.name: .string(name),
        TagKey.switchedOn: tag.switchedOn.map { .string($0.rawValue) },
        TagKey.color: tag.color.map { .string($0.rawValue) },
        TagKey.emoji: tag.emoji.map(ICloudValue.string),
    ]
    for field in tagFields {
        fields[field.timeKey] = times[field].map { .int($0.wholeMilliseconds) }
    }
    return ICloudRecord(
        id: SyncedRow.tag(name).recordID, type: SyncedRow.RecordType.tag.rawValue, fields: fields, systemFields: nil)
}

/// Applies `record`, from iCloud, to the tag named `name`: it takes each of
/// its switch, color and emoji whose change in the record is the latest. A
/// tag left with nothing of its own is just a name.
func applyTag(_ record: ICloudRecord, named name: String, in db: Database) throws -> Bool {
    var tag = try ownTag(name, in: db)
    let local = try fieldTimes(of: .tag(name), in: db)
    let incoming = try record.fieldTimes(of: tagFields)
    let own = try tagRecord(name, in: db)
    let won = tagFields.filter { field in
        FieldChange(changedAt: incoming[field], holdsSomething: record.value(of: field.rawValue) != nil)
            .wins(over: FieldChange(changedAt: local[field], holdsSomething: own.value(of: field.rawValue) != nil))
    }
    if won.contains(.switchedOn) {
        tag.switchedOn = try record.optionalText(TagKey.switchedOn).map { name in
            guard let tagSwitch = TagSwitch(rawValue: name) else {
                throw unreadable("A tag from iCloud has an unknown switch on")
            }
            return tagSwitch
        }
    }
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
    try save(tag, in: db)
    try stamp(incoming.filter { won.contains($0.key) }, of: .tag(name), in: db)
    return true
}
