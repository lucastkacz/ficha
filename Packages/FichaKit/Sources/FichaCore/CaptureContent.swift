import Foundation

/// What a capture holds, cleaned up the same way wherever Lucas types it: its
/// text, and a note and a source if he wants, without surrounding spaces or
/// line breaks. A note or source left blank is no note or source.
public struct CaptureContent: Sendable {
    public let text: String
    public let note: String?
    public let source: String?

    /// What these fields make, or nil when the text is blank, since there's
    /// nothing to capture.
    public init?(text: String, note: String?, source: String?) {
        guard let text = nonBlank(text) else {
            return nil
        }
        self.text = text
        self.note = nonBlank(note)
        self.source = nonBlank(source)
    }
}

/// The value without surrounding spaces or line breaks, or nil when nothing is left.
private func nonBlank(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return nil
    }
    return value
}
