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

        try engine.bury(mayo.id)
        window.read(on: ladder)

        #expect(window.sidebarItem == .cards(.all))
        #expect(window.tags.isEmpty)
        #expect(window.listedCardIDs == [serendipia.id])
    }

    // So that Lucas can undo it, and a card that gets the tag later is set
    // aside too.
    @Test("a set-aside tag stays listed without cards, and choosing it lists no cards rather than All cards")
    func aSetAsideTagStaysListedWithoutCards() throws {
        let mayo = try approve(
            card(.concept, front: "Revolución de Mayo", back: "1810.", tags: ["historia"]), in: engine)
        try approveCard("serendipia", in: engine)
        var window = openWindow()
        window.chooseSetAside(on: "historia")
        window.choose(.cards(.tag("historia")))

        try engine.delete([mayo.id])
        window.read(on: ladder)

        #expect(window.tags == [CardTag(name: "historia", switchedOn: .setAside)])
        #expect(window.sidebarItem == .cards(.tag("historia")))
        #expect(window.listedCardIDs == [])
    }

    @Test("Set Aside in a tag's menu is ticked while the tag is set aside, and choosing it again undoes it")
    func setAsideIsTickedAsTheTagStands() throws {
        let ubuntu = try approve(
            card(.word, front: "ubuntu", back: "Humanidad.", tags: ["filosofía", "lenguaje"]), in: engine)
        var window = openWindow()
        #expect(window.menu(for: "filosofía")?.isSetAsideTicked == false)

        window.chooseSetAside(on: "filosofía")

        #expect(window.menu(for: "filosofía")?.isSetAsideTicked == true)
        #expect(window.menu(for: "lenguaje")?.isSetAsideTicked == false)
        #expect(try engine.cards().map(\.standing) == [.setAside(by: ["filosofía"])])
        window.chooseSetAside(on: "filosofía")
        #expect(window.menu(for: "filosofía")?.isSetAsideTicked == false)
        #expect(try engine.cards().map(\.standing) == [ubuntu.standing])
    }

    @Test("the Color submenu offers None and Finder's seven colors, and ticks the tag's color, or None")
    func theColorSubmenuTicksTheTagsColorOrNone() throws {
        try approve(card(.word, front: "fotosíntesis", back: "Luz en azúcar.", tags: ["ciencia"]), in: engine)
        var window = openWindow()
        let colors: [TagColor?] = [nil, .red, .orange, .yellow, .green, .blue, .purple, .gray]
        #expect(window.menu(for: "ciencia")?.colorItems.map(\.color) == colors)
        #expect(window.menu(for: "ciencia")?.colorItems.filter(\.isTicked).map(\.color) == [nil])

        window.chooseColor(.green, on: "ciencia")

        #expect(window.menu(for: "ciencia")?.colorItems.filter(\.isTicked).map(\.color) == [.green])
        #expect(window.tags == [CardTag(name: "ciencia", color: .green)])
        window.chooseColor(nil, on: "ciencia")
        #expect(window.menu(for: "ciencia")?.colorItems.filter(\.isTicked).map(\.color) == [nil])
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
        #expect(window.emojiEntry("🇦🇷") == .emoji(try TagEmoji("🇦🇷")))

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

    @Test("New, Due and Learned leave set-aside cards out, while All cards and the tag's group hold them")
    func newDueAndLearnedLeaveSetAsideCardsOut() throws {
        // eudaimonía gets to the 30-day step, from which a card is learned,
        // and comes due there; ataraxia is new.
        let eudaimonia = try approve(
            card(.concept, front: "eudaimonía", back: "Vida plena.", tags: ["filosofía"]), in: engine)
        let ataraxia = try approve(
            card(.concept, front: "ataraxia", back: "Serenidad.", tags: ["filosofía"]), in: engine)
        try engine.climb(eudaimonia, to: 5, movingForward: time)
        time.advance(by: days(30))
        var window = openWindow()
        window.chooseSetAside(on: "filosofía")

        for group in [CardGroup.new, .due, .learned] {
            window.choose(.cards(group))
            #expect(window.listedCardIDs == [], "\(group)")
        }
        for group in [CardGroup.all, .tag("filosofía")] {
            window.choose(.cards(group))
            #expect(window.listedCardIDs == [eudaimonia.id, ataraxia.id], "\(group)")
        }
    }

    @Test("the Due column says a set-aside card is set aside, where its due time goes")
    func theDueColumnSaysASetAsideCardIsSetAside() throws {
        let eudaimonia = try approve(
            card(.concept, front: "eudaimonía", back: "Vida plena.", tags: ["filosofía"]), in: engine)
        try engine.meet(eudaimonia)
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.meet(serendipia)
        var window = openWindow()

        window.chooseSetAside(on: "filosofía")

        let rows = try #require(window.listedCardRows)
        #expect(rows.map(\.dueColumn) == [.setAside, .due(time.now + hours(1))])
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
        #expect(window.actions == [.edit, .bury, .delete])
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

        #expect(offeredInAllCards == [.bury, .delete])
        #expect(offeredInBuried == [.unbury, .delete])
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
