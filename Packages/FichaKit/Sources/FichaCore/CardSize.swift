/// How large a card's text and images show in the review panel and the Cards
/// window, from 80% to 200% by 10%, as Anki's zoom goes by 10% a step. It's one
/// size for both windows, this Mac's own. The limits and the panel widening
/// with the card are our own. The app keeps it and draws with it; its
/// arithmetic is here so it's tested.
public struct CardSize: Sendable, Hashable {
    private static let smallest = 80
    private static let largest = 200
    private static let step = 10

    /// The size a card shows at until the user changes it.
    public static let normal = CardSize(step: 100)
    /// Every size, smallest first.
    public static let steps = stride(from: smallest, through: largest, by: step).map(CardSize.init(step:))

    /// The size as a percentage of the normal one, always one of the steps.
    public let percent: Int

    /// The size a stored percent says, or nil for anything that isn't a step.
    public init?(percent: Int) {
        guard (Self.smallest...Self.largest).contains(percent), percent % Self.step == 0 else {
            return nil
        }
        self.percent = percent
    }

    private init(step percent: Int) {
        self.percent = percent
    }

    /// The next size up, or this one at the largest.
    public var larger: CardSize {
        percent < Self.largest ? CardSize(step: percent + Self.step) : self
    }

    /// The next size down, or this one at the smallest.
    public var smaller: CardSize {
        percent > Self.smallest ? CardSize(step: percent - Self.step) : self
    }

    /// `length`, in points, at this size.
    public func scaled(_ length: Double) -> Double {
        length * Double(percent) / 100
    }

    /// The review panel's width: 400 pt up to 100%, since its buttons keep
    /// their size and have to fit, and 400 pt times the size above it.
    public var panelWidth: Double {
        max(400, scaled(400))
    }

    /// The tallest a side's image shows in the review panel, whose tallest is
    /// `panelTallest`: a third of that, so a card with an image on each side
    /// and a line or two of text on each fits without scrolling at 100%, and
    /// never more than 280 pt, at this size. A card with an image on each side
    /// may scroll above 100%, but an image never runs past the panel's tallest,
    /// so all of it can be seen by scrolling.
    public func imageHeightLimit(panelTallest: Double) -> Double {
        min(scaled(min(280, panelTallest / 3)), panelTallest)
    }

    /// The widest a side's image shows when it's offered `offered`: the image
    /// shrinks below 100% with the rest of the card, in a panel that stays
    /// 400 pt wide, and doesn't grow past what it's offered above it.
    public func imageWidthLimit(offered: Double) -> Double {
        min(offered, scaled(offered))
    }
}

/// A key that changes the card size, held with ⌘: + and = make a card larger,
/// since + takes Shift on a keyboard like the US one, - makes it smaller, and
/// 0 returns it to normal, as Anki's Zoom In, Zoom Out and Reset Zoom. AppKit
/// and SwiftUI match a shortcut by what its key types without ⌘, which is ٠ on
/// the number row's 0 key in Arabic and ㄢ in Zhuyin. So a press of ⌘ alone
/// stands for what its layout types with ⌘, the one macOS's ⌘ shortcuts take on
/// that layout, as for `LetterKey`, and a press of ⌘ and Shift for what its
/// layout types with Shift, since + takes Shift on a US keyboard, = on a German
/// one, and 0 on a French or an Italian one, where ⌘ alone still types à or é.
/// macOS's own layouts for Ficha's languages type all four keys this way, as
/// `UCKeyTranslate` read them. This rule is our own. The windows keep the
/// shortcuts themselves; this rule is here so it's tested.
public enum CardSizeKey: Character, CaseIterable, Sendable {
    case plus = "+"
    case equals = "="
    case minus = "-"
    case zero = "0"

    /// The key a press stands for, from what its layout types with it, or nil
    /// when that's none of these.
    public init?(typed: String) {
        guard typed.count == 1, let character = typed.first else {
            return nil
        }
        self.init(rawValue: character)
    }

    /// What the key makes of `size`, which stays as it is at a limit.
    public func applied(to size: CardSize) -> CardSize {
        switch self {
        case .plus, .equals: size.larger
        case .minus: size.smaller
        case .zero: .normal
        }
    }
}
