import AppKit
import FichaCore
import FichaData
import SwiftUI

/// A tag as a small capsule, like the review panel's "New" and "Ahead"
/// badges: its emoji before its whole name, as in "economía › Argentina",
/// tinted with its color, or gray like "Ahead" when it has none, its own or
/// else the tags' it sits inside. The name always shows, so neither the color
/// nor the emoji is the only cue. The Cards window's Tags column draws a
/// card's tags with it, in a row, and the review panel draws them the same
/// way after its badge.
struct TagCapsule: View {
    let tag: CardTag
    @Environment(\.colorScheme) private var colorScheme

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

    /// The text's color: the tag's, or the secondary gray of "Ahead". In
    /// light mode, the tag's is a third darker, so that yellow and green
    /// read on the faint capsule; in dark mode, they read as they are.
    private var tint: AnyShapeStyle {
        tag.shownColor.map { AnyShapeStyle($0.color.mix(with: .black, by: colorScheme == .light ? 1 / 3 : 0)) }
            ?? AnyShapeStyle(.secondary)
    }

    /// The capsule's: the text's, faint.
    private var background: AnyShapeStyle {
        tag.shownColor.map { AnyShapeStyle($0.color.opacity(0.15)) } ?? AnyShapeStyle(.secondary.opacity(0.15))
    }
}

extension CardTag {
    /// How the tag is named where it stands alone, as in a capsule or a
    /// menu: its emoji, its own or else the tags' it sits inside, when it has
    /// one, before its whole name, written with " › ", as in "economía ›
    /// Argentina".
    var title: String {
        title(shown: TagPath.shown(name))
    }

    /// How the tag is named when `shown` names it, as in a tree, by its last
    /// level: its emoji, when it shows one, before `shown`.
    func title(shown: String) -> String {
        shownEmoji.map { "\($0) \(shown)" } ?? shown
    }

    /// The SF Symbol drawn before the tag's name, in the sidebar and in All
    /// Tags: the tag filled, tinted with the color it shows, its own or else
    /// the tags' it sits inside, or outlined while it shows none.
    var symbolName: String {
        shownColor == nil ? "tag" : "tag.fill"
    }

    /// Its symbol (`symbolName`), tinted with the color it shows, for
    /// SwiftUI.
    @ViewBuilder var symbol: some View {
        if let color = shownColor {
            Image(systemName: symbolName).foregroundStyle(color.color)
        } else {
            Image(systemName: symbolName)
        }
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
