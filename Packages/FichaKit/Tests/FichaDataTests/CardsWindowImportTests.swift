import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the Cards window's Import sheet: the preview of the file chosen,
/// the tag field and Update or Skip, and what the import did, from files the
/// tests write in a folder of their own, into an engine in memory.
final class CardsWindowImportTests {
    let time: ManualTimeSource
    let engine: Engine
    let ladder = ReviewSettings.defaults.ladder
    /// A folder of the test's own, for the files it imports.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaCardsWindowImportTests-\(UUID().uuidString)",
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

    /// Writes `text` as UTF-8 to a file named `name` in the test's folder,
    /// and returns the file.
    private func file(_ name: String, _ text: String) throws -> URL {
        let file = folder.appending(path: name)
        try Data(text.utf8).write(to: file)
        return file
    }

    /// Opens the Cards window, reads the cards, and opens the Import sheet
    /// on the file `name` with `text`, as choosing it in the open panel does.
    private func importSheet(on name: String, _ text: String) throws -> CardsWindowState {
        var window = engine.openCardsWindow(on: ladder)
        window.read(on: ladder)
        window.startImport()
        window.previewImport(of: try file(name, text))
        return window
    }

    @Test(
        "the Import sheet starts before a file is chosen, and choosing one shows its preview, which Import goes on from"
    )
    func choosingAFileShowsItsPreview() throws {
        try approveCard("serendipia", in: engine)
        var window = engine.openCardsWindow(on: ladder)
        window.read(on: ladder)

        window.startImport()
        let beforeChoosing = window.importing
        window.previewImport(
            of: try file("Palabras.txt", "serendipia\tUn hallazgo.\nefímero\tQue dura poco.\npetricor\n"))

        #expect(beforeChoosing?.step == .choosingFile)
        #expect(beforeChoosing?.canImport == false)
        let importing = try #require(window.importing)
        let preview = try #require(importing.preview)
        #expect(preview.fileName == "Palabras.txt")
        #expect(preview.newCount == 1)
        #expect(preview.repeatedCount == 1)
        #expect(preview.leftOut == [LeftOutLine(line: 3, reason: .oneColumn)])
        #expect(importing.tagFields == [CardsWindowState.TagField(proposed: "Palabras", name: "Palabras")])
        #expect(importing.repeatedCards == .update)
        #expect(importing.canImport)
    }

    @Test("the tag field renames the tag every imported card gets, and leaves it out when it's blank")
    func theTagFieldRenamesOrRemovesTheTag() throws {
        var renamed = try importSheet(on: "Palabras.txt", "efímero\tQue dura poco.\n")
        var removed = try importSheet(on: "Lenguaje.txt", "petricor\tEl olor de la lluvia.\n")

        renamed.nameImportTag("Palabras", as: "vocabulario")
        renamed.importCards()
        removed.nameImportTag("Lenguaje", as: " ")
        removed.importCards()

        #expect(renamed.importing?.tagFields == [CardsWindowState.TagField(proposed: "Palabras", name: "vocabulario")])
        #expect(try engine.cards().map(\.tags) == [["vocabulario"], []])
    }

    @Test("with Skip, Import is off while every card repeats one of yours, and the repeated cards stay as they are")
    func skipLeavesTheRepeatedCardsAsTheyAre() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        var window = try importSheet(on: "Palabras.txt", "serendipia\tUn hallazgo valioso.\n")

        window.chooseForRepeatedCards(.skip)
        let isImportOnWithSkip = window.importing?.canImport
        window.importCards()
        let afterImportWhileOff = window.importing?.step
        window.chooseForRepeatedCards(.update)

        #expect(isImportOnWithSkip == false)
        #expect(afterImportWhileOff == window.importing?.preview.map { .preview($0) })
        #expect(window.importing?.canImport == true)
        #expect(try engine.cards() == [serendipia])
    }

    @Test(
        "once the import is done, the sheet says how many cards came in, were updated and were skipped, and the table lists them"
    )
    func theSheetSaysWhatTheImportDid() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try approveCard("petricor", in: engine)
        var window = try importSheet(
            on: "Palabras.txt",
            "serendipia\tUn hallazgo valioso.\npetricor\tEl olor de la lluvia.\nefímero\tQue dura poco.\n")
        window.chooseForRepeatedCards(.skip)
        window.chooseForRepeatedCards(.update)

        window.importCards()

        #expect(window.importing?.step == .done(ImportOutcome(added: 1, updated: 2, skipped: 0, copyBeforeImport: nil)))
        #expect(window.listedFronts == ["serendipia", "petricor", "efímero"])
        #expect(try engine.cards().first?.back == "Un hallazgo valioso.")
        #expect(try engine.cards().first?.id == serendipia.id)

        window.closeImport()

        #expect(window.importing == nil)
    }

    @Test("a file that can't be read leaves the sheet where it was, saying why until it's dismissed")
    func aFileThatCantBeReadSaysWhy() throws {
        var window = engine.openCardsWindow(on: ladder)
        window.startImport()

        window.previewImport(of: folder.appending(path: "Nada.txt"))

        #expect(window.importing?.step == .choosingFile)
        #expect(
            window.importing?.failure
                == CardsWindowState.ImportFailure(
                    action: .preview, error: .unreadableFile("Nada.txt", .cannotOpen)))

        window.dismissImportFailure()

        #expect(window.importing?.failure == nil)
        #expect(window.importing?.step == .choosingFile)
    }
}

extension CardsWindowState {
    /// The fronts of the cards the table lists, in the order the engine
    /// read them, or nil when it lists the inbox or couldn't read them.
    fileprivate var listedFronts: [String]? {
        guard case .success(.cards(let rows)) = listing else {
            return nil
        }
        return rows.map(\.card.front)
    }
}
