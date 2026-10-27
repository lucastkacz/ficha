import FichaCore
import Foundation
import UniformTypeIdentifiers

/// A side of a card: its front or its back.
public enum CardSide: Sendable, Hashable, CaseIterable {
    case front
    case back
}

/// The image on each side of a card, or none.
public struct SideImages: Sendable, Equatable {
    public internal(set) var front: ImageName?
    public internal(set) var back: ImageName?

    init(front: ImageName? = nil, back: ImageName? = nil) {
        self.front = front
        self.back = back
    }

    /// The image on `side`, or nil for none.
    public subscript(side: CardSide) -> ImageName? {
        get {
            switch side {
            case .front: front
            case .back: back
            }
        }
        set {
            switch side {
            case .front: front = newValue
            case .back: back = newValue
            }
        }
    }

    /// Every image on the sides, each once.
    var all: Set<ImageName> {
        Set([front, back].compactMap(\.self))
    }
}

/// The images a window shows, by name, each read from where Ficha keeps
/// them, or why it couldn't be, or held as it came in, dragged or pasted,
/// until a card that has it is saved.
public struct ShownImages: Sendable, Equatable {
    private var images: [ImageName: Result<Data, EngineError>] = [:]
    /// The images that came in and aren't kept yet.
    private var held: [ImageName: Data] = [:]

    /// The image named `name`, as a JPEG or a PNG, or why it couldn't be
    /// read, or nil when the window doesn't show it.
    public subscript(name: ImageName) -> Result<Data, EngineError>? {
        held[name].map(Result.success) ?? images[name]
    }

    /// Holds `image`, which came in, until a card that has it is saved.
    mutating func hold(_ image: CardImage) {
        held[image.name] = image.data
    }

    /// The images among `names` it holds, which aren't kept yet, ready to
    /// keep.
    func held(among names: Set<ImageName>) -> [CardImage] {
        names.sorted { $0.rawValue < $1.rawValue }.compactMap { name in
            held[name].map { CardImage(name: name, data: $0) }
        }
    }

    /// Shows the images named `names`: reads with `engine` those it hasn't
    /// read yet, or couldn't, and lets go of the others, held ones too.
    mutating func show(_ names: Set<ImageName>, readingWith engine: Engine) {
        held = held.filter { names.contains($0.key) }
        images = images.filter { names.contains($0.key) }
        for name in names where held[name] == nil {
            if case .success = images[name] { continue }
            images[name] = Result { () throws(EngineError) in try engine.image(name) }
        }
    }
}

/// What's dragged or pasted onto a side of a card, as its image.
public enum DroppedImage: Sendable, Equatable {
    /// A file, as Finder drags or copies it, which the window reads.
    case file(URL)
    /// An image's data, as a browser or the pasteboard holds it: none when
    /// what came in holds neither a file nor an image, as a web address.
    case data(Data)

    /// What the items of a drag's or a paste's pasteboard bring as a side's
    /// image: the first that holds one, or no data when none does, which the
    /// window refuses, and the log names the types they held.
    public init(pasteboardItems items: [some PasteboardItem]) {
        guard let image = Self.firstImage(in: items) else {
            let types = items.map(\.typeIdentifiers)
            logger.notice("No image on the pasteboard, whose items held \(types, privacy: .public)")
            self = .data(Data())
            return
        }
        self = image
    }

    /// The image ⌘V puts on a side while the user types its text: the one the
    /// items bring, as on the side's image well, when none of them holds text,
    /// as a screenshot copied to the clipboard, and a file only when it's an
    /// image's. Nil when one holds text, for the text to take it, as Finder's
    /// copy of a file holds its name, or when they bring no image. It reads no
    /// item's data while one holds text.
    public init?(pastedIntoText items: [some PasteboardItem]) {
        let holdsText = items.contains { item in
            item.typeIdentifiers.contains { UTType($0)?.conforms(to: .plainText) == true }
        }
        guard !holdsText, let image = Self.firstImage(in: items) else { return nil }
        if case .file(let file) = image, UTType(filenameExtension: file.pathExtension)?.conforms(to: .image) != true {
            return nil
        }
        self = image
    }

    /// The image the first of `items` that brings one brings.
    private static func firstImage(in items: [some PasteboardItem]) -> DroppedImage? {
        for item in items {
            if let image = image(in: item) {
                return image
            }
        }
        return nil
    }

    /// The image `item` brings: the local file a Finder drag names, or else
    /// the data of its first image type that holds some, as when a browser
    /// drags an image beside its web address and the file it promises. Nil
    /// when it holds neither, as a web address alone: Ficha never fetches
    /// one.
    private static func image(in item: some PasteboardItem) -> DroppedImage? {
        let types = item.typeIdentifiers
        if types.contains(UTType.fileURL.identifier), let reference = item.data(ofType: UTType.fileURL.identifier),
            let file = URL(dataRepresentation: reference, relativeTo: nil), file.isFileURL
        {
            return .file(file)
        }
        for type in types where UTType(type)?.conforms(to: .image) == true {
            if let image = item.data(ofType: type), !image.isEmpty {
                return .data(image)
            }
        }
        return nil
    }
}

/// One item of a drag's or a paste's pasteboard, which the app reads from
/// AppKit's, so what a side takes from it is tested without the OS.
public protocol PasteboardItem {
    /// Its types, in the order its source wrote them.
    var typeIdentifiers: [String] { get }
    /// Its data of `type`, or nil when it has none.
    func data(ofType type: String) -> Data?
}

extension CardsWindowState {
    /// Puts the image `dropped` brings on `side` of the card the form makes,
    /// in place of the one it had, shrunk as every image that comes in. The
    /// window holds it until Add saves the card. Something that isn't an
    /// image, or a file that can't be read, stays out, and the window
    /// records why.
    public mutating func putImageInForm(_ dropped: DroppedImage, on side: CardSide) {
        guard let form = cardForm, let image = imageComingIn(dropped) else { return }
        var draft = form.draft
        draft[side].image = image.name
        changeDraft(draft)
        showFiles()
    }

    /// Removes the image on `side` of the card the form makes.
    public mutating func removeImageFromForm(on side: CardSide) {
        guard var draft = cardForm?.draft else { return }
        draft[side].image = nil
        changeDraft(draft)
        showFiles()
    }

    /// Puts the image `dropped` brings on `side` of the card the user edits, in
    /// place of the one it had, shrunk as every image that comes in. The
    /// window holds it until Save saves the card. Something that isn't an
    /// image, or a file that can't be read, stays out, and the window
    /// records why.
    public mutating func putImageInEditor(_ dropped: DroppedImage, on side: CardSide) {
        guard case .card = editing, let image = imageComingIn(dropped) else { return }
        editedImages[side] = image.name
        showFiles()
    }

    /// Removes the image on `side` of the card the user edits, which Save then
    /// takes away from the card.
    public mutating func removeImageFromEditor(on side: CardSide) {
        guard case .card = editing else { return }
        editedImages[side] = nil
        showFiles()
    }

    /// The image `dropped` brings, shrunk and held until a card that has it
    /// is saved, or nil when it isn't an image, or its file can't be read,
    /// which the window records.
    private mutating func imageComingIn(_ dropped: DroppedImage) -> CardImage? {
        var image: CardImage?
        perform(.putImage) { _ throws(EngineError) in
            switch dropped {
            case .file(let file):
                let data: Data
                do {
                    data = try Data(contentsOf: file)
                } catch {
                    logger.error("Couldn't read a file dropped for an image: \(String(describing: error))")
                    throw .unreadableFileForSide(file.lastPathComponent)
                }
                image = try CardImage(shrinking: data)
            case .data(let data):
                image = try CardImage(shrinking: data)
            }
        }
        if let image {
            images.hold(image)
        }
        return image
    }

    /// The images and sounds on `content`'s sides that came in and aren't
    /// kept yet, which saving it keeps.
    func heldFiles(of content: CardContent) -> HeldFiles {
        HeldFiles(images: images.held(among: content.images), sounds: sounds.held(among: content.sounds))
    }

    /// Shows the images and sounds of the card the detail shows, of the card
    /// the user edits and of the card the form makes, and lets go of the
    /// others.
    mutating func showFiles() {
        var names = Set<ImageName>()
        if case .card(let row, _) = detail {
            names.formUnion(row.card.images)
        }
        if case .card = editing {
            names.formUnion(editedImages.all)
        }
        for form in [cardForm, setAsideCardForm].compactMap(\.self) {
            names.formUnion([form.draft.front.image, form.draft.back.image].compactMap(\.self))
        }
        images.show(names, readingWith: engine)
        showSounds()
    }
}

/// The images and sounds that came in for a card and aren't kept yet, which
/// saving it keeps.
struct HeldFiles {
    let images: [CardImage]
    let sounds: [CardSound]
}

extension Engine {
    /// Creates a card with `content`, as `create(_:bothWays:from:)` does, once
    /// the images and sounds `held` for it are kept. When the card can't be
    /// created, those no card uses go again.
    @discardableResult
    func create(keeping held: HeldFiles, _ content: CardContent, bothWays: Bool, from captureID: Int64?)
        throws(EngineError) -> Card
    {
        try keeping(held) { () throws(EngineError) in try create(content, bothWays: bothWays, from: captureID) }
    }

    /// Edits a card with `content`, as `edit(_:with:bothWays:)` does, once the
    /// images and sounds `held` for it are kept. When the card can't be
    /// edited, those no card uses go again.
    @discardableResult
    func edit(_ cardID: Int64, keeping held: HeldFiles, with content: CardContent, bothWays: Bool)
        throws(EngineError) -> Card
    {
        try keeping(held) { () throws(EngineError) in try edit(cardID, with: content, bothWays: bothWays) }
    }

    /// Keeps the images and sounds `held`, then does `work`, and when either
    /// fails, removes those of them no card uses.
    func keeping<Value>(_ held: HeldFiles, _ work: () throws(EngineError) -> Value) throws(EngineError)
        -> Value
    {
        do throws(EngineError) {
            for image in held.images {
                try keepImage(image)
            }
            for sound in held.sounds {
                try keepSound(sound)
            }
            return try work()
        } catch {
            removeFilesNoCardUses(images: Set(held.images.map(\.name)), sounds: Set(held.sounds.map(\.name)))
            throw error
        }
    }
}
