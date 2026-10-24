import Foundation

/// What a card holds, and the one check of what a valid card is, wherever it
/// comes from: approving a capture or an expansion, fixing or editing a card,
/// creating one, and the sample cards. A new way in, such as a form or an
/// import, builds one too, and never writes a card's content around it, so
/// that no way in lets in a card another refuses. Each side, the front and
/// the back, holds text, an image, a sound, or any of them together, one image
/// and one sound at most: an image or a sound Ficha already holds, by its
/// name. It cleans the content up the same way each time: its type, if it has
/// one, its sides' text, and its tags and source, without surrounding spaces
/// or line breaks. A tag or source left blank is no tag or source, and a
/// side's text left blank is none.
public struct CardContent: Sendable, Equatable {
    /// Its type, or nil when it has none.
    public let type: CardType?
    /// The front's text, or empty when the front holds only an image or a
    /// sound.
    public let front: String
    /// The back's text, or empty when the back holds only an image or a
    /// sound.
    public let back: String
    public let tags: [String]
    public let source: String?
    /// The front's image, or nil when it has none.
    public let frontImage: ImageName?
    /// The back's image, or nil when it has none.
    public let backImage: ImageName?
    /// The front's sound, or nil when it has none.
    public let frontSound: SoundName?
    /// The back's sound, or nil when it has none.
    public let backSound: SoundName?

    /// What these fields make, or nil when a side, the front or the back, has
    /// neither text, an image nor a sound, since a card needs both sides. A
    /// nil type is no type.
    public init?(
        type: CardType?,
        front: String,
        back: String,
        tags: [String],
        source: String?,
        frontImage: ImageName? = nil,
        backImage: ImageName? = nil,
        frontSound: SoundName? = nil,
        backSound: SoundName? = nil
    ) {
        guard !Self.isBlank(front, image: frontImage, sound: frontSound),
            !Self.isBlank(back, image: backImage, sound: backSound)
        else {
            return nil
        }
        self.type = type
        self.front = nonBlank(front) ?? ""
        self.back = nonBlank(back) ?? ""
        self.tags = tags.compactMap(nonBlank)
        self.source = nonBlank(source)
        self.frontImage = frontImage
        self.backImage = backImage
        self.frontSound = frontSound
        self.backSound = backSound
    }

    /// Whether `side`'s text, a front's or a back's, is blank by the rule
    /// `init` follows, for fields to say which side keeps them from making a
    /// card while it has no image nor sound.
    public static func isBlank(_ side: String) -> Bool {
        nonBlank(side) == nil
    }

    /// Whether a side with `text`, `image` and `sound`, or none, is blank by
    /// the rule `init` follows: it has neither text, an image nor a sound.
    public static func isBlank(_ text: String, image: ImageName?, sound: SoundName?) -> Bool {
        isBlank(text) && image == nil && sound == nil
    }

    /// The tags a Tags field holds, `text`, separated by commas, as they come
    /// in: `init` cleans them up as it does wherever a card comes from.
    public static func tags(inField text: String) -> [String] {
        text.split(separator: ",").map(String.init)
    }

    /// What a Tags field holds for `tags` when it starts with them, as when
    /// the user edits a card: separated by commas, each after a space.
    public static func tagsField(of tags: [String]) -> String {
        tags.joined(separator: ", ")
    }

    /// The images on its sides, each once.
    public var images: Set<ImageName> {
        Set([frontImage, backImage].compactMap(\.self))
    }

    /// The sounds on its sides, each once.
    public var sounds: Set<SoundName> {
        Set([frontSound, backSound].compactMap(\.self))
    }

    /// This content with the images and sounds given in place of its own,
    /// where they aren't nil: as a refine session's content keeps the images
    /// and sounds of the card it changes, since refining never adds one. Each
    /// side keeps its text, so it's never blank.
    public func keepingFiles(
        frontImage: ImageName?, backImage: ImageName?, frontSound: SoundName?, backSound: SoundName?
    ) -> CardContent {
        CardContent(
            checked: self, frontImage: frontImage ?? self.frontImage, backImage: backImage ?? self.backImage,
            frontSound: frontSound ?? self.frontSound, backSound: backSound ?? self.backSound)
    }

    /// `content` with these images and sounds, which leave no side blank,
    /// since each replaces one or keeps it.
    private init(
        checked content: CardContent, frontImage: ImageName?, backImage: ImageName?, frontSound: SoundName?,
        backSound: SoundName?
    ) {
        type = content.type
        front = content.front
        back = content.back
        tags = content.tags
        source = content.source
        self.frontImage = frontImage
        self.backImage = backImage
        self.frontSound = frontSound
        self.backSound = backSound
    }
}
