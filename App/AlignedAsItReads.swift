import FichaCore
import SwiftUI

/// A text the user wrote, a card's side or source, or a capture's text, note
/// or source, on as many lines as it needs, unless a line limit says
/// otherwise, and aligned at the side it starts reading from, as
/// `alignedAsItReads(_:)` says. It takes the width it's offered.
struct TextAsItReads: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
            .alignedAsItReads(text)
    }
}

extension View {
    /// Aligns the user's text, `text`, which this view shows or edits, at the
    /// side it starts reading from, whatever the app's language: a Spanish
    /// card at the left on a Mac in Arabic, and an Arabic card at the right
    /// on a Mac in English, its lines too (ADR 0027). SwiftUI already gives a
    /// text its own direction within its lines, macOS 26's content-based
    /// writing direction, but aligns a `Text` at the layout's leading side,
    /// its default `Text.AlignmentStrategy`, `.layoutBased`. Apple documents
    /// text fields and editors as aligned by their writing direction instead,
    /// `.writingDirectionBased`, under which `.trailing` means against it,
    /// which would flip this view's side twice; so this sets `.layoutBased`,
    /// the strategy Apple names for an alignment chosen explicitly, and picks
    /// the side from the text. The strategy alone can't do it: a `Text` wraps
    /// its content tightly, so its alignment only places its lines against
    /// one another, and the frame still needs the side, which places the text
    /// as a whole. The view takes the width it's offered. A text without a
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
            .multilineTextAlignment(strategy: .layoutBased)
            .frame(maxWidth: .infinity, alignment: readsAsTheLayout ? .leading : .trailing)
    }
}
