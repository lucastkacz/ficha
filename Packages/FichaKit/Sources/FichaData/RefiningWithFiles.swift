import FichaCore
import Foundation
internal import GRDB

/// A card a refine session drafted, as Lucas approved it and the `ficha` CLI
/// reads it: what it holds, and what becomes of each side's image and sound.
/// The engine checks it as `CardContent` does once its files are in.
public struct CardDraft: Sendable, Equatable {
    /// Its type, or nil when it has none.
    public let type: CardType?
    public let front: String
    public let back: String
    public let tags: [String]
    public let source: String?
    public let frontImage: FileChange
    public let backImage: FileChange
    public let frontSound: FileChange
    public let backSound: FileChange

    public init(
        type: CardType?,
        front: String,
        back: String,
        tags: [String],
        source: String?,
        frontImage: FileChange,
        backImage: FileChange,
        frontSound: FileChange,
        backSound: FileChange
    ) {
        self.type = type
        self.front = front
        self.back = back
        self.tags = tags
        self.source = source
        self.frontImage = frontImage
        self.backImage = backImage
        self.frontSound = frontSound
        self.backSound = backSound
    }
}

/// What a refine session does with a side's image or its sound.
public enum FileChange: Sendable, Equatable {
    /// Keeps the one the card has, or puts none on a new card.
    case keep
    /// Takes the card's off.
    case remove
    /// Puts this file on the side, in place of the card's.
    case put(FileForSide)
}

/// A file a refine session puts on a side of a card.
public enum FileForSide: Sendable, Equatable {
    /// The file at this URL on the Mac, which comes in as one dropped on the
    /// Cards window's form does: an image shrunk, a sound converted.
    case file(URL)
    /// An image Ficha holds already, by its name.
    case image(ImageName)
    /// A sound Ficha holds already, by its name.
    case sound(SoundName)

    /// The file `text` gives, as a refine session writes it for the `ficha`
    /// CLI: an image or a sound Ficha holds, by the name `ficha cards`
    /// prints, or else the path of a file on the Mac, from the home folder
    /// when it starts with `~`, and from the folder the command runs in when
    /// it doesn't start with `/` either. Blank text gives none.
    public init?(_ text: String) {
        if text.allSatisfy(\.isWhitespace) {
            return nil
        } else if let image = ImageName(rawValue: text) {
            self = .image(image)
        } else if let sound = SoundName(rawValue: text) {
            self = .sound(sound)
        } else {
            self = .file(URL(filePath: NSString(string: text).expandingTildeInPath))
        }
    }
}

/// The kind of a file on a side of a card: an image or a sound.
public enum FileKind: String, Sendable, CaseIterable {
    case image
    case sound
}

extension Engine {
    /// Approves a capture into the cards `drafts`, as `approve(_:into:)`
    /// does, with the images and sounds they put on their sides: files come
    /// in shrunk or converted, as from the Cards window's form. A side whose
    /// image or sound is left out or removed has none.
    @discardableResult
    public func approve(_ captureID: Int64, into drafts: [CardDraft]) async throws(EngineError) -> [Card] {
        var held = FilesComingIn()
        var contents: [CardContent] = []
        for (position, draft) in drafts.enumerated() {
            let files = try await held.bringIn(draft, with: self)
            contents.append(
                try draft.content(with: files.applied(to: nil), orIfBlank: .blankSideOnNewCard(position: position)))
        }
        return try keeping(held.files) { () throws(EngineError) in try approve(captureID, into: contents) }
    }

    /// Fixes a flagged card with `draft`, as `fix(_:with:)` does with a
    /// card's content, with the images and sounds it puts on its sides or
    /// takes off: files come in shrunk or converted, as from the Cards
    /// window's form, and a side whose image or sound is left out keeps its
    /// own. One the card no longer has goes, unless another card uses it.
    @discardableResult
    public func fix(_ cardID: Int64, with draft: CardDraft) async throws(EngineError) -> Card {
        var held = FilesComingIn()
        let files = try await held.bringIn(draft, with: self)
        let (before, fixed) = try keeping(held.files) { () throws(EngineError) in
            try fix(cardID) { card throws(EngineError) in
                try draft.content(with: files.applied(to: card), orIfBlank: .sideLeftBlank(cardID))
            }
        }
        removeFilesNoCardUses(before: before, after: fixed)
        return fixed
    }

    /// Approves an expansion with `draft`, as `approveExpansion(_:into:)`
    /// does with a card's content, with the images and sounds it puts on its
    /// card's sides or takes off, as `fix(_:with:)` does with a draft.
    @discardableResult
    public func approveExpansion(_ captureID: Int64, into draft: CardDraft) async throws(EngineError) -> Card {
        var held = FilesComingIn()
        let files = try await held.bringIn(draft, with: self)
        let (before, approved) = try keeping(held.files) { () throws(EngineError) in
            try approveExpansion(captureID) { card throws(EngineError) in
                try draft.content(with: files.applied(to: card), orIfBlank: .sideLeftBlank(card.id))
            }
        }
        removeFilesNoCardUses(before: before, after: approved)
        return approved
    }

    /// Puts `file` on `side` of the card with this id, an image or a sound,
    /// as the file says, in place of the side's own: any card, flagged,
    /// buried or set aside, which stays where it stands. A file from the Mac
    /// comes in shrunk or converted, as from the Cards window's form, and a
    /// video gives its sound. The one it replaces goes, unless another card
    /// uses it. Returns the card.
    @discardableResult
    public func attach(_ file: FileForSide, to side: CardSide, of cardID: Int64) async throws(EngineError) -> Card {
        var held = FilesComingIn()
        let files = try await held.bringIn(file, on: side, with: self)
        return try keeping(held.files) { () throws(EngineError) in
            try changeFiles(of: cardID) { card in files.applied(to: card) }
        }
    }

    /// Takes the image or the sound, as `kind` says, off `side` of the card
    /// with this id, which keeps the rest of what it holds: any card, as
    /// `attach(_:to:of:)` puts one on any card. The file goes, unless another
    /// card uses it. A side without one, or left with neither text, an image
    /// nor a sound, is refused. Returns the card.
    @discardableResult
    public func detach(_ kind: FileKind, from side: CardSide, of cardID: Int64) throws(EngineError) -> Card {
        var files = DraftFiles()
        switch kind {
        case .image: files.change(image: .remove, on: side)
        case .sound: files.change(sound: .remove, on: side)
        }
        return try changeFiles(of: cardID) { card throws(EngineError) in
            let changed = files.applied(to: card)
            guard changed != card.files else { throw .noFileOnSide(cardID, kind, side) }
            return changed
        }
    }

    /// Changes the images and sounds on the sides of the card with this id to
    /// those `newFiles` gives for the card as it is, or nothing when it
    /// throws, and nothing else: the card stays where it stands. Those it no
    /// longer has go, unless another card uses them. Returns the card.
    private func changeFiles(of cardID: Int64, to newFiles: (Card) throws(EngineError) -> SideFiles)
        throws(EngineError) -> Card
    {
        let changedAt = time.now
        let (before, changed) = try write { db in
            let card = try existingCard(cardID, in: db)
            guard let content = card.content(with: try newFiles(card)) else {
                throw EngineError.sideLeftBlank(cardID)
            }
            return (card, try replaceContent(of: cardID, with: content, at: changedAt, in: db))
        }
        removeFilesNoCardUses(before: before, after: changed)
        return changed
    }
}

extension Card {
    /// The image and the sound on each side.
    fileprivate var files: SideFiles {
        SideFiles(frontImage: frontImage, backImage: backImage, frontSound: frontSound, backSound: backSound)
    }

    /// What the card holds with `files` on its sides, or nil when a side is
    /// left with neither text, an image nor a sound.
    fileprivate func content(with files: SideFiles) -> CardContent? {
        CardContent(
            type: type, front: front, back: back, tags: tags, source: source, frontImage: files.frontImage,
            backImage: files.backImage, frontSound: files.frontSound, backSound: files.backSound)
    }
}

extension CardDraft {
    /// What the draft holds with `files` on its sides, or the error `blank`
    /// when a side is left with neither text, an image nor a sound.
    fileprivate func content(with files: SideFiles, orIfBlank blank: EngineError) throws(EngineError) -> CardContent {
        guard
            let content = CardContent(
                type: type, front: front, back: back, tags: tags, source: source, frontImage: files.frontImage,
                backImage: files.backImage, frontSound: files.frontSound, backSound: files.backSound)
        else {
            throw blank
        }
        return content
    }
}

/// The image and the sound on each side of a card, or none.
private struct SideFiles: Equatable {
    var frontImage: ImageName?
    var backImage: ImageName?
    var frontSound: SoundName?
    var backSound: SoundName?
}

/// What a draft does with a side's file, once a file it puts came in: keeps
/// the card's, takes it off, or puts the one named.
private enum NameChange<Name> {
    case keep
    case remove
    case put(Name)

    /// The file a side has once the change is made to `name`, the one it had.
    func applied(to name: Name?) -> Name? {
        switch self {
        case .keep: name
        case .remove: nil
        case .put(let name): name
        }
    }
}

/// What a draft does with each side's image and sound, once the files it
/// puts came in: by default, nothing.
private struct DraftFiles {
    var frontImage = NameChange<ImageName>.keep
    var backImage = NameChange<ImageName>.keep
    var frontSound = NameChange<SoundName>.keep
    var backSound = NameChange<SoundName>.keep

    /// Makes `change` to the image on `side`.
    mutating func change(image change: NameChange<ImageName>, on side: CardSide) {
        switch side {
        case .front: frontImage = change
        case .back: backImage = change
        }
    }

    /// Makes `change` to the sound on `side`.
    mutating func change(sound change: NameChange<SoundName>, on side: CardSide) {
        switch side {
        case .front: frontSound = change
        case .back: backSound = change
        }
    }

    /// The images and sounds a card's sides have once the changes are made
    /// to `card`'s, or to none for a new card.
    func applied(to card: Card?) -> SideFiles {
        SideFiles(
            frontImage: frontImage.applied(to: card?.frontImage), backImage: backImage.applied(to: card?.backImage),
            frontSound: frontSound.applied(to: card?.frontSound), backSound: backSound.applied(to: card?.backSound))
    }
}

/// The images and sounds that came in for refine sessions' changes, held until
/// the cards that have them are saved.
private struct FilesComingIn {
    private var images: [CardImage] = []
    private var sounds: [CardSound] = []

    /// The files held, ready to keep.
    var files: HeldFiles {
        HeldFiles(images: images, sounds: sounds)
    }

    /// Brings in the files `draft` puts on its sides, holding those that
    /// came in from the Mac, and returns what it does with each.
    mutating func bringIn(_ draft: CardDraft, with engine: Engine) async throws(EngineError) -> DraftFiles {
        DraftFiles(
            frontImage: try imageChange(draft.frontImage, with: engine),
            backImage: try imageChange(draft.backImage, with: engine),
            frontSound: try await soundChange(draft.frontSound, with: engine),
            backSound: try await soundChange(draft.backSound, with: engine))
    }

    /// Brings in `file`, an image or a sound, as the file says, holding it
    /// when it came in from the Mac, and returns the change that puts it on
    /// `side`.
    mutating func bringIn(_ file: FileForSide, on side: CardSide, with engine: Engine) async throws(EngineError)
        -> DraftFiles
    {
        var files = DraftFiles()
        switch file {
        case .image:
            files.change(image: .put(try image(file, with: engine)), on: side)
        case .sound:
            files.change(sound: .put(try await sound(file, with: engine)), on: side)
        case .file(let url):
            let data = try contents(of: url)
            do throws(EngineError) {
                let image = try CardImage(shrinking: data)
                images.append(image)
                files.change(image: .put(image.name), on: side)
            } catch .notAnImage {
                do throws(EngineError) {
                    files.change(sound: .put(try await sound(file, with: engine)), on: side)
                } catch .fileNotASound {
                    throw .notAnImageOrSound(url.lastPathComponent)
                }
            }
        }
        return files
    }

    /// What `change` does with a side's image, once the file it puts came in.
    private mutating func imageChange(_ change: FileChange, with engine: Engine) throws(EngineError)
        -> NameChange<ImageName>
    {
        switch change {
        case .keep: .keep
        case .remove: .remove
        case .put(let file): .put(try image(file, with: engine))
        }
    }

    /// What `change` does with a side's sound, once the file it puts came in.
    private mutating func soundChange(_ change: FileChange, with engine: Engine) async throws(EngineError)
        -> NameChange<SoundName>
    {
        switch change {
        case .keep: .keep
        case .remove: .remove
        case .put(let file): .put(try await sound(file, with: engine))
        }
    }

    /// The image `file` puts on a side, once it came in: shrunk and held,
    /// from the Mac, or one Ficha holds. A file that isn't an image, or a
    /// sound Ficha holds, is refused.
    private mutating func image(_ file: FileForSide, with engine: Engine) throws(EngineError) -> ImageName {
        switch file {
        case .file(let url):
            let image: CardImage
            do throws(EngineError) {
                image = try CardImage(shrinking: contents(of: url))
            } catch .notAnImage {
                throw .fileNotAnImage(url.lastPathComponent)
            }
            images.append(image)
            return image.name
        case .image(let name):
            guard engine.images.contains(name) else { throw .noFileNamed(name.rawValue) }
            return name
        case .sound(let name):
            throw .fileNotAnImage(name.rawValue)
        }
    }

    /// The sound `file` puts on a side, once it came in: converted and held,
    /// from the Mac, a video's too, or one Ficha holds. A file with no
    /// sound, or an image Ficha holds, is refused.
    private mutating func sound(_ file: FileForSide, with engine: Engine) async throws(EngineError) -> SoundName {
        switch file {
        case .file(let url):
            try checkFile(at: url)
            let sound: CardSound
            do throws(EngineError) {
                sound = try await CardSound(converting: url)
            } catch .notASound {
                throw .fileNotASound(url.lastPathComponent)
            }
            sounds.append(sound)
            return sound.name
        case .sound(let name):
            guard engine.sounds.contains(name) else { throw .noFileNamed(name.rawValue) }
            return name
        case .image(let name):
            throw .fileNotASound(name.rawValue)
        }
    }
}

/// Checks that there's a file at `url` Ficha can read, or says why not.
private func checkFile(at url: URL) throws(EngineError) {
    let path = url.path(percentEncoded: false)
    var isFolder: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), !isFolder.boolValue else {
        throw .noSuchFile(path)
    }
    guard FileManager.default.isReadableFile(atPath: path) else {
        logger.error("A file a refine session gave for a side of a card can't be read")
        throw .unreadableFileForSide(url.lastPathComponent)
    }
}

/// What the file at `url` holds, or why it couldn't be read.
private func contents(of url: URL) throws(EngineError) -> Data {
    try checkFile(at: url)
    do {
        return try Data(contentsOf: url)
    } catch {
        logger.error("Couldn't read a file a refine session gave: \(String(describing: error))")
        throw .unreadableFileForSide(url.lastPathComponent)
    }
}
