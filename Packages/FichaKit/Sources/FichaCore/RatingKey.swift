/// The review panel's rating keys, 1 to 4 for again to easy, as Anki's, by
/// their place on the Mac's keyboard rather than by what its layout types
/// with them: the number row's 1 key types ١ in Apple's Arabic layouts and &
/// in its French ones, which a shortcut for "1" doesn't take, since AppKit
/// and SwiftUI match a shortcut by what its key types. The keys keep their
/// ratings in every layout (ADR 0027). This rule is our own. The panel's
/// view keeps the shortcuts themselves; this map is here so it's tested.
public enum RatingKey {
    /// The key that rates a card `rating`, "1" to "4" in Anki's order, again's
    /// first: the one its button shows and its shortcut takes.
    public static func digit(of rating: Rating) -> Character {
        switch rating {
        case .again: "1"
        case .hard: "2"
        case .good: "3"
        case .easy: "4"
        }
    }

    /// The rating key, "1" to "4", that the Mac's key `keyCode` is, one of
    /// the number row's or the numeric keypad's, or nil for any other key.
    public static func digit(forKeyCode keyCode: UInt16) -> Character? {
        rating(forKeyCode: keyCode).map(digit(of:))
    }

    /// The rating whose key the Mac's key `keyCode` is. The codes are the
    /// Mac's virtual key codes, the same on every layout: `kVK_ANSI_1` to
    /// `kVK_ANSI_4` and `kVK_ANSI_Keypad1` to `kVK_ANSI_Keypad4`, in Carbon's
    /// `Events.h`.
    private static func rating(forKeyCode keyCode: UInt16) -> Rating? {
        switch keyCode {
        case 0x12, 0x53: .again
        case 0x13, 0x54: .hard
        case 0x14, 0x55: .good
        case 0x15, 0x56: .easy
        default: nil
        }
    }
}
