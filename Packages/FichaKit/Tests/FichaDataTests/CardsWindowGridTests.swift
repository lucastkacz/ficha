import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the Cards window's grid (#536): what each tile shows of its
/// card, its front's picture or its text, and the dot for where the card
/// stands, or the mark of a card set aside on its own (#539), how clicks and
/// the arrow keys select tiles, as in Photos and the Finder, and what
/// dragging a tile drags, on the default scheduler.
struct CardsWindowGridTests {
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

    @Test(
        "a tile shows its card's front picture, or else the front's text, or a word for a front that holds a sound alone",
        .bug(id: 536))
    func aTileShowsTheFrontsPictureOrItsText() async throws {
        let la = try await addTone(440, to: engine)
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let cards = try [
            card(nil, front: "¿Qué ave es?", back: "El hornero.", frontImage: bird),
            card(nil, front: "", back: "El hornero, que canta.", frontImage: bird, frontSound: la),
            card(nil, front: "petricor", back: "El olor de la lluvia."),
            card(nil, front: "¿Qué nota es?", back: "La.", frontSound: la),
            card(nil, front: "", back: "La.", frontSound: la),
        ].map { try engine.create($0) }

        let window = openWindow()

        #expect(window.tiles.map(\.id) == cards.map(\.id))
        #expect(
            window.tiles.map(\.face) == [
                .picture(bird), .picture(bird), .text("petricor"), .text("¿Qué nota es?"), .sound,
            ])
        #expect(try window.tileImages.image(bird)?.get() == engine.image(bird))
    }

    // The grid's tiles read their pictures as each appears, so the window
    // reads only the images its detail shows: the hornero's two once it's
    // selected, and never the egg's tile's.
    @Test(
        "the window reads no tile's picture as it lists the cards or as Lucas selects one: each tile reads its own, and the detail its card's",
        .bug(id: 536))
    func eachTileReadsItsOwnPicture() throws {
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let nest = try engine.addImage(picture(width: 800, height: 600, red: 0.3))
        let egg = try engine.addImage(picture(width: 800, height: 600, red: 0.1))
        let hornero = try engine.create(
            card(nil, front: "¿Qué ave es?", back: "El hornero.", frontImage: bird, backImage: nest))
        try engine.create(card(nil, front: "¿De quién es este huevo?", back: "Del hornero.", frontImage: egg))
        var window = openWindow()
        let readOnOpening = [bird, nest, egg].filter { window.images[$0] != nil }

        window.select([hornero.id])

        #expect(window.tiles.map(\.face) == [.picture(bird), .picture(egg)])
        #expect(readOnOpening.isEmpty)
        #expect(try window.images[bird]?.get() == engine.image(bird))
        #expect(try window.images[nest]?.get() == engine.image(nest))
        #expect(window.images[egg] == nil)
        #expect(try window.tileImages.image(egg)?.get() == engine.image(egg))
    }

    // A deck's row counts a card met once its front-first way is, so a
    // tile's dot goes by that way too, unless the card is due either way.
    @Test(
        "a tile's dot says its card is due when either of its ways is, and else met or new by its front-first way alone",
        .bug(id: 536))
    func aTilesDotSaysWhereItsCardStands() throws {
        let ubuntu = try engine.create(card(nil, front: "ubuntu", back: "Soy porque somos."), bothWays: true)
        let ojala = try engine.create(card(nil, front: "ojalá", back: "Ojalá que llueva café."))
        let efimero = try engine.create(card(nil, front: "efímero", back: "Que dura poco."), bothWays: true)
        let acaso = try engine.create(card(nil, front: "acaso", back: "Quizás."))
        // ubuntu is learned front first, and due back first only.
        try engine.climbUntilLearned(ubuntu, movingForward: time)
        try engine.meet(ubuntu, way: .backFirst)
        // acaso is met and due, but flagged, so it won't show up.
        try engine.meet(acaso)
        try engine.flag(acaso.id, note: note("Falta un ejemplo"))
        time.advance(by: hours(1))
        // efímero is met, due in an hour, and new back first.
        try engine.meet(efimero)

        let window = openWindow()

        #expect(window.tiles.map(\.id) == [ubuntu.id, ojala.id, efimero.id, acaso.id])
        #expect(window.tiles.map(\.mark) == [.due, .new, .met, .met])
    }

    // A card set aside on its own won't show up until it's put back, so its
    // tile says so in its dot's place, met or new, due or not, while a card
    // whose deck is set aside keeps its dot, never due (#539). The legend
    // names the mark while a tile has it.
    @Test(
        "a tile marks its card set aside on its own, met or not, and the legend names the mark while a tile has it",
        .bug(id: 539))
    func aTileMarksACardSetAsideOnItsOwn() throws {
        let ubuntu = try engine.create(card(nil, front: "ubuntu", back: "Soy porque somos."))
        let ojala = try engine.create(card(nil, front: "ojalá", back: "Ojalá que llueva café."))
        let acaso = try engine.create(card(nil, front: "acaso", back: "Quizás."))
        // ubuntu is met and due, and acaso new; both are set aside.
        try engine.meet(ubuntu)
        time.advance(by: hours(2))
        try engine.bury([ubuntu.id, acaso.id])
        var window = openWindow()
        let legendWithThem = window.legendMarks
        let tilesWithThem = window.tiles.map(\.mark)

        window.select([ubuntu.id, acaso.id])
        window.putBack()
        window.read(with: scheduler)

        #expect(window.tiles.map(\.id) == [ubuntu.id, ojala.id, acaso.id])
        #expect(tilesWithThem == [.setAside, .new, .setAside])
        #expect(legendWithThem == [.met, .due, .new, .setAside])
        #expect(window.tiles.map(\.mark) == [.due, .new, .new])
        #expect(window.legendMarks == [.met, .due, .new])
    }

    @Test(
        "a click selects a tile alone, a ⌘-click adds one or takes it out, and a Shift-click selects the run from the last one clicked",
        .bug(id: 536))
    func clicksSelectTilesAsInTheFinder() throws {
        let ids = try ["uno", "dos", "tres", "cuatro", "cinco"].map { front in
            try engine.create(card(nil, front: front, back: "Un número.")).id
        }
        var window = openWindow()

        window.clickTile(ids[1], .alone)
        let clicked = window.selection
        window.clickTile(ids[3], .adding)
        let added = window.selection
        window.clickTile(ids[1], .adding)
        let takenOut = window.selection
        window.clickTile(ids[0], .extending)
        let run = window.selection
        window.clickTile(ids[4], .extending)
        let longerRun = window.selection

        #expect(clicked == [ids[1]])
        #expect(added == [ids[1], ids[3]])
        #expect(takenOut == [ids[3]])
        #expect(run == [ids[0], ids[1]])
        #expect(longerRun == Set(ids[1...4]))
        guard case .cards(let shown) = window.detail else {
            Issue.record("The detail doesn't show the selected cards")
            return
        }
        #expect(shown.map(\.id) == Array(ids[1...4]))
    }

    // Seven tiles, three a row:
    //   0 1 2
    //   3 4 5
    //   6
    @Test(
        "the arrow keys select the tile before or after the selected one, or the one above or below it, Shift extending the run, and at an edge the selection stays",
        .bug(id: 536))
    func theArrowKeysMoveTheSelection() throws {
        let ids = try (1...7).map { number in
            try engine.create(card(nil, front: "Carta \(number)", back: "Un número.")).id
        }
        var window = openWindow()

        window.moveSelection(.backward, tilesPerRow: 3, extending: false)
        let first = window.selection
        window.moveSelection(.down, tilesPerRow: 3, extending: false)
        let below = window.selection
        window.moveSelection(.forward, tilesPerRow: 3, extending: false)
        window.moveSelection(.forward, tilesPerRow: 3, extending: false)
        let endOfTheRow = window.selection
        window.moveSelection(.forward, tilesPerRow: 3, extending: false)
        let onTheNextRow = window.selection
        window.moveSelection(.up, tilesPerRow: 3, extending: false)
        window.moveSelection(.up, tilesPerRow: 3, extending: false)
        let top = window.selection
        window.moveSelection(.up, tilesPerRow: 3, extending: false)
        let stillTop = window.selection
        window.clickTile(ids[5], .alone)
        window.moveSelection(.down, tilesPerRow: 3, extending: false)
        let last = window.selection
        window.moveSelection(.down, tilesPerRow: 3, extending: false)
        let stillLast = window.selection
        window.moveSelection(.up, tilesPerRow: 3, extending: true)
        let runUp = window.selection
        window.moveSelection(.backward, tilesPerRow: 3, extending: true)
        let longerRun = window.selection

        #expect(first == [ids[0]])
        #expect(below == [ids[3]])
        #expect(endOfTheRow == [ids[5]])
        #expect(onTheNextRow == [ids[6]])
        #expect(top == [ids[0]])
        #expect(stillTop == [ids[0]])
        // No tile right below the 6th: down goes to the last, as in the
        // Finder.
        #expect(last == [ids[6]])
        #expect(stillLast == [ids[6]])
        #expect(runUp == Set(ids[3...6]))
        #expect(longerRun == Set(ids[2...6]))
        #expect(window.cardToReveal == ids[2])
    }

    // Nine tiles, three a row:
    //   0 1 2
    //   3 4 5
    //   6 7 8
    @Test(
        "after a ⌘-click takes a tile out of the selection, an arrow key moves from that tile, the last one Lucas clicked, and not from the first",
        .bug(id: 536))
    func anArrowAfterACommandClickMovesFromTheTileClicked() throws {
        let ids = try (1...9).map { number in
            try engine.create(card(nil, front: "Carta \(number)", back: "Un número.")).id
        }
        var window = openWindow()
        window.clickTile(ids[2], .adding)
        window.clickTile(ids[4], .adding)
        window.clickTile(ids[6], .adding)
        window.clickTile(ids[6], .adding)
        let left = window.selection

        window.moveSelection(.forward, tilesPerRow: 3, extending: false)
        let movedForward = window.selection
        window.clickTile(ids[0], .adding)
        window.clickTile(ids[0], .adding)
        window.moveSelection(.down, tilesPerRow: 3, extending: false)

        #expect(left == [ids[2], ids[4]])
        #expect(movedForward == [ids[7]])
        #expect(window.selection == [ids[3]])
        #expect(window.cardToReveal == ids[3])
    }

    @Test(
        "a click between the tiles selects none, and a Shift-click or Shift with an arrow key after it starts afresh, from no tile clicked before",
        .bug(id: 536))
    func aClickBetweenTheTilesStartsAfresh() throws {
        let ids = try (1...7).map { number in
            try engine.create(card(nil, front: "Carta \(number)", back: "Un número.")).id
        }
        var window = openWindow()
        window.clickTile(ids[5], .alone)

        window.clickBetweenTiles()
        let none = window.selection
        let detailOfNone = window.detail
        window.moveSelection(.forward, tilesPerRow: 3, extending: true)
        let firstAlone = window.selection
        window.moveSelection(.forward, tilesPerRow: 3, extending: true)
        let runFromTheFirst = window.selection
        window.clickBetweenTiles()
        window.clickTile(ids[3], .extending)
        let clickedAlone = window.selection
        window.clickTile(ids[1], .extending)

        #expect(none.isEmpty)
        #expect(detailOfNone == .noCardSelected)
        #expect(firstAlone == [ids[0]])
        #expect(runFromTheFirst == [ids[0], ids[1]])
        #expect(clickedAlone == [ids[3]])
        #expect(window.selection == Set(ids[1...3]))
    }

    @Test(
        "dragging a selected tile drags every selected tile, in the grid's order, and dragging another drags it alone, leaving the selection as it is",
        .bug(id: 536))
    func draggingATileDragsTheSelectionWithIt() throws {
        let ids = try ["uno", "dos", "tres", "cuatro"].map { front in
            try engine.create(card(nil, front: front, back: "Un número.")).id
        }
        var window = openWindow()
        window.clickTile(ids[3], .alone)
        window.clickTile(ids[1], .adding)

        let draggedSelected = window.draggedCards(from: ids[3])
        let draggedAlone = window.draggedCards(from: ids[2])

        #expect(draggedSelected == [.card(ids[1]), .card(ids[3])])
        #expect(draggedAlone == [.card(ids[2])])
        #expect(window.selection == [ids[1], ids[3]])
    }

    @Test("Select All selects every tile the grid lists", .bug(id: 536))
    func selectAllSelectsEveryTile() throws {
        try engine.create(card(nil, front: "ojalá", back: "Ojalá que llueva café."), deck: "Palabras")
        let ids = try ["uno", "dos", "tres"].map { front in
            try engine.create(card(nil, front: front, back: "Un número."), deck: "Números").id
        }
        var window = openWindow()
        window.choose(.cards(.deck("Números")))

        window.selectAllTiles()

        #expect(window.selection == Set(ids))
        guard case .cards(let shown) = window.detail else {
            Issue.record("The detail doesn't show the selected cards")
            return
        }
        #expect(shown.map(\.id) == ids)
    }
}
