import Foundation

// Anki's boxes to type the answer in, which its renderer leaves in a card's
// sides as `[[type:Field]]`, `[[type:cloze:Field]]` or `[[type:nc:Field]]`,
// for `{{type:Field}}` and its kin, and its reviewer replaces
// (`qt/aqt/reviewer.py`): with a box on the question side, and with the
// right answer on the answer side. Ficha shows no box, and the right answer
// as it shows when nothing was typed.

/// `question`, a card's question side as Anki renders it, without its boxes.
func questionWithoutTypedAnswers(_ question: String) -> String {
    guard question.contains("[[type:") else {
        return question
    }
    return question.replacing(/\[\[type:.+?\]\]/, with: "")
}

/// `answer`, a card's answer side as Anki renders it, with each box showing
/// the right answer: the field of the first box on `question`, its question
/// side, as plain text. When `answer` has the line that marks where the
/// answer starts, `<hr id=answer>`, the line moves to just before each box,
/// as Anki's reviewer moves it, so an answer that shows the question with
/// `{{FrontSide}}`, and its box with it, shows the right answer after the
/// line. No box shows anything when the question has none, or its field is
/// empty. `fields` are the card's fields, by their names, and `cardNumber`
/// its cloze number, for a box that asks for a cloze.
func answerShowingTypedAnswers(_ answer: String, question: String, fields: [String: String], cardNumber: Int)
    -> String
{
    let box = /\[\[type:(.+?)\]\]/
    guard answer.contains("[[type:"), answer.firstMatch(of: box) != nil else {
        return answer
    }
    guard let asked = question.contains("[[type:") ? question.firstMatch(of: box)?.output.1 : nil,
        let rightAnswer = rightAnswer(toBox: asked, fields: fields, cardNumber: cardNumber), !rightAnswer.isEmpty
    else {
        return answer.replacing(box, with: "")
    }
    let line = "<hr id=answer>"
    let shown = escapingHTML(plainText(fromHTML: rightAnswer))
    return answer.contains(line)
        ? answer.replacing(line, with: "").replacing(box, with: line + shown) : answer.replacing(box, with: shown)
}

/// The right answer, as HTML, to the box whose placeholder names `asked`:
/// `Field`, `nc:Field`, for an answer compared without accents, or
/// `cloze:Field`, for the text of the card's cloze in it. Nil for a field
/// that isn't among `fields`.
private func rightAnswer(toBox asked: Substring, fields: [String: String], cardNumber: Int) -> String? {
    // Anki reads the field's name as what follows the first colon.
    func fieldName(after prefix: String, in name: Substring) -> Substring {
        name.hasPrefix(prefix)
            ? name.split(separator: ":", omittingEmptySubsequences: false).dropFirst().first ?? "" : name
    }
    let isCloze = asked.hasPrefix("cloze:")
    let name = fieldName(after: "nc:", in: fieldName(after: "cloze:", in: asked))
    guard let field = fields[String(name)] else {
        return nil
    }
    return isCloze ? clozeText(of: field, number: cardNumber) : field
}
