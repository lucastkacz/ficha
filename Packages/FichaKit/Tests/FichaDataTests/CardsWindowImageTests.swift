import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on images in the Cards window: the card form and the card editor
/// put an image on a side, dragged or pasted, replace it or remove it, and
/// the detail shows a card's images, on the default ladder.
struct CardsWindowImageTests {
    let time = ManualTimeSource(now: Date(timeIntervalSince1970: 1_760_000_000))
    let engine: Engine
    let ladder = ReviewSettings.defaults.ladder

    init() throws {
        engine = try Engine(location: .inMemory, time: time)
    }

    /// Opens the Cards window and reads the cards, as the window does once
    /// it listens for the reasons to read them again.
    private func openWindow() -> CardsWindowState {
        var window = engine.openCardsWindow(on: ladder)
        window.read(on: ladder)
        return window
    }

    @Test("a side with only an image turns Add on; removing it turns it off again")
    func aSideWithOnlyAnImageTurnsAddOn() throws {
        var window = openWindow()
        window.openNewCardForm()
        window.typeInForm(back: "Un hornero.")

        window.putImageInForm(try picture(width: 800, height: 600), on: .front)
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
        window.putImageInForm(try picture(width: 800, height: 600, red: 0.8), on: .front)
        window.putImageInForm(try picture(width: 800, height: 600, red: 0.1), on: .back)
        // Dropping another image on a side replaces its image.
        window.putImageInForm(try picture(width: 3000, height: 2000, red: 0.3), on: .back)
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

        window.putImageInForm(Data("hornero.txt".utf8), on: .front)

        #expect(window.cardForm?.draft.front.image == nil)
        #expect(window.failure?.action == .putImage)
        #expect(window.failure?.error == .notAnImage)
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
        window.putImageInEditor(try picture(width: 800, height: 600, red: 0.1), on: .front)
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
    /// Types into the form's sides, in place of what they held, as Lucas
    /// would, leaving alone each side whose text is nil.
    fileprivate mutating func typeInForm(front: String? = nil, back: String? = nil) {
        guard var draft = cardForm?.draft else { return }
        draft.front.text = front ?? draft.front.text
        draft.back.text = back ?? draft.back.text
        changeDraft(draft)
    }
}
