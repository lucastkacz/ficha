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
    private func importSheet(on name: String, _ text: String) async throws -> CardsWindowState {
        var window = engine.openCardsWindow(on: ladder)
        window.read(on: ladder)
        window.startImport()
        await window.previewImportAndWait(of: try file(name, text))
        return window
    }

    /// Opens the Cards window, reads the cards, and opens the Import sheet
    /// on `package`, written as `name`, as choosing it in the open panel does.
    private func ankiImportSheet(on name: String, _ package: AnkiPackage) async throws -> CardsWindowState {
        let file = folder.appending(path: name)
        try package.write(to: file)
        var window = engine.openCardsWindow(on: ladder)
        window.read(on: ladder)
        window.startImport()
        await window.previewImportAndWait(of: file)
        return window
    }

    @Test(
        "the Import sheet starts before a file is chosen, and choosing one shows its preview, which Import goes on from"
    )
    func choosingAFileShowsItsPreview() async throws {
        try approveCard("serendipia", in: engine)
        var window = engine.openCardsWindow(on: ladder)
        window.read(on: ladder)

        window.startImport()
        let beforeChoosing = window.importing
        await window.previewImportAndWait(
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
    func theTagFieldRenamesOrRemovesTheTag() async throws {
        var renamed = try await importSheet(on: "Palabras.txt", "efímero\tQue dura poco.\n")
        var removed = try await importSheet(on: "Lenguaje.txt", "petricor\tEl olor de la lluvia.\n")

        renamed.nameImportTag("Palabras", as: "vocabulario")
        await renamed.importCardsAndWait()
        removed.nameImportTag("Lenguaje", as: " ")
        await removed.importCardsAndWait()

        #expect(renamed.importing?.tagFields == [CardsWindowState.TagField(proposed: "Palabras", name: "vocabulario")])
        #expect(renamed.importing?.tagFields.map(\.isLeftOut) == [false])
        #expect(removed.importing?.tagFields.map(\.isLeftOut) == [true])
        #expect(try engine.cards().map(\.tags) == [["vocabulario"], []])
    }

    @Test("with Skip, Import is off while every card repeats one of yours, and the repeated cards stay as they are")
    func skipLeavesTheRepeatedCardsAsTheyAre() async throws {
        let serendipia = try approveCard("serendipia", in: engine)
        var window = try await importSheet(on: "Palabras.txt", "serendipia\tUn hallazgo valioso.\n")

        window.chooseForRepeatedCards(.skip)
        let isImportOnWithSkip = window.importing?.canImport
        await window.importCardsAndWait()
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
    func theSheetSaysWhatTheImportDid() async throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try approveCard("petricor", in: engine)
        var window = try await importSheet(
            on: "Palabras.txt",
            "serendipia\tUn hallazgo valioso.\npetricor\tEl olor de la lluvia.\nefímero\tQue dura poco.\n")
        window.chooseForRepeatedCards(.skip)
        window.chooseForRepeatedCards(.update)

        await window.importCardsAndWait()

        #expect(window.importing?.step == .done(ImportOutcome(added: 1, updated: 2, skipped: 0, copyBeforeImport: nil)))
        #expect(window.listedFronts == ["serendipia", "petricor", "efímero"])
        #expect(try engine.cards().first?.back == "Un hallazgo valioso.")
        #expect(try engine.cards().first?.id == serendipia.id)

        window.closeImport()

        #expect(window.importing == nil)
    }

    @Test(
        "once a file with a Both ways column is imported, the table lists its cards going both ways as the column says, an updated one too"
    )
    func importedCardsGoBothWaysAsTheColumnSays() async throws {
        let serendipia = try approveCard("serendipia", in: engine)
        var window = try await importSheet(
            on: "Palabras.txt",
            """
            #columns:Front\tBack\tBoth ways
            serendipia\tUn hallazgo valioso.\tsí
            petricor\tEl olor de la lluvia.\t
            efímero\tQue dura poco.\tx

            """)

        await window.importCardsAndWait()

        #expect(window.importing?.step == .done(ImportOutcome(added: 2, updated: 1, skipped: 0, copyBeforeImport: nil)))
        #expect(window.listedFronts == ["serendipia", "petricor", "efímero"])
        #expect(window.listedBothWays == [true, false, true])
        #expect(try engine.cards().first?.id == serendipia.id)
    }

    // As Great Works of Art can come in under Arte.
    @Test(
        "the preview of an Anki package lists its decks and its tags apart, and the user renames a deck, also to one they have, and renames or clears a tag"
    )
    func anAnkiPackagesDecksAndTagsAreListedApart() async throws {
        try engine.makeDeck(named: "Arte")
        var window = try await ankiImportSheet(
            on: "Great Works of Art.apkg",
            AnkiPackage(notes: [
                AnkiNote(
                    type: .basic, fields: ["Leonardo da Vinci", "La Gioconda."], tags: ["Renaissance", "Painting"],
                    deck: "Great Works of Art::Artists"),
                AnkiNote(
                    type: .basic, fields: ["fémur", "El hueso del muslo."], tags: ["repaso"],
                    deck: "Medicina::Anatomía"),
                AnkiNote(type: .basic, fields: ["sístole", "La contracción del corazón."], deck: "Medicina"),
            ]))
        let deckFields = window.importing?.deckFields
        let tagFields = window.importing?.tagFields

        window.nameImportDeck("Great Works of Art::Artists", as: "Arte")
        window.nameImportDeck("Medicina::Anatomía", as: "Medicina:: Anatomía humana")
        window.removeImportTag("repaso")
        window.nameImportTag("Renaissance", as: "Renacimiento")
        await window.importCardsAndWait()

        #expect(
            deckFields
                == ["Great Works of Art", "Great Works of Art::Artists", "Medicina", "Medicina::Anatomía"].map {
                    CardsWindowState.ImportDeckField(proposed: $0, name: $0)
                })
        #expect(
            tagFields
                == ["Renaissance", "Painting", "repaso"].map { CardsWindowState.TagField(proposed: $0, name: $0) })
        #expect(window.importing?.offersDeckChoice == false)
        #expect(try engine.cards().map(\.deck) == ["Arte", "Medicina::Anatomía humana", "Medicina"])
        #expect(try engine.cards().map(\.tags) == [["Renacimiento", "Painting"], [], []])
    }

    // In Great Works of Art only the decks inside it hold cards, and it comes
    // in under Arte by one field, as a tag's rename takes the tags inside it
    // along (ADR 0021).
    @Test(
        "the sheet has a field for each deck the cards sit inside too, and renaming one renames the decks inside it, but one renamed on its own keeps its name"
    )
    func renamingADeckInTheSheetRenamesTheDecksInsideIt() async throws {
        var window = try await ankiImportSheet(
            on: "Great Works of Art.apkg",
            AnkiPackage(notes: [
                AnkiNote(
                    type: .basic, fields: ["Leonardo da Vinci", "La Gioconda."], deck: "Great Works of Art::Artists"),
                AnkiNote(
                    type: .basic, fields: ["La Gioconda", "Leonardo da Vinci."], deck: "Great Works of Art::Titles"),
                AnkiNote(type: .basic, fields: ["sístole", "La contracción del corazón."], deck: "Medicina"),
            ]))
        let proposed = window.importing?.deckFields.map(\.proposed)

        window.nameImportDeck("Great Works of Art::Titles", as: "Títulos")
        window.nameImportDeck("Great Works of Art", as: "Arte:: Great Works of Art")
        let names = window.importing?.deckFields.map(\.name)
        await window.importCardsAndWait()

        #expect(
            proposed == [
                "Great Works of Art", "Great Works of Art::Artists", "Great Works of Art::Titles", "Medicina",
            ])
        #expect(
            names == ["Arte:: Great Works of Art", "Arte::Great Works of Art::Artists", "Títulos", "Medicina"])
        #expect(try engine.cards().map(\.deck) == ["Arte::Great Works of Art::Artists", "Títulos", "Medicina"])
    }

    @Test(
        "the sheet lists Default among the decks the cards come into while some new cards name no deck beside others that name one, and a menu of decks while none names one"
    )
    func defaultIsListedWhileSomeNewCardsNameNoDeck() async throws {
        try approveCard("fémur", in: engine)
        let mixed = try await ankiImportSheet(
            on: "Medicina.apkg",
            AnkiPackage(notes: [
                AnkiNote(type: .basic, fields: ["sístole", "La contracción del corazón."], deck: "Medicina"),
                AnkiNote(type: .basic, fields: ["gripe", "Una infección por el virus de la influenza."]),
            ]))
        let decked = try await ankiImportSheet(
            on: "Anatomía.apkg",
            AnkiPackage(notes: [
                AnkiNote(type: .basic, fields: ["sístole", "La contracción del corazón."], deck: "Medicina"),
                AnkiNote(type: .basic, fields: ["fémur", "El hueso del muslo."]),
            ]))
        let deckless = try await importSheet(on: "Palabras.txt", "efímero\tQue dura poco.\n")

        #expect(mixed.importing?.listsDefault == true)
        #expect(mixed.importing?.offersDeckChoice == false)
        #expect(decked.importing?.listsDefault == false)
        #expect(deckless.importing?.listsDefault == false)
        #expect(deckless.importing?.offersDeckChoice == true)
    }

    @Test("Import is off while a deck's field is blank or names Default, which the sheet says why")
    func importIsOffWhileADecksFieldIsBlankOrNamesDefault() async throws {
        var window = try await ankiImportSheet(
            on: "Medicina.apkg",
            AnkiPackage(notes: [
                AnkiNote(type: .basic, fields: ["sístole", "La contracción del corazón."], deck: "Medicina")
            ]))

        window.nameImportDeck("Medicina", as: " ")
        let blank = window.importing
        window.nameImportDeck("Medicina", as: "Default::Cardiología")
        let named = window.importing
        window.nameImportDeck("Medicina", as: "Cardiología")

        #expect(blank?.deckFields.map(\.entry) == [.blankName])
        #expect(blank?.canImport == false)
        #expect(named?.deckFields.map(\.entry) == [.refused(.defaultDeckName("Default"))])
        #expect(named?.canImport == false)
        #expect(window.importing?.deckFields.map(\.entry) == [.name("Cardiología")])
        #expect(window.importing?.canImport == true)
    }

    @Test(
        "for a file that puts its cards in no deck, the sheet offers Default, every deck you have, and one New Deck… names, and Import puts the cards in the one chosen"
    )
    func aFileWithNoDeckLetsTheUserChooseOne() async throws {
        try engine.makeDeck(named: "Idiomas")
        var chosen = try await importSheet(on: "Palabras.txt", "efímero\tQue dura poco.\n")
        var unchosen = try await importSheet(on: "Más palabras.txt", "petricor\tEl olor de la lluvia.\n")
        let offered = chosen.importing

        let choicesOffered = chosen.importDeckChoices.map(\.name)
        chosen.chooseImportDeck("Idiomas")
        let choosingIdiomas = chosen.importing?.chosenDeck
        chosen.askForNewImportDeck()
        chosen.cancelNewDeck()
        let cancelled = chosen.importing
        chosen.askForNewImportDeck()
        let naming = chosen.importing?.isNamingNewDeck
        let refused = chosen.newDeckEntry("Default")
        chosen.chooseNewDeck("Idiomas:: Inglés")
        let choicesWithTheNewDeck = chosen.importDeckChoices.map(\.name)
        chosen.chooseImportDeck("Ciencias")
        await chosen.importCardsAndWait()
        await unchosen.importCardsAndWait()

        #expect(offered?.offersDeckChoice == true)
        #expect(offered?.chosenDeck == Deck.defaultName)
        #expect(offered?.deckFields == [])
        #expect(choicesOffered == [Deck.defaultName, "Idiomas"])
        #expect(choosingIdiomas == "Idiomas")
        #expect(cancelled?.isNamingNewDeck == false)
        #expect(cancelled?.chosenDeck == "Idiomas")
        #expect(naming == true)
        #expect(refused == .refused(.defaultDeckName("Default")))
        #expect(choicesWithTheNewDeck == [Deck.defaultName, "Idiomas", "Idiomas::Inglés"])
        #expect(chosen.importing?.isNamingNewDeck == false)
        #expect(try engine.cards().map(\.deck) == ["Idiomas::Inglés", Deck.defaultName])
    }

    @Test("the preview of an Anki package counts the cards that stay out by why, in the order each reason first comes")
    func anAnkiPackagesCardsLeftOutAreCounted() async throws {
        let package = AnkiPackage(notes: [
            AnkiNote(type: .basic, fields: ["perro", "[sound:dog.mp3]"]),
            AnkiNote(
                type: .imageOcclusion,
                fields: ["{{c1::image-occlusion:rect:left=.1:top=.2:width=.3:height=.1}}", "", "", "", ""]),
            AnkiNote(type: .basic, fields: ["[sound:gato.mp3]", "cat"]),
            AnkiNote(type: .basic, fields: ["casa", "house"]),
        ])
        let file = folder.appending(path: "Inglés.apkg")
        try package.write(to: file)
        var window = engine.openCardsWindow(on: ladder)
        window.startImport()

        await window.previewImportAndWait(of: file)

        let preview = try #require(window.importing?.preview)
        #expect(preview.kind == .ankiPackage)
        #expect(preview.newCount == 1)
        #expect(
            preview.leftOutCounts == [
                ImportPreview.LeftOutCount(reason: .missingAnkiSound, count: 2),
                ImportPreview.LeftOutCount(reason: .ankiImageOcclusion, count: 1),
            ])
    }

    // A big file takes a while, and the app reads it away from the main
    // actor, so the window answers meanwhile.
    @Test(
        "while the file chosen is read, the sheet says so, and a reading that ends after the sheet closed shows nothing"
    )
    func whileTheFileIsReadTheSheetSaysSo() async throws {
        var window = engine.openCardsWindow(on: ladder)
        window.read(on: ladder)
        window.startImport()
        let file = try file("Palabras.txt", "efímero\tQue dura poco.\n")

        let reading = window.previewImport(of: file)
        let whileReading = window.importing
        await window.finishImportWork(try #require(reading).run())
        let read = window.importing
        let readingAgain = window.previewImport(of: file)
        window.closeImport()
        window.startImport()
        await window.finishImportWork(try #require(readingAgain).run())

        #expect(whileReading?.busy == .reading("Palabras.txt"))
        #expect(whileReading?.step == .choosingFile)
        #expect(read?.busy == nil)
        #expect(read?.preview?.newCount == 1)
        #expect(window.importing?.step == .choosingFile)
        #expect(window.importing?.busy == nil)
    }

    @Test("while the cards are imported, the sheet says so and Import is off, and once they are, the table lists them")
    func whileTheCardsAreImportedTheSheetSaysSo() async throws {
        var window = try await importSheet(on: "Palabras.txt", "efímero\tQue dura poco.\n")

        let importing = window.importCards()
        let whileImporting = window.importing
        let importingTwice = window.importCards()
        await window.finishImportWork(try #require(importing).run())

        #expect(whileImporting?.busy == .importing)
        #expect(whileImporting?.canImport == false)
        #expect(importingTwice == nil)
        #expect(window.importing?.step == .done(ImportOutcome(added: 1, updated: 0, skipped: 0, copyBeforeImport: nil)))
        #expect(window.importing?.busy == nil)
        #expect(window.listedFronts == ["efímero"])
    }

    @Test("a file that can't be read leaves the sheet where it was, saying why until it's dismissed")
    func aFileThatCantBeReadSaysWhy() async throws {
        var window = engine.openCardsWindow(on: ladder)
        window.startImport()

        await window.previewImportAndWait(of: folder.appending(path: "Nada.txt"))

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

    /// Whether each card the table lists goes both ways, in the order the
    /// engine read them, or nil when it lists the inbox or couldn't read
    /// them.
    fileprivate var listedBothWays: [Bool]? {
        guard case .success(.cards(let rows)) = listing else {
            return nil
        }
        return rows.map(\.card.bothWays)
    }
}
