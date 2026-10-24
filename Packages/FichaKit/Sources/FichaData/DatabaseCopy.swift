import Foundation

/// A copy of everything Ficha keeps but its sounds, as it was at one moment,
/// which the engine saved in its Backups folder: a backup, or a copy before
/// an update, a restore or an import. It's the database's file, and the
/// images its cards refer to, which the copies share in the Backups folder's
/// Images folder, each once for all of them. Its file's name says its kind, and when it was saved,
/// by the engine's time, in UTC, like `Backup 2026-10-22T120000Z.sqlite`, with a
/// number after the time when two copies of a kind were saved in the same
/// second, as Finder numbers a copy.
public struct DatabaseCopy: Sendable, Hashable, Identifiable, Encodable {
    /// Why the engine saved it.
    public enum Kind: String, Sendable, Encodable, CaseIterable {
        /// A backup, which Ficha saves on its own or when Lucas clicks Back Up
        /// Now: the only kind it counts and prunes.
        case backup
        /// A copy before a new version of Ficha changed the database.
        case beforeUpdate
        /// A copy of everything as it was just before a restore, so restoring
        /// it undoes the restore.
        case beforeRestore
        /// A copy of everything as it was just before an import, so restoring
        /// it undoes the import.
        case beforeImport

        /// How its file's name starts.
        fileprivate var namePrefix: String {
            switch self {
            case .backup: "Backup"
            case .beforeUpdate: "Before update"
            case .beforeRestore: "Before restore"
            case .beforeImport: "Before import"
            }
        }
    }

    public let kind: Kind
    /// When it was saved, by the engine's time, to the second.
    public let savedAt: Date
    /// What its file weighs, in bytes: the database's, without the images
    /// the copies share.
    public let size: Int64
    /// Its file's name in the Backups folder, which `ficha restore` takes.
    public let name: String

    public var id: String {
        name
    }

    /// The number after its time, when another copy of its kind was saved in
    /// the same second: 2 for the second one, and 1 for the first.
    let number: Int

    /// The `number`th copy of `kind` saved at `time`, in its second, with
    /// `size` bytes.
    init(_ kind: Kind, savedAt time: Date, number: Int, size: Int64) {
        self.kind = kind
        savedAt = Date(timeIntervalSince1970: time.timeIntervalSince1970.rounded(.down))
        self.size = size
        self.number = number
        let suffix = number > 1 ? " \(number)" : ""
        name = "\(kind.namePrefix) \(time.formatted(timeInName))\(suffix).sqlite"
    }

    /// The copy whose file is named `name`, with `size` bytes, or nil when the
    /// name isn't one the engine gives a copy.
    init?(name: String, size: Int64) {
        guard let match = name.wholeMatch(of: copyName),
            let kind = Kind.allCases.first(where: { $0.namePrefix == match.output.1 }),
            let savedAt = try? timeInName.parse(String(match.output.2))
        else {
            return nil
        }
        self.kind = kind
        self.savedAt = savedAt
        self.size = size
        self.name = name
        number = match.output.3.flatMap { Int($0) } ?? 1
    }

    private enum CodingKeys: String, CodingKey {
        case kind, savedAt, size, name
    }
}

/// A copy's file name: how its kind's names start, its time, and a number
/// after it when there were others in the same second. A regex isn't
/// `Sendable`, so each use makes its own.
private var copyName: Regex<(Substring, Substring, Substring, Substring?)> {
    /(.+) (\d{4}-\d{2}-\d{2}T\d{6}Z)(?: ([2-9]|[1-9]\d+))?\.sqlite/
}

/// A copy's time in its file's name: ISO 8601's basic format for the time,
/// which has no colons, since Finder shows a colon in a name as a slash, in
/// UTC, like `2026-10-22T120000Z`.
private let timeInName = Date.ISO8601FormatStyle(timeSeparator: .omitted, timeZone: .gmt)
