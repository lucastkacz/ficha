import FichaCore
import SwiftUI

extension View {
    /// Aligns a card's text, `text`, which this view shows or edits, at the
    /// side it starts reading from, whatever the app's language: a Spanish
    /// card at the left on a Mac in Arabic, and an Arabic card at the right
    /// on a Mac in English, its lines too (ADR 0027). SwiftUI already gives a
    /// text its own direction within its lines, macOS 26's content-based
    /// writing direction, but aligns it, a text field's too, at the layout's
    /// leading side. The view takes the width it's offered. A text without a
    /// letter, an empty field's among them, keeps the layout's alignment.
    func alignedAsItReads(_ text: String) -> some View {
        modifier(AlignedAsItReads(text: text))
    }
}

extension LayoutDirection {
    /// Whether `text` starts reading from this layout's leading side, as
    /// `ReadingDirection` finds from its first letter: a Spanish card does in
    /// English and not in Arabic. A text without a letter does.
    func readsFromLeadingSide(_ text: String) -> Bool {
        switch ReadingDirection(of: text) {
        case nil: true
        case .leftToRight: self == .leftToRight
        case .rightToLeft: self == .rightToLeft
        }
    }
}

private struct AlignedAsItReads: ViewModifier {
    let text: String
    @Environment(\.layoutDirection) private var layoutDirection

    func body(content: Content) -> some View {
        let readsAsTheLayout = layoutDirection.readsFromLeadingSide(text)
        content
            .multilineTextAlignment(readsAsTheLayout ? .leading : .trailing)
            .frame(maxWidth: .infinity, alignment: readsAsTheLayout ? .leading : .trailing)
    }
}
