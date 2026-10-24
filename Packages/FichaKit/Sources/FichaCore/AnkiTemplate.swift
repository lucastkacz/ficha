import Foundation

/// A card template of Anki's, parsed as Anki parses one
/// (`rslib/src/template.rs`): text, field replacements with their filters,
/// like `{{Front}}` or `{{text:hint:Notes}}`, and sections, `{{#Field}}…{{/Field}}`
/// and `{{^Field}}…{{/Field}}`, which show what they hold when the field is
/// filled, or when it's empty. Comments, `<!--…-->`, are text, whatever
/// they hold. A template that starts with `{{=<% %>=}}` writes `<%` and `%>`
/// in place of the braces.
struct AnkiTemplate {
    /// A part of a template.
    indirect enum Node {
        case text(Substring)
        /// A field's value, or a special field's, through `filters`, in the
        /// order they apply: `{{text:hint:Notes}}` applies `hint`, then
        /// `text`, to the field Notes.
        case replacement(field: String, filters: [String])
        /// What `nodes` show when the field `key` is filled, or when it's
        /// empty if `isNegated`.
        case section(key: String, isNegated: Bool, nodes: [Node])
    }

    let nodes: [Node]

    /// The template `text`, or an error when Anki couldn't parse it either.
    init(parsing text: String) throws(AnkiTemplateError) {
        var tokens = try Self.tokens(of: text)[...]
        nodes = try Self.nodes(from: &tokens, inSection: nil)
    }

    /// The template, as Anki renders it for a card whose fields, its note's
    /// and the special ones, are `fields`: on the question side when
    /// `frontSide` is nil, and on the answer side with `frontSide`, the
    /// question as rendered, for `{{FrontSide}}`. `cardNumber` is the card's
    /// template index plus one, which is its cloze number for a cloze card.
    /// A field that isn't there is an error, as in Anki, also in a section
    /// that shows nothing.
    func render(fields: [String: String], cardNumber: Int, frontSide: String?) throws(AnkiTemplateError) -> String {
        var renderer = Renderer(fields: fields, cardNumber: cardNumber, frontSide: frontSide)
        try renderer.render(nodes)
        return renderer.output
    }

    /// A token of a template, as Anki's tokenizer reads them.
    private enum Token {
        case text(Substring)
        case replacement(Substring)
        case openSection(Substring)
        case openNegatedSection(Substring)
        case closeSection(Substring)
    }

    /// The tokens of `template`, in order, or an error when a `{{` is never
    /// closed.
    private static func tokens(of template: String) throws(AnkiTemplateError) -> [Token] {
        var rest = template[...]
        var (open, close) = ("{{", "}}")
        let alternativeDirective = "{{=<% %>=}}"
        if template.drop(while: \.isWhitespace).hasPrefix(alternativeDirective) {
            rest = template.drop(while: \.isWhitespace).dropFirst(alternativeDirective.count)
            (open, close) = ("<%", "%>")
        }
        var tokens: [Token] = []
        while !rest.isEmpty {
            if rest.hasPrefix("<!--") {
                let end = rest.firstRange(of: "-->")?.upperBound ?? rest.endIndex
                tokens.append(.text(rest[..<end]))
                rest = rest[end...]
            } else if rest.hasPrefix(open) {
                guard let end = rest.firstRange(of: close) else {
                    throw .unclosedHandlebars
                }
                tokens.append(token(inside: rest[rest.index(rest.startIndex, offsetBy: open.count)..<end.lowerBound]))
                rest = rest[end.upperBound...]
            } else {
                let end =
                    [rest.firstRange(of: open)?.lowerBound, rest.firstRange(of: "<!--")?.lowerBound]
                    .compactMap(\.self).min() ?? rest.endIndex
                tokens.append(.text(rest[..<end]))
                rest = rest[end...]
            }
        }
        return tokens
    }

    /// The token that `content`, what a pair of handlebars holds, makes:
    /// trimmed, a section's start or end by its first character, and a
    /// replacement otherwise.
    private static func token(inside content: Substring) -> Token {
        let trimmed = content.drop { $0 == "{" }.trimmingCharacters(in: .whitespacesAndNewlines)[...]
        guard trimmed.count >= 2, let first = trimmed.first else {
            return .replacement(trimmed)
        }
        let rest = trimmed.dropFirst().drop(while: \.isWhitespace)
        return switch first {
        case "#": .openSection(rest)
        case "^": .openNegatedSection(rest)
        case "/": .closeSection(rest)
        default: .replacement(trimmed)
        }
    }

    /// The nodes that `tokens` make, up to the end of the section `section`
    /// when it's open, which they drop as they go.
    private static func nodes(from tokens: inout ArraySlice<Token>, inSection section: Substring?)
        throws(AnkiTemplateError) -> [Node]
    {
        var nodes: [Node] = []
        while let token = tokens.popFirst() {
            switch token {
            case .text(let text):
                nodes.append(.text(text))
            case .replacement(let content):
                let parts = content.split(separator: ":", omittingEmptySubsequences: false).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                nodes.append(.replacement(field: parts.last ?? "", filters: parts.dropLast().reversed()))
            case .openSection(let key):
                nodes.append(
                    .section(key: String(key), isNegated: false, nodes: try Self.nodes(from: &tokens, inSection: key)))
            case .openNegatedSection(let key):
                nodes.append(
                    .section(key: String(key), isNegated: true, nodes: try Self.nodes(from: &tokens, inSection: key)))
            case .closeSection(let key):
                guard key == section else {
                    throw .sectionNotOpen(String(key))
                }
                return nodes
            }
        }
        if let section {
            throw .sectionNotClosed(String(section))
        }
        return nodes
    }
}

/// Why Anki can't render a card's template, and shows an error in its place.
enum AnkiTemplateError: Error, Equatable {
    /// A `{{` is never closed by `}}`.
    case unclosedHandlebars
    /// A section, `{{#Field}}` or `{{^Field}}`, is never closed.
    case sectionNotClosed(String)
    /// A section is closed, `{{/Field}}`, where it isn't open.
    case sectionNotOpen(String)
    /// The template names this field, which the note type doesn't have.
    case unknownField(String)
}

/// A template being rendered for a card.
private struct Renderer {
    let fields: [String: String]
    let cardNumber: Int
    /// The question, rendered, on the answer side; nil on the question side.
    let frontSide: String?
    /// What's rendered so far.
    var output = ""

    /// Renders `nodes`, after what's rendered so far.
    mutating func render(_ nodes: [AnkiTemplate.Node]) throws(AnkiTemplateError) {
        for node in nodes {
            switch node {
            case .text(let text):
                output += text
            case .replacement(field: "FrontSide", filters: _):
                output += frontSide ?? ""
            case .replacement(let field, let filters):
                // An empty field's name with a filter hands the filter
                // nothing, for it to add its own text.
                let value = field.isEmpty && !filters.isEmpty ? "" : fields[field]
                guard let value else {
                    throw .unknownField(field)
                }
                output += applying(filters, to: value, of: field)
            case .section(let key, let isNegated, let nodes):
                if try isFilled(key) != isNegated {
                    try render(nodes)
                } else {
                    // A section that shows nothing is still checked for
                    // errors, as Anki checks it.
                    var hidden = Renderer(fields: fields, cardNumber: cardNumber, frontSide: frontSide)
                    try hidden.render(nodes)
                }
            }
        }
    }

    /// Whether the field `key` is filled, as a section asks: it holds more
    /// than spaces, line breaks, and `<br>` and `<div>` tags. A cloze
    /// number's key, like `c2`, is filled for that card alone.
    private func isFilled(_ key: String) throws(AnkiTemplateError) -> Bool {
        if let value = fields[key] {
            return !isEmptyField(value)
        }
        guard key.wholeMatch(of: /c\d+/) != nil else {
            throw .unknownField(key)
        }
        return false
    }

    /// `value`, the field `field`'s, through `filters`, in order, as Anki
    /// applies its own (`rslib/src/template_filters.rs`). `type:cloze:` and
    /// `type:nc:` are one filter each.
    private func applying(_ filters: [String], to value: String, of field: String) -> String {
        let filters =
            switch filters {
            case ["cloze", "type"]: ["type-cloze"]
            case ["nc", "type"]: ["type-nc"]
            default: filters
            }
        return filters.reduce(value) { text, filter in applying(filter, to: text, of: field) }
    }

    /// `text`, from the field `field`, through `filter`, as Anki renders
    /// what it gives: a box to type the answer in is the placeholder that
    /// Anki's reviewer, and `AnkiTypedAnswers.swift`, replace; a reading
    /// drawn over its kanji comes after them, `話（はなし）`; and text Anki
    /// speaks is nothing. A filter Anki doesn't have passes the text on.
    private func applying(_ filter: String, to text: String, of field: String) -> String {
        let isQuestion = frontSide == nil
        switch filter {
        case "text":
            return escapingHTML(plainText(fromHTML: text))
        case "hint":
            // Anki shows a link that reveals the text: Ficha shows the text.
            return text
        case "type":
            return typedAnswerBox(asking: field)
        case "type-nc":
            return typedAnswerBox(asking: "nc:" + field)
        case "type-cloze":
            return typedAnswerBox(asking: "cloze:" + field)
        case "cloze":
            return revealingClozes(in: text, number: cardNumber, onQuestion: isQuestion)
        case "cloze-only":
            return isQuestion ? clozeHint(of: text, number: cardNumber) : clozeText(of: text, number: cardNumber)
        case "furigana", "kanji", "kana":
            return text.replacing("&nbsp;", with: " ").replacing(/\ ?([^ >]+?)\[(.+?)\]/) { match in
                let (whole, kanji, reading) = match.output
                guard !reading.hasPrefix("sound:") else { return String(whole) }
                return switch filter {
                case "kanji": String(kanji)
                case "kana": String(reading)
                // Anki draws the reading small over the kanji: plain text
                // writes it after them, in parentheses.
                default: "\(kanji)（\(reading)）"
                }
            }
        case _ where filter == "tts" || filter.hasPrefix("tts "):
            return ""
        default:
            return text
        }
    }
}

/// Whether `field` is empty, as Anki's sections see it: it holds only
/// spaces, line breaks, and `<br>` and `<div>` tags.
private func isEmptyField(_ field: String) -> Bool {
    field.wholeMatch(of: /(?i)(?:\s|<\/?(?:br|div) ?\/?>)*/) != nil
}

/// `text`, plain text, as HTML that shows it as it is.
func escapingHTML(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}
