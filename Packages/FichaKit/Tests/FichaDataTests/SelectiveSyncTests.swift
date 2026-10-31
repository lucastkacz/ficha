import FichaCore
import Foundation
import GRDB
import Testing

// For the interface to iCloud's engine, which the fake implements, and for
// what waits to be sent.
@testable import FichaData

/// Tests on selective sync (ADR 0020, as ADR 0024 changes it, #355, #385):
/// which cards go up to iCloud, as the user chooses every card or only those
/// in the decks they tick, on two devices, a Mac and an iPhone, each an
/// engine in memory in Buenos Aires on one clock, syncing through a fake
/// iCloud.
final class SelectiveSyncTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let iCloud = FakeICloud()
    let mac: Device
    let iPhone: Device
    /// A data folder of the test's own, for an app and the CLI to share.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaSelectiveSyncTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 21, in: calendar))
        mac = try Device(Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: iCloud)
        iPhone = try Device(Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: iCloud)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    @Test(
        "while only the cards in a chosen deck sync, one goes up with its review log, flag and burial, and one in another deck, or in Default, stays on its device"
    )
    func onlyTheCardsInAChosenDeckSync() async throws {
        let ubuntu = try mac.engine.create(
            card(.concept, front: "ubuntu", back: "Soy porque somos.", tags: ["zulú"]), deck: "Filosofía")
        try mac.engine.meet(ubuntu)
        try mac.engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        try mac.engine.bury(ubuntu.id)
        let petricor = try mac.engine.create(
            card(.word, front: "petricor", back: "El olor de la lluvia.", tags: ["filosofía"]), deck: "Lenguaje")
        try mac.engine.meet(petricor)
        try mac.engine.create(card(.word, front: "saudade", back: "Nostalgia de lo que se fue."))
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Filosofía")

        try await mac.syncNow()
        try await iPhone.syncNow()

        #expect(try iPhone.cardsAsSeen() == [try mac.engine.card(fronted: "ubuntu").asSeen])
        #expect(try iPhone.logAsSeen().map(\.uuid) == [try ubuntusEntry(on: mac)])
        #expect(records(ofType: .card).count == 1)
        #expect(records(ofType: .reviewLogEntry).count == 1)
        #expect(try mac.engine.changesToSend().isEmpty)
    }

    // Idiomas is chosen; Idiomas antiguos only starts with its name. lunfardo
    // comes once Idiomas is chosen, in a deck made then, two levels in.
    @Test(
        "a card in a deck inside a chosen deck syncs, however deep, a new deck's too, and one in a deck whose name only starts the same doesn't"
    )
    func aDeckInsideAChosenDeckSyncs() async throws {
        try mac.engine.create(card(.word, front: "idioma", back: "La lengua de un pueblo."), deck: "Idiomas")
        try mac.engine.create(
            card(.word, front: "sobremesa", back: "La charla después de comer."), deck: "Idiomas::Español")
        try mac.engine.create(
            card(.word, front: "fiaca", back: "Pereza, desgano."), deck: "Idiomas::Español::Rioplatense")
        try mac.engine.create(card(.word, front: "rosa", back: "Rosa, rosae."), deck: "Idiomas antiguos")
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Idiomas")
        try mac.engine.create(
            card(.word, front: "lunfardo", back: "La jerga porteña."), deck: "Idiomas::Jergas::Porteñas")

        try await syncBoth()

        #expect(try Set(iPhone.engine.cards().map(\.front)) == ["idioma", "sobremesa", "fiaca", "lunfardo"])
        #expect(try iPhone.engine.card(fronted: "fiaca").deck == "Idiomas::Español::Rioplatense")
        #expect(try mac.engine.changesToSend().isEmpty)
    }

    // The Mac's keyboard writes í as one character, and text from elsewhere
    // can write it as an i and an accent, which Swift takes for the same name
    // and the database's SQL doesn't: a deck's name is kept as the one
    // character.
    @Test("a deck whose accent is written apart syncs with the chosen deck it sits inside")
    func aDeckWithItsAccentWrittenApartSyncs() async throws {
        try mac.engine.create(
            card(.concept, front: "cepo", back: "Un límite a la compra de dólares."),
            deck: "Economi\u{301}a::Argentina")
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Econom\u{ED}a")
        try await syncBoth()

        #expect(try iPhone.engine.cards().map(\.front) == ["cepo"])
    }

    // The deletion is recorded as the card goes, by the database's triggers,
    // with what syncs then.
    @Test("deleting a card in a deck inside a chosen deck deletes it on every device")
    func deletingACardInsideAChosenDeck() async throws {
        let cepo = try mac.engine.create(
            card(.concept, front: "cepo", back: "Un límite a la compra de dólares."), deck: "Economía::Argentina")
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Economía")
        try await syncBoth()
        #expect(try iPhone.engine.cards().map(\.front) == ["cepo"])

        try mac.engine.delete([cepo.id])
        try await syncBoth()

        #expect(try iPhone.engine.cards().isEmpty)
        #expect(records(ofType: .card).isEmpty)
    }

    @Test("Default can be chosen, and its cards sync without the cards of any other deck")
    func defaultCanBeChosen() async throws {
        try mac.engine.create(card(.word, front: "saudade", back: "Nostalgia de lo que se fue."))
        try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."), deck: "Lenguaje")
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: Deck.defaultName)

        try await syncBoth()

        #expect(try iPhone.engine.cards().map(\.front) == ["saudade"])
        for device in [mac, iPhone] {
            #expect(try chosenDecks(on: device) == [Deck.defaultName])
        }
    }

    // The Mac chooses first, the iPhone after; then the iPhone unticks
    // Filosofía, and the Mac, later still, has every card sync again.
    @Test("the choice of what syncs travels, and each of its parts keeps its latest change, whichever device made it")
    func theChoiceTravels() async throws {
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Filosofía")
        time.advance(by: minutes(1))
        try iPhone.engine.setChosenToSync(true, ofDeck: "Lenguaje")
        try await syncBoth()

        for device in [mac, iPhone] {
            #expect(try device.engine.syncsOnlyChosenDecks())
            #expect(try chosenDecks(on: device) == ["Filosofía", "Lenguaje"])
        }

        time.advance(by: minutes(1))
        try iPhone.engine.setChosenToSync(false, ofDeck: "Filosofía")
        time.advance(by: minutes(1))
        try mac.engine.syncOnlyChosenDecks(false)
        try await syncBoth()

        for device in [mac, iPhone] {
            #expect(try !device.engine.syncsOnlyChosenDecks())
            #expect(try chosenDecks(on: device) == ["Lenguaje"])
        }
    }

    // Chosen on the iPhone, which has no card in the deck: the Mac hears it,
    // and sends its card, which never went up, with its first view and image.
    @Test("a card that starts syncing goes up whole, with its review log and its images")
    func aCardThatStartsSyncingGoesUpWhole() async throws {
        let bird = try mac.engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let hornero = try mac.engine.create(
            card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird), deck: "Aves")
        try mac.engine.meet(hornero)
        try mac.engine.syncOnlyChosenDecks(true)
        try await syncBoth()

        #expect(try iPhone.engine.cards().isEmpty)
        #expect(!iCloud.records.contains { $0.id == SyncedFile(bird).recordID })

        time.advance(by: minutes(1))
        try iPhone.engine.setChosenToSync(true, ofDeck: "Aves")
        try await syncBoth()

        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
        #expect(try iPhone.logAsSeen() == mac.logAsSeen())
        #expect(try iPhone.engine.keptImages() == [bird])
    }

    // Filosofía is chosen, and the card lives in Aves: the Mac moves it to
    // Filosofía, or has every card sync.
    @Test(
        "a card starts syncing, and goes up whole, as it moves into a chosen deck, or as every card syncs again",
        arguments: [true, false])
    func aCardStartsSyncingInEachWay(movingIntoAChosenDeck: Bool) async throws {
        let hornero = try mac.engine.create(
            card(nil, front: "¿Qué pájaro es?", back: "Un hornero."), deck: "Aves")
        try mac.engine.meet(hornero)
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Filosofía")
        try await syncBoth()

        #expect(try iPhone.engine.cards().isEmpty)

        time.advance(by: minutes(1))
        if movingIntoAChosenDeck {
            try mac.engine.changeDeck(of: [hornero.id], to: "Filosofía")
        } else {
            try mac.engine.syncOnlyChosenDecks(false)
        }
        try await syncBoth()

        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
        #expect(try iPhone.logAsSeen() == mac.logAsSeen())
    }

    // The file proposes Idiomas::Latín, inside the chosen Idiomas, and
    // Himnos, which no device chose.
    @Test(
        "a card an import brings into a new deck inside a chosen one syncs, and one in any other new deck stays on its device"
    )
    func aNewDeckInsideAChosenOneSyncs() async throws {
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Idiomas")
        let read = [
            ImportedCard(
                content: try card(.word, front: "rosa", back: "Rosa, rosae."), fields: [], line: 1,
                deck: "Idiomas::Latín"),
            ImportedCard(
                content: try card(nil, front: "¿Qué himno es?", back: "El de la Argentina."), fields: [], line: 2,
                deck: "Himnos"),
        ]
        let preview = try mac.engine.preview(
            ImportReading(cards: read, leftOut: []), of: "Himnos.txt", kind: .cardsFile, images: [:], sounds: [:])
        try mac.engine.importCards(preview, choosing: ImportChoices())
        try await syncBoth()

        #expect(try mac.engine.card(fronted: "¿Qué himno es?").deck == "Himnos")
        #expect(try iPhone.engine.cards().map(\.front) == ["rosa"])
        for device in [mac, iPhone] {
            #expect(try chosenDecks(on: device) == ["Idiomas"])
        }
    }

    @Test(
        "a card that stops syncing leaves iCloud, with its review log and images, and every device keeps its copy, without sending it again"
    )
    func aCardThatStopsSyncingLeavesICloud() async throws {
        let bird = try mac.engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let hornero = try mac.engine.create(
            card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", tags: ["aves"], frontImage: bird), deck: "Aves")
        try mac.engine.meet(hornero)
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Aves")
        try await syncBoth()
        let asSeen = try mac.cardsAsSeen()

        time.advance(by: minutes(1))
        try iPhone.engine.setChosenToSync(false, ofDeck: "Aves")
        try await syncBoth()
        let saves = iCloud.saves
        try await syncBoth()

        for device in [mac, iPhone] {
            #expect(try device.cardsAsSeen() == asSeen)
            #expect(try device.logAsSeen().map(\.kind) == [.firstView])
            #expect(try device.engine.keptImages() == [bird])
            #expect(try device.engine.changesToSend().isEmpty)
        }
        expectOnlyLeft(records(ofType: .card), keeping: [.deck])
        expectOnlyLeft(records(ofType: .reviewLogEntry), keeping: [])
        #expect(!iCloud.records.contains { $0.id == SyncedFile(bird).recordID })
        #expect(iCloud.saves == saves)
    }

    // The Mac unticks Aves, and sends why, then the card as one that left.
    // The iPhone hears them in either order, each in a fetch of its own.
    @Test(
        "a card that stops syncing stays on a device that hears it left before it hears why, and on one that hears why first",
        arguments: [true, false])
    func whicheverArrivesFirst(leftFirst: Bool) async throws {
        try mac.engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero."), deck: "Aves")
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Aves")
        try await syncBoth()
        let asSeen = try mac.cardsAsSeen()

        time.advance(by: minutes(1))
        try mac.engine.setChosenToSync(false, ofDeck: "Aves")
        try await mac.syncNow()
        try await mac.syncNow()
        let left = try #require(records(ofType: .card).only)
        let why = try #require(records(ofType: .deck).only)
        #expect(left.hasLeft)
        let stretch = try #require(try iPhone.engine.syncStretch())
        for record in leftFirst ? [left, why] : [why, left] {
            try iPhone.sync.handle(
                .fetchedRecordZoneChanges(.init(modifications: [record], deletions: [])), from: iPhone.iCloud,
                startedIn: stretch)
            try iPhone.sync.handle(.didFetchChanges, from: iPhone.iCloud, startedIn: stretch)
            #expect(try iPhone.cardsAsSeen() == asSeen)
        }
        try await syncBoth(times: 3)

        for device in [mac, iPhone] {
            #expect(try device.cardsAsSeen() == asSeen)
            #expect(try chosenDecks(on: device).isEmpty)
            #expect(try device.engine.changesToSend().isEmpty)
        }
        expectOnlyLeft(records(ofType: .card), keeping: [.deck])
    }

    // Zulú isn't chosen: the card leaves as Change Deck moves it there out of
    // Filosofía, and the record that left holds its new deck, which says why.
    @Test(
        "a card that Change Deck moves into a deck that isn't chosen leaves iCloud, each device keeps it, and the other device takes its new deck"
    )
    func aCardThatLeavesAsItsDeckChanges() async throws {
        let ubuntu = try mac.engine.create(
            card(.concept, front: "ubuntu", back: "Soy porque somos."), deck: "Filosofía")
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Filosofía")
        try await syncBoth()

        time.advance(by: minutes(1))
        try mac.engine.changeDeck(of: [ubuntu.id], to: "Zulú")
        try await syncBoth()

        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
        #expect(try iPhone.engine.card(fronted: "ubuntu").deck == "Zulú")
        expectOnlyLeft(records(ofType: .card), keeping: [.deck])
        let left = try #require(records(ofType: .card).only)
        #expect(left.value(of: SyncedField.deck.rawValue) == .string("Zulú"))
    }

    // Zulú isn't chosen: ubuntu leaves as the Mac moves it there, and the
    // iPhone, which kept its copy, moves it back to Filosofía.
    @Test(
        "a card that left iCloud as Change Deck moved it syncs again as it moves back into a chosen deck, and reaches the other device"
    )
    func aCardThatLeftSyncsAgainAsItMovesBack() async throws {
        let ubuntu = try mac.engine.create(
            card(.concept, front: "ubuntu", back: "Soy porque somos."), deck: "Filosofía")
        try mac.engine.meet(ubuntu)
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Filosofía")
        try await syncBoth()
        time.advance(by: minutes(1))
        try mac.engine.changeDeck(of: [ubuntu.id], to: "Zulú")
        try await syncBoth()
        expectOnlyLeft(records(ofType: .card), keeping: [.deck])

        time.advance(by: minutes(1))
        try iPhone.engine.changeDeck(of: [iPhone.engine.card(fronted: "ubuntu").id], to: "Filosofía")
        try await syncBoth()

        #expect(try mac.engine.card(fronted: "ubuntu").deck == "Filosofía")
        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
        #expect(try iPhone.logAsSeen() == mac.logAsSeen())
        #expect(records(ofType: .card).map(\.hasLeft) == [false])
        #expect(try mac.engine.changesToSend().isEmpty)
    }

    @Test("a card deleted while it doesn't sync is deleted on that device alone, and one that never synced too")
    func aCardDeletedWhileItDoesntSyncStaysElsewhere() async throws {
        let ubuntu = try mac.engine.create(
            card(.concept, front: "ubuntu", back: "Soy porque somos."), deck: "Filosofía")
        let petricor = try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Filosofía")
        try await syncBoth()
        time.advance(by: minutes(1))
        try mac.engine.setChosenToSync(false, ofDeck: "Filosofía")
        try await syncBoth()

        try mac.engine.delete([ubuntu.id, petricor.id])
        try await syncBoth()

        #expect(try mac.engine.cards().isEmpty)
        #expect(try iPhone.engine.cards().map(\.front) == ["ubuntu"])
        expectOnlyLeft(records(ofType: .card), keeping: [.deck])
        #expect(try mac.engine.changesToSend().isEmpty)
    }

    // Neither device hears the other before it sends: the Mac deletes
    // ubuntu, which syncs there, and the iPhone moves it to Zulú, a deck
    // both know that isn't chosen; the deletion reaches iCloud first, or the
    // card's record as one that left does.
    @Test(
        "a card deleted on one device while the other moves it into a deck that isn't chosen is gone from both, whichever sends first",
        arguments: [true, false])
    func aDeletionWinsOverAMoveOutOfWhatSyncs(deletionFirst: Bool) async throws {
        let ubuntu = try mac.engine.create(
            card(.concept, front: "ubuntu", back: "Soy porque somos."), deck: "Filosofía")
        try mac.engine.makeDeck(named: "Zulú")
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Filosofía")
        try await syncBoth()

        time.advance(by: minutes(1))
        try mac.engine.delete([ubuntu.id])
        try iPhone.engine.changeDeck(of: [iPhone.engine.card(fronted: "ubuntu").id], to: "Zulú")
        let (first, second) = deletionFirst ? (mac, iPhone) : (iPhone, mac)
        try await first.send()
        #expect(records(ofType: .card).map(\.hasLeft) == (deletionFirst ? [] : [true]))
        try await second.send()
        try await syncBoth()

        for device in [mac, iPhone] {
            #expect(try device.engine.cards().isEmpty)
            #expect(try device.engine.changesToSend().isEmpty)
        }
        #expect(records(ofType: .card).isEmpty)
    }

    // Each device reviews the card while it doesn't sync, the Mac first.
    @Test("ticking a deck again joins the copies on both devices, with the reviews each made meanwhile")
    func tickingAgainJoins() async throws {
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."), deck: "Zulú")
        try mac.engine.meet(ubuntu)
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Zulú")
        try await syncBoth()
        let ubuntuOnIPhone = try iPhone.engine.card(fronted: "ubuntu")
        time.advance(by: minutes(1))
        try mac.engine.setChosenToSync(false, ofDeck: "Zulú")
        try await syncBoth()
        let ladder = ReviewSettings.defaults.ladder

        time.move(to: try #require(try mac.engine.standing(of: ubuntu.id, on: ladder).due))
        try mac.engine.review(ubuntu, .good)
        time.advance(by: minutes(30))
        try iPhone.engine.review(ubuntuOnIPhone, .good)
        try await syncBoth()

        #expect(try mac.logAsSeen().count == 2)
        #expect(try iPhone.logAsSeen().count == 2)

        time.advance(by: minutes(1))
        try iPhone.engine.setChosenToSync(true, ofDeck: "Zulú")
        try await syncBoth(times: 3)

        #expect(try mac.logAsSeen().map(\.kind) == [.firstView, .review(.good), .review(.good)])
        #expect(try iPhone.logAsSeen() == mac.logAsSeen())
        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
        #expect(
            try iPhone.engine.standing(of: ubuntuOnIPhone.id, on: ladder)
                == mac.engine.standing(of: ubuntu.id, on: ladder))
        #expect(records(ofType: .card).allSatisfy { !$0.hasLeft && $0.value(of: "front") == .string("ubuntu") })
    }

    @Test("an expansion or a follow-up of a card that doesn't sync stays on its device, and every other capture syncs")
    func capturesFollowTheirCards() async throws {
        let ubuntu = try approveInDeck("ubuntu", deck: "Filosofía", in: mac.engine)
        let petricor = try approveInDeck("petricor", in: mac.engine)
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Filosofía")
        try mac.engine.newCapture("saudade")
        try mac.engine.followUp(ubuntu.id, text: "¿Quién lo dijo primero?")
        try mac.engine.followUp(petricor.id, text: "¿De qué idioma viene?")
        try mac.engine.expand(text: "petricor", note: "Del griego", source: nil)

        try await syncBoth()

        #expect(
            try iPhone.engine.inbox().asSeen
                == InboxAsSeen(captures: ["saudade"], expansions: [], followUps: ["¿Quién lo dijo primero? → ubuntu"]))
        #expect(try mac.engine.changesToSend().isEmpty)
    }

    @Test("what the CLI writes follows the choice, as the app's own changes do")
    func whatTheCLIWritesFollowsTheChoice() async throws {
        let cli = try Engine(location: .folder(folder), time: time, calendar: calendar)
        let app = try Device(Engine(location: .folder(folder), time: time, calendar: calendar), syncingThrough: iCloud)
        try cli.syncOnlyChosenDecks(true)
        try cli.setChosenToSync(true, ofDeck: "Filosofía")
        try cli.create(card(.concept, front: "ubuntu", back: "Soy porque somos."), deck: "Filosofía")
        try cli.create(card(.word, front: "petricor", back: "El olor de la lluvia."), deck: "Lenguaje")

        try await app.syncNow()
        try await iPhone.syncNow()

        #expect(try iPhone.engine.cards().map(\.front) == ["ubuntu"])
        #expect(try chosenDecks(on: iPhone) == ["Filosofía"])
    }

    // Before decks, historia was chosen to sync and ciencia wasn't; the
    // update left every card in Default, chosen here so that both cards are
    // in iCloud, and on the iPhone, as the conversion runs.
    @Test(
        "with Default chosen, a card whose tag was chosen to sync before decks stays in iCloud as turning the tag into a deck moves it there, chosen in the same write, and one whose tag wasn't leaves, kept on both devices, the other's copy with its tags"
    )
    func withDefaultChosenACardOfAChosenTagStaysInICloud() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try saveDatabaseBeforeDecks(at: folder.appending(path: "Ficha.sqlite"), at: time.now)
        let app = try Device(Engine(location: .folder(folder), time: time, calendar: calendar), syncingThrough: iCloud)
        try app.engine.syncOnlyChosenDecks(true)
        try app.engine.setChosenToSync(true, ofDeck: Deck.defaultName)
        try await app.syncNow()
        try await iPhone.syncNow()
        #expect(try Set(iPhone.engine.cards().map(\.front)) == ["Coliseo", "ADN"])

        time.advance(by: minutes(1))
        try app.engine.convertTagsToDecks(["historia", "ciencia"])

        #expect(try !app.engine.changesToSend().contains { $0.kind == .deleted && $0.row.recordType == .card })
        for _ in 0..<2 {
            try await app.syncNow()
            try await iPhone.syncNow()
        }
        #expect(try iPhone.engine.card(fronted: "Coliseo").deck == "historia::Roma")
        #expect(try iPhone.engine.card(fronted: "Coliseo").asSeen == app.engine.card(fronted: "Coliseo").asSeen)
        // ADN left iCloud with its deck alone, as a card does that stops
        // syncing: the iPhone's copy keeps the tag it had.
        #expect(try iPhone.engine.card(fronted: "ADN").deck == "ciencia")
        #expect(try iPhone.engine.card(fronted: "ADN").tags == ["ciencia"])
        let coliseo = try #require(records(ofType: .card).first { $0.value(of: "front") == .string("Coliseo") })
        #expect(!coliseo.hasLeft)
        #expect(coliseo.value(of: SyncedField.deck.rawValue) == .string("historia::Roma"))
        expectOnlyLeft(records(ofType: .card).filter { $0.value(of: "front") != .string("Coliseo") }, keeping: [.deck])
        #expect(try chosenDecks(on: iPhone) == [Deck.defaultName, "historia"])
    }

    // The Mac makes Arte and Historia empty, holds cards in Lenguaje and in
    // Default, which aren't chosen, and makes Idiomas::Latín, inside the
    // Idiomas the iPhone chose; the iPhone makes Música empty, and Filosofía's
    // cards come to it.
    @Test(
        "under selective sync, each device lists the decks that sync, those it holds cards of and those made on it, and every deck once every card syncs, as `ficha decks` does all along"
    )
    func whichDecksEachDeviceLists() async throws {
        try mac.engine.makeDeck(named: "Arte")
        try mac.engine.makeDeck(named: "Historia")
        try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."), deck: "Lenguaje")
        try mac.engine.create(card(.word, front: "saudade", back: "Nostalgia de lo que se fue."))
        try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."), deck: "Filosofía")
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Filosofía")
        try iPhone.engine.makeDeck(named: "Música")
        try iPhone.engine.setChosenToSync(true, ofDeck: "Idiomas")
        try await syncBoth()
        try mac.engine.makeDeck(named: "Idiomas::Latín")
        try await syncBoth()

        #expect(
            try mac.engine.decks().map(\.name)
                == [Deck.defaultName, "Arte", "Filosofía", "Historia", "Idiomas", "Idiomas::Latín", "Lenguaje"])
        #expect(try iPhone.engine.decks().map(\.name) == ["Filosofía", "Idiomas", "Idiomas::Latín", "Música"])
        let every = [
            Deck.defaultName, "Arte", "Filosofía", "Historia", "Idiomas", "Idiomas::Latín", "Lenguaje", "Música",
        ]
        // `ficha decks` lists every deck, as the Sync tab does, for a refine
        // session to draft into and choose from.
        let iPhoneLadder = try iPhone.engine.progressSettings().ladder
        #expect(try iPhone.engine.countedDecks(on: iPhoneLadder, asTheSyncTabLists: true).map(\.deck.name) == every)

        try iPhone.engine.syncOnlyChosenDecks(false)
        try await syncBoth()

        #expect(try mac.engine.decks().map(\.name) == every)
        #expect(try iPhone.engine.decks().map(\.name) == every)
    }

    // The Mac makes Música empty, which the iPhone hears of and doesn't list,
    // since it neither syncs nor holds cards there, until it makes Música
    // too: by its name, or by moving a card there, as New Deck… in the
    // Change Deck sheet does, and deleting it.
    @Test(
        "under selective sync, a deck heard of from the other device and then made here is listed here",
        arguments: [false, true])
    func aDeckHeardOfAndThenMadeHereIsListed(byChangeDeck: Bool) async throws {
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.makeDeck(named: "Música")
        try await syncBoth()

        #expect(try iPhone.engine.decks().isEmpty)

        if byChangeDeck {
            let saudade = try iPhone.engine.create(card(.word, front: "saudade", back: "Nostalgia de lo que se fue."))
            try iPhone.engine.changeDeck(of: [saudade.id], to: "Música")
            try iPhone.engine.delete([saudade.id])
        } else {
            try iPhone.engine.makeDeck(named: "Música")
        }

        #expect(try iPhone.engine.decks().map(\.name) == ["Música"])
    }

    // Every card syncs while the iPhone colors Historia, which it knows from
    // coliseo's deck, Historia::Roma; then only Idiomas syncs, and the Mac
    // moves coliseo there.
    @Test(
        "under selective sync, a deck a device only colored, which it knew from a card, isn't listed there once the card leaves it"
    )
    func aDeckOnlyColoredHereIsntListedOnceItsCardLeaves() async throws {
        let coliseo = try mac.engine.create(
            card(.concept, front: "Coliseo", back: "Un anfiteatro."), deck: "Historia::Roma")
        try await syncBoth()
        try iPhone.engine.setColor(.blue, ofDeck: "Historia")
        try await syncBoth()

        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Idiomas")
        try mac.engine.changeDeck(of: [coliseo.id], to: "Idiomas")
        try await syncBoth()

        #expect(try iPhone.engine.decks().map(\.name) == ["Idiomas"])
        #expect(try mac.engine.decks().map(\.name) == ["Historia", "Historia::Roma", "Idiomas"])
    }

    // The iPhone holds petricor in Lenguaje, which doesn't sync, and colors
    // its tag palabras, whose row syncs; the Mac holds no card with it.
    @Test(
        "Clear Unused Tags under selective sync deletes a tag's own row alone, and another device's card that doesn't sync keeps the tag"
    )
    func clearUnusedTagsLeavesOtherDevicesCardsTheirTags() async throws {
        try iPhone.engine.syncOnlyChosenDecks(true)
        try iPhone.engine.create(
            card(.word, front: "petricor", back: "El olor de la lluvia.", tags: ["palabras"]), deck: "Lenguaje")
        try iPhone.engine.setColor(.green, of: "palabras")
        try await syncBoth()

        #expect(try mac.engine.unusedTags() == ["palabras"])
        #expect(try mac.engine.clearUnusedTags() == ["palabras"])
        try await syncBoth()

        #expect(try mac.engine.allTags().isEmpty)
        #expect(try iPhone.engine.card(fronted: "petricor").tags == ["palabras"])
        #expect(try iPhone.engine.allTags() == [CardTag(name: "palabras")])
        #expect(records(ofType: .tagChange).isEmpty)
    }

    /// Syncs the Mac, then the iPhone, `times` times, so that what one sends
    /// as it hears the other reaches it: a device sends what a fetch had it
    /// note at its next sync.
    private func syncBoth(times: Int = 3) async throws {
        for _ in 0..<times {
            try await mac.syncNow()
            try await iPhone.syncNow()
        }
    }

    /// The records of `type` iCloud holds.
    private func records(ofType type: SyncedRow.RecordType) -> [ICloudRecord] {
        iCloud.records.filter { $0.type == type.rawValue }
    }

    /// Checks that each of `records` is one that left iCloud, holding the
    /// fields `kept` and nothing else but when each last changed, for those
    /// that ever changed.
    private func expectOnlyLeft(_ records: [ICloudRecord], keeping kept: [SyncedField]) {
        #expect(!records.isEmpty)
        let keys = Set(kept.flatMap { [$0.rawValue, $0.timeKey] }).union(["left"])
        for record in records {
            let held = Set(record.fields.compactMap { $0.value == nil ? nil : $0.key })
            #expect(record.hasLeft)
            #expect(held.isSubset(of: keys))
            #expect(held.isSuperset(of: kept.map(\.rawValue)))
        }
    }

    /// The names of the decks chosen to sync on `device`, as every deck
    /// lists them once every card syncs, or as the Sync tab does.
    private func chosenDecks(on device: Device) throws -> Set<String> {
        let tab = device.engine.openSyncTab()
        let listed = tab.onlyChosenDecks ? tab.deckLines.map(\.node.deck) : try device.engine.decks()
        return Set(listed.filter(\.chosenToSync).map(\.name))
    }

    /// The ID of ubuntu's only entry in `device`'s review log.
    private func ubuntusEntry(on device: Device) throws -> UUID? {
        let ubuntu = try device.engine.card(fronted: "ubuntu")
        return try #require(try device.engine.reviewLog().filter { $0.cardID == ubuntu.id }.only).uuid
    }
}
