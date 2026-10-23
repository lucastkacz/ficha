import Foundation

/// The name of an image Ficha holds, by which a card's side refers to it: the
/// SHA-256 of its bytes, in lowercase hex, and its format's extension, `jpg`
/// or `png`, like `3f2a…c1.jpg`. Named by its content, an image never changes
/// once it's in, and the same image coming in twice is kept once. Any other
/// name is refused, so a name never reaches outside the images' folder.
public struct ImageName: RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: String

    /// The name `rawValue`, or nil when it isn't 64 lowercase hex digits and
    /// `.jpg` or `.png`.
    public init?(rawValue: String) {
        let parts = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 64, parts[0].allSatisfy(Self.hexDigits.contains),
            Self.extensions.contains(String(parts[1]))
        else {
            return nil
        }
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }

    private static let hexDigits = Set("0123456789abcdef")
    private static let extensions: Set = ["jpg", "png"]
}
