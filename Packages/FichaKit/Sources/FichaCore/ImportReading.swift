import Foundation

/// What `CardsTextFile` made of the text file of cards a deck's `.ficha`
/// holds, before anything is imported: the cards it holds, in the file's
/// order, and the lines it left out, with why.
public struct ImportReading: Sendable, Equatable {
    /// The cards, in the file's order.
    public let cards: [ImportedCard]
    /// The lines that make no card, in the file's order.
    public let leftOut: [LeftOutLine]
    /// Whether the file's `#columns` header names its Type column, as
    /// Ficha's export writes it, so that the column surely holds types: a
    /// card's type by a name the user has no type of makes one then.
    /// Without it, the column in the type's place may hold another field, as
    /// Anki's Notes in Plain Text puts an Add Reverse field's "y" or an
    /// Extra field's sentence there, so the import leaves such a card's line
    /// out instead, saying why (`LeftOutLine.Reason.unknownType`).
    public let typeColumnIsNamed: Bool

    public init(cards: [ImportedCard], leftOut: [LeftOutLine], typeColumnIsNamed: Bool = false) {
        self.cards = cards
        self.leftOut = leftOut
        self.typeColumnIsNamed = typeColumnIsNamed
    }
}

/// A card a file holds, as its reader read it.
public struct ImportedCard: Sendable, Equatable {
    /// What the card holds, checked as every card is, with no type: the
    /// type the file gives it is `typeName`.
    public let content: CardContent
    /// The type the file gives the card, as it names it, which the import
    /// finds among the four Ficha comes with, by its raw value, and the
    /// user's types, by its name, or makes, in a file that names its Type
    /// column (`ImportReading.typeColumnIsNamed`); or nil for none.
    public let typeName: String?
    /// Whether it goes both ways, as it comes in.
    public let bothWays: Bool
    /// The line of the file it starts on, counted from 1.
    public let line: Int
    /// The deck the file puts it in, by its whole name, its levels joined by
    /// `::` and cleaned up as `TagPath` cleans up a tag's: what the text
    /// file's Deck column holds; or nil when its column is blank or missing.
    public let deck: String?

    public init(content: CardContent, typeName: String? = nil, bothWays: Bool = false, line: Int, deck: String? = nil) {
        self.content = content
        self.typeName = typeName
        self.bothWays = bothWays
        self.line = line
        self.deck = deck
    }
}

/// What a reader finds for a file a file of cards names for a side, an image
/// or a sound, by the name the file gives it: the name of a file in the
/// deck's `.ficha`.
public enum FileLookup<Name: Sendable & Equatable>: Sendable, Equatable {
    /// The file, which Ficha holds by this name for the card.
    case found(Name)
    /// Nothing by that name comes with the file.
    case missing
    /// What comes by that name isn't a file of its kind Ficha can read: an
    /// image, or a sound.
    case unreadable
}

/// What a reader finds for an image a file of cards names for a side.
public typealias ImageLookup = FileLookup<ImageName>

/// What a reader finds for a sound a file of cards names for a side.
public typealias SoundLookup = FileLookup<SoundName>

/// A line of a file of cards that makes no card, and why, which `make
/// preview-import` lists.
public struct LeftOutLine: Sendable, Equatable {
    /// Why a line makes no card.
    public enum Reason: Sendable, Equatable {
        /// It has one column, a front with no back: its columns aren't
        /// separated by what separates the file's.
        case oneColumn
        /// Its front is blank.
        case blankFront
        /// Its back is blank.
        case blankBack
        /// Its type column holds this, which names neither one of the four
        /// types Ficha comes with nor a user type the user has, in a file
        /// that doesn't name its Type column, which makes no type
        /// (`ImportReading.typeColumnIsNamed`).
        case unknownType(String)
        /// A field it opens with a quote is never closed by another.
        case unclosedQuote
        /// A field it opens with a quote has another quote inside that isn't
        /// doubled, as a quote in a quoted field must be.
        case strayQuote
        /// A side of it has no text, and the image it names for that side,
        /// this, doesn't come with the file, as in a zip that lacks it.
        case missingImage(String)
        /// A side of it has no text, and what comes as the image it names
        /// for that side, this, isn't an image Ficha can read.
        case notAnImage(String)
        /// A side of it has neither text nor an image, and the sound it
        /// names for that side, this, doesn't come with the file, as in a zip
        /// that lacks it.
        case missingSound(String)
        /// A side of it has neither text nor an image, and what comes as the
        /// sound it names for that side, this, isn't a sound Ficha can read.
        case notASound(String)
    }

    /// The line it is, or starts on, counted from 1.
    public let line: Int
    public let reason: Reason

    public init(line: Int, reason: Reason) {
        self.line = line
        self.reason = reason
    }
}
