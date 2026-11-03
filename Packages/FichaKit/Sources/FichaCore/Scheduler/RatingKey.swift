/// The review panel's rating keys, 1 to 4 for again to easy, as Anki's, by
/// their place on the Mac's keyboard rather than by what its layout types
/// with them: the number row's 1 key types ١ in Apple's Arabic layouts and &
/// in its French ones, which a shortcut for "1" doesn't take, since AppKit
/// and SwiftUI match a shortcut by what its key types. The keys keep their
/// ratings in every layout (ADR 0027). This rule is our own.
public enum RatingKey {
    /// The rating key, "1" to "4", that the Mac's key `keyCode` is, one of
    /// the number row's or the numeric keypad's, or nil for any other key.
    /// The codes are the Mac's virtual key codes, the same on every layout:
    /// `kVK_ANSI_1` to `kVK_ANSI_4` and `kVK_ANSI_Keypad1` to
    /// `kVK_ANSI_Keypad4`, in Carbon's `Events.h`.
    public static func digit(forKeyCode keyCode: UInt16) -> Character? {
        switch keyCode {
        case 0x12, 0x53: "1"
        case 0x13, 0x54: "2"
        case 0x14, 0x55: "3"
        case 0x15, 0x56: "4"
        default: nil
        }
    }
}
