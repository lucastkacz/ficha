/// The review panel's letter keys, R, A, M and E, on a layout of another
/// script: Russian types к, ф, ь and у with them, Arabic ق, ش, و and ث, and
/// 2-Set Korean ㄱ, ㅁ, ㅡ and ㄷ, and a shortcut for "r" doesn't take к, since
/// AppKit and SwiftUI match a shortcut by what its key types. Such a key stands
/// for the letter its layout types with ⌘, the one macOS's ⌘ shortcuts take on
/// that layout. A letter's place on the keyboard won't do, as it does for
/// `RatingKey`, since it differs between Latin layouts: French types a on
/// QWERTY's Q key. A key that types ASCII stays as it is, so Dvorak – QWERTY ⌘'s
/// p stays p, though it types r with ⌘ on the same key. This rule is our own.
/// The panel's view keeps the shortcuts themselves; this rule is here so it's
/// tested.
public enum LetterKey {
    /// The ASCII letter a key stands for, from what its layout types with it,
    /// `typed`, and what it types with ⌘ held, `typedWithCommand`; or nil when
    /// the key types ASCII, or nothing, as a dead key does, or when ⌘ gives no
    /// ASCII letter.
    public static func letter(typed: String, typedWithCommand: String) -> Character? {
        guard let typedCharacter = typed.first, !typedCharacter.isASCII, typedWithCommand.count == 1,
            let letter = typedWithCommand.first, letter.isASCII, letter.isLetter
        else {
            return nil
        }
        return letter
    }
}
