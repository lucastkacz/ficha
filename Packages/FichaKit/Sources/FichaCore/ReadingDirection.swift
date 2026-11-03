/// Which way a text reads, from its first letter, as Unicode's bidirectional
/// algorithm finds a paragraph's direction from its first strong character
/// (rules P2 and P3). The app aligns a card's text at the side it starts
/// from, whatever its own language: a Spanish card at the left on a Mac in
/// Arabic, an Arabic card at the right on a Mac in English (ADR 0027). The
/// letters this finds by their blocks are our own shortcut, since Swift
/// doesn't give a character's bidirectional class.
public enum ReadingDirection: Sendable, Equatable {
    case leftToRight
    case rightToLeft

    /// The direction `text` reads in: its first letter's, after any digits,
    /// punctuation or emoji. Nil when it has no letter, as a number alone,
    /// which reads as whatever is around it does.
    public init?(of text: String) {
        guard let letter = text.unicodeScalars.first(where: \.properties.isAlphabetic) else {
            return nil
        }
        self = Self.rightToLeftBlocks.contains { $0.contains(letter.value) } ? .rightToLeft : .leftToRight
    }

    /// The blocks whose letters read right to left: Hebrew, Arabic, Syriac,
    /// Thaana, N'Ko, Samaritan and Mandaic, their presentation forms, and
    /// the historic scripts beyond the first plane that Unicode gives that
    /// direction.
    private static let rightToLeftBlocks: [ClosedRange<UInt32>] = [
        0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF, 0x10800...0x10FFF, 0x1E800...0x1EFFF,
    ]
}
