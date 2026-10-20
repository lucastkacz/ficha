import Foundation

/// Whether a capture's text repeats `text`, which is another capture's text or
/// a card's front: they're the same once their surrounding spaces and line
/// breaks are trimmed, ignoring case and accents. In Spanish, ñ is a letter of
/// its own and not an n with an accent, so “año” doesn't repeat “ano”.
public func repeats(_ captureText: String, _ text: String) -> Bool {
    comparable(captureText) == comparable(text)
}

/// Whether `text`, a card's front, back or source, mentions `search`, what
/// Lucas looks for in the Cards window: it contains it once both are compared
/// as duplicates are, trimmed, ignoring case and accents, but not the ñ, so
/// “fertil” is in “Muy fértil” and “ano” isn't in “año”. A blank search is in
/// every text.
public func mentions(_ text: String, _ search: String) -> Bool {
    let search = comparable(search)
    return search.isEmpty || comparable(text).contains(search)
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
