import AppKit
import FichaData
import SwiftUI

/// A tag as a small capsule, like the review panel's "New" and "Ahead"
/// badges: its emoji before its name, tinted with its color, or gray like
/// "Ahead" when it has none. The name always shows, so neither the color nor
/// the emoji is the only cue. The Cards window's Tags column draws a card's
/// tags with it, in a row, and the review panel draws them the same way after
/// its badge.
struct TagCapsule: View {
    let tag: CardTag

    var body: some View {
        Text(verbatim: tag.title)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(background, in: .capsule)
            .fixedSize()
    }

    /// The text's color: the tag's, or the secondary gray of "Ahead".
    private var tint: AnyShapeStyle {
        tag.color.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(.secondary)
    }

    /// The capsule's: the text's, faint.
    private var background: AnyShapeStyle {
        tag.color.map { AnyShapeStyle($0.color.opacity(0.15)) } ?? AnyShapeStyle(.secondary.opacity(0.15))
    }
}

extension CardTag {
    /// How the tag is named wherever it shows: its emoji, when it has one,
    /// before its name.
    var title: String {
        emoji.map { "\($0) \(name)" } ?? name
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
