import AppKit
import FichaData
import SwiftUI

// How Finder's tag colors, which a deck takes, look in the app: as the
// system's colors, by Finder's names, and as a dot in a menu. `TagColor` is
// named for the tags, which had them first and keep them in the database.

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
        case .red: String(localized: "Red", comment: "One of Finder's tag colors, which a deck can have.")
        case .orange: String(localized: "Orange", comment: "One of Finder's tag colors, which a deck can have.")
        case .yellow: String(localized: "Yellow", comment: "One of Finder's tag colors, which a deck can have.")
        case .green: String(localized: "Green", comment: "One of Finder's tag colors, which a deck can have.")
        case .blue: String(localized: "Blue", comment: "One of Finder's tag colors, which a deck can have.")
        case .purple: String(localized: "Purple", comment: "One of Finder's tag colors, which a deck can have.")
        case .gray: String(localized: "Gray", comment: "One of Finder's tag colors, which a deck can have.")
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

/// An item's label in the Color submenu of a deck's menu: the color's name,
/// as Finder names it, after its swatch, or None.
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
            // A key of its own, since the Prioritize submenu and the emoji
            // field say "None" too, of a deck and an emoji, which a language
            // may word apart from a color, as Portuguese's "Nenhuma".
            Text(
                String(
                    localized: "color.none", defaultValue: "None",
                    comment: "The first item of the Color submenu of a deck's menu: no color.")
            )
        }
    }
}
