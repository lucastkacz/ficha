import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the Cards window following a rename or a deletion of a deck it
/// didn't make (ADR 0024): one the `ficha` CLI makes, another engine on the
/// same database, as the app and the CLI are, or one another device made,
/// heard in a fetch. Once the window reads the cards again, it follows each
/// as it follows its own Rename… and Delete…. On the default scheduler; they
/// start at 9 in the morning in Buenos Aires, when active hours start.
final class CardsWindowDeckChangesTests {
    let time: ManualTimeSource
    let calendar: Calendar
    let scheduler = ReviewSettings.defaults.scheduler
    /// A data folder of the test's own, which the app and the CLI share.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaDataTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 14, in: calendar))
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    // The window opened with the last card added to Arte::Pintura; the
    // sidebar chose Arte, which is closed. The card form's Deck field holds
    // Arte::Escultura, which New Deck… named, and La Gioconda's editor its
    // own deck.
    @Test(
        "a rename the CLI makes is followed once the window reads again: the sidebar, the decks it closed, the card form's deck, the editor's and the last deck added to, so Add never makes the old deck again"
    )
    func aRenameTheCLIMakes() throws {
        let app = try Engine(location: .folder(folder), time: time, calendar: calendar)
        let cli = try Engine(location: .folder(folder), time: time, calendar: calendar)
        let gioconda = try approveInDeck("La Gioconda", deck: "Arte::Pintura", in: app)
        try approveInDeck("Coliseo", deck: "Historia", in: app)
        var window = app.openCardsWindow(with: scheduler, lastDeckAddedTo: "Arte::Pintura")
        window.read(with: scheduler)
        window.choose(.cards(.deck("Arte")))
        window.setDeckOpen(false, "Arte")
        window.openNewCardForm()
        var draft = try #require(window.cardForm?.draft)
        draft.deck = "Arte::Escultura"
        window.changeDraft(draft)
        window.select([gioconda.id])
        window.startEditing()

        try cli.renameDeck("Arte", to: "Cultura::Arte")
        window.read(with: scheduler)

        #expect(window.sidebarItem == .cards(.deck("Cultura::Arte")))
        #expect(!window.isDeckOpen("Cultura::Arte"))
        #expect(window.cardForm?.draft.deck == "Cultura::Arte::Escultura")
        #expect(window.editedDeck == "Cultura::Arte::Pintura")
        #expect(window.lastDeckAddedTo == "Cultura::Arte::Pintura")
        draft = try #require(window.cardForm?.draft)
        draft.front.text = "El David"
        draft.back.text = "De Miguel Ángel."
        window.changeDraft(draft)
        window.addCard()
        #expect(window.failure == nil)
        #expect(
            try app.decks().map(\.name) == [
                "Cultura", "Cultura::Arte", "Cultura::Arte::Escultura", "Cultura::Arte::Pintura", "Historia",
            ])
    }

    // The window opened with the last card added to Arte::Pintura, where
    // the card form started, and Show Card set it aside on petricor.
    // Coliseo's editor holds Arte::Escultura, which New Deck… named.
    @Test(
        "a deletion the CLI makes is let go of once the window reads again: the form Show Card set aside goes to the deck a new card starts in, and the editor and the last deck added to go to Default"
    )
    func aDeletionTheCLIMakes() throws {
        let app = try Engine(location: .folder(folder), time: time, calendar: calendar)
        let cli = try Engine(location: .folder(folder), time: time, calendar: calendar)
        try approveInDeck("petricor", in: app)
        try approveInDeck("La Gioconda", deck: "Arte::Pintura", in: app)
        let coliseo = try approveInDeck("Coliseo", deck: "Historia", in: app)
        var window = app.openCardsWindow(with: scheduler, lastDeckAddedTo: "Arte::Pintura")
        window.read(with: scheduler)
        window.openNewCardForm()
        var draft = try #require(window.cardForm?.draft)
        draft.front.text = "petricor"
        window.changeDraft(draft)
        window.showRepeatedCard()
        window.select([coliseo.id])
        window.startEditing()
        window.setDeckInEditor("Arte::Escultura")

        try cli.deleteDeck("Arte")
        window.read(with: scheduler)

        #expect(window.editedDeck == Deck.defaultName)
        #expect(window.lastDeckAddedTo == Deck.defaultName)
        window.cancelEditing()
        window.openNewCardForm()
        #expect(window.cardForm?.draft.front.text == "petricor")
        #expect(window.cardForm?.draft.deck == Deck.defaultName)
        #expect(window.deckFieldChoices(.form).map(\.name) == [Deck.defaultName, "Historia"])
    }

    // Every card syncs. The window on the Mac opened with the last card
    // added to Idiomas::Inglés, where the card form started, and Coliseo's
    // editor holds Arte.
    @Test(
        "a rename and a deletion another device made, heard in a fetch, are followed once the window reads again"
    )
    func changesHeardFromAnotherDevice() async throws {
        let iCloud = FakeICloud()
        let mac = try Device(Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: iCloud)
        let iPhone = try Device(
            Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: iCloud)
        try approveInDeck("hello", deck: "Idiomas::Inglés", in: mac.engine)
        try approveInDeck("La Gioconda", deck: "Arte", in: mac.engine)
        let coliseo = try approveInDeck("Coliseo", deck: "Historia", in: mac.engine)
        try await syncBoth(mac, iPhone)
        var window = mac.engine.openCardsWindow(with: scheduler, lastDeckAddedTo: "Idiomas::Inglés")
        window.read(with: scheduler)
        window.openNewCardForm()
        window.select([coliseo.id])
        window.startEditing()
        window.setDeckInEditor("Arte")

        time.advance(by: minutes(1))
        try iPhone.engine.renameDeck("Idiomas", to: "Lenguas")
        try iPhone.engine.deleteDeck("Arte")
        try await syncBoth(mac, iPhone)
        window.read(with: scheduler)

        #expect(window.cardForm?.draft.deck == "Lenguas::Inglés")
        #expect(window.lastDeckAddedTo == "Lenguas::Inglés")
        #expect(window.editedDeck == Deck.defaultName)
    }

    // Every card syncs. The iPhone renames Arte to Cultura; then the Mac,
    // which hasn't heard of it, makes a deck Cultura and renames it
    // Humanidades, and only then hears of the iPhone's rename, which its
    // own, made later, follows on. The window on the Mac read after its own
    // rename, with the card form on Arte.
    @Test(
        "a rename heard after one made later is followed with the later one following on, as the device's cards went"
    )
    func aRenameHeardAfterOneMadeLater() async throws {
        let iCloud = FakeICloud()
        let mac = try Device(Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: iCloud)
        let iPhone = try Device(
            Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: iCloud)
        try approveInDeck("La Gioconda", deck: "Arte", in: mac.engine)
        try await syncBoth(mac, iPhone)
        var window = mac.engine.openCardsWindow(with: scheduler)
        window.choose(.cards(.deck("Arte")))
        window.openNewCardForm()

        time.advance(by: minutes(1))
        try iPhone.engine.renameDeck("Arte", to: "Cultura")
        time.advance(by: minutes(1))
        try mac.engine.makeDeck(named: "Cultura")
        try mac.engine.renameDeck("Cultura", to: "Humanidades")
        window.read(with: scheduler)
        try await syncBoth(mac, iPhone)
        window.read(with: scheduler)

        #expect(try mac.engine.cards().map(\.deck) == ["Humanidades"])
        #expect(window.cardForm?.draft.deck == "Humanidades")
    }

    /// Syncs the Mac, then the iPhone, three times, so that what one sends
    /// as it hears the other reaches it.
    private func syncBoth(_ mac: Device, _ iPhone: Device) async throws {
        for _ in 0..<3 {
            try await mac.syncNow()
            try await iPhone.syncNow()
        }
    }
}
