import Foundation

/// How often Ficha saves a backup on its own, and how many backups it keeps,
/// as Lucas sets them in Settings' Backups tab. Backups can't be turned off.
public struct BackupSettings: Sendable, Equatable {
    /// How often Ficha saves a backup on its own: once in each hour, day or
    /// week of the Mac's calendar.
    public enum Frequency: String, Sendable, CaseIterable {
        case hourly
        case daily
        case weekly

        /// The part of the calendar a backup is due once in.
        var period: Calendar.Component {
            switch self {
            case .hourly: .hour
            case .daily: .day
            case .weekly: .weekOfYear
            }
        }
    }

    /// How many backups Ficha may keep: from 1 to 30.
    public static let keptRange = 1...30

    /// Every day, keeping the last 7.
    public static let defaults = BackupSettings(frequency: .daily, keptCount: 7)

    public var frequency: Frequency
    /// How many backups Ficha keeps: as each one is saved, the oldest ones
    /// beyond this number go.
    public let keptCount: Int

    /// The settings with `frequency` and `keptCount`, or nil when the count
    /// is outside `keptRange`.
    public init?(frequency: Frequency, kept keptCount: Int) {
        guard Self.keptRange.contains(keptCount) else {
            return nil
        }
        self.init(frequency: frequency, keptCount: keptCount)
    }

    private init(frequency: Frequency, keptCount: Int) {
        self.frequency = frequency
        self.keptCount = keptCount
    }

    /// Whether a backup is due at `now`: none of the backups saved at
    /// `backupTimes` falls in the hour, day or week `now` is in, by
    /// `calendar`. A backup saved earlier in that period, on its own or with
    /// Back Up Now, is that period's backup.
    public func isBackupDue(at now: Date, savedAt backupTimes: [Date], calendar: Calendar) -> Bool {
        guard let period = calendar.dateInterval(of: frequency.period, for: now) else {
            // A calendar that can't say which hour, day or week it is: a
            // backup too many is better than one too few.
            return true
        }
        return !backupTimes.contains { period.contains($0) && $0 < period.end }
    }
}
