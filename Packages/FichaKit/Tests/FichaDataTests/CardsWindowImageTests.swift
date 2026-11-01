import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on images in the Cards window: the card form and the card editor
/// put an image on a side, dragged or pasted, replace it or remove it, and
/// the detail shows a card's images, on the default scheduler.
struct CardsWindowImageTests {
    let time = ManualTimeSource(now: Date(timeIntervalSince1970: 1_760_000_000))
    let engine: Engine
    let scheduler = ReviewSettings.defaults.scheduler

    init() throws {
        engine = try Engine(location: .inMemory, time: time)
    }

    /// Opens the Cards window and reads the cards, as the window does once
    /// it listens for the reasons to read them again.
    private func openWindow() -> CardsWindowState {
        var window = engine.openCardsWindow(with: scheduler)
        window.read(with: scheduler)
        return window
    }

    @Test("a side with only an image turns Add on; removing it turns it off again")
    func aSideWithOnlyAnImageTurnsAddOn() throws {
        var window = openWindow()
        window.openNewCardForm()
        window.typeInForm(back: "Un hornero.")

        window.putImageInForm(.data(try picture(width: 800, height: 600)), on: .front)
        let withImage = try #require(window.cardForm)
        window.removeImageFromForm(on: .front)
        let withoutImage = try #require(window.cardForm)

        #expect(withImage.canAdd)
        #expect(!withoutImage.canAdd)
        #expect(withoutImage.draft.front.image == nil)
    }

    @Test("Add saves the images on the form's sides, which Ficha keeps from then on, and clears them for the next card")
    func addSavesTheImagesOnTheSides() throws {
        var window = openWindow()
        window.openNewCardForm()
        window.typeInForm(front: "¿Qué pájaro es?", back: "Un hornero.")
        window.putImageInForm(.data(try picture(width: 800, height: 600, red: 0.8)), on: .front)
        window.putImageInForm(.data(try picture(width: 800, height: 600, red: 0.1)), on: .back)
        // Dropping another image on a side replaces its image.
        window.putImageInForm(.data(try picture(width: 3000, height: 2000, red: 0.3)), on: .back)
        let bird = try #require(window.cardForm?.draft.front.image)
        let nest = try #require(window.cardForm?.draft.back.image)
        let shownBird = try #require(try window.images[bird]?.get())
        let notKeptYet = Result { try engine.image(bird) }

        window.addCard()

        let added = try #require(try engine.cards().first)
        #expect(added.frontImage == bird)
        #expect(added.backImage == nest)
        #expect(throws: EngineError.imagesFolder) { try notKeptYet.get() }
        #expect(try engine.image(bird) == shownBird)
        #expect(try pixelSize(of: engine.image(nest)) == (1600, 1067))
        #expect(window.cardForm?.draft.front.image == nil)
        #expect(window.cardForm?.draft.back.image == nil)
        #expect(window.images[bird] == nil)
    }

    @Test("what isn't an image stays off the side, and the window says why")
    func whatIsntAnImageStaysOff() throws {
        var window = openWindow()
        window.openNewCardForm()
        window.typeInForm(front: "¿Qué pájaro es?", back: "Un hornero.")

        window.putImageInForm(.data(Data("hornero.txt".utf8)), on: .front)

        #expect(window.cardForm?.draft.front.image == nil)
        #expect(window.failure?.action == .putImage)
        #expect(window.failure?.error == .notAnImage)
    }

    @Test("an image file dropped on a side comes in, and one that can't be read stays off, and the window names it")
    func anImageFileComesIn() throws {
        let folder = URL.temporaryDirectory.appending(
            path: "FichaCardsWindowImageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let nest = folder.appending(path: "nido.jpg")
        try picture(width: 800, height: 600).write(to: nest)
        var window = openWindow()
        window.openNewCardForm()
        window.typeInForm(back: "Un hornero.")

        window.putImageInForm(.file(nest), on: .front)
        // Gone from its folder before it was read.
        window.putImageInForm(.file(folder.appending(path: "hornero.jpg")), on: .back)

        #expect(window.cardForm?.draft.front.image != nil)
        #expect(window.cardForm?.draft.back.image == nil)
        #expect(window.failure?.action == .putImage)
        #expect(window.failure?.error == .unreadableFileForSide("hornero.jpg"))
    }

    @Test(
        "an image a browser drags comes in as its data, though the drag also holds its web address and a promised file")
    func anImageABrowserDragsComesIn() throws {
        let png = try picture(width: 800, height: 600)
        // The types Safari's drag of a PNG on a web page held, in its order
        // (#229), each with data of its kind.
        let fromSafari = Dragged([
            ("dyn.ah62d4rv4gu8yc6durvwwa3xmrvw1gkdusm1044pxqyuha2pxsvw0e55bsmwca7d3sbwu", Data("bplist00".utf8)),
            ("public.png", png),
            ("com.apple.WebKit.custom-pasteboard-data", Data("https://aves.example".utf8)),
            ("public.tiff", Data("MM".utf8)),
            ("public.url", Data("https://aves.example/hornero.png".utf8)),
            ("public.url-name", Data("hornero.png".utf8)),
            ("public.utf8-plain-text", Data("https://aves.example/hornero.png".utf8)),
            ("com.apple.webarchive", Data("bplist00".utf8)),
            ("com.apple.pasteboard.promised-file-content-type", Data("public.png".utf8)),
            ("com.apple.pasteboard.promised-file-url", Data()),
        ])

        #expect(DroppedImage(pasteboardItems: [fromSafari]) == .data(png))
    }

    @Test(
        "a file Finder drags comes in as the file, and a web address alone brings no image, which the window refuses")
    func aFileComesInAndAWebAddressDoesNot() throws {
        let nest = URL(filePath: "/Users/lucas/Pictures/nido.jpg")
        let fromFinder = Dragged([
            ("public.file-url", nest.dataRepresentation), ("public.utf8-plain-text", Data("nido.jpg".utf8)),
        ])
        let webAddress = Data("https://aves.example/hornero.png".utf8)
        let fromABrowsersBar = Dragged([("public.url", webAddress), ("public.utf8-plain-text", webAddress)])
        var window = openWindow()
        window.openNewCardForm()

        let file = DroppedImage(pasteboardItems: [fromABrowsersBar, fromFinder])
        let none = DroppedImage(pasteboardItems: [fromABrowsersBar])
        window.putImageInForm(none, on: .front)

        #expect(file == .file(nest))
        #expect(window.cardForm?.draft.front.image == nil)
        #expect(window.failure?.error == .notAnImage)
    }

    @Test("⌘V in a side's text brings a copied image or an image's file only while the clipboard holds no text")
    func pastingIntoASidesTextBringsAnImageWithoutText() throws {
        let png = try picture(width: 800, height: 600)
        let screenshot = Dragged([("public.png", png)])
        let fromFinder = Dragged([
            ("public.file-url", URL(filePath: "/Users/lucas/Pictures/nido.jpg").dataRepresentation),
            ("public.utf8-plain-text", Data("nido.jpg".utf8)),
        ])
        let words = Dragged([("public.utf8-plain-text", Data("petricor".utf8))])
        let webAddress = Dragged([("public.url", Data("https://aves.example/hornero.png".utf8))])
        let nest = URL(filePath: "/Users/lucas/Pictures/nido.jpg")
        let song = URL(filePath: "/Users/lucas/Music/zamba.m4a")

        #expect(DroppedImage(pastedIntoText: [screenshot]) == .data(png))
        #expect(DroppedImage(pastedIntoText: [fromFinder]) == nil)
        #expect(DroppedImage(pastedIntoText: [words, screenshot]) == nil)
        #expect(DroppedImage(pastedIntoText: [webAddress]) == nil)
        #expect(DroppedImage(pastedIntoText: [Dragged([("public.file-url", nest.dataRepresentation)])]) == .file(nest))
        #expect(DroppedImage(pastedIntoText: [Dragged([("public.file-url", song.dataRepresentation)])]) == nil)
    }

    @Test("the detail shows the selected card's images")
    func theDetailShowsTheCardsImages() throws {
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let hornero = try engine.create(card(nil, front: "", back: "Un hornero.", frontImage: bird))
        try engine.create(card(nil, front: "petricor", back: "El olor de la lluvia."))
        var window = openWindow()

        window.select([hornero.id])

        #expect(try window.images[bird]?.get() == engine.image(bird))
    }

    @Test("Save gives the edited card the images put on it, replaced or removed, and Cancel leaves it as it was")
    func editingACardChangesItsImages() throws {
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let nest = try engine.addImage(picture(width: 800, height: 600, red: 0.3))
        let hornero = try engine.create(
            card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird, backImage: nest))
        var window = openWindow()
        window.select([hornero.id])

        window.startEditing()
        window.removeImageFromEditor(on: .front)
        window.cancelEditing()
        window.startEditing()
        let editing = window.editedImages
        window.putImageInEditor(.data(try picture(width: 800, height: 600, red: 0.1)), on: .front)
        window.removeImageFromEditor(on: .back)
        let egg = try #require(window.editedImages.front)
        window.saveCard(
            try card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: egg, backImage: nil))

        #expect(editing.front == bird && editing.back == nest)
        let edited = try #require(try engine.cards().first)
        #expect(edited.frontImage == egg)
        #expect(edited.backImage == nil)
        #expect(window.editing == nil)
        #expect(try window.images[egg]?.get() == engine.image(egg))
        #expect(window.images[bird] == nil)
    }
}

extension CardsWindowState {
    /// Types into the form's sides, in place of what they held, as the user
    /// would, leaving alone each side whose text is nil.
    mutating func typeInForm(front: String? = nil, back: String? = nil) {
        guard var draft = cardForm?.draft else { return }
        draft.front.text = front ?? draft.front.text
        draft.back.text = back ?? draft.back.text
        changeDraft(draft)
    }
}

/// An item of a drag's or a paste's pasteboard, made by hand: its types, in
/// the order its source wrote them, each with its data.
private struct Dragged: PasteboardItem {
    let contents: [(type: String, data: Data)]

    init(_ contents: [(type: String, data: Data)]) {
        self.contents = contents
    }

    var typeIdentifiers: [String] {
        contents.map(\.type)
    }

    func data(ofType type: String) -> Data? {
        contents.first { $0.type == type }?.data
    }
}
