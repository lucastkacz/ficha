import Foundation

/// Lucas's note on what to fix in a card he flags, cleaned up the same way
/// wherever he types it: without surrounding spaces or line breaks.
public struct FlagNote: Sendable {
    public let text: String

    /// The note these words make, or nil when they're blank, since a flag
    /// says what to fix.
    public init?(_ text: String) {
        guard let text = nonBlank(text) else {
            return nil
        }
        self.text = text
    }
}
