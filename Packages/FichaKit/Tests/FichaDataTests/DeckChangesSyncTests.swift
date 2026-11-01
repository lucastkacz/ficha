import FichaCore
import Foundation
import Testing

// For what waits to be sent, the records iCloud holds, and how a deletion's
// record holds the cards it deleted.
@testable import FichaData

/// Tests on renames and deletions of decks across devices (ADR 0024): each
/// reaches every card the other device holds, those that don't sync too, also
/// once a device comes back online, and a deletion deletes there every card
/// the deleting device deleted, on two devices, a Mac and an iPhone, each an
/// engine in memory in Buenos Aires on one clock, syncing through a fake
/// iCloud.
final class DeckChangesSyncTests {
    let time: ManualTimeSource
    let iCloud = FakeICloud()
    let mac: Device
    let iPhone: Device

    init() throws {
        let calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 21, in: calendar))
        mac = try Device(
            Engine(location: .inMemory, time: time, ids: CountingIDSource(device: 1), calendar: calendar),
            syncingThrough: iCloud)
        iPhone = try Device(
            Engine(location: .inMemory, time: time, ids: CountingIDSource(device: 2), calendar: calendar),
            syncingThrough: iCloud)
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
        "a deletion deletes the cards the other device holds that sync, with their review logs, and moves to Default those that don't, which the deleting device never held"
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

    // Default and Arte sync, then the Mac unticks Arte, so La Gioconda
    // leaves iCloud and stays on both devices, while Default stays chosen.
    // Lucas's decision of 2026-10-31, on the spec's review: a deck's deletion
    // deletes the cards its device deleted on every device, whether or not
    // they sync, so that none comes back through Default.
    @Test(
        "a deletion deletes on the other device the cards the deleting one deleted, those that don't sync too, which never go up again through Default"
    )
    func aDeletionDeletesTheCardsThatDontSync() async throws {
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: Deck.defaultName)
        try mac.engine.setChosenToSync(true, ofDeck: "Arte")
        try mac.engine.create(card(.concept, front: "La Gioconda", back: "De Leonardo."), deck: "Arte::Pintura")
        try await syncBoth()
        let gioconda = try #require(records(ofType: .card).only).id
        try mac.engine.setChosenToSync(false, ofDeck: "Arte")
        try await syncBoth()
        #expect(try iPhone.engine.card(fronted: "La Gioconda").deck == "Arte::Pintura")
        let timesSent = iCloud.timesSent(gioconda)

        time.advance(by: minutes(1))
        try mac.engine.deleteDeck("Arte")
        try await syncBoth()

        for device in [mac, iPhone] {
            #expect(try device.engine.cards().isEmpty)
            #expect(try device.engine.decks().isEmpty)
            #expect(try device.engine.changesToSend().isEmpty)
        }
        #expect(iCloud.timesSent(gioconda) == timesSent)
    }

    // As above, and the iPhone adds La Piedad to Arte::Escultura once Arte
    // no longer syncs, so the Mac never holds it.
    @Test(
        "a deletion moves to Default a card the other device holds that the deleting one never did and that doesn't sync, which then syncs there as Default does"
    )
    func aDeletionMovesACardTheDeletingDeviceNeverHeld() async throws {
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: Deck.defaultName)
        try mac.engine.setChosenToSync(true, ofDeck: "Arte")
        try mac.engine.create(card(.concept, front: "La Gioconda", back: "De Leonardo."), deck: "Arte::Pintura")
        try await syncBoth()
        try mac.engine.setChosenToSync(false, ofDeck: "Arte")
        try await syncBoth()
        try iPhone.engine.create(card(.concept, front: "La Piedad", back: "De Miguel Ángel."), deck: "Arte::Escultura")
        try await syncBoth()
        #expect(try mac.engine.cards().map(\.front) == ["La Gioconda"])

        time.advance(by: minutes(1))
        try mac.engine.deleteDeck("Arte")
        try await syncBoth()

        for device in [mac, iPhone] {
            #expect(try device.engine.cards().map { "\($0.front) \($0.deck)" } == ["La Piedad "])
            #expect(try device.engine.changesToSend().isEmpty)
        }
    }

    // iCloud holds 1 MB in a record beside its files.
    @Test("a deletion's record names the first 60,000 cards it deleted, 16 bytes each, and reads them back in order")
    func aDeletionsRecordNamesAtMost60000Cards() throws {
        let cards = (0...60_000).map { _ in UUID() }

        let packed = packedCardIDs(cards)

        #expect(packed.count == 960_000)
        #expect(try unpackedCardIDs(packed) == Array(cards.prefix(60_000)))
        #expect(throws: (any Error).self) { try unpackedCardIDs(packed.dropLast()) }
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

    // Only Idiomas syncs, which the Mac set aside and colored purple. The
    // iPhone made Arte, which has no card and doesn't sync. The iPhone hears
    // of the decks' records, the old names' deletions among them, in one
    // event of its fetch, and of the renames in another, before or after it.
    @Test(
        "a rename heard apart from the deletion of its deck's record, before or after it, moves what the deck has of its own there, and that it was made there",
        arguments: [true, false])
    func aRenameHeardApartFromItsDecksDeletion(deletionFirst: Bool) async throws {
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Idiomas")
        try mac.engine.setAside(deck: "Idiomas")
        try mac.engine.setColor(.purple, ofDeck: "Idiomas")
        try iPhone.engine.makeDeck(named: "Arte")
        try await syncBoth()
        iPhone.iCloud.eventsByType = deletionFirst ? [[.deck], [.deckChange]] : [[.deckChange], [.deck]]

        time.advance(by: minutes(1))
        try mac.engine.renameDeck("Idiomas", to: "Lenguas")
        time.advance(by: minutes(1))
        try mac.engine.renameDeck("Arte", to: "Cultura")
        try await syncBoth()

        for device in [mac, iPhone] {
            #expect(
                try device.engine.decks() == [
                    Deck(name: "Cultura"),
                    Deck(name: "Lenguas", switchedOn: .setAside, color: .purple, chosenToSync: true),
                ])
            #expect(try device.engine.changesToSend().isEmpty)
        }
    }

    // Only Arte syncs. The iPhone adds Guernica to Arte::Pintura once the
    // Mac deleted Arte, before it hears of it, so the Mac never holds it.
    // The iPhone hears of the deletion of Arte's record in one event of its
    // fetch, and of the deck's deletion in another, before or after it, and
    // of La Gioconda's deletion last.
    @Test(
        "a deletion heard apart from the deletion of its deck's record, before or after it, deletes the cards there that sync, never moving one to Default",
        arguments: [true, false])
    func aDeletionHeardApartFromItsDecksDeletion(deletionFirst: Bool) async throws {
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Arte")
        try mac.engine.create(card(.concept, front: "La Gioconda", back: "De Leonardo."), deck: "Arte")
        try await syncBoth()
        iPhone.iCloud.eventsByType = deletionFirst ? [[.deck], [.deckChange]] : [[.deckChange], [.deck]]

        time.advance(by: minutes(1))
        try mac.engine.deleteDeck("Arte")
        try await mac.syncNow()
        try iPhone.engine.create(card(.concept, front: "Guernica", back: "De Picasso."), deck: "Arte::Pintura")
        try await iPhone.syncNow()
        let guernica = try #require(try records(ofType: .card).first { try $0.text("front") == "Guernica" }).id
        // What its deletion changed, before the Mac fetches.
        try await iPhone.send()
        try await syncBoth()

        for device in [mac, iPhone] {
            #expect(try device.engine.cards().isEmpty)
            #expect(try device.engine.decks().isEmpty)
            #expect(try device.engine.changesToSend().isEmpty)
        }
        #expect(iCloud.timesSent(guernica) == 1)
        for type in [SyncedRow.RecordType.card, .deck] {
            #expect(records(ofType: type).isEmpty)
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
