import Foundation

/// What a card holds, and the one check of what a valid card is, wherever it
/// comes from: approving a capture or an expansion, fixing or editing a card,
/// creating one, and the sample cards. A new way in, such as a form or an
/// import, builds one too, and never writes a card's content around it, so
/// that no way in lets in a card another refuses. Each side, the front and
/// the back, holds text, an image, or both, one image at most: an image Ficha
/// already holds, by its name. It cleans the content up the same way each
/// time: its type, if it has one, its sides' text, and its tags and source,
/// without surrounding spaces or line breaks. A tag or source left blank is
/// no tag or source, and a side's text left blank is none.
public struct CardContent: Sendable, Equatable {
    /// Its type, or nil when it has none.
    public let type: CardType?
    /// The front's text, or empty when the front holds only an image.
    public let front: String
    /// The back's text, or empty when the back holds only an image.
    public let back: String
    public let tags: [String]
    public let source: String?
    /// The front's image, or nil when it has none.
    public let frontImage: ImageName?
    /// The back's image, or nil when it has none.
    public let backImage: ImageName?

    /// What these fields make, or nil when a side, the front or the back, has
    /// neither text nor an image, since a card needs both sides. A nil type
    /// is no type.
    public init?(
        type: CardType?,
        front: String,
        back: String,
        tags: [String],
        source: String?,
        frontImage: ImageName? = nil,
        backImage: ImageName? = nil
    ) {
        guard !Self.isBlank(front, image: frontImage), !Self.isBlank(back, image: backImage) else {
            return nil
        }
        self.type = type
        self.front = nonBlank(front) ?? ""
        self.back = nonBlank(back) ?? ""
        self.tags = tags.compactMap(nonBlank)
        self.source = nonBlank(source)
        self.frontImage = frontImage
        self.backImage = backImage
    }

    /// Whether `side`'s text, a front's or a back's, is blank by the rule
    /// `init` follows, for fields to say which side keeps them from making a
    /// card while it has no image.
    public static func isBlank(_ side: String) -> Bool {
        nonBlank(side) == nil
    }

    /// Whether a side with `text` and `image`, or none, is blank by the rule
    /// `init` follows: it has neither text nor an image.
    public static func isBlank(_ text: String, image: ImageName?) -> Bool {
        isBlank(text) && image == nil
    }

    /// The tags a Tags field holds, `text`, separated by commas, as they come
    /// in: `init` cleans them up as it does wherever a card comes from.
    public static func tags(inField text: String) -> [String] {
        text.split(separator: ",").map(String.init)
    }

    /// The images on its sides, each once.
    public var images: Set<ImageName> {
        Set([frontImage, backImage].compactMap(\.self))
    }

    /// This content with the images `front` and `back` in place of its own,
    /// where they aren't nil: as a refine session's content keeps the images
    /// of the card it changes, since refining never adds one. Each side keeps
    /// its text, so it's never blank.
    public func keepingImages(front: ImageName?, back: ImageName?) -> CardContent {
        CardContent(
            checked: self, frontImage: front ?? frontImage, backImage: back ?? backImage)
    }

    /// `content` with these images, which leave no side blank, since each
    /// replaces one or keeps it.
    private init(checked content: CardContent, frontImage: ImageName?, backImage: ImageName?) {
        type = content.type
        front = content.front
        back = content.back
        tags = content.tags
        source = content.source
        self.frontImage = frontImage
        self.backImage = backImage
    }
}
