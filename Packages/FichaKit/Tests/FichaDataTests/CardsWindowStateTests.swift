import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the Cards window while it's open: what it lists, shows and offers
/// as Lucas chooses, searches and selects, and as it reads his cards again,
/// and what it asks and does as he acts, on the default ladder.
struct CardsWindowStateTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let ladder = ReviewSettings.defaults.ladder

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    /// Opens the Cards window and reads Lucas's cards, as the window does
    /// once it listens for the reasons to read them again.
    private func openWindow() -> CardsWindowState {
        var window = engine.openCardsWindow(on: ladder)
        window.read(on: ladder)
        return window
    }

    @Test("a tag that loses its last card sends the sidebar back to All cards")
    func aTagThatLosesItsLastCardSendsTheSidebarBackToAllCards() throws {
        let mayo = try approve(
            card(.concept, front: "Revolución de Mayo", back: "1810.", tags: ["historia"]), in: engine)
        let serendipia = try approveCard("serendipia", in: engine)
        var window = openWindow()
        window.choose(.cards(.tag("historia")))
        #expect(window.listedCardIDs == [mayo.id])

        try engine.delete([mayo.id])
        window.read(on: ladder)

        #expect(window.sidebarItem == .cards(.all))
        #expect(window.tags.isEmpty)
        #expect(window.listedCardIDs == [serendipia.id])
    }

    // So that Lucas can undo it, and a card that moves in later is set aside
    // too.
    @Test("a set-aside deck stays listed without cards, and choosing it lists no cards rather than All cards")
    func aSetAsideDeckStaysListedWithoutCards() throws {
        let mayo = try approveInDeck("Revolución de Mayo", deck: "Historia", in: engine)
        try approveCard("serendipia", in: engine)
        var window = openWindow()
        window.chooseSetAside(onDeck: "Historia")
        window.choose(.cards(.deck("Historia")))

        try engine.delete([mayo.id])
        window.read(on: ladder)

        #expect(window.deckRows.map(\.id) == [Deck.defaultName, "Historia"])
        #expect(window.menu(forDeck: "Historia")?.isSetAsideTicked == true)
        #expect(window.sidebarItem == .cards(.deck("Historia")))
        #expect(window.listedCardIDs == [])
    }

    @Test("the Color submenu offers None and Finder's seven colors, and ticks the tag's color, or None")
    func theColorSubmenuTicksTheTagsColorOrNone() throws {
        try approve(card(.word, front: "fotosíntesis", back: "Luz en azúcar.", tags: ["ciencia"]), in: engine)
        var window = openWindow()
        let colors: [TagColor?] = [nil, .red, .orange, .yellow, .green, .blue, .purple, .gray]
        #expect(window.menu(for: ["ciencia"])?.colorItems.map(\.color) == colors)
        #expect(window.menu(for: ["ciencia"])?.colorItems.filter(\.isTicked).map(\.color) == [nil])

        window.chooseColor(.green, on: ["ciencia"])

        #expect(window.menu(for: ["ciencia"])?.colorItems.filter(\.isTicked).map(\.color) == [.green])
        #expect(window.tags == [CardTag(name: "ciencia", color: .green)])
        window.chooseColor(nil, on: ["ciencia"])
        #expect(window.menu(for: ["ciencia"])?.colorItems.filter(\.isTicked).map(\.color) == [nil])
        #expect(window.tags == [CardTag(name: "ciencia")])
    }

    // The sheet says why while OK refuses, so nothing fails.
    @Test("the emoji sheet refuses what isn't one emoji, and takes an empty field as removing the tag's emoji")
    func theEmojiSheetRefusesWhatIsntOneEmoji() throws {
        try approve(card(.concept, front: "Revolución de Mayo", back: "1810.", tags: ["argentina"]), in: engine)
        var window = openWindow()
        window.askForEmoji(on: "argentina")
        #expect(window.question == .emoji(CardTag(name: "argentina")))
        #expect(window.emojiEntry("argentina") == .refused(.notOneEmoji))
        #expect(window.emojiEntry("🇦🇷🇺🇾") == .refused(.notOneEmoji))
        #expect(window.emojiEntry(" ") == .removal)
        #expect(window.emojiEntry("🇦🇷") == .emoji(try Emoji("🇦🇷")))

        window.chooseEmoji("argentina")
        #expect(window.question == .emoji(CardTag(name: "argentina")))
        #expect(window.failure == nil)
        window.chooseEmoji("🇦🇷")
        #expect(window.question == nil)
        #expect(window.tags == [CardTag(name: "argentina", emoji: "🇦🇷")])

        window.askForEmoji(on: "argentina")
        #expect(window.question == .emoji(CardTag(name: "argentina", emoji: "🇦🇷")))
        window.chooseEmoji("")
        #expect(window.question == nil)
        #expect(window.tags == [CardTag(name: "argentina")])
    }

    @Test("New, Due and Learned leave set-aside cards out, while All cards, the deck's group and a tag's hold them")
    func newDueAndLearnedLeaveSetAsideCardsOut() throws {
        // eudaimonía gets to the 30-day step, from which a card is learned,
        // and comes due there; ataraxia is new.
        let eudaimonia = try approveInDeck("eudaimonía", deck: "Filosofía", tags: ["ética"], in: engine)
        let ataraxia = try approveInDeck("ataraxia", deck: "Filosofía", tags: ["ética"], in: engine)
        try engine.climb(eudaimonia, to: 5, movingForward: time)
        time.advance(by: days(30))
        var window = openWindow()
        window.chooseSetAside(onDeck: "Filosofía")

        for group in [CardGroup.new, .due, .learned] {
            window.choose(.cards(group))
            #expect(window.listedCardIDs == [], "\(group)")
        }
        for group in [CardGroup.all, .deck("Filosofía"), .tag("ética")] {
            window.choose(.cards(group))
            #expect(window.listedCardIDs == [eudaimonia.id, ataraxia.id], "\(group)")
        }
    }

    @Test("the Due column says a set-aside card is set aside, where its due time goes")
    func theDueColumnSaysASetAsideCardIsSetAside() throws {
        let eudaimonia = try approveInDeck("eudaimonía", deck: "Filosofía", in: engine)
        try engine.meet(eudaimonia)
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.meet(serendipia)
        var window = openWindow()

        window.chooseSetAside(onDeck: "Filosofía")

        let rows = try #require(window.listedCardRows)
        #expect(rows.map(\.frontFirst.dueColumn) == [.setAside, .due(time.now + hours(1))])
    }

    @Test("selected cards the table no longer lists are left out of the selected rows")
    func selectedCardsTheTableNoLongerListsAreLeftOut() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        var window = openWindow()
        window.select([serendipia.id, ubuntu.id])
        #expect(window.selectedRows.map(\.id) == [serendipia.id, ubuntu.id])

        window.search(for: "seren")

        #expect(window.selection == [serendipia.id, ubuntu.id])
        #expect(window.selectedRows.map(\.id) == [serendipia.id])
        #expect(window.shownCard?.row.id == serendipia.id)
    }

    @Test("selecting a flagged card in the inbox shows the card, with its review log, and offers what a card offers")
    func aFlaggedCardInTheInboxShowsAsTheCard() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.climb(ubuntu, to: 1, movingForward: time)
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        try engine.newCapture("¿Por qué bostezamos?")
        var window = openWindow()
        window.choose(.inbox)

        window.selectInInbox(.card(ubuntu.id))

        let shown = try #require(window.shownCard)
        #expect(window.selectedRows.map(\.id) == [ubuntu.id])
        #expect(shown.row.id == ubuntu.id)
        #expect(try shown.reviewLog?.get().map(\.entry.kind) == [.firstView, .review(.good)])
        #expect(window.actions == [.edit, .bury, .changeDeck, .delete])
    }

    @Test("selecting an expansion in the inbox shows it, with the card it expands, and offers Edit and Discard")
    func anExpansionInTheInboxOffersEditAndDiscard() throws {
        try approveCard("serendipia", in: engine)
        try engine.expand(text: "Serendipia", note: "También es una película", source: nil)
        let expansion = try #require(try engine.inbox().expansions.first)
        var window = openWindow()
        window.choose(.inbox)

        window.selectInInbox(.capture(expansion.capture.id))

        #expect(window.selectedRows.isEmpty)
        #expect(window.detail == .expansion(expansion))
        #expect(window.actions == [.edit, .discard])
    }

    @Test(
        "the inbox lists a follow-up with its card, among the rest by when it was added, and a search finds it by its text"
    )
    func theInboxListsAFollowUpWithItsCard() throws {
        let poderes = try approve(
            card(
                .concept, front: "La división de poderes en la Argentina",
                back: "Ejecutivo, Legislativo y Judicial.", tags: ["política", "argentina"]),
            in: engine)
        time.advance(by: hours(1))
        let navaja = try engine.newCapture("Navaja de Ockham")
        time.advance(by: hours(1))
        try engine.followUp(poderes.id, text: "¿Cómo se eligen los jueces?")
        time.advance(by: hours(1))
        let bostezo = try engine.newCapture("¿Por qué bostezamos?")
        let followUp = try #require(try engine.inbox().followUps.first)
        var window = openWindow()

        window.choose(.inbox)
        let listed = window.listedInboxRows
        window.search(for: "JUECES")

        #expect(followUp.card == poderes)
        #expect(listed?.map(\.item) == [.capture(bostezo), .followUp(followUp), .capture(navaja)])
        #expect(listed?.map(\.text) == ["¿Por qué bostezamos?", "¿Cómo se eligen los jueces?", "Navaja de Ockham"])
        #expect(window.listedInboxRows?.map(\.item) == [.followUp(followUp)])
    }

    @Test(
        "selecting a follow-up in the inbox shows it, with its card, and offers Edit, Convert to Card and Discard")
    func aFollowUpInTheInboxShowsItsCard() throws {
        let poderes = try approve(
            card(
                .concept, front: "La división de poderes en la Argentina",
                back: "Ejecutivo, Legislativo y Judicial.", tags: ["política", "argentina"]),
            in: engine)
        let saved = try engine.followUp(poderes.id, text: "¿Cómo se eligen los jueces?")
        var window = openWindow()
        window.choose(.inbox)

        window.selectInInbox(.capture(saved.id))

        let followUp = try #require(window.shownFollowUp)
        #expect(window.selectedRows.isEmpty)
        #expect(followUp.capture == saved)
        #expect(followUp.card == poderes)
        #expect(window.actions == [.edit, .convertToCard, .discard])
    }

    @Test("editing a follow-up keeps its card, and discarding it takes it out of the inbox")
    func editingAFollowUpKeepsItsCard() throws {
        let poderes = try approveCard("La división de poderes", in: engine)
        let followUp = try engine.followUp(poderes.id, text: "¿Cómo se eligen los jueces?")
        var window = openWindow()
        window.choose(.inbox)
        window.selectInInbox(.capture(followUp.id))

        window.startEditing()
        let editing = window.editing
        window.saveCapture(
            text: "¿Cómo se eligen los jueces de la Corte?", note: "Y quién los puede remover", source: "")
        let edited = window.shownFollowUp
        window.askToDiscard()
        let asked = window.question
        let toDiscard = try #require(edited?.capture)
        window.discard(toDiscard)
        // As the window does once the engine says the inbox changed.
        window.read(on: ladder)

        #expect(editing == .capture(followUp))
        #expect(edited?.capture.text == "¿Cómo se eligen los jueces de la Corte?")
        #expect(edited?.capture.note == "Y quién los puede remover")
        #expect(edited?.capture.followsUpCardID == poderes.id)
        #expect(edited?.card == poderes)
        #expect(asked == .discard(toDiscard))
        #expect(window.failure == nil)
        #expect(window.listedInboxRows == [])
        #expect(try engine.inbox().followUps.isEmpty)
        #expect(try engine.cards() == [poderes])
    }

    @Test("a follow-up whose card was deleted shows as a plain capture")
    func aFollowUpWhoseCardWasDeletedShowsAsACapture() throws {
        let poderes = try approveCard("La división de poderes", in: engine)
        let followUp = try engine.followUp(poderes.id, text: "¿Cómo se eligen los jueces?")
        var window = openWindow()
        window.select([poderes.id])
        window.askToDelete()
        window.delete(try #require(window.cardsToDelete))

        window.choose(.inbox)
        window.selectInInbox(.capture(followUp.id))

        let capture = try #require(try engine.inbox().captures.first)
        #expect(capture.text == "¿Cómo se eligen los jueces?")
        #expect(capture.followsUpCardID == nil)
        #expect(window.listedInboxRows?.map(\.item) == [.capture(capture)])
        #expect(window.detail == .capture(capture))
        #expect(window.actions == [.edit, .convertToCard, .discard])
    }

    // No group of the sidebar lists buried cards with others, so a selection
    // of both, which offers neither, can't be made here.
    @Test("Bury is offered while none of the selected cards is buried, and Unbury while all of them are")
    func buryAndUnburyAreOfferedForTheCardsTheyWorkOn() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let ojala = try approveCard("ojalá", in: engine)
        let acaso = try approveCard("acaso", in: engine)
        try engine.bury(ojala.id)
        try engine.bury(acaso.id)
        var window = openWindow()

        window.select([serendipia.id, ubuntu.id])
        let offeredInAllCards = window.actions
        window.choose(.cards(.buried))
        window.select([ojala.id, acaso.id])
        let offeredInBuried = window.actions

        #expect(offeredInAllCards == [.bury, .turnOnBothWays, .changeDeck, .delete])
        #expect(offeredInBuried == [.unbury, .turnOnBothWays, .changeDeck, .delete])
    }

    // So that a whole subject goes both ways from its tag, ⌘A and one click.
    @Test("several selected cards offer Turn On Both Ways while any goes one way, and Turn Off once all go both ways")
    func theSelectionTurnsBothWaysOnOrOff() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let petricor = try approveCard("petricor", in: engine)
        try engine.setBothWays(true, of: [ubuntu.id])
        var window = openWindow()

        window.select([ubuntu.id])
        let offeredForOne = window.actions
        window.select([serendipia.id, petricor.id])
        let offeredForOneWay = window.actions
        window.select([serendipia.id, ubuntu.id, petricor.id])
        let offeredForAMix = window.actions
        window.turnOnBothWays()
        let turnedOn = try engine.cards().map(\.bothWays)
        let offeredForBothWays = window.actions
        window.turnOffBothWays()

        #expect(offeredForOne == [.edit, .flag, .bury, .changeDeck, .delete])
        #expect(offeredForOneWay == [.bury, .turnOnBothWays, .changeDeck, .delete])
        #expect(offeredForAMix == [.bury, .turnOnBothWays, .changeDeck, .delete])
        #expect(turnedOn == [true, true, true])
        #expect(offeredForBothWays == [.bury, .turnOffBothWays, .changeDeck, .delete])
        #expect(try engine.cards().map(\.bothWays) == [false, false, false])
        #expect(window.actions == [.bury, .turnOnBothWays, .changeDeck, .delete])
    }

    // The Back-first step and Back-first due columns show `backFirst`, and
    // sort by it, empty ones last, in the app's `CardRowOrder`, since a
    // table's order stays in the app.
    @Test(
        "turning Both ways on gives the selected cards a back-first way, new, and turning it off takes it from the table, keeping its step"
    )
    func turningBothWaysOnAndOffFillsAndEmptiesTheBackFirstColumns() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try approveCard("petricor", in: engine)
        try engine.meet(serendipia)
        var window = openWindow()
        let before = try #require(window.listedCardRows).map(\.backFirst)

        window.select([serendipia.id, ubuntu.id])
        window.turnOnBothWays()
        let turnedOn = try #require(window.listedCardRows).map(\.backFirst?.standing)
        time.advance(by: minutes(10))
        try engine.meet(serendipia, way: .backFirst)
        let metBackFirstAt = time.now
        window.read(on: ladder)
        let metBackFirst = try #require(window.listedCardRows).map(\.backFirst?.standing)
        window.turnOffBothWays()
        let turnedOff = try #require(window.listedCardRows).map(\.backFirst)
        window.turnOnBothWays()

        #expect(before == [nil, nil, nil])
        #expect(turnedOn == [.new, .new, nil])
        #expect(metBackFirst == [.onLadder(step: 0, due: metBackFirstAt + hours(1)), .new, nil])
        #expect(turnedOff == [nil, nil, nil])
        #expect(
            try #require(window.listedCardRows).map(\.backFirst?.due) == [metBackFirstAt + hours(1), nil, nil])
    }

    @Test(
        "the detail shows a card's front-first and back-first ways, and its review log says which way each entry went")
    func theDetailShowsEachWayAndItsReviewLogsWays() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.setBothWays(true, of: [serendipia.id])
        try engine.meet(serendipia)
        try engine.meet(ubuntu)
        time.advance(by: minutes(10))
        try engine.meet(serendipia, way: .backFirst)
        try engine.reviewWhenDue(serendipia, .good, movingForward: time)
        var window = openWindow()

        window.select([serendipia.id])
        let shownBothWays = try #require(window.shownCard)
        window.select([ubuntu.id])
        let shownOneWay = try #require(window.shownCard)

        #expect(shownBothWays.row.frontFirst.standing == .onLadder(step: 1, due: time.now + hours(4)))
        #expect(shownBothWays.row.backFirst?.dueColumn == .due(time.now + minutes(10)))
        #expect(shownBothWays.row.backFirst?.step == 0)
        #expect(try shownBothWays.reviewLog?.get().map(\.entry.way) == [.frontFirst, .backFirst, .frontFirst])
        #expect(shownOneWay.row.backFirst == nil)
        #expect(try shownOneWay.reviewLog?.get().map(\.entry.way) == [.frontFirst])
    }

    @Test("Flag is offered only for a single card in Lucas's reviews")
    func flagIsOfferedOnlyForASingleCardInReviews() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        let ojala = try approveCard("ojalá", in: engine)
        let acaso = try approveCard("acaso", in: engine)
        try engine.flag(ojala.id, note: note("Falta un ejemplo"))
        try engine.bury(acaso.id)
        var window = openWindow()

        window.select([serendipia.id])
        let offeredForOne = window.actions.contains(.flag)
        window.select([serendipia.id, ubuntu.id])
        let offeredForTwo = window.actions.contains(.flag)
        window.select([ojala.id])
        let offeredForAFlaggedOne = window.actions.contains(.flag)
        window.choose(.cards(.buried))
        window.select([acaso.id])
        let offeredForABuriedOne = window.actions.contains(.flag)

        #expect(offeredForOne)
        #expect(!offeredForTwo)
        #expect(!offeredForAFlaggedOne)
        #expect(!offeredForABuriedOne)
    }

    @Test("Delete asks only about the selected cards the table lists")
    func deleteAsksOnlyAboutTheSelectedCardsTheTableLists() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        var window = openWindow()
        window.select([serendipia.id, ubuntu.id])
        window.search(for: "seren")

        window.askToDelete()
        let asked = try #require(window.cardsToDelete)
        window.delete(asked)
        window.search(for: "")

        #expect(asked.map(\.id) == [serendipia.id])
        #expect(window.question == nil)
        #expect(window.listedCardIDs == [ubuntu.id])
    }

    @Test("an action that fails records the action and how many cards it was on")
    func anActionThatFailsRecordsTheActionAndHowManyCards() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        var window = openWindow()
        window.select([serendipia.id, ubuntu.id])
        // Deleted outside the window, before it reads the cards again.
        try engine.delete([ubuntu.id])

        window.bury()

        #expect(window.failure?.action == .bury(cardCount: 2))
        #expect(window.failure?.error == .cardNotFound(ubuntu.id))
    }

    @Test("the No Type group lists exactly the cards with no type, flagged ones too but not the buried ones")
    func theNoTypeGroupListsTheCardsWithNoType() throws {
        try approveCard("serendipia", in: engine)
        let petricor = try engine.create(card(nil, front: "petricor", back: "El olor de la lluvia."))
        let ubuntu = try engine.create(card(nil, front: "ubuntu", back: "Soy porque somos."))
        let ataraxia = try engine.create(card(nil, front: "ataraxia", back: "Serenidad."))
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        try engine.bury(ataraxia.id)
        var window = openWindow()

        window.choose(.cards(.noType))

        #expect(window.typeGroups == [.type(.word), .type(.concept), .type(.quote), .type(.question), .noType])
        #expect(window.listedCardIDs == [petricor.id, ubuntu.id])
    }

    @Test("No Type isn't offered when every card has a type, and once it's gone the sidebar goes back to All cards")
    func noTypeIsNotOfferedWhenEveryCardHasAType() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let buried = try engine.create(card(nil, front: "ataraxia", back: "Serenidad."))
        try engine.bury(buried.id)
        var window = openWindow()
        #expect(window.typeGroups == [.type(.word), .type(.concept), .type(.quote), .type(.question)])
        let petricor = try engine.create(card(nil, front: "petricor", back: "El olor de la lluvia."))
        window.read(on: ladder)
        window.choose(.cards(.noType))

        try engine.edit(petricor.id, with: card(.word, front: "petricor", back: "El olor de la lluvia."))
        window.read(on: ladder)

        #expect(window.typeGroups == [.type(.word), .type(.concept), .type(.quote), .type(.question)])
        #expect(window.sidebarItem == .cards(.all))
        #expect(window.listedCardIDs == [serendipia.id, petricor.id])
    }

    @Test("saving an edit ends it, and the detail shows the card as saved at once")
    func savingAnEditShowsTheCardAsSavedAtOnce() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        var window = openWindow()
        window.select([serendipia.id])

        window.startEditing()
        let editing = window.editing
        window.saveCard(try card(.word, front: "serendipia", back: "Un hallazgo valioso que se da por accidente."))

        #expect(editing == .card(serendipia))
        #expect(window.editing == nil)
        #expect(window.shownCard?.row.card.back == "Un hallazgo valioso que se da por accidente.")
    }

    @Test("editing a card starts with its Both ways, and saving turns it on or off as the editor says")
    func editingACardKeepsOrSwitchesBothWays() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try engine.setBothWays(true, of: [ubuntu.id])
        var window = openWindow()

        window.select([serendipia.id])
        window.startEditing()
        let startedForSerendipia = window.editedBothWays
        window.setBothWaysInEditor(true)
        window.saveCard(try card(.word, front: serendipia.front, back: serendipia.back))
        window.select([ubuntu.id])
        window.startEditing()
        let startedForUbuntu = window.editedBothWays
        window.saveCard(try card(.word, front: ubuntu.front, back: "Soy porque somos."))

        #expect(!startedForSerendipia)
        #expect(startedForUbuntu)
        #expect(try engine.cards().map(\.bothWays) == [true, true])
        #expect(window.shownCard?.row.card.bothWays == true)
    }

    // The Edited column shows and sorts by it, in the app's `CardRowOrder`,
    // since a table's order stays in the app.
    @Test("the table lists a card with when its front or back last changed, and one never edited with none")
    func theTableListsWhenACardWasEdited() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try approveCard("ubuntu", in: engine)
        try approveCard("petricor", in: engine)
        var window = openWindow()
        time.advance(by: hours(1))
        window.select([serendipia.id])
        window.startEditing()
        window.saveCard(try card(.word, front: "serendipia", back: "Un hallazgo valioso que se da por accidente."))
        let serendipiaEditedAt = time.now
        time.advance(by: hours(1))

        window.select([ubuntu.id])
        window.startEditing()
        window.saveCard(try card(.concept, front: "ubuntu", back: "Soy porque somos."))
        window.select([serendipia.id])
        window.startEditing()
        window.saveCard(
            try card(
                .word, front: "serendipia", back: "Un hallazgo valioso que se da por accidente.", tags: ["lenguaje"]))

        let rows = try #require(window.listedCardRows)
        #expect(rows.map(\.card.front) == ["serendipia", "ubuntu", "petricor"])
        #expect(rows.map(\.card.editedAt) == [serendipiaEditedAt, time.now, nil])
    }
}

extension CardsWindowState {
    /// The ids of the cards the table lists, in the order the engine read
    /// them, or nil when it lists the inbox or couldn't read them.
    fileprivate var listedCardIDs: [Int64]? {
        listedCardRows?.map(\.id)
    }

    /// The cards the table lists, in the order the engine read them, or nil
    /// when it lists the inbox or couldn't read them.
    fileprivate var listedCardRows: [CardRow]? {
        guard case .success(.cards(let rows)) = listing else {
            return nil
        }
        return rows
    }

    /// What the table lists in the inbox, in the order the engine read it,
    /// or nil when it lists cards or couldn't read the inbox.
    fileprivate var listedInboxRows: [InboxRow]? {
        guard case .success(.inbox(let rows)) = listing else {
            return nil
        }
        return rows
    }

    /// The follow-up the detail shows, with its card, or nil when it shows
    /// something else.
    fileprivate var shownFollowUp: FollowUp? {
        guard case .followUp(let followUp) = detail else {
            return nil
        }
        return followUp
    }

    /// The card the detail shows whole, with its review log, or nil when it
    /// shows something else.
    fileprivate var shownCard: (row: CardRow, reviewLog: Result<[ReviewLogRow], EngineError>?)? {
        guard case .card(let row, let reviewLog) = detail else {
            return nil
        }
        return (row, reviewLog)
    }

    /// The cards the window asks whether to delete, or nil when it asks
    /// nothing about deleting.
    fileprivate var cardsToDelete: [CardRow]? {
        guard case .delete(let rows) = question else {
            return nil
        }
        return rows
    }
}
