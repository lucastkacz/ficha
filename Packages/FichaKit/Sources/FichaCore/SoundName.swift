import Foundation

/// The name of a sound Ficha holds, by which a card's side refers to it: the
/// SHA-256 of its bytes, in lowercase hex, and `m4a`, the format every sound
/// is converted to as it comes in, like `3f2a…c1.m4a`. Named by its content,
/// a sound never changes once it's in, and the same sound coming in twice is
/// kept once. Any other name is refused, so a name never reaches outside the
/// sounds' folder.
public struct SoundName: RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: String

    /// The name `rawValue`, or nil when it isn't 64 lowercase hex digits and
    /// `.m4a`.
    public init?(rawValue: String) {
        let parts = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 64, parts[0].allSatisfy(Self.hexDigits.contains), parts[1] == "m4a"
        else {
            return nil
        }
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }

    private static let hexDigits = Set("0123456789abcdef")
}
