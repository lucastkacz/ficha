import Foundation

/// Whether a capture's text repeats `text`, which is another capture's text or
/// a card's front: they're the same once their surrounding spaces and line
/// breaks are trimmed, ignoring case, accents, superscripts and subscripts, so
/// “H2O” repeats “H₂O”. In Spanish, ñ is a letter of its own and not an n
/// with an accent, so “año” doesn't repeat “ano”.
public func repeats(_ captureText: String, _ text: String) -> Bool {
    comparable(captureText) == comparable(text)
}

/// `text`, another capture's text or a card's front, as `repeats` compares
/// it, for finding the duplicates among many at once: two texts repeat each
/// other when their keys are the same.
public func duplicateKey(_ text: String) -> String {
    comparable(text)
}

/// Whether `text`, a card's front, back or source, mentions `search`, what
/// Lucas looks for in the Cards window: it contains it once both are compared
/// as duplicates are, trimmed, ignoring case, accents, superscripts and
/// subscripts, but not the ñ, so “fertil” is in “Muy fértil”, “h2o” in “H₂O”,
/// and “ano” isn't in “año”. A blank search is in every text.
public func mentions(_ text: String, _ search: String) -> Bool {
    let search = comparable(search)
    return search.isEmpty || comparable(text).contains(search)
}

/// The text as duplicates are compared: trimmed, in lowercase, without
/// accents, but with its ñ, and with each superscript or subscript as the
/// character it raises or lowers, a minus sign as typed.
private func comparable(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .map { character in
            character == "ñ"
                ? "ñ" : String(typedForms[character] ?? character).folding(options: .diacriticInsensitive, locale: nil)
        }
        .joined()
}

/// The character as typed for each of Unicode's superscripts and subscripts
/// of a digit, a sign or a Latin or Greek letter, the ones its names call
/// so: “²” is “2”. A minus, raised, lowered or the minus sign “−”, is “-”: an
/// import raises a “-” or a “−” alike, and Unicode's own normalization makes
/// a raised one “−”.
private let typedForms = Dictionary(
    uniqueKeysWithValues: zip(
        "¹²³⁰ⁱ⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾ⁿ₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎ₐₑₒₓₔₕₖₗₘₙₚₛₜᵢᵣᵤᵥᵦᵧᵨᵩᵪⱼ−",
        "1230i456789+-=()n0123456789+-=()aeoxəhklmnpstiruvβγρφχj-"))
