import Foundation

// Anki's formulas: LaTeX in a card's side between `[$]` and `[/$]`,
// `[$$]` and `[/$$]`, or `[latex]` and `[/latex]`, which Anki draws as a
// picture, named after the formula, and a package carries in its media
// (`rslib/src/latex.rs`). Ficha's sides are plain text, so a side that is
// one formula alone shows Anki's picture of it, and a formula among text,
// one of several, or one whose picture the package lacks or Ficha can't
// read, shows as its LaTeX.

/// The name of Anki's picture of the formula `html`, a side as Anki renders
/// it, shows alone, with nothing else that shows: a PNG named after the
/// SHA-1 digest of the formula's LaTeX, as `sha1` gives it, as lowercase
/// hex. Nil when the side shows no formula, more than one, or other text.
func pictureOfFormula(shownAloneIn html: String, sha1: (String) -> String) -> String? {
    guard mayHoldFormula(html) else {
        return nil
    }
    let shown = htmlWithoutHiddenMarkup(html)
    // What `[latex]`, `[$]` or `[$$]` holds, in any case, as Anki finds it.
    let matches = shown.matches(of: /(?si)\[latex\](.+?)\[\/latex\]|\[\$\](.+?)\[\/\$\]|\[\$\$\](.+?)\[\/\$\$\]/)
    guard matches.count == 1, let match = matches.first,
        plainText(fromHTML: String(shown[..<match.range.lowerBound] + shown[match.range.upperBound...]))
            .allSatisfy(\.isWhitespace)
    else {
        return nil
    }
    let latex: String
    if let standard = match.output.1 {
        latex = String(standard)
    } else if let inline = match.output.2 {
        latex = "$\(inline)$"
    } else if let display = match.output.3 {
        latex = "\\begin{displaymath}\(display)\\end{displaymath}"
    } else {
        return nil
    }
    return "latex-\(sha1(latexWithoutHTML(latex))).png"
}

/// `latex`, a formula's LaTeX as a side shows it, without its comments,
/// `<style>`s and `<script>`s, as Anki hands it to LaTeX
/// (`strip_html_for_latex`): with a line break for each `<br>`, `<br/>` and
/// `<div>`, but not `<br />`, since Anki's pattern ignores its space,
/// without its tags, and, when it holds an `&`, with its character
/// references decoded and its no-break spaces as spaces. Anki knows every
/// reference's name, and decodes none when one is malformed, so a formula
/// with such a reference may be named apart from Anki's picture, and come in
/// as its LaTeX.
private func latexWithoutHTML(_ latex: String) -> String {
    let withoutTags = latex.replacing(/(?i)<br\/?>|<div>/, with: "\n").replacing(/(?s)<.*?>/, with: "")
    guard withoutTags.contains("&") else {
        return withoutTags
    }
    return characterReferencesDecoded(in: withoutTags).replacing("\u{A0}", with: " ")
}

/// Whether `html` may hold a formula: a `[` before a `$` or before `latex`,
/// in any case. It searches the side's UTF-8 bytes, as `holdsBox` does,
/// since almost no side holds one.
private func mayHoldFormula(_ html: String) -> Bool {
    let bytes = html.utf8
    var rest = bytes[...]
    while let start = rest.firstIndex(of: UInt8(ascii: "[")) {
        rest = bytes[bytes.index(after: start)...]
        if rest.first == UInt8(ascii: "$") || String(decoding: rest.prefix(5), as: UTF8.self).lowercased() == "latex" {
            return true
        }
    }
    return false
}
