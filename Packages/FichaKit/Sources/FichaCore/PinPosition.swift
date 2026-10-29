import Foundation

/// Where a pinned tag sits among the pinned tags, in the order the user chose
/// for the Cards window's sidebar (ADR 0022): a key that sorts as text, as in
/// fractional indexing, so that moving one tag gives it a key between its new
/// neighbors' and leaves every other tag's as it was. Two devices that pin a
/// tag at the same place at once can give two tags the same key, and their
/// names break the tie.
///
/// A key is digits of base 62, `0` to `9`, `A` to `Z` and `a` to `z`, in the
/// order ASCII sorts them, read as a fraction between 0 and 1 that never ends
/// in `0`: so each fraction has one key, keys sort as their fractions do,
/// character by character as SQLite and Swift compare text, and there's
/// always another between two.
public struct PinPosition: Sendable, Hashable, Comparable {
    /// The digits, in the order they sort.
    private static let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf8)

    /// The key, as the `tag` table keeps it and a tag's record carries it.
    public let key: String
    /// The value of each of its digits, from 0 to 61.
    private let values: [Int]

    /// The position `key` names, or nil when it names none: when it's empty,
    /// has a character that isn't one of its digits, or ends in `0`.
    public init?(key: String) {
        var values: [Int] = []
        for byte in key.utf8 {
            guard let value = Self.digits.firstIndex(of: byte) else {
                return nil
            }
            values.append(value)
        }
        guard let last = values.last, last != 0 else {
            return nil
        }
        self.init(values: values)
    }

    /// The position whose digits have `values`.
    private init(values: [Int]) {
        self.values = values
        key = String(decoding: values.map { Self.digits[$0] }, as: UTF8.self)
    }

    public static func < (lhs: PinPosition, rhs: PinPosition) -> Bool {
        lhs.values.lexicographicallyPrecedes(rhs.values)
    }

    /// A position after `before` and before `after`, near halfway between
    /// them with as few digits as it can: before every other when `before`
    /// is nil, and after every other when `after` is nil. When `after`
    /// isn't after `before`, as when two tags have the same key, it's only
    /// after `before`.
    public static func between(_ before: PinPosition?, _ after: PinPosition?) -> PinPosition {
        let low = before?.values ?? []
        let high = after.flatMap { after in before.map { after > $0 } ?? true ? after.values : nil }
        return PinPosition(values: midpoint(low, high))
    }

    /// The digits of a fraction between the one `low` writes, which is 0
    /// when it has none, and the one `high` writes, which is 1 when it's
    /// nil, and is greater: their common digits, then the digit halfway
    /// between the first that differ when there's one, and otherwise one
    /// more digit after the lower.
    private static func midpoint(_ low: [Int], _ high: [Int]?) -> [Int] {
        if let high {
            // A digit `low` lacks is 0.
            let common = zip(high, low + Array(repeating: 0, count: max(high.count - low.count, 0)))
                .prefix { $0 == $1 }.count
            if common > 0 {
                return Array(high.prefix(common))
                    + midpoint(Array(low.dropFirst(common)), Array(high.dropFirst(common)))
            }
        }
        let lowDigit = low.first ?? 0
        let highDigit = high?.first ?? digits.count
        if highDigit - lowDigit > 1 {
            return [(lowDigit + highDigit + 1) / 2]
        }
        if let high, high.count > 1 {
            // `high`'s first digit alone is less than `high`, and more than
            // `low`.
            return [highDigit]
        }
        return [lowDigit] + midpoint(Array(low.dropFirst()), nil)
    }
}
