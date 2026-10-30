import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the Cards window's Export sheet: what it offers to export, what
/// it starts on, and the file it writes, into a folder of the test's own,
/// from an engine in memory.
final class CardsWindowExportTests {
    let time: ManualTimeSource
    let engine: Engine
    let ladder = ReviewSettings.defaults.ladder
    /// A folder of the test's own, for the files it exports.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaCardsWindowExportTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    init() throws {
        let calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// The Cards window, open on All cards with its cards read.
    private func openWindow() -> CardsWindowState {
        var window = engine.openCardsWindow(on: ladder)
        window.read(on: ladder)
        return window
    }

    /// Approves a capture into one word card with this front and `tags`, and
    /// returns the card.
    @discardableResult
    private func approveCard(_ front: String, tags: [String] = []) throws -> Card {
        try approve(card(.word, front: front, back: "Lo que hay que saber de «\(front)».", tags: tags), in: engine)
    }

    @Test(
        "the Export sheet offers the selected cards only while some are selected, then all cards and each tag with cards, each with how many it takes, buried ones too"
    )
    func theExportSheetOffersEachChoiceWithItsCount() throws {
        let mayo = try approveCard("Revolución de Mayo", tags: ["historia"])
        try approveCard("Sócrates", tags: ["historia", "filosofía"])
        let ubuntu = try approveCard("ubuntu")
        let cabildo = try approveCard("Cabildo abierto", tags: ["historia"])
        try engine.bury(cabildo.id)
        let guernica = try approveCard("Guernica", tags: ["arte"])
        // All Tags still lists a tag with a color and no cards.
        try engine.setColor(.red, of: "arte")
        try engine.delete([guernica.id])
        var unselected = openWindow()
        var selected = openWindow()
        selected.select([mayo.id, ubuntu.id])

        unselected.startExport()
        selected.startExport()

        let all = CardsWindowState.ExportChoice(cards: .all, cardCount: 4)
        let philosophy = CardsWindowState.ExportChoice(cards: .tag("filosofía"), cardCount: 1)
        let history = CardsWindowState.ExportChoice(cards: .tag("historia"), cardCount: 3)
        #expect(unselected.exporting?.choices == [all, philosophy, history])
        #expect(unselected.exporting?.cardChoices == [all])
        #expect(unselected.exporting?.tagChoices == [philosophy, history])
        let selectedCards = CardsWindowState.ExportChoice(cards: .cards([mayo.id, ubuntu.id]), cardCount: 2)
        #expect(selected.exporting?.choices == [selectedCards, all, philosophy, history])
        #expect(selected.exporting?.cardChoices == [selectedCards, all])
    }

    // Which another Ficha proposes as their tag when it imports them.
    @Test("the save panel proposes the tag's name for a tag's cards, and a name for the selected cards or all of them")
    func theSavePanelProposesTheTagsName() throws {
        let mayo = try approveCard("Revolución de Mayo", tags: ["historia"])
        let ubuntu = try approveCard("ubuntu")
        var window = openWindow()
        window.select([mayo.id, ubuntu.id])

        window.startExport()
        let selected = window.exporting?.fileName
        window.chooseCardsToExport(.tag("historia"))
        let history = window.exporting?.fileName
        window.chooseCardsToExport(.all)

        #expect(selected == .selectedCards)
        #expect(history == .tag("historia"))
        #expect(window.exporting?.fileName == .allCards)
    }

    // One selected card is often just the one the detail shows.
    @Test(
        "the Export sheet starts on the selected cards when several are selected, else on the tag the sidebar chose, else on all cards"
    )
    func theExportSheetStartsOnWhatTheWindowPointsAt() throws {
        let mayo = try approveCard("Revolución de Mayo", tags: ["historia"])
        let socrates = try approveCard("Sócrates", tags: ["historia", "filosofía"])
        try approveCard("ubuntu")
        var several = openWindow()
        several.select([mayo.id, socrates.id])
        var tag = openWindow()
        tag.choose(.cards(.tag("filosofía")))
        tag.select([socrates.id])
        var one = openWindow()
        one.select([mayo.id])

        several.startExport()
        tag.startExport()
        one.startExport()

        #expect(several.exporting?.chosen == .cards([mayo.id, socrates.id]))
        #expect(several.exporting?.cardCount == 2)
        #expect(tag.exporting?.chosen == .tag("filosofía"))
        #expect(tag.exporting?.cardCount == 1)
        #expect(one.exporting?.chosen == .all)
        #expect(one.exporting?.cardCount == 3)
    }

    @Test(
        "Export writes what the user chose to the file they picked, the selected cards, a tag's or all, and closes the sheet"
    )
    func exportWritesWhatTheUserChose() async throws {
        let mayo = try approveCard("Revolución de Mayo", tags: ["historia"])
        try approveCard("Sócrates", tags: ["historia", "filosofía"])
        let ubuntu = try approveCard("ubuntu")
        var window = openWindow()
        window.select([mayo.id, ubuntu.id])

        var exportedFronts: [[String]] = []
        for choice in [CardsToExport.cards([mayo.id, ubuntu.id]), .tag("historia"), .all] {
            let file = folder.appending(path: "Tarjetas \(exportedFronts.count).txt")
            window.startExport()
            window.chooseCardsToExport(choice)
            window.export(to: file)
            #expect(window.exporting == nil)
            exportedFronts.append(try await CardsTextFile.read(Data(contentsOf: file)).cards.map(\.content.front))
        }

        #expect(
            exportedFronts == [
                ["Revolución de Mayo", "ubuntu"],
                ["Revolución de Mayo", "Sócrates"],
                ["Revolución de Mayo", "Sócrates", "ubuntu"],
            ])
    }

    @Test("Export writes which cards go both ways, as the selection's Both ways button left them")
    func exportWritesWhichCardsGoBothWays() async throws {
        let mayo = try approveCard("Revolución de Mayo", tags: ["historia"])
        let socrates = try approveCard("Sócrates", tags: ["historia"])
        try approveCard("ubuntu")
        var window = openWindow()
        window.select([mayo.id, socrates.id])
        window.turnOnBothWays()
        let file = folder.appending(path: "Tarjetas.txt")

        window.startExport()
        window.chooseCardsToExport(.all)
        window.export(to: file)

        let exported = try await CardsTextFile.read(Data(contentsOf: file)).cards
        #expect(exported.map(\.content.front) == ["Revolución de Mayo", "Sócrates", "ubuntu"])
        #expect(exported.map(\.bothWays) == [true, true, false])
    }

    // The save panel proposes a zip then, and the sheet says the images go.
    @Test("Export writes a zip when a card it takes has an image, and a text file when none does")
    func exportWritesAZipWhenACardHasAnImage() throws {
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        try engine.create(card(nil, front: "hornero", back: "Un pájaro.", tags: ["aves"], frontImage: bird))
        try approveCard("ubuntu", tags: ["filosofía"])
        var window = openWindow()

        window.startExport()
        let all = window.exporting?.writesZip
        window.chooseCardsToExport(.tag("filosofía"))
        let philosophy = window.exporting?.writesZip

        #expect(all == true)
        #expect(philosophy == false)
    }

    @Test("a file that can't be saved leaves the Export sheet open, saying why")
    func aFileThatCantBeSavedSaysWhy() throws {
        try approveCard("ubuntu")
        var window = openWindow()
        window.startExport()

        window.export(to: folder.appending(path: "Una carpeta que no existe/Tarjetas.txt"))

        #expect(window.failure?.action == .export)
        #expect(window.failure?.error == .unwritableFile("Tarjetas.txt"))
        #expect(window.exporting?.chosen == .all)
    }

    @Test("with no cards, Export is off and writes nothing")
    func withNoCardsExportIsOff() throws {
        var window = openWindow()
        let file = folder.appending(path: "Tarjetas.txt")

        window.startExport()
        window.export(to: file)

        #expect(window.exporting?.choices == [CardsWindowState.ExportChoice(cards: .all, cardCount: 0)])
        #expect(window.exporting?.canExport == false)
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }
}
