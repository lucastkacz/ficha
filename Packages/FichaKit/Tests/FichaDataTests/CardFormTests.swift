import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the Cards window's form, which creates cards: from New Card, or
/// from a capture in the inbox with Convert to Card, on the default scheduler.
struct CardFormTests {
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

    // So that the next card on the same subject is quick, as in Anki. The
    // form shows no tags and no type, so the card it adds has neither (#538).
    @Test("after Add, the front and back are empty and the source stays, and the card has no tags and no type")
    func afterAddTheSidesAreEmptyAndTheRestStays() throws {
        var window = openWindow()
        window.openNewCardForm()
        window.type(front: "petricor", back: "El olor de la lluvia.", source: "Un podcast")

        window.addCard()

        let added = try #require(try engine.cards().first)
        #expect(added.type == nil)
        #expect(added.front == "petricor")
        #expect(added.tags == [])
        #expect(added.source == "Un podcast")
        #expect(added.captureID == nil)
        #expect(try engine.reviewNow(.defaults) == [.new(added)])
        let draft = try #require(window.cardForm?.draft)
        #expect(draft.front.text == "")
        #expect(draft.back.text == "")
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

    // So that typing doesn't read every card's front at each key.
    @Test("the warning checks the front against the cards as the window last read them")
    func theWarningChecksTheCardsAsLastRead() throws {
        var window = openWindow()
        window.openNewCardForm()
        window.type(front: "petricor", back: "El olor de la lluvia.")
        // From the command line, while the form is open.
        let petricor = try engine.create(card(nil, front: "Petricor", back: "Olor a tierra mojada."))

        window.type(front: "petricor ")
        let typedBeforeReading = window.cardForm?.frontWarning
        window.read(with: scheduler)

        #expect(typedBeforeReading == nil)
        #expect(window.cardForm?.frontWarning == .repeats(petricor))
    }

    // As the source does, so that several words in a row go both ways.
    @Test("Both ways is off for a new card, Add saves the card going the way it says, and it stays for the next card")
    func bothWaysIsOffForANewCardAndStaysAfterAdd() throws {
        var window = openWindow()
        window.openNewCardForm()
        let opened = try #require(window.cardForm)
        window.type(front: "petricor", back: "El olor de la lluvia.")
        window.addCard()

        window.switchBothWays(true)
        window.type(front: "coloratura", back: "Los adornos rápidos del canto.")
        window.addCard()

        #expect(!opened.draft.bothWays)
        #expect(try engine.cards().map(\.bothWays) == [false, true])
        #expect(window.cardForm?.draft.bothWays == true)
    }

    @Test("the form from a capture starts with Both ways off, and a card added with it on goes both ways")
    func theFormFromACaptureStartsWithBothWaysOff() throws {
        let capture = try engine.newCapture("coloratura", source: "Una ópera de Mozart")
        var window = openWindow()
        window.openNewCardForm()
        window.switchBothWays(true)
        window.closeCardForm()
        window.choose(.inbox)
        window.selectInInbox(.capture(capture.id))

        window.convertToCard()
        let opened = try #require(window.cardForm)
        window.type(front: "coloratura", back: "Los adornos rápidos del canto.")
        window.switchBothWays(true)
        window.addCard()

        #expect(!opened.draft.bothWays)
        let added = try #require(try engine.cards().first)
        #expect(added.bothWays)
        #expect(added.captureID == capture.id)
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

    @Test("Convert to Card on a follow-up opens the form beside the follow-up and its card, in the card's deck")
    func theFormFromAFollowUpShowsItsCard() throws {
        let poderes = try approve(
            card(
                .concept, front: "La división de poderes en la Argentina",
                back: "Ejecutivo, Legislativo y Judicial.", tags: ["política", "argentina"],
                source: "La Constitución Nacional"),
            in: engine)
        let followUp = try engine.followUp(poderes.id, text: "¿Cómo se eligen los jueces?")
        var window = openWindow()
        window.choose(.inbox)
        window.selectInInbox(.capture(followUp.id))

        window.convertToCard()

        let form = try #require(window.cardForm)
        #expect(form.capture == followUp)
        #expect(form.followUp?.capture == followUp)
        #expect(form.followUp?.card == poderes)
        #expect(form.draft.deck == poderes.deck)
        #expect(form.draft.front.text == "")
        #expect(form.draft.back.text == "")
        #expect(form.draft.source == "")
    }

    @Test(
        "adding cards from a follow-up leaves its card as it is, and closing the form after them takes the follow-up out of the inbox"
    )
    func closingTheFormFromAFollowUpLeavesItsCard() throws {
        let poderes = try approve(
            card(
                .concept, front: "La división de poderes en la Argentina",
                back: "Ejecutivo, Legislativo y Judicial.", tags: ["política", "argentina"]),
            in: engine)
        try engine.climb(poderes, goods: 2, movingForward: time)
        let standing = try engine.standing(of: poderes.id, with: scheduler)
        let followUp = try engine.followUp(poderes.id, text: "¿Cómo se eligen los jueces?")
        var window = openWindow()
        window.choose(.inbox)
        window.selectInInbox(.capture(followUp.id))
        window.convertToCard()
        window.type(front: "¿Quién propone a los jueces de la Corte Suprema?", back: "El presidente.")
        window.addCard()
        window.type(front: "¿Quién aprueba a los jueces de la Corte Suprema?", back: "El Senado, con dos tercios.")
        window.addCard()
        let followUpsWhileOpen = try engine.inbox().followUps

        window.closeCardForm()

        let cards = try engine.cards()
        #expect(followUpsWhileOpen.map(\.capture) == [followUp])
        #expect(window.cardForm == nil)
        #expect(window.failure == nil)
        #expect(cards.first == poderes)
        #expect(try engine.standing(of: poderes.id, with: scheduler) == standing)
        #expect(
            cards.dropFirst().map(\.front) == [
                "¿Quién propone a los jueces de la Corte Suprema?", "¿Quién aprueba a los jueces de la Corte Suprema?",
            ])
        // The form shows no tags, so they don't take the card's (#538).
        #expect(cards.dropFirst().map(\.tags) == [[], []])
        #expect(cards.dropFirst().map(\.captureID) == [followUp.id, followUp.id])
        #expect(try engine.inbox().followUps.isEmpty)
        #expect(try engine.inbox().captures.isEmpty)
    }

    // A deck's grid lists a card just added at its end, which may be far
    // down it.
    @Test(
        "after Add, the grid selects the card added and scrolls to it while it lists it, and a card added to a deck it doesn't list leaves the selection as it was",
        .bug(id: 536))
    func addSelectsTheCardAddedAndScrollsToIt() throws {
        let ojala = try engine.create(card(nil, front: "ojalá", back: "Ojalá que llueva café."), deck: "Palabras")
        var window = openWindow()
        window.choose(.cards(.deck("Palabras")))
        window.clickTile(ojala.id, .alone)
        window.openNewCardForm()

        window.type(front: "petricor", back: "El olor de la lluvia.")
        window.addCard()
        let petricor = try #require(window.cardForm?.addedCards.last)
        let selectedOnAdding = window.selectedRows.map(\.id)
        let revealedOnAdding = window.cardToReveal
        // The grid scrolled to it.
        window.cardRevealed()
        var draft = try #require(window.cardForm?.draft)
        draft.deck = "Historia"
        window.changeDraft(draft)
        window.type(front: "Coliseo", back: "En Roma.")
        window.addCard()

        #expect(petricor.deck == "Palabras")
        #expect(selectedOnAdding == [petricor.id])
        #expect(revealedOnAdding == petricor.id)
        #expect(try engine.cards().map(\.front) == ["ojalá", "petricor", "Coliseo"])
        #expect(window.listedCardIDs == [ojala.id, petricor.id])
        #expect(window.selectedRows.map(\.id) == [petricor.id])
        #expect(window.cardToReveal == nil)
    }

    // So that what was typed isn't lost.
    @Test(
        "showing the card a front repeats sets the form aside and selects the card in its deck, scrolled to, and New Card brings the form back as it was",
        .bug(id: 536))
    func showingTheRepeatedCardSelectsIt() throws {
        let serendipia = try approveInDeck("serendipia", deck: "Palabras", in: engine)
        let ataraxia = try approveCard("ataraxia", in: engine)
        var window = openWindow()
        window.search(for: "algo")

        window.openNewCardForm()
        window.type(front: "Serendipia", back: "Un hallazgo por casualidad.")
        window.putImageInForm(.data(try picture(width: 800, height: 600)), on: .back)
        window.showRepeatedCard()
        let shownFirst = (window.sidebarItem, window.search, window.selectedRows.map(\.id), window.cardForm)
        let revealedFirst = window.cardToReveal
        // The grid scrolled to it.
        window.cardRevealed()
        window.openNewCardForm()
        let broughtBack = try #require(window.cardForm)
        window.type(front: "ataraxia")
        window.showRepeatedCard()

        #expect(shownFirst.0 == .cards(.deck("Palabras")))
        #expect(shownFirst.1 == "")
        #expect(shownFirst.2 == [serendipia.id])
        #expect(shownFirst.3 == nil)
        #expect(revealedFirst == serendipia.id)
        #expect(broughtBack.draft.front.text == "Serendipia")
        #expect(broughtBack.draft.back.text == "Un hallazgo por casualidad.")
        #expect(broughtBack.frontWarning == .repeats(serendipia))
        let image = try #require(broughtBack.draft.back.image)
        #expect(try window.images[image]?.get() != nil)
        #expect(window.sidebarItem == .cards(.deck(Deck.defaultName)))
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
    /// Types into the form's fields, in place of what they held, as the user
    /// would, leaving alone each field whose text is nil.
    fileprivate mutating func type(front: String? = nil, back: String? = nil, source: String? = nil) {
        guard var draft = cardForm?.draft else { return }
        draft.front.text = front ?? draft.front.text
        draft.back.text = back ?? draft.back.text
        draft.source = source ?? draft.source
        changeDraft(draft)
    }

    /// Turns the form's Both ways switch on, or off when `bothWays` is false.
    fileprivate mutating func switchBothWays(_ bothWays: Bool) {
        guard var draft = cardForm?.draft else { return }
        draft.bothWays = bothWays
        changeDraft(draft)
    }

    /// The ids of the cards the grid lists, or nil when it lists the inbox
    /// or couldn't read them.
    fileprivate var listedCardIDs: [Int64]? {
        guard case .success(.cards(let rows)) = listing else {
            return nil
        }
        return rows.map(\.id)
    }
}
