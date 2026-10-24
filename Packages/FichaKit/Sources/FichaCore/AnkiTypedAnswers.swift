import Foundation

// Anki's boxes to type the answer in, which its renderer leaves in a card's
// sides as placeholders, `[[type:Field]]`, `[[type:cloze:Field]]` or
// `[[type:nc:Field]]`, for `{{type:Field}}` and its kin, and its reviewer
// replaces (`qt/aqt/reviewer.py`): with a box on the question side, and with
// the right answer on the answer side. Ficha shows no box, and the right
// answer as Anki shows it when nothing was typed.

/// How each box's placeholder starts.
private let boxStart = "[[type:"

/// The placeholder Anki's renderer leaves for a box that asks for `name`:
/// `Field`, `nc:Field` or `cloze:Field`.
func typedAnswerBox(asking name: String) -> String {
    boxStart + name + "]]"
}

/// `question`, a card's question side as Anki renders it, without its boxes.
func questionWithoutTypedAnswers(_ question: String) -> String {
    guard holdsBox(question) else {
        return question
    }
    return question.replacing(/\[\[type:.+?\]\]/, with: "")
}

/// `answer`, a card's answer side as Anki renders it, with each box showing
/// the right answer: the field of `note`, whose note type is `noteType`,
/// that the first box on `question`, its question side, asks for, as plain
/// text; for a box that asks for a cloze, the text of the cloze numbered
/// `cardNumber` in it. When `answer` has the line that marks where the
/// answer starts, the line moves to just before each box, as Anki's
/// reviewer moves it, so an answer that shows the question with
/// `{{FrontSide}}`, and its box with it, shows the right answer after the
/// line. No box shows anything when the question has none, or its field is
/// empty or isn't one of the note's.
func answerShowingTypedAnswers(
    _ answer: String, question: String, note: AnkiNote, noteType: AnkiNoteType, cardNumber: Int
) -> String {
    guard holdsBox(answer) else {
        return answer
    }
    let box = /\[\[type:(.+?)\]\]/
    guard answer.firstMatch(of: box) != nil else {
        return answer
    }
    guard holdsBox(question), let boxName = question.firstMatch(of: box)?.output.1,
        let expected = rightAnswer(toBoxAsking: boxName, note: note, noteType: noteType, cardNumber: cardNumber),
        !expected.isEmpty
    else {
        return answer.replacing(box, with: "")
    }
    // The reviewer moves the line spelled this way alone, while Ficha's back
    // starts at the line in any spelling.
    let answerLine = "<hr id=answer>"
    let shown = escapingHTML(plainText(fromHTML: expected))
    return answer.contains(answerLine)
        ? answer.replacing(answerLine, with: "").replacing(box, with: answerLine + shown)
        : answer.replacing(box, with: shown)
}

/// The right answer, as HTML, to the box that asks for `boxName`: `Field`,
/// `nc:Field`, for an answer compared without accents, or `cloze:Field`,
/// for the text of the card's cloze in it. Nil when `noteType` has no such
/// field, as for Anki's special fields, like Tags.
private func rightAnswer(toBoxAsking boxName: Substring, note: AnkiNote, noteType: AnkiNoteType, cardNumber: Int)
    -> String?
{
    // After a prefix, Anki reads the field's name between the first colon
    // and the second.
    func fieldName(after prefix: String, in name: Substring) -> Substring {
        name.hasPrefix(prefix)
            ? name.split(separator: ":", omittingEmptySubsequences: false).dropFirst().first ?? "" : name
    }
    let isCloze = boxName.hasPrefix("cloze:")
    let name = fieldName(after: "nc:", in: fieldName(after: "cloze:", in: boxName))
    guard let index = noteType.fields.firstIndex(of: String(name)) else {
        return nil
    }
    let field = note.field(at: index)
    return isCloze ? typedClozeText(of: field, number: cardNumber) : field
}

/// Whether `side` holds a box. It searches the side's UTF-8 bytes, which on
/// a long side costs a tenth of what `String.contains` does: a deck can have
/// tens of thousands of cards, and almost none has a box.
private func holdsBox(_ side: String) -> Bool {
    let bytes = side.utf8
    var rest = bytes[...]
    while let start = rest.firstIndex(of: UInt8(ascii: "[")) {
        if bytes[start...].starts(with: boxStart.utf8) {
            return true
        }
        rest = bytes[bytes.index(after: start)...]
    }
    return false
}
