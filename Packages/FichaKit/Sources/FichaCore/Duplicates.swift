import Foundation

/// Whether a capture's text repeats `text`, another capture's text or a card's
/// front: they're the same once their surrounding spaces and line breaks are
/// trimmed, ignoring case and accents. In Spanish, ñ is a letter of its own
/// and not an n with an accent, so “año” doesn't repeat “ano”.
public func repeats(_ captureText: String, _ text: String) -> Bool {
    comparable(captureText) == comparable(text)
}

/// The text as duplicates are compared: trimmed, in lowercase and without
/// accents, but with its ñ.
private func comparable(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .map { character in
            character == "ñ" ? "ñ" : String(character).folding(options: .diacriticInsensitive, locale: nil)
        }
        .joined()
}
