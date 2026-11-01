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
    /// Whether the file's `#columns` header names its Type column, as
    /// Ficha's Export writes it, so that the column surely holds types: a
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
    /// column (`ImportReading.typeColumnIsNamed`); or nil for none, as an
    /// Anki card's, whose note type never becomes one.
    public let typeName: String?
    /// Whether it goes both ways: a card that comes in new comes in so, but
    /// one way when an import that brings progress finds its back-first way
    /// alone suspended (`backFirstProgress`); and a card of the user's it
    /// updates takes it when `fields` has Both ways, and keeps its own
    /// otherwise.
    public let bothWays: Bool
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
    /// an Anki card's note's tags.
    public let proposedTags: [String]
    /// The deck the file puts it in, by its whole name, its levels joined by
    /// `::` and cleaned up as `TagPath` cleans up a tag's, which the user may
    /// rename in the preview: an Anki card's home deck, or what a text file's
    /// Deck column holds; or nil when the file puts it in none, such as an
    /// Anki card in Anki's Default, or a text file's card with that column
    /// blank or missing. A card it comes into new takes it, and one of the
    /// user's it updates keeps its own.
    public let deck: String?
    /// Where it stood in the app the file comes from, which an import that
    /// brings progress gives it when it comes in new to Ficha: an Anki
    /// card's; nil for a text file's, which says nothing of it. For a card
    /// that goes both ways, where its front-first way stood.
    public let progress: ImportedProgress?
    /// Where its back-first way stood in the app the file comes from, for a
    /// card made of two of the file's, one for each way, which an import
    /// that brings progress gives that way as it gives `progress`: the
    /// reversed card's of a note of Anki's that makes one (ADR 0016); nil
    /// for any other card.
    public let backFirstProgress: ImportedProgress?
    /// Whether the file gives the card images it comes in without, since a
    /// side holds one image at most: an Anki card with more than one image
    /// on a side, which brings the first.
    public let hasImagesDropped: Bool
    /// Whether the file gives the card sounds it comes in without, since a
    /// side holds one sound at most: an Anki card with more than one sound
    /// on a side, which brings the first.
    public let hasSoundsDropped: Bool
    /// Whether the file gives the card a sound Ficha can't read, which it
    /// comes in without, since its side holds something else: an Anki
    /// card's.
    public let hasUnreadableSoundsLeftOut: Bool

    public init(
        content: CardContent, typeName: String? = nil, bothWays: Bool = false, fields: Set<CardField>, line: Int,
        proposedTags: [String] = [], deck: String? = nil,
        progress: ImportedProgress? = nil, backFirstProgress: ImportedProgress? = nil, hasImagesDropped: Bool = false,
        hasSoundsDropped: Bool = false, hasUnreadableSoundsLeftOut: Bool = false
    ) {
        self.content = content
        self.typeName = typeName
        self.bothWays = bothWays
        self.fields = fields
        self.line = line
        self.proposedTags = proposedTags
        self.deck = deck
        self.progress = progress
        self.backFirstProgress = backFirstProgress
        self.hasImagesDropped = hasImagesDropped
        self.hasSoundsDropped = hasSoundsDropped
        self.hasUnreadableSoundsLeftOut = hasUnreadableSoundsLeftOut
    }
}

/// Where a card stood in the app a file comes from, such as Anki, which an
/// import that brings progress gives it (ADR 0013).
public struct ImportedProgress: Sendable, Equatable {
    /// How far along it was.
    public enum Stage: Sendable, Equatable {
        /// It hadn't been studied yet: it comes in new.
        case new
        /// It was being learned, or relearned after a lapse, due at `due`:
        /// it comes in on its first learning step, due then.
        case learning(due: Date)
        /// It was in review, every `interval`, with `ease` as Anki's ease,
        /// such as 2.5 for 250%, due at `due`: it comes in graduated, with
        /// that interval and ease, due then.
        case review(interval: Duration, ease: Double, due: Date)
    }

    public let stage: Stage
    /// Whether it was taken out of reviews for good there, as Anki suspends
    /// a card: it comes in buried, with its progress.
    public let isSuspended: Bool

    public init(stage: Stage, isSuspended: Bool) {
        self.stage = stage
        self.isSuspended = isSuspended
    }
}

extension ImportedProgress.Stage {
    /// The placement an import that brings a card's progress gives it, as it
    /// stood there (ADR 0013): a card being learned with no interval, so on
    /// its first learning step, and one in review with its interval and ease,
    /// each due when it was due there. Nil for a new card, which comes in
    /// new.
    public var placement: Placement? {
        switch self {
        case .new:
            nil
        case .learning(let due):
            Placement(interval: .zero, due: due)
        case .review(let interval, let ease, let due):
            Placement(interval: interval, due: due, ease: ease)
        }
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
    /// The back's sound, which a file gives with a column for it, as the
    /// back's image. The front's sound goes with the front, as its image.
    case backSound
    /// Whether the card goes both ways, which a file gives with a column
    /// for it, even blank, as the back's image.
    case bothWays
}

/// What a reader finds for a file a file of cards names for a side, an image
/// or a sound, by the name the file gives it, such as the name of a file in a
/// zip.
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
        /// An Anki card with a side left with neither text, an image nor a
        /// sound once its images on the web are dropped, such as one with
        /// only an image on the web.
        case emptyAnkiSide
        /// An Anki card with a side that holds only an image its package
        /// lacks, as when Anki exports a deck without its media.
        case missingAnkiImage
        /// An Anki card with a side that holds only an image Ficha can't
        /// read, such as a damaged file.
        case unreadableAnkiImage
        /// An Anki card with a side that holds only a sound its package
        /// lacks, as when Anki exports a deck without its media.
        case missingAnkiSound
        /// An Anki card with a side that holds only a sound Ficha can't
        /// read, such as a damaged file.
        case unreadableAnkiSound
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
