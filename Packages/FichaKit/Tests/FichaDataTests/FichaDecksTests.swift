import FichaCore
import FichaData
import Foundation
import Testing

/// The painters Arte argentino's paintings may be by, each with the year
/// they died.
private let painters: [String: Int] = [
    "Cándido López": 1902,
    "Prilidiano Pueyrredón": 1870,
    "Eduardo Sívori": 1918,
    "Ángel Della Valle": 1903,
    "Ernesto de la Cárcova": 1927,
    "Martín Malharro": 1911,
    "Fernando Fader": 1935,
    "Pío Collivadino": 1945,
]

/// Tests on Ficha's decks (ADR 0040, #458), the three zips of cards in the
/// repo's `App/FichaDecks/`, which the app bundles: how each comes in, what
/// their pictures credit, how an update of the app leaves one the user
/// added, and how the Cards window offers them. They start at 9 in the
/// morning in Buenos Aires, when active hours start, on a new install, with
/// engines in memory, or, for an update, on a database in a folder of the
/// test's own. Each fails while a file it reads isn't in the repo.
final class FichaDecksTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    let scheduler = ReviewSettings.defaults.scheduler
    /// A folder of the test's own, for a database and the files it writes.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaDecksTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
        engine = try Engine(location: .inMemory, time: time, ids: CountingIDSource(), calendar: calendar)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    @Test(
        "each of Ficha's decks comes in through the same import as a Ficha package, into its deck, with no tag, each picture's front its image alone, and the deck's emoji, and adding it again adds nothing",
        .bug(id: 458),
        arguments: [(FichaDeck.palabrasLindas, 40), (FichaDeck.arteArgentino, 50), (FichaDeck.floresDeBuenosAires, 30)])
    func eachDeckComesInThroughTheImport(deck: FichaDeck, cardCount: Int) async throws {
        let shipped = try fileInTheRepo(of: deck)
        let imported = try await cardsAsTheImportBringsThem(from: shipped)
        let file = try await engine.readFichaDeck(deck, at: shipped)

        let added = try engine.add(file)
        let cards = try engine.cards()
        let fileAgain = try await engine.readFichaDeck(deck, at: shipped)
        let addedAgain = try engine.add(fileAgain)

        let hasPictures = deck != .palabrasLindas
        #expect(file.cardCount == cardCount)
        #expect(added.added == cardCount)
        #expect(cards.map(content(of:)) == imported.map(content(of:)))
        #expect(cards.allSatisfy { $0.deck == deck.name && $0.tags.isEmpty })
        #expect(cards.allSatisfy { ($0.frontImage != nil) == hasPictures && $0.front.isEmpty == hasPictures })
        #expect(try engine.decks().first { $0.name == deck.name }?.emoji == deck.emoji)
        #expect(addedAgain.added == 0)
        #expect(try engine.cards() == cards)
    }

    // As Wikimedia Commons credits them: "Imagen: Google Art Project ·
    // Dominio público · Wikimedia Commons", or "Imagen: Jane Doe · CC BY-SA
    // 4.0 · Wikimedia Commons". Arte argentino's 50 paintings and Flores de
    // Buenos Aires' 30 flowers have pictures.
    @Test(
        "every picture of Ficha's decks credits its author and its license on its card's back's last line, public domain, CC0, CC BY or CC BY-SA, and has its Wikimedia Commons page as its source",
        .bug(id: 458))
    func everyPictureIsCredited() async throws {
        var pictures: [Card] = []
        for deck in FichaDeck.allCases {
            let cards = try await cardsAsTheImportBringsThem(from: try fileInTheRepo(of: deck))
            pictures += cards.filter { $0.frontImage != nil || $0.backImage != nil }
        }

        let uncredited = pictures.filter { !isCredit($0.back.components(separatedBy: "\n").last ?? "") }
        let withoutPage = pictures.filter { $0.source?.hasPrefix("https://commons.wikimedia.org/wiki/File:") != true }
        #expect(pictures.count == 80)
        #expect(uncredited.map(\.back) == [])
        #expect(withoutPage.map(\.source) == [])
    }

    // A painter who died before 1956 has been dead for 70 years, so their
    // works are in the public domain in Argentina; and a work from before
    // 1931 is in the United States too, where Wikimedia Commons is. A
    // painting's back says its title, its painter, then its year and museum,
    // such as "1894 · Museo Nacional de Bellas Artes, Buenos Aires".
    @Test(
        "every painting of Arte argentino is by a painter who died before 1956, and from a year before 1931",
        .bug(id: 458))
    func everyPaintingIsInThePublicDomain() async throws {
        let paintings = try await cardsAsTheImportBringsThem(from: try fileInTheRepo(of: .arteArgentino))

        let lines = paintings.map { $0.back.components(separatedBy: "\n") }
        let byOthers = lines.filter { $0.count < 2 || painters[$0[1]] == nil }
        let fromLater = lines.filter { $0.count < 3 || (Int($0[2].prefix(while: \.isNumber)) ?? 1931) >= 1931 }
        #expect(paintings.count == 50)
        #expect(painters.values.allSatisfy { $0 < 1956 })
        #expect(byOthers == [])
        #expect(fromLater == [])
    }

    // The user added Arte argentino and reviewed two of its cards. Then an
    // update of the app brings a newer file of it, and the app opens the
    // same database again.
    @Test(
        "an update of the app leaves a deck the user added, and its progress, as they were: a newer file of it, with a card's back changed and one card more, finds it added, and the Cards window doesn't offer it",
        .bug(id: 458))
    func anUpdateLeavesAnAddedDeckAsItWas() async throws {
        let shipped = try fileInTheRepo(of: .arteArgentino)
        let data = folder.appending(path: "Ficha", directoryHint: .isDirectory)
        let before = try await addArte(from: shipped, in: data)
        let newer = try await newerArte(than: shipped)

        let updated = try Engine(location: .folder(data), time: time, ids: CountingIDSource(), calendar: calendar)
        let file = try await updated.readFichaDeck(.arteArgentino, at: newer)
        var window = updated.openCardsWindow(with: scheduler)
        window.read(with: scheduler)
        window.offerFichaDecks([file])

        #expect(try updated.hasAdded(file))
        #expect(window.offeredFichaDecks == [])
        #expect(try updated.cards() == before.cards)
        #expect(try updated.reviewLog() == before.log)
    }

    // The user has a deck of their own, Lenguaje, with a new card, so Arte
    // argentino comes in after it.
    @Test(
        "the Cards window lists Ficha's decks the user hasn't added after Decks, shows one's first card front and back, and once Add Deck… and How fast?'s Start add it, lists it no longer and chooses the deck",
        .bug(id: 458))
    func theCardsWindowOffersFichasDecks() async throws {
        var files: [FichaDeckFile] = []
        for deck in FichaDeck.allCases {
            let shipped = try fileInTheRepo(of: deck)
            files.append(try await engine.readFichaDeck(deck, at: shipped))
        }
        try approveInDeck("serendipia", deck: "Lenguaje", in: engine)
        var window = engine.openCardsWindow(with: scheduler)
        window.read(with: scheduler)

        window.offerFichaDecks(files)
        let sections = window.sidebarSections.map(\.id)
        let offered = window.offeredFichaDecks
        window.choose(.fichaDeck(.palabrasLindas))
        let words = try #require(window.shownFichaDeck)
        window.choose(.fichaDeck(.arteArgentino))
        let arte = try #require(window.shownFichaDeck)
        let painting = try #require(arte.firstCard)
        let image = try #require(painting.frontImage)
        let picture = try? window.images[image]?.get()
        window.askToAddFichaDeck()
        let asked = window.howFast
        window.startHowFast()

        #expect(sections == [.cardGroups, .inbox, .decks, .fichaDecks, .tags, .types])
        #expect(offered == FichaDeck.allCases)
        #expect(words.deck == .palabrasLindas)
        #expect(words.firstCard?.front.isEmpty == false)
        #expect(words.firstCard?.frontImage == nil)
        #expect(words.firstCard?.back.components(separatedBy: "\n").count == 2)
        #expect(arte.cardCount == 50)
        #expect(painting.front == "")
        #expect(painting.back.components(separatedBy: "\n").count == 4)
        #expect(picture?.isEmpty == false)
        #expect(asked?.subject == .fichaDeck(.arteArgentino))
        #expect(asked?.line == .fichaDeck(cardCount: 50))
        #expect(asked?.decksAhead == ["Lenguaje"])
        #expect(window.question == nil)
        #expect(window.offeredFichaDecks == [.palabrasLindas, .floresDeBuenosAires])
        #expect(window.sidebarItem == .cards(.deck(FichaDeck.arteArgentino.name)))
        #expect(try engine.cards().count { $0.deck == FichaDeck.arteArgentino.name } == 50)
    }

    /// The file of `deck` in the repo's `App/FichaDecks/`, five folders up
    /// from this file, which the app bundles: the test fails while it isn't
    /// there.
    private func fileInTheRepo(of deck: FichaDeck) throws -> URL {
        let file = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "App/FichaDecks/\(deck.fileName).zip")
        try #require(
            FileManager.default.fileExists(atPath: file.path(percentEncoded: false)),
            "App/FichaDecks/\(deck.fileName).zip isn't in the repo: add the file of \(deck.name).")
        return file
    }

    /// The cards of `file`, as the Import sheet's import brings a Ficha
    /// package's into a Ficha of their own, without the tag it proposes after
    /// the file's name.
    private func cardsAsTheImportBringsThem(from file: URL) async throws -> [Card] {
        let ficha = try Engine(location: .inMemory, time: time, calendar: calendar)
        let preview = try await ficha.previewImport(of: file)
        let choices = ImportChoices(tagNames: Dictionary(uniqueKeysWithValues: preview.proposedTags.map { ($0, "") }))
        try ficha.importCards(preview, choosing: choices)
        return try ficha.cards()
    }

    /// Adds Arte argentino from `shipped` to a Ficha on the database in the
    /// folder `data`, as Add Deck… does, meets its first two cards, and
    /// reviews the first again once it's due; and returns its cards and the
    /// review log as they are then, once that Ficha is gone.
    private func addArte(from shipped: URL, in data: URL) async throws -> (cards: [Card], log: [ReviewLogEntry]) {
        let ficha = try Engine(location: .folder(data), time: time, ids: CountingIDSource(), calendar: calendar)
        let file = try await ficha.readFichaDeck(.arteArgentino, at: shipped)
        try ficha.add(file)
        let cards = try ficha.cards()
        try #require(cards.count == 50)
        try ficha.meet(cards[0])
        try ficha.meet(cards[1])
        try ficha.reviewWhenDue(cards[0], .good, movingForward: time)
        return (try ficha.cards(), try ficha.reviewLog())
    }

    /// A newer file of Arte argentino than `shipped`, as an update of the app
    /// could bring: its cards, with the first one's back changed, and one
    /// card more, exported as Ficha exports a deck, from a Ficha of its own.
    private func newerArte(than shipped: URL) async throws -> URL {
        let ficha = try Engine(location: .inMemory, time: time, calendar: calendar)
        let preview = try await ficha.previewImport(of: shipped)
        let choices = ImportChoices(tagNames: Dictionary(uniqueKeysWithValues: preview.proposedTags.map { ($0, "") }))
        try ficha.importCards(preview, choosing: choices)
        let first = try #require(try ficha.cards().first)
        let changed = try card(
            first.type, front: first.front, back: first.back + " Restaurada en 2027.", source: first.source,
            frontImage: first.frontImage, backImage: first.backImage)
        try ficha.edit(first.id, with: changed)
        let more = try card(nil, front: "Una pintura más", back: "De alguien.")
        try ficha.create(more, deck: FichaDeck.arteArgentino.name)
        let newer = folder.appending(path: "Newer", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: newer, withIntermediateDirectories: true)
        let file = newer.appending(path: "\(FichaDeck.arteArgentino.fileName).zip")
        try ficha.export(.deck(FichaDeck.arteArgentino.name), to: file)
        return file
    }
}

/// Whether `line` credits a picture as Ficha's decks do: "Imagen: <author> ·
/// <license> · Wikimedia Commons", three parts joined by " · ", with an
/// author, and a license `isLicense(_:)` takes.
private func isCredit(_ line: String) -> Bool {
    let parts = line.components(separatedBy: " · ")
    guard parts.count == 3, parts[0].hasPrefix("Imagen: "), parts[2] == "Wikimedia Commons" else {
        return false
    }
    let author = parts[0].dropFirst("Imagen: ".count)
    return !author.trimmingCharacters(in: .whitespaces).isEmpty && isLicense(parts[1])
}

/// Whether `license` is one a picture of Ficha's decks may have: "Dominio
/// público", "CC0", or "CC BY" or "CC BY-SA" with its version, such as "CC
/// BY-SA 4.0" or "CC BY 2.0".
private func isLicense(_ license: String) -> Bool {
    if license == "Dominio público" || license == "CC0" {
        return true
    }
    for kind in ["CC BY ", "CC BY-SA "] where license.hasPrefix(kind) {
        let version = license.dropFirst(kind.count).split(separator: ".", omittingEmptySubsequences: false)
        return version.count == 2
            && version.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }
    }
    return false
}

extension CardsWindowState {
    /// The decks of Ficha's the sidebar's Ficha's Decks section lists, in its
    /// order: none while it lists none.
    fileprivate var offeredFichaDecks: [FichaDeck] {
        for case .fichaDecks(let files) in sidebarSections {
            return files.map(\.deck)
        }
        return []
    }
}
