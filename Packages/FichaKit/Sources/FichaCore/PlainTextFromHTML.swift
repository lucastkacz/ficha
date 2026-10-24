import Foundation

/// `html`, a field of a file that says it holds HTML, such as Anki's, as the
/// plain text a card holds: without its tags, with a line break for each
/// `<br>` and around each block, such as a `<div>` or a `<p>`, and with its
/// character references decoded, a no-break space as a space. Spaces and
/// line breaks in the HTML itself are one space, as a browser shows them,
/// and none at the start or the end of a line. A comment, a `<script>` and a
/// `<style>` are left out whole. What only looks like a tag or a reference,
/// such as a `<` before a space or an `&` before no known name, stays as it
/// is.
public func plainText(fromHTML html: String) -> String {
    var reader = HTMLReader(Array(html.unicodeScalars))
    reader.convert()
    return String(reader.text)
}

/// `html` without what `plainText(fromHTML:)` leaves out whole, its
/// comments, `<script>`s and `<style>`s, each ended where it ends them, and
/// with the rest as it is.
func htmlWithoutHiddenMarkup(_ html: String) -> String {
    var reader = HTMLReader(Array(html.unicodeScalars))
    return reader.withoutHiddenMarkup()
}

/// `value`, an attribute's value in HTML, such as the name of an image's
/// file, with its character references decoded, a no-break space's as a
/// space, as Anki decodes a name (`rslib/src/text.rs`, `decode_entities`).
/// What only looks like a reference stays as it is.
func characterReferencesDecoded(in value: String) -> String {
    let scalars = Array(value.unicodeScalars)
    var decoded = String.UnicodeScalarView()
    var index = 0
    while index < scalars.count {
        if scalars[index] == "&", let (scalar, end) = characterReference(in: scalars, at: index) {
            decoded.append(scalar == "\u{A0}" ? " " : scalar)
            index = end + 1
        } else {
            decoded.append(scalars[index])
            index += 1
        }
    }
    return String(decoded)
}

/// The character the reference that starts at `index` of `html`, its `&`,
/// stands for, and where it ends, its `;`, or nil when it isn't one.
private func characterReference(in html: [Unicode.Scalar], at index: Int) -> (Unicode.Scalar, Int)? {
    guard let end = html[index...].prefix(34).firstIndex(of: ";") else {
        return nil
    }
    let name = String(String.UnicodeScalarView(html[(index + 1)..<end]))
    let scalar: Unicode.Scalar?
    if name.hasPrefix("#x") || name.hasPrefix("#X") {
        scalar = UInt32(name.dropFirst(2), radix: 16).flatMap { Unicode.Scalar($0) }
    } else if name.hasPrefix("#") {
        scalar = UInt32(name.dropFirst()).flatMap { Unicode.Scalar($0) }
    } else {
        scalar = namedReferences[name]
    }
    return scalar.map { ($0, end) }
}

/// The elements that start and end a line of their own.
private let blockElements: Set<String> = [
    "address", "article", "aside", "blockquote", "dd", "div", "dl", "dt", "figcaption", "figure", "footer", "h1",
    "h2", "h3", "h4", "h5", "h6", "header", "hr", "li", "main", "nav", "ol", "p", "pre", "section", "table", "tr",
    "ul",
]

/// The character references a field may hold by name: HTML's own, the
/// quotes and dashes a word processor types, and the Latin-1 letters and
/// signs.
private let namedReferences: [String: Unicode.Scalar] = {
    var references: [String: Unicode.Scalar] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "ndash": "\u{2013}", "mdash": "\u{2014}",
        "lsquo": "\u{2018}", "rsquo": "\u{2019}", "sbquo": "\u{201A}", "ldquo": "\u{201C}", "rdquo": "\u{201D}",
        "bdquo": "\u{201E}", "hellip": "\u{2026}", "bull": "\u{2022}", "euro": "\u{20AC}", "trade": "\u{2122}",
    ]
    // Latin-1's, from U+00A0 to U+00FF, in order.
    let latin1 = """
        nbsp iexcl cent pound curren yen brvbar sect uml copy ordf laquo not shy reg macr deg plusmn sup2 sup3 \
        acute micro para middot cedil sup1 ordm raquo frac14 frac12 frac34 iquest Agrave Aacute Acirc Atilde Auml \
        Aring AElig Ccedil Egrave Eacute Ecirc Euml Igrave Iacute Icirc Iuml ETH Ntilde Ograve Oacute Ocirc Otilde \
        Ouml times Oslash Ugrave Uacute Ucirc Uuml Yacute THORN szlig agrave aacute acirc atilde auml aring aelig \
        ccedil egrave eacute ecirc euml igrave iacute icirc iuml eth ntilde ograve oacute ocirc otilde ouml divide \
        oslash ugrave uacute ucirc uuml yacute thorn yuml
        """
    for (offset, name) in latin1.split(separator: " ").enumerated() {
        if let scalar = Unicode.Scalar(0xA0 + offset) {
            references[String(name)] = scalar
        }
    }
    return references
}()

/// HTML being read from its start, into plain text or without its hidden
/// markup.
private struct HTMLReader {
    private let html: [Unicode.Scalar]
    private var index = 0
    /// The plain text so far.
    private(set) var text = String.UnicodeScalarView()
    /// Whether spaces or line breaks in the HTML came after the text so far,
    /// which are a space before the next text on the line.
    private var isSpacePending = false

    init(_ html: [Unicode.Scalar]) {
        self.html = html
    }

    mutating func convert() {
        while index < html.count {
            let scalar = html[index]
            if scalar == "<", let end = endOfMarkup() {
                index = readMarkup(upTo: end) + 1
            } else if scalar == "&", let (decoded, end) = reference() {
                append(decoded)
                index = end + 1
            } else if scalar.properties.isWhitespace && scalar != "\u{A0}" {
                isSpacePending = true
                index += 1
            } else {
                append(scalar)
                index += 1
            }
        }
    }

    /// The HTML without the comments, `<script>`s and `<style>`s that
    /// `convert()` leaves out whole, and with the rest as it is.
    mutating func withoutHiddenMarkup() -> String {
        var kept = String.UnicodeScalarView()
        while index < html.count {
            if html[index] == "<", let end = endOfMarkup(),
                let hiddenEnd = endOfHiddenMarkup(upTo: end, named: tagName(upTo: end))
            {
                index = hiddenEnd + 1
            } else {
                kept.append(html[index])
                index += 1
            }
        }
        return String(kept)
    }

    /// Adds `scalar` to the text, after the space pending, if any, within a
    /// line. A no-break space is a space.
    private mutating func append(_ scalar: Unicode.Scalar) {
        if isSpacePending, let last = text.last, last != "\n" {
            text.append(" ")
        }
        isSpacePending = false
        text.append(scalar == "\u{A0}" ? " " : scalar)
    }

    /// Ends the line, without the spaces at its end.
    private mutating func breakLine() {
        while text.last == " " {
            text.removeLast()
        }
        text.append("\n")
        isSpacePending = false
    }

    /// Where the tag or the comment that starts at `index` ends, its `>`, or
    /// nil when no tag or comment starts there.
    private func endOfMarkup() -> Int? {
        guard index + 1 < html.count else {
            return nil
        }
        if isAtComment {
            return firstIndex(of: "-->", from: index + 4).map { $0 + 2 } ?? html.count - 1
        }
        let next = html[index + 1]
        guard next == "/" || next == "!" || next.properties.isAlphabetic else {
            return nil
        }
        return html[(index + 1)...].firstIndex(of: ">")
    }

    /// Reads the tag or the comment between `index` and `end`, its `>`: a
    /// line break for `<br>` and around a block, and nothing else. A
    /// `<script>` or a `<style>` is skipped up to its end. Returns where what
    /// it read ends.
    private mutating func readMarkup(upTo end: Int) -> Int {
        let name = tagName(upTo: end)
        if let hiddenEnd = endOfHiddenMarkup(upTo: end, named: name) {
            return hiddenEnd
        }
        if name == "br" {
            breakLine()
        } else if blockElements.contains(name) {
            if let last = text.last, last != "\n" {
                breakLine()
            }
        }
        return end
    }

    /// Whether a comment starts at `index`.
    private var isAtComment: Bool {
        html[index + 1] == "!" && starts(with: "<!--", at: index)
    }

    /// Where the comment, `<script>` or `<style>` that starts at `index`, with
    /// a comment or a tag named `name` that ends at `end`, its `>`, ends: the
    /// comment's end, or the `>` of the element's closing tag, or the HTML's
    /// end when it has none. Nil when what starts there shows.
    private func endOfHiddenMarkup(upTo end: Int, named name: String) -> Int? {
        if isAtComment {
            return end
        }
        guard html[index + 1] != "/", name == "script" || name == "style" else {
            return nil
        }
        let closing = firstIndex(of: "</\(name)", from: end + 1, ignoringCase: true)
        return closing.flatMap { html[$0...].firstIndex(of: ">") } ?? html.count - 1
    }

    /// The name, in lowercase, of the tag between `index` and `end`, its
    /// `>`, whether it opens an element or closes one.
    private func tagName(upTo end: Int) -> String {
        var nameStart = index + 1
        if html[nameStart] == "/" {
            nameStart += 1
        }
        var nameEnd = nameStart
        while nameEnd < end, html[nameEnd].properties.isAlphabetic || ("0"..."9").contains(html[nameEnd]) {
            nameEnd += 1
        }
        return String(String.UnicodeScalarView(html[nameStart..<nameEnd])).lowercased()
    }

    /// The character the reference that starts at `index`, its `&`, stands
    /// for, and where it ends, its `;`, or nil when it isn't one.
    private func reference() -> (Unicode.Scalar, Int)? {
        characterReference(in: html, at: index)
    }

    /// Whether the HTML has `prefix` at `position`.
    private func starts(with prefix: String, at position: Int) -> Bool {
        firstIndex(of: prefix, from: position) == position
    }

    /// Where `target` is first found from `position` on, or nil when it
    /// isn't, ignoring the case of its letters when `ignoringCase`.
    private func firstIndex(of target: String, from position: Int, ignoringCase: Bool = false) -> Int? {
        let target = Array((ignoringCase ? target.lowercased() : target).unicodeScalars)
        guard !target.isEmpty, position + target.count <= html.count else {
            return nil
        }
        for start in position...(html.count - target.count) {
            let matches = target.indices.allSatisfy { offset in
                let scalar = html[start + offset]
                let compared =
                    ignoringCase ? (scalar.properties.lowercaseMapping.unicodeScalars.first ?? scalar) : scalar
                return compared == target[offset]
            }
            if matches {
                return start
            }
        }
        return nil
    }
}
