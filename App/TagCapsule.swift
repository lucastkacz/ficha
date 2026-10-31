import AppKit
import FichaData
import SwiftUI

/// A tag as a small capsule, like the review panel's "New" and "Ahead"
/// badges: its emoji before its whole name, as in "economía › Argentina",
/// tinted with its color, or gray like "Ahead" when it has none, its own or
/// else the tags' it sits inside. The name always shows, so neither the color
/// nor the emoji is the only cue. The Cards window's Tags column draws a
/// card's tags with it, in a row, and the review panel draws them the same
/// way after its badge and the card's deck (`DeckCapsule`).
struct TagCapsule: View {
    let tag: CardTag

    var body: some View {
        Text(verbatim: tag.title)
            .capsuleLook(tintedWith: tag.shownColor)
            .fixedSize()
    }
}

/// A card's deck as a capsule, drawn as a tag's (`TagCapsule`): its emoji
/// before its whole name, as in "🏛 Historia › Roma", or Default's in the
/// Mac's language, tinted with its color, its own or else the decks' it sits
/// inside. The review panel draws it first on a card's line, before its tags.
/// A long name gives way in its middle when the line has no room for it,
/// which its tooltip names whole.
struct DeckCapsule: View {
    let deck: Deck

    var body: some View {
        Text(verbatim: deck.title)
            .truncationMode(.middle)
            .capsuleLook(tintedWith: deck.shownColor)
            .help(Text(verbatim: deck.title))
    }
}

/// How a tag or a deck looks as a capsule, in its color or gray.
private struct CapsuleLook: ViewModifier {
    let color: TagColor?
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(background, in: .capsule)
    }

    /// The text's color: the tag's or the deck's, or the secondary gray of
    /// "Ahead". In light mode, the color is a third darker, so that yellow
    /// and green read on the faint capsule; in dark mode, they read as they
    /// are.
    private var tint: AnyShapeStyle {
        color.map { AnyShapeStyle($0.color.mix(with: .black, by: colorScheme == .light ? 1 / 3 : 0)) }
            ?? AnyShapeStyle(.secondary)
    }

    /// The capsule's: the text's, faint.
    private var background: AnyShapeStyle {
        color.map { AnyShapeStyle($0.color.opacity(0.15)) } ?? AnyShapeStyle(.secondary.opacity(0.15))
    }
}

extension View {
    /// The view as a tag's or a deck's capsule, tinted with `color`, or gray
    /// when it's nil.
    func capsuleLook(tintedWith color: TagColor?) -> some View {
        modifier(CapsuleLook(color: color))
    }
}

extension TagColor {
    /// The system's color of the same name, which works in light and dark
    /// mode, as Finder's tag colors do.
    var nsColor: NSColor {
        switch self {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .gray: .systemGray
        }
    }

    /// The same color, for SwiftUI.
    var color: Color {
        Color(nsColor: nsColor)
    }

    /// Its name, as Finder names its tag colors.
    var name: String {
        switch self {
        case .red: String(localized: "Red", comment: "One of Finder's tag colors, which a tag can have.")
        case .orange: String(localized: "Orange", comment: "One of Finder's tag colors, which a tag can have.")
        case .yellow: String(localized: "Yellow", comment: "One of Finder's tag colors, which a tag can have.")
        case .green: String(localized: "Green", comment: "One of Finder's tag colors, which a tag can have.")
        case .blue: String(localized: "Blue", comment: "One of Finder's tag colors, which a tag can have.")
        case .purple: String(localized: "Purple", comment: "One of Finder's tag colors, which a tag can have.")
        case .gray: String(localized: "Gray", comment: "One of Finder's tag colors, which a tag can have.")
        }
    }

    /// A dot of the color, for a menu item, which draws it in the color
    /// rather than as a template, in the menu's light or dark appearance.
    var swatch: Image {
        let color = nsColor
        // AppKit draws it when the menu shows, on whichever thread it draws.
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { @Sendable rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return Image(nsImage: image)
    }
}

/// An item's label in the Color submenu of a tag's menu or a deck's: the
/// color's name, as Finder names it, after its swatch, or None.
struct ColorItemLabel: View {
    /// The color the item gives, or nil for None, which takes it away.
    let color: TagColor?

    var body: some View {
        if let color {
            Label {
                Text(verbatim: color.name)
            } icon: {
                color.swatch
            }
        } else {
            Text("None", comment: "The first item of the Color submenu of a tag's menu or a deck's: no color.")
        }
    }
}
