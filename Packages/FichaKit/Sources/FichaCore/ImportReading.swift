import Foundation

/// What a reader made of a file of cards, before anything is imported: the
/// cards it holds, in the file's order, and the lines it left out, with why.
/// A text file's reader is `CardsTextFile`; another kind of file gets a
/// reader of its own that gives the same, so the preview, the duplicates,
/// the tags and the import itself are the same for every kind.
public struct ImportReading: Sendable, Equatable {
    /// The cards, in the file's order.
    public let cards: [ImportedCard]
    /// The lines that make no card, in the file's order.
    public let leftOut: [LeftOutLine]

    public init(cards: [ImportedCard], leftOut: [LeftOutLine]) {
        self.cards = cards
        self.leftOut = leftOut
    }
}

/// A card a file holds, as its reader read it.
public struct ImportedCard: Sendable, Equatable {
    /// What the card holds, checked as every card is.
    public let content: CardContent
    /// Which of a card's fields beyond its front and back the file gives it:
    /// an import that updates a card the user has keeps the card's own
    /// fields that the file doesn't give, and sets the others, even blank.
    public let fields: Set<CardField>
    /// The line of the file it starts on, counted from 1; for a card of an
    /// Anki package, its place among the package's cards, in the order they
    /// come in.
    public let line: Int
    /// The tags the import proposes for it, on top of its own, which the
    /// user may rename or leave out in the preview: a text file's name, or
    /// an Anki card's deck and its note's tags.
    public let proposedTags: [String]
    /// Whether the file gives the card images it comes in without, since a
    /// side holds one image at most: an Anki card with more than one image
    /// on a side, which brings the first.
    public let hasImagesDropped: Bool

    public init(
        content: CardContent, fields: Set<CardField>, line: Int, proposedTags: [String] = [],
        hasImagesDropped: Bool = false
    ) {
        self.content = content
        self.fields = fields
        self.line = line
        self.proposedTags = proposedTags
        self.hasImagesDropped = hasImagesDropped
    }
}

/// A field of a card beyond its front and back, which every card has, and
/// which a file of cards may give a card or not.
public enum CardField: Sendable, Hashable, CaseIterable {
    case tags
    case type
    case source
    /// The back's image, which a file gives with a column for it, even
    /// blank. The front's image goes with the front, which an import that
    /// updates a card keeps.
    case backImage
}

/// What a reader finds for an image a file of cards names for a side, by the
/// name the file gives it, such as the name of a file in a zip.
public enum ImageLookup: Sendable, Equatable {
    /// The image, which Ficha holds by this name for the card.
    case found(ImageName)
    /// Nothing by that name comes with the file.
    case missing
    /// What comes by that name isn't an image Ficha can read.
    case notAnImage
}

/// A line of a file of cards that makes no card, and why, for the preview to
/// list; for an Anki package, a card of it that makes no card.
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
        /// Its type column holds this, which isn't a card type.
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
        /// An Anki card with a side left with neither text nor an image once
        /// its sounds and its images on the web are dropped, such as one
        /// that holds only a sound.
        case emptyAnkiSide
        /// An Anki card with a side that holds only an image its package
        /// lacks, as when Anki exports a deck without its media.
        case missingAnkiImage
        /// An Anki card with a side that holds only an image Ficha can't
        /// read, such as an SVG.
        case unreadableAnkiImage
        /// An Anki card of an Image Occlusion note type, which hides parts
        /// of an image.
        case ankiImageOcclusion
        /// An Anki card whose template Anki can't render either, and shows
        /// an error in its place: it names a field its note type doesn't
        /// have, or it opens what it never closes.
        case brokenAnkiTemplate
    }

    /// The line it is, or starts on, counted from 1.
    public let line: Int
    public let reason: Reason

    public init(line: Int, reason: Reason) {
        self.line = line
        self.reason = reason
    }
}
