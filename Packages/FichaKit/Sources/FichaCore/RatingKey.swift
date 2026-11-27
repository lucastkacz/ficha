/// The review panel's rating keys, 1 to 3, one for each of its buttons
/// (`AnswerButton`), by their place on the Mac's keyboard rather than by what
/// its layout types with them: the number row's 1 key types ١ in Apple's
/// Arabic layouts and & in its French ones, which a shortcut for "1" doesn't
/// take, since AppKit and SwiftUI match a shortcut by what its key types. The
/// keys keep their buttons in every layout. Anki's 4, easy, is no rating key
/// in the panel (ADR 0039). This rule is our own. The panel's view keeps the
/// shortcuts themselves; this map is here so it's tested.
public enum RatingKey {
    /// The rating key, "1" to "3", that the Mac's key `keyCode` is, one of
    /// the number row's or the numeric keypad's, or nil for any other key,
    /// their 4 included. The codes are the Mac's virtual key codes, the same
    /// on every layout: `kVK_ANSI_1` to `kVK_ANSI_3` and `kVK_ANSI_Keypad1`
    /// to `kVK_ANSI_Keypad3`, in Carbon's `Events.h`.
    public static func digit(forKeyCode keyCode: UInt16) -> Character? {
        switch keyCode {
        case 0x12, 0x53: "1"
        case 0x13, 0x54: "2"
        case 0x14, 0x55: "3"
        default: nil
        }
    }
}
