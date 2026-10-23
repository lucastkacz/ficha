import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the Cards window's form, which creates cards: from New Card, or
/// from a capture in the inbox with Convert to Card, on the default ladder.
struct CardFormTests {
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

    @Test("Add is off while a side is blank")
    func addIsOffWhileASideIsBlank() throws {
        var window = openWindow()
        window.openNewCardForm()
        let opened = try #require(window.cardForm)

        window.type(front: "petricor")
        let withFrontOnly = window.cardForm?.canAdd
        window.type(front: "  ", back: "El olor de la lluvia.")
        let withBlankFront = window.cardForm?.canAdd
        window.type(front: "petricor", back: "El olor de la lluvia.")
        let withBothSides = window.cardForm?.canAdd

        #expect(!opened.canAdd)
        #expect(withFrontOnly == false)
        #expect(withBlankFront == false)
        #expect(withBothSides == true)
        window.addCard()
        #expect(try engine.cards().map(\.front) == ["petricor"])
    }

    // So that the next card on the same subject is quick, as in Anki.
    @Test("after Add, the front and back are empty and the type, tags and source stay")
    func afterAddTheSidesAreEmptyAndTheRestStays() throws {
        var window = openWindow()
        window.openNewCardForm()
        window.type(front: "petricor", back: "El olor de la lluvia.", tags: "lenguaje, ciencia", source: "Un podcast")
        window.choose(type: .word)

        window.addCard()

        let added = try #require(try engine.cards().first)
        #expect(added.type == .word)
        #expect(added.front == "petricor")
        #expect(added.tags == ["lenguaje", "ciencia"])
        #expect(added.source == "Un podcast")
        #expect(added.captureID == nil)
        #expect(try engine.reviewNow(.defaults) == [.firstView(added)])
        let draft = try #require(window.cardForm?.draft)
        #expect(draft.front.text == "")
        #expect(draft.back.text == "")
        #expect(draft.type == .word)
        #expect(draft.tags == "lenguaje, ciencia")
        #expect(draft.source == "Un podcast")
        #expect(window.cardForm?.addedCards == [added])
        #expect(window.cardForm?.canAdd == false)
        #expect(window.listedCardIDs == [added.id])
    }

    // Add stays on, to keep a duplicate on purpose, like the same word with
    // another meaning.
    @Test("the warning names the card a front repeats and goes when the front changes")
    func theWarningNamesTheCardAFrontRepeats() throws {
        try approveCard("serendipia", in: engine)
        let anio = try engine.create(card(nil, front: "Año", back: "Doce meses."))
        var window = openWindow()
        window.openNewCardForm()

        window.type(front: " año ", back: "Otro significado.")
        let warned = window.cardForm?.frontWarning
        let canAddWarned = window.cardForm?.canAdd
        window.type(front: "ano")
        let changed = window.cardForm?.frontWarning
        window.type(front: "año")
        window.addCard()
        let afterAdd = window.cardForm?.frontWarning

        #expect(warned == .repeats(anio))
        #expect(canAddWarned == true)
        #expect(changed == nil)
        #expect(afterAdd == nil)
        #expect(try engine.cards().map(\.front) == ["serendipia", "Año", "año"])
    }

    @Test("the form from a capture shows its text, note and source, with the source filled in")
    func theFormFromACaptureShowsIt() throws {
        let capture = try engine.newCapture(
            "Ubuntu: soy porque somos", note: "Buscar de dónde viene", source: "Un discurso de Mandela")
        var window = openWindow()
        window.choose(.inbox)
        window.selectInInbox(.capture(capture.id))
        #expect(window.actions == [.edit, .convertToCard, .discard])

        window.convertToCard()

        let form = try #require(window.cardForm)
        #expect(form.capture == capture)
        #expect(form.draft.source == "Un discurso de Mandela")
        #expect(form.draft.front.text == "")
        #expect(form.draft.back.text == "")
        #expect(form.draft.type == nil)
        #expect(form.draft.tags == "")
    }

    @Test(
        "closing the form from a capture after adding cards takes it out of the inbox, and closing with none leaves it")
    func closingTheFormFromACaptureApprovesItOnlyAfterCards() throws {
        let ubuntu = try engine.newCapture("Ubuntu: soy porque somos")
        let bostezo = try engine.newCapture("¿Por qué bostezamos?")
        var window = openWindow()
        window.choose(.inbox)
        window.selectInInbox(.capture(ubuntu.id))
        window.convertToCard()
        window.type(front: "ubuntu", back: "Soy porque somos.")
        window.addCard()
        window.type(front: "¿Qué quiere decir «ubuntu»?", back: "Soy porque somos.")
        window.addCard()
        let inboxWhileOpen = try engine.inbox().captures

        window.closeCardForm()
        window.selectInInbox(.capture(bostezo.id))
        window.convertToCard()
        window.closeCardForm()

        #expect(inboxWhileOpen == [ubuntu, bostezo])
        #expect(window.cardForm == nil)
        #expect(window.failure == nil)
        #expect(try engine.cards().map(\.captureID) == [ubuntu.id, ubuntu.id])
        #expect(try engine.inbox().captures == [bostezo])
    }

    // So that what was typed isn't lost.
    @Test(
        "showing the card a front repeats sets the form aside and selects the card where the sidebar lists it, scrolled to, and New Card brings the form back as it was"
    )
    func showingTheRepeatedCardSelectsIt() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ataraxia = try approveCard("ataraxia", in: engine)
        try engine.bury(ataraxia.id)
        var window = openWindow()
        window.choose(.cards(.due))
        window.search(for: "algo")

        window.openNewCardForm()
        window.type(front: "Serendipia", back: "Un hallazgo por casualidad.")
        window.putImageInForm(.data(try picture(width: 800, height: 600)), on: .back)
        window.showRepeatedCard()
        let shownFirst = (window.sidebarItem, window.search, window.selectedRows.map(\.id), window.cardForm)
        let revealedFirst = window.cardToReveal
        // The table scrolled to it.
        window.cardRevealed()
        window.openNewCardForm()
        let broughtBack = try #require(window.cardForm)
        window.type(front: "ataraxia")
        window.showRepeatedCard()

        #expect(shownFirst.0 == .cards(.all))
        #expect(shownFirst.1 == "")
        #expect(shownFirst.2 == [serendipia.id])
        #expect(shownFirst.3 == nil)
        #expect(revealedFirst == serendipia.id)
        #expect(broughtBack.draft.front.text == "Serendipia")
        #expect(broughtBack.draft.back.text == "Un hallazgo por casualidad.")
        #expect(broughtBack.frontWarning == .repeats(serendipia))
        let image = try #require(broughtBack.draft.back.image)
        #expect(try window.images[image]?.get() != nil)
        #expect(window.sidebarItem == .cards(.buried))
        #expect(window.selectedRows.map(\.id) == [ataraxia.id])
        #expect(window.cardToReveal == ataraxia.id)
    }

    @Test(
        "a form from a capture that Show Card set aside comes back with Convert to Card, and approves the capture only once it closes"
    )
    func aFormFromACaptureSetAsideApprovesItOnlyOnceItCloses() throws {
        try approveCard("serendipia", in: engine)
        let capture = try engine.newCapture("Serendipia: un hallazgo por casualidad")
        var window = openWindow()
        window.choose(.inbox)
        window.selectInInbox(.capture(capture.id))
        window.convertToCard()
        window.type(front: "hallazgo", back: "Lo que se encuentra.")
        window.addCard()
        window.type(front: "serendipia", back: "Un hallazgo por casualidad.")

        window.showRepeatedCard()
        let inboxWhileSetAside = try engine.inbox().captures
        window.choose(.inbox)
        window.selectInInbox(.capture(capture.id))
        window.convertToCard()
        let broughtBack = window.cardForm
        window.showRepeatedCard()
        // A new card's form: the one set aside closes first.
        window.openNewCardForm()

        #expect(inboxWhileSetAside == [capture])
        #expect(broughtBack?.capture == capture)
        #expect(broughtBack?.addedCards.map(\.front) == ["hallazgo"])
        #expect(broughtBack?.draft.front.text == "serendipia")
        #expect(window.cardForm?.capture == nil)
        #expect(window.cardForm?.draft.front.text == "")
        #expect(try engine.inbox().captures == [])
    }

    @Test("Add from a capture that left the inbox meanwhile saves nothing, records why and keeps the fields")
    func addFromACaptureThatLeftTheInboxSavesNothing() throws {
        let capture = try engine.newCapture("Ubuntu: soy porque somos")
        var window = openWindow()
        window.choose(.inbox)
        window.selectInInbox(.capture(capture.id))
        window.convertToCard()
        window.type(front: "ubuntu", back: "Soy porque somos.")
        // Discarded in a refine session, while the form is open.
        try engine.discard(capture.id)

        window.addCard()

        #expect(window.failure?.action == .addCard)
        #expect(window.failure?.error == .captureNotInInbox(capture.id))
        #expect(window.cardForm?.draft.front.text == "ubuntu")
        #expect(window.cardForm?.addedCards == [])
        #expect(try engine.cards().isEmpty)
    }
}

extension CardsWindowState {
    /// Types into the form's fields, in place of what they held, as Lucas
    /// would, leaving alone each field whose text is nil.
    fileprivate mutating func type(
        front: String? = nil, back: String? = nil, tags: String? = nil, source: String? = nil
    ) {
        guard var draft = cardForm?.draft else { return }
        draft.front.text = front ?? draft.front.text
        draft.back.text = back ?? draft.back.text
        draft.tags = tags ?? draft.tags
        draft.source = source ?? draft.source
        changeDraft(draft)
    }

    /// Picks `type` in the form's type picker, or None when it's nil.
    fileprivate mutating func choose(type: CardType?) {
        guard var draft = cardForm?.draft else { return }
        draft.type = type
        changeDraft(draft)
    }

    /// The ids of the cards the table lists, or nil when it lists the inbox
    /// or couldn't read them.
    fileprivate var listedCardIDs: [Int64]? {
        guard case .success(.cards(let rows)) = listing else {
            return nil
        }
        return rows.map(\.id)
    }
}
