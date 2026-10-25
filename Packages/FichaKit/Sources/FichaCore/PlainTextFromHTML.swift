import Foundation

/// `html`, a field of a file that says it holds HTML, such as Anki's, as the
/// plain text a card holds: without its tags, with a line break for each
/// `<br>` and around each block, such as a `<div>` or a `<p>`, and with its
/// character references decoded, a no-break space as a space. Spaces and
/// line breaks in the HTML itself are one space, as a browser shows them,
/// and none at the start or the end of a line. A ruby's text, the reading a
/// browser shows small over the text before it, comes after that text in
/// parentheses, `話（はなし）`, and the parentheses a browser without ruby
/// shows, its `<rp>`s, are left out. A superscript, `<sup>`, or a subscript,
/// `<sub>`, comes in as Unicode's own superscripts or subscripts, `SO₄²⁻`,
/// when Unicode has each of its characters as one, and as its text
/// otherwise. A comment, a `<script>` and a `<style>` are left out whole.
/// What only looks like a tag or a reference, such as a `<` before a space
/// or an `&` before no known name, stays as it is.
public func plainText(fromHTML html: String) -> String {
    var reader = HTMLReader(Array(html.unicodeScalars))
    reader.convert()
    return String(String.UnicodeScalarView(reader.text))
}

/// `html` without its comments, `<script>`s and `<style>`s, which
/// `plainText(fromHTML:)` leaves out whole, each ended where it ends them,
/// and with the rest as it is.
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

/// The elements of a ruby: the text it's over, `<rb>`, its text, `<rt>` and
/// `<rtc>`, and its parentheses, `<rp>`.
private let rubyElements: Set<String> = ["ruby", "rb", "rt", "rtc", "rp"]

/// A superscript, `<sup>`, or a subscript, `<sub>`.
private enum SuperOrSubscript: String {
    case sup, sub

    /// Unicode's superscript, or subscript, for each character that has
    /// one: the digits, `+ - − = ( )`, and a few letters. They're the ones
    /// in Unicode's Superscripts and Subscripts block, and Latin-1's ¹²³,
    /// all of which the system font draws.
    var unicodeForms: [Unicode.Scalar: Unicode.Scalar] {
        switch self {
        case .sup: superscripts
        case .sub: subscripts
        }
    }
}

private let superscripts = Dictionary(
    uniqueKeysWithValues: zip("0123456789+-−=()in".unicodeScalars, "⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁻⁼⁽⁾ⁱⁿ".unicodeScalars))

private let subscripts = Dictionary(
    uniqueKeysWithValues: zip(
        "0123456789+-−=()aeoxəhklmnpst".unicodeScalars, "₀₁₂₃₄₅₆₇₈₉₊₋₋₌₍₎ₐₑₒₓₔₕₖₗₘₙₚₛₜ".unicodeScalars))

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
    private(set) var text: [Unicode.Scalar] = []
    /// Whether spaces or line breaks in the HTML came after the text so far,
    /// which are a space before the next text on the line.
    private var isSpacePending = false
    /// The part of a ruby being read, if any.
    private var rubyPart: RubyPart?
    /// The superscripts and subscripts being read, the innermost last, each
    /// with where its text starts in `text`.
    private var openSuperOrSubscripts: [(element: SuperOrSubscript, start: Int)] = []

    /// A part of a ruby that the plain text shows apart from the text it's
    /// over: its text, the reading, or a parenthesis for a browser without
    /// ruby.
    private enum RubyPart: Equatable {
        /// Its text, `<rt>`, after its `（`, at its start before anything
        /// shows in it.
        case text(isAtStart: Bool)
        /// A parenthesis, `<rp>`, which shows nothing.
        case parenthesis
    }

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
        endRubyPart()
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
    /// line and not at the start of a ruby's text. A no-break space is a
    /// space. In a ruby's parenthesis it shows nothing.
    private mutating func append(_ scalar: Unicode.Scalar) {
        guard rubyPart != .parenthesis else {
            return
        }
        if isSpacePending, let last = text.last, last != "\n", rubyPart != .text(isAtStart: true) {
            text.append(" ")
        }
        isSpacePending = false
        text.append(scalar == "\u{A0}" ? " " : scalar)
        if rubyPart == .text(isAtStart: true) {
            rubyPart = .text(isAtStart: false)
        }
    }

    /// Ends the line, without the spaces at its end, which no superscript or
    /// subscript being read starts after any more.
    private mutating func breakLine() {
        while text.last == " " {
            text.removeLast()
        }
        openSuperOrSubscripts = openSuperOrSubscripts.map { ($0.element, min($0.start, text.count)) }
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
    /// line break for `<br>` and around a block, a ruby's tag, a
    /// superscript's or a subscript's, and nothing else. A `<script>` or a
    /// `<style>` is skipped up to its end. Returns where what it read ends.
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
        } else if rubyElements.contains(name) {
            readRubyTag(named: name, isClosing: isAtClosingTag)
        } else if let element = SuperOrSubscript(rawValue: name) {
            readSuperOrSubscriptTag(of: element, isClosing: isAtClosingTag)
        }
        return end
    }

    /// Reads a superscript's or a subscript's tag, `element`'s: its text
    /// starts after the text so far, and once it ends it turns into
    /// Unicode's forms of its characters when Unicode has each of them. Its
    /// closing tag ends the innermost `element` being read; one without an
    /// opening tag does nothing, and one without a closing tag leaves its
    /// text as it is.
    private mutating func readSuperOrSubscriptTag(of element: SuperOrSubscript, isClosing: Bool) {
        guard isClosing else {
            openSuperOrSubscripts.append((element, text.count))
            return
        }
        guard let open = openSuperOrSubscripts.lastIndex(where: { $0.element == element }) else {
            return
        }
        // Spaces and line breaks at its start, such as the space before its
        // text, show in a browser the same at any size.
        let start = text[openSuperOrSubscripts[open].start...].firstIndex { $0 != " " && $0 != "\n" } ?? text.count
        openSuperOrSubscripts.removeSubrange(open...)
        let forms = text[start...].map { element.unicodeForms[$0] }
        guard !forms.isEmpty, forms.allSatisfy({ $0 != nil }) else {
            return
        }
        text.replaceSubrange(start..., with: forms.compactMap { $0 })
    }

    /// Reads a ruby's tag named `name`: its text, `<rt>`, starts after a
    /// `（`, and its parenthesis, `<rp>`, starts showing nothing. Each ends
    /// at the next of the ruby's tags, as HTML ends it when its closing tag
    /// is left out, and a space at its ends, or at the ruby's end, shows
    /// nothing, as in a browser.
    private mutating func readRubyTag(named name: String, isClosing: Bool) {
        endRubyPart()
        if isClosing {
            if name == "ruby" {
                isSpacePending = false
            }
        } else if name == "rt" {
            isSpacePending = false
            append("（")
            rubyPart = .text(isAtStart: true)
        } else if name == "rp" {
            rubyPart = .parenthesis
        }
    }

    /// Ends the part of a ruby being read, if any: its text with its `）`.
    private mutating func endRubyPart() {
        guard let part = rubyPart else {
            return
        }
        rubyPart = nil
        isSpacePending = false
        if part != .parenthesis {
            append("）")
        }
    }

    /// Whether a comment starts at `index`.
    private var isAtComment: Bool {
        html[index + 1] == "!" && starts(with: "<!--", at: index)
    }

    /// Whether the tag that starts at `index` closes an element.
    private var isAtClosingTag: Bool {
        html[index + 1] == "/"
    }

    /// Where the comment, `<script>` or `<style>` that starts at `index`, with
    /// a comment or a tag named `name` that ends at `end`, its `>`, ends: the
    /// comment's end, or the `>` of the element's closing tag, or the HTML's
    /// end when it has none. Nil when what starts there shows.
    private func endOfHiddenMarkup(upTo end: Int, named name: String) -> Int? {
        if isAtComment {
            return end
        }
        guard !isAtClosingTag, name == "script" || name == "style" else {
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
