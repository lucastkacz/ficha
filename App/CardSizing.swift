import AppKit
import FichaCore
import SwiftUI

extension EnvironmentValues {
    /// The size a card's text and images show at, which the review panel's
    /// window and the Cards window's detail set as the user chose it, and 100%
    /// everywhere else, as in the editor and the card form.
    @Entry var cardSize = CardSize.normal
}

/// The styles of the user's text on a card.
enum CardTextStyle {
    /// A card's upper side, or a capture's text: its largest.
    case title
    /// A card's lower side, or a capture's note and source.
    case body
    /// A card's source in the Cards window.
    case callout
    /// A card's source in the review panel.
    case caption

    /// The font at 100%. The body has none: a text with `.body` takes taller
    /// lines than one without a font in Arabic.
    fileprivate var normalFont: Font? {
        switch self {
        case .title: .title2.weight(.semibold)
        case .body: nil
        case .callout: .callout
        case .caption: .caption
        }
    }

    /// The font at `size`, scaled from the size AppKit gives the style.
    fileprivate func font(at size: CardSize) -> Font {
        let style: NSFont.TextStyle =
            switch self {
            case .title: .title2
            case .body: .body
            case .callout: .callout
            case .caption: .caption1
            }
        return .system(
            size: size.scaled(NSFont.preferredFont(forTextStyle: style).pointSize),
            weight: self == .title ? .semibold : .regular)
    }
}

extension View {
    /// Draws the user's text on a card in `style` at the card size: at 100% as
    /// the style's own font, whose lines a font of its size doesn't quite match,
    /// and at any other size as a font scaled from it, never as a scaled bitmap,
    /// so it stays sharp.
    func cardFont(_ style: CardTextStyle) -> some View {
        modifier(CardFont(style: style))
    }
}

private struct CardFont: ViewModifier {
    let style: CardTextStyle
    @Environment(\.cardSize) private var cardSize

    func body(content: Content) -> some View {
        content.font(cardSize == .normal ? style.normalFont : style.font(at: cardSize))
    }
}

/// The keys that change the card size, ⌘+, ⌘=, ⌘− and ⌘0, as hidden buttons in
/// a window's background, as ⌘F is in the Cards window. Each changes `model`'s
/// size, which every window shows at once, and at a limit nothing happens. The
/// window's `performKeyEquivalent(with:)` passes them what a press stands for
/// (`asCardSizeShortcut`), so they turn off SwiftUI's own remapping, which moves
/// a shortcut to another key on some layouts.
struct CardSizeKeys: View {
    let model: AppModel
    /// What else a press does in this window, at a limit too.
    var pressed: () -> Void = {}

    var body: some View {
        ForEach(CardSizeKey.allCases, id: \.self) { key in
            Button {
                model.cardSize = key.applied(to: model.cardSize)
                pressed()
            } label: {
                title(of: key)
            }
            .keyboardShortcut(KeyEquivalent(key.rawValue), modifiers: .command, localization: .custom)
            .hidden()
        }
    }

    /// What `key`'s button is called, though it never shows.
    private func title(of key: CardSizeKey) -> Text {
        switch key {
        case .plus, .equals:
            Text(
                "Make Card Larger",
                comment:
                    "A hidden button of the review panel and the Cards window: ⌘+, which makes a card's text and images larger."
            )
        case .minus:
            Text(
                "Make Card Smaller",
                comment:
                    "A hidden button of the review panel and the Cards window: ⌘−, which makes a card's text and images smaller."
            )
        case .zero:
            Text(
                "Normal Card Size",
                comment:
                    "A hidden button of the review panel and the Cards window: ⌘0, which returns a card's text and images to their normal size, 100%."
            )
        }
    }
}

extension NSEvent {
    /// This key press as the press of the card size's shortcut it stands for
    /// (`CardSizeKey`), held with ⌘ alone, however its layout types it, or nil
    /// when it stands for none.
    var asCardSizeShortcut: NSEvent? {
        guard type == .keyDown else { return nil }
        let modifiers = modifierFlags.intersection([.shift, .control, .option, .command])
        guard modifiers == .command || modifiers == [.command, .shift],
            let typed = charactersIgnoringModifiers,
            let typedWithCommand = characters(byApplyingModifiers: .command),
            let key = CardSizeKey(
                typed: typed, typedWithCommand: typedWithCommand, isShiftHeld: modifiers.contains(.shift))
        else {
            return nil
        }
        return asPress(of: String(key.rawValue), modifierFlags: .command)
    }

    /// This key press as one of a key that types `key`, with `modifierFlags`
    /// held.
    func asPress(of key: String, modifierFlags: NSEvent.ModifierFlags) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown, location: locationInWindow, modifierFlags: modifierFlags, timestamp: timestamp,
            windowNumber: windowNumber, context: nil, characters: key, charactersIgnoringModifiers: key,
            isARepeat: isARepeat, keyCode: keyCode)
    }
}
