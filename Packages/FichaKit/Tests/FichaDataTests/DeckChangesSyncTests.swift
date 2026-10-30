import FichaCore
import Foundation
import Testing

// For what waits to be sent, and the records iCloud holds.
@testable import FichaData

/// Tests on renames and deletions of decks across devices (ADR 0024): each
/// reaches every card the other device holds, those that don't sync too, also
/// once a device comes back online, on two devices, a Mac and an iPhone, each
/// an engine in memory in Buenos Aires on one clock, syncing through a fake
/// iCloud.
final class DeckChangesSyncTests {
    let time: ManualTimeSource
    let iCloud = FakeICloud()
    let mac: Device
    let iPhone: Device

    init() throws {
        let calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 21, in: calendar))
        mac = try Device(Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: iCloud)
        iPhone = try Device(Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: iCloud)
    }

    // Only Idiomas syncs, so La Gioconda stays on the iPhone; Arte is orange,
    // and the Mac holds no card of it.
    @Test(
        "a rename reaches the cards the other device holds, those that don't sync too, and each deck keeps what it has of its own there"
    )
    func aRenameReachesACardThatDoesntSync() async throws {
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Idiomas")
        try mac.engine.create(card(.word, front: "hello", back: "Hola."), deck: "Idiomas::Inglés")
        try mac.engine.makeDeck(named: "Arte")
        try mac.engine.setColor(.orange, ofDeck: "Arte")
        try await syncBoth()
        try iPhone.engine.create(card(.concept, front: "La Gioconda", back: "De Leonardo."), deck: "Arte::Pintura")
        try await syncBoth()

        time.advance(by: minutes(1))
        try mac.engine.renameDeck("Idiomas", to: "Lenguas")
        time.advance(by: minutes(1))
        try mac.engine.renameDeck("Arte", to: "Cultura::Arte")
        try await syncBoth()

        #expect(try iPhone.engine.card(fronted: "La Gioconda").deck == "Cultura::Arte::Pintura")
        for device in [mac, iPhone] {
            #expect(try device.engine.card(fronted: "hello").deck == "Lenguas::Inglés")
            #expect(
                try device.engine.decks() == [
                    Deck(name: "Cultura"), Deck(name: "Cultura::Arte", color: .orange),
                    Deck(name: "Cultura::Arte::Pintura", inheritedColor: .orange),
                    Deck(name: "Lenguas", chosenToSync: true), Deck(name: "Lenguas::Inglés"),
                ])
            #expect(try device.engine.changesToSend().isEmpty)
        }
        #expect(try records(ofType: .card).map { try $0.text("deck") } == ["Lenguas::Inglés"])
    }

    // Only Arte::Pintura syncs: La Gioconda and Guernica do, La Piedad stays
    // on the iPhone. The Mac reviewed La Gioconda.
    @Test(
        "a deletion deletes the cards the other device holds that sync, with their review logs, and moves those that don't to Default"
    )
    func aDeletionReachesTheOtherDevice() async throws {
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Arte::Pintura")
        let gioconda = try mac.engine.create(
            card(.concept, front: "La Gioconda", back: "De Leonardo."), deck: "Arte::Pintura")
        try mac.engine.meet(gioconda)
        try await syncBoth()
        try iPhone.engine.create(card(.concept, front: "Guernica", back: "De Picasso."), deck: "Arte::Pintura")
        try iPhone.engine.create(card(.concept, front: "La Piedad", back: "De Miguel Ángel."), deck: "Arte::Escultura")
        try await syncBoth()

        time.advance(by: minutes(1))
        try mac.engine.deleteDeck("Arte")
        try await syncBoth()

        #expect(try mac.engine.cards().isEmpty)
        #expect(try mac.engine.decks().isEmpty)
        #expect(try iPhone.engine.cards().map { "\($0.front) \($0.deck)" } == ["La Piedad "])
        #expect(try iPhone.engine.decks().map(\.name) == [Deck.defaultName])
        #expect(try iPhone.engine.reviewLog().isEmpty)
        for type in [SyncedRow.RecordType.card, .reviewLogEntry, .deck] {
            #expect(records(ofType: type).isEmpty)
        }
        for device in [mac, iPhone] {
            #expect(try device.engine.changesToSend().isEmpty)
        }
    }

    // Every card syncs. The Mac renames Historia, and deletes Música, while
    // the iPhone is offline, and syncs again meanwhile; the iPhone, offline,
    // adds Partenón to Historia::Grecia.
    @Test("each change reaches the other device once it comes back online, also to a card it added offline")
    func aChangeHeardAfterComingBackOnline() async throws {
        try mac.engine.create(card(.concept, front: "Coliseo", back: "Un anfiteatro."), deck: "Historia")
        try mac.engine.create(card(.concept, front: "fuga", back: "Una forma musical."), deck: "Música")
        try await syncBoth()

        iPhone.iCloud.isOffline = true
        time.advance(by: minutes(1))
        try mac.engine.renameDeck("Historia", to: "Pasado")
        time.advance(by: minutes(1))
        try mac.engine.deleteDeck("Música")
        try await mac.syncNow()
        try iPhone.engine.create(card(.concept, front: "Partenón", back: "Un templo."), deck: "Historia::Grecia")
        await #expect(throws: FakeICloudError.self) { try await self.iPhone.syncNow() }
        try await mac.syncNow()
        #expect(try Set(iPhone.engine.cards().map(\.deck)) == ["Historia", "Música", "Historia::Grecia"])

        iPhone.iCloud.isOffline = false
        try await syncBoth()

        for device in [mac, iPhone] {
            #expect(
                try Set(device.engine.cards().map { "\($0.front) \($0.deck)" }) == [
                    "Coliseo Pasado", "Partenón Pasado::Grecia",
                ])
            #expect(try device.engine.decks().map(\.name) == ["Pasado", "Pasado::Grecia"])
            #expect(try device.engine.changesToSend().isEmpty)
        }
    }

    // Every card syncs, and Historia has nothing of its own. The iPhone,
    // offline, colors Historia after the Mac renamed it, and before it hears
    // of the rename, so its record comes back to iCloud for a while.
    @Test("a color a device offline meanwhile gave a deck moves with the rename once it hears of it")
    func aDeckColoredOfflineMovesWithTheRename() async throws {
        try mac.engine.create(card(.concept, front: "Coliseo", back: "Un anfiteatro."), deck: "Historia")
        try await syncBoth()

        iPhone.iCloud.isOffline = true
        time.advance(by: minutes(1))
        try mac.engine.renameDeck("Historia", to: "Pasado")
        try await mac.syncNow()
        time.advance(by: minutes(1))
        try iPhone.engine.setColor(.orange, ofDeck: "Historia")
        iPhone.iCloud.isOffline = false
        try await syncBoth()

        for device in [mac, iPhone] {
            #expect(try device.engine.card(fronted: "Coliseo").deck == "Pasado")
            let decks = try device.engine.decks()
            #expect(decks == [Deck(name: "Pasado", color: .orange)])
            #expect(try device.engine.changesToSend().isEmpty)
        }
    }

    // Only Idiomas syncs, and none of its decks has a card. The iPhone made
    // Idiomas::Latín and the Mac Idiomas::Griego; the Mac moves both to the
    // top, where they no longer sync. Each device lists those made on it
    // there: the Mac both, as it moved them, the iPhone Latín alone.
    @Test(
        "under selective sync, an empty deck moved out of a chosen one stays listed on the device that moved it, and on the one that made it"
    )
    func aDeckMovedOutOfAChosenOneStaysListed() async throws {
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Idiomas")
        try iPhone.engine.makeDeck(named: "Idiomas::Latín")
        try mac.engine.makeDeck(named: "Idiomas::Griego")
        try await syncBoth()

        time.advance(by: minutes(1))
        try mac.engine.moveDeck("Idiomas::Latín", into: nil)
        try mac.engine.moveDeck("Idiomas::Griego", into: nil)
        try await syncBoth()

        #expect(try mac.engine.decks().map(\.name) == ["Griego", "Idiomas", "Latín"])
        #expect(try iPhone.engine.decks().map(\.name) == ["Idiomas", "Latín"])
        for device in [mac, iPhone] {
            #expect(try device.engine.changesToSend().isEmpty)
        }
    }

    /// Syncs the Mac, then the iPhone, three times, so that what one sends
    /// as it hears the other reaches it.
    private func syncBoth() async throws {
        for _ in 0..<3 {
            try await mac.syncNow()
            try await iPhone.syncNow()
        }
    }

    /// The records of `type` iCloud holds.
    private func records(ofType type: SyncedRow.RecordType) -> [ICloudRecord] {
        iCloud.records.filter { $0.type == type.rawValue }
    }
}
