import Foundation

/// One device's side of a field of a row that syncs, as sync compares two
/// devices' sides to merge the row (ADR 0017): when the field last changed
/// there, and whether it holds something there.
public struct FieldChange: Sendable, Equatable {
    /// When the field last changed, or nil when it hasn't since its row came
    /// in, nor since before Ficha recorded changes to sync.
    public let changedAt: Date?
    /// Whether the field holds something, rather than nothing.
    public let holdsSomething: Bool

    public init(changedAt: Date?, holdsSomething: Bool) {
        self.changedAt = changedAt
        self.holdsSomething = holdsSomething
    }

    /// Whether this side, iCloud's, wins over `local`, this device's: the
    /// later change wins, and a time is later than none. iCloud's wins a tie,
    /// so every device ends with what iCloud holds. When neither side has a
    /// time, something wins over nothing, so a first sync never loses what a
    /// field got before Ficha recorded changes.
    public func wins(over local: FieldChange) -> Bool {
        switch (changedAt, local.changedAt) {
        case (let incoming?, let local?): incoming >= local
        case (_?, nil): true
        case (nil, _?): false
        case (nil, nil): holdsSomething || !local.holdsSomething
        }
    }
}
