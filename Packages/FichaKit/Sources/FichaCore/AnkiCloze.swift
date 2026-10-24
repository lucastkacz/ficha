import Foundation

// Anki's clozes, `{{c1::text}}` or `{{c1::text::hint}}`, as Anki parses and
// shows them (`rslib/src/cloze.rs`): a card for each cloze number, which
// hides its own clozes on the question side and shows the others.

/// A part of a field with clozes.
private indirect enum ClozePart {
    case text(Substring)
    /// A cloze, for the cards whose numbers are `numbers`, like `c1` or
    /// `c1,2`, with what it holds and its hint, if it has one.
    case cloze(numbers: [Int], parts: [ClozePart], hint: Substring?)
}

/// `field` as a cloze card numbered `number` shows it: on the question side,
/// each of its clozes as "[...]", or as "[hint]" with a hint, and the others
/// as their text; on the answer side, every cloze as its text. A field
/// without that card's cloze shows nothing, as in Anki.
func revealingClozes(in field: String, number: Int, onQuestion: Bool) -> String {
    let parts = clozeParts(of: field)
    guard parts.contains(where: { holdsCloze(number, $0) }) else {
        return ""
    }
    return parts.map { revealed($0, number: number, onQuestion: onQuestion) }.joined()
}

/// The text of the clozes numbered `number` in `field`, separated by
/// commas, as Anki's `cloze-only` filter gives them.
func clozeText(of field: String, number: Int) -> String {
    clozeTexts(of: field, number: number).joined(separator: ", ")
}

/// The text of the clozes numbered `number` in `field`, as Anki gives it
/// for its box to type the answer in: once when they all say the same, and
/// otherwise separated by commas.
func typedClozeText(of field: String, number: Int) -> String {
    let texts = clozeTexts(of: field, number: number)
    return Set(texts).count == 1 ? texts[0] : texts.joined(separator: ", ")
}

/// The text of each cloze numbered `number` in `field`, in order.
private func clozeTexts(of field: String, number: Int) -> [String] {
    clozes(numbered: number, in: clozeParts(of: field)).map { cloze in
        cloze.parts.map { revealed($0, number: number, onQuestion: false) }.joined()
    }
}

/// The hints of the clozes numbered `number` in `field`, or "..." for one
/// without a hint, separated by commas.
func clozeHint(of field: String, number: Int) -> String {
    clozes(numbered: number, in: clozeParts(of: field)).map { String($0.hint ?? "...") }.joined(separator: ", ")
}

/// Whether some cloze in `field` is one Anki's Image Occlusion draws: a
/// shape over an image, as `{{c1::image-occlusion:rect:left=…}}`.
func holdsImageOcclusion(_ field: String) -> Bool {
    func isOcclusion(_ part: ClozePart) -> Bool {
        guard case .cloze(_, let parts, _) = part else {
            return false
        }
        if case .text(let text) = parts.first, text.hasPrefix("image-occlusion:") {
            return true
        }
        return parts.contains(where: isOcclusion)
    }
    return clozeParts(of: field).contains(where: isOcclusion)
}

/// `part` as the card numbered `number` shows it.
private func revealed(_ part: ClozePart, number: Int, onQuestion: Bool) -> String {
    switch part {
    case .text(let text):
        return String(text)
    case .cloze(let numbers, _, let hint) where onQuestion && numbers.contains(number):
        return "[\(hint ?? "...")]"
    case .cloze(_, let parts, _):
        return parts.map { revealed($0, number: number, onQuestion: onQuestion) }.joined()
    }
}

/// Whether `part` is, or holds, a cloze numbered `number`.
private func holdsCloze(_ number: Int, _ part: ClozePart) -> Bool {
    guard case .cloze(let numbers, let parts, _) = part else {
        return false
    }
    return numbers.contains(number) || parts.contains { holdsCloze(number, $0) }
}

/// The clozes numbered `number` in `parts`, outer ones first.
private func clozes(numbered number: Int, in parts: [ClozePart]) -> [(parts: [ClozePart], hint: Substring?)] {
    parts.flatMap { part -> [(parts: [ClozePart], hint: Substring?)] in
        guard case .cloze(let numbers, let inner, let hint) = part else {
            return []
        }
        return (numbers.contains(number) ? [(inner, hint)] : []) + clozes(numbered: number, in: inner)
    }
}

/// `field`'s parts, as Anki's parser reads them: a cloze opens with `{{c`,
/// its numbers and `::`, and the first `}}` after closes the innermost one
/// open, so clozes nest, ten deep at most. Text in a cloze after `::` is its
/// hint. A `}}` outside a cloze is text, and so is a cloze never closed.
private func clozeParts(of field: String) -> [ClozePart] {
    /// A cloze open, with what it holds so far.
    struct OpenCloze {
        let opening: Substring
        let numbers: [Int]
        var parts: [ClozePart] = []
        var hint: Substring?
    }
    var parts: [ClozePart] = []
    var open: [OpenCloze] = []
    var rest = field[...]
    /// Adds `part` to the innermost cloze open, or to the field's parts.
    func add(_ part: ClozePart) {
        if open.isEmpty {
            parts.append(part)
        } else {
            open[open.count - 1].parts.append(part)
        }
    }
    while !rest.isEmpty {
        if let opening = rest.prefixMatch(of: /\{\{c(\d+(?:,\d+)*)::/) {
            if open.count < 10 {
                let numbers = opening.output.1.split(separator: ",").compactMap { Int($0) }
                open.append(OpenCloze(opening: opening.output.0, numbers: numbers))
            }
            rest = rest[opening.range.upperBound...]
        } else if rest.hasPrefix("}}") {
            if let cloze = open.popLast() {
                add(.cloze(numbers: cloze.numbers, parts: cloze.parts, hint: cloze.hint))
            } else {
                add(.text(rest.prefix(2)))
            }
            rest = rest.dropFirst(2)
        } else {
            let end =
                rest.indices.dropFirst().first { index in
                    switch rest[index] {
                    case "}": rest[index...].hasPrefix("}}")
                    case "{": rest[index...].prefixMatch(of: /\{\{c\d+(?:,\d+)*::/) != nil
                    default: false
                    }
                } ?? rest.endIndex
            var text = rest[..<end]
            if !open.isEmpty, let separator = text.firstRange(of: "::") {
                open[open.count - 1].hint = text[separator.upperBound...]
                text = text[..<separator.lowerBound]
            }
            add(.text(text))
            rest = rest[end...]
        }
    }
    // A cloze never closed is its opening and what it holds, as text.
    while let cloze = open.popLast() {
        add(.text(cloze.opening))
        for part in cloze.parts {
            add(part)
        }
    }
    return parts
}
