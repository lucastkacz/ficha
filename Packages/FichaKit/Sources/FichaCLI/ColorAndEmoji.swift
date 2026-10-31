import ArgumentParser
import FichaData
import Foundation

// What `ficha tag color` and `emoji` share with `ficha deck color` and
// `emoji`: the color or the emoji each reads from its argument, as the Cards
// window's Color menu and Emoji… sheet give a tag or a deck one.

/// What a `ficha` command gives a color or an emoji to.
enum TagOrDeck {
    case tag
    case deck

    /// How a message names one, whichever it is.
    fileprivate var named: String {
        switch self {
        case .tag: "a tag"
        case .deck: "a deck"
        }
    }
}

/// The color `text` gives, by its name, or nil for none, written "none"; or
/// an error naming the colors a tag or a deck, as `what` says, can have.
func chosenColor(_ text: String, for what: TagOrDeck) throws -> TagColor? {
    if text == "none" {
        return nil
    }
    guard let chosen = TagColor(rawValue: text) else {
        throw ValidationError(
            """
            “\(text)” isn't a color \(what.named) can have. Pick one of \
            \(TagColor.allCases.map(\.rawValue).joined(separator: ", ")), or none.
            """)
    }
    return chosen
}

/// The emoji `text` gives, or nil for none, written "none" or left empty; or
/// an error when it isn't one emoji.
func chosenEmoji(_ text: String) throws -> Emoji? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return text == "none" || text.isEmpty ? nil : try Emoji(text)
}
