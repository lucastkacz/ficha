import FichaCore
import Foundation
import Testing

// For what waits to be sent, and the records iCloud holds.
@testable import FichaData

/// Tests on renames and deletions of tags across devices (ADR 0022): each
/// reaches every card the other device holds, those that don't sync too, also
/// once a device comes back online, on two devices, a Mac and an iPhone, each
/// an engine in memory in Buenos Aires on one clock, syncing through a fake
/// iCloud.
final class TagChangesSyncTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let iCloud = FakeICloud()
    let mac: Device
    let iPhone: Device

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 21, in: calendar))
        mac = try Device(Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: iCloud)
        iPhone = try Device(Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: iCloud)
    }

    // Only Filosofía syncs, so ubuntu and cepo stay on the iPhone; economía
    // is orange on the Mac, which holds no card of it.
    @Test(
        "a rename reaches a card the other device holds and doesn't sync, and the tag keeps its color there"
    )
    func aRenameReachesACardThatDoesntSync() async throws {
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Filosofía")
        try mac.engine.setColor(.orange, of: "economía")
        try await syncBoth()
        try iPhone.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos.", tags: ["economía"]))
        try iPhone.engine.create(
            card(.concept, front: "cepo", back: "Un límite a la compra de dólares.", tags: ["economía::Argentina"]))
        try await syncBoth()

        time.advance(by: minutes(1))
        try mac.engine.renameTag("economía", to: "economics")
        try await syncBoth()

        #expect(try iPhone.engine.card(fronted: "ubuntu").tags == ["economics"])
        #expect(try iPhone.engine.card(fronted: "cepo").tags == ["economics::Argentina"])
        let iPhonesTags = try iPhone.engine.allTags()
        #expect(
            iPhonesTags == [
                CardTag(name: "economics", color: .orange),
                CardTag(name: "economics::Argentina", inheritedColor: .orange),
            ])
        #expect(records(ofType: .card).isEmpty)
        for device in [mac, iPhone] {
            #expect(try device.engine.changesToSend().isEmpty)
        }
    }

    @Test("a deletion reaches a card the other device holds and doesn't sync, and deletes no card there")
    func aDeletionReachesACardThatDoesntSync() async throws {
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Filosofía")
        try mac.engine.setColor(.green, of: "economía")
        try await syncBoth()
        try iPhone.engine.create(
            card(
                .concept, front: "cepo", back: "Un límite a la compra de dólares.",
                tags: ["economía::Argentina", "zulú"]))
        try await syncBoth()

        time.advance(by: minutes(1))
        try mac.engine.deleteTags(["economía"])
        try await syncBoth()

        #expect(try iPhone.engine.cards().map(\.tags) == [["zulú"]])
        let iPhonesTags = try iPhone.engine.allTags().map(\.name)
        #expect(iPhonesTags == ["zulú"])
        for device in [mac, iPhone] {
            #expect(try device.engine.changesToSend().isEmpty)
        }
    }

    // The Mac deletes literatura and renames economía while the iPhone is
    // offline, and syncs again meanwhile.
    @Test("each change reaches the other device once it comes back online")
    func aChangeHeardAfterComingBackOnline() async throws {
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Filosofía")
        try await syncBoth()
        try iPhone.engine.create(card(.concept, front: "cepo", back: "Un límite.", tags: ["economía", "literatura"]))
        try await syncBoth()

        iPhone.iCloud.isOffline = true
        time.advance(by: minutes(1))
        try mac.engine.deleteTags(["literatura"])
        time.advance(by: minutes(1))
        try mac.engine.renameTag("economía", to: "economics")
        try await mac.syncNow()
        await #expect(throws: FakeICloudError.self) { try await self.iPhone.syncNow() }
        try await mac.syncNow()
        #expect(try iPhone.engine.card(fronted: "cepo").tags == ["economía", "literatura"])

        iPhone.iCloud.isOffline = false
        try await syncBoth()

        #expect(try iPhone.engine.card(fronted: "cepo").tags == ["economics"])
    }

    // Both cards live in Filosofía, which is chosen; cepo carries the tag
    // filosofía alone, beside zulú, and inflación beside economía.
    @Test("a deletion of a tag changes for no card whether it syncs, since decks decide it")
    func aDeletionChangesNothingOfWhatSyncs() async throws {
        try mac.engine.create(
            card(.concept, front: "cepo", back: "Un límite a la compra de dólares.", tags: ["filosofía", "zulú"]),
            deck: "Filosofía")
        try mac.engine.create(
            card(.concept, front: "inflación", back: "Suben los precios.", tags: ["filosofía", "economía"]),
            deck: "Filosofía")
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Filosofía")
        try await syncBoth()
        #expect(try iPhone.engine.cards().count == 2)

        time.advance(by: minutes(1))
        try mac.engine.deleteTags(["filosofía"])
        try await syncBoth()

        for device in [mac, iPhone] {
            #expect(try device.engine.card(fronted: "cepo").tags == ["zulú"])
            #expect(try device.engine.card(fronted: "inflación").tags == ["economía"])
            #expect(try device.engine.changesToSend().isEmpty)
        }
        let cards = records(ofType: .card)
        #expect(cards.filter(\.hasLeft).isEmpty)
        #expect(cards.count == 2)
    }

    // Every card syncs. The iPhone, offline, puts economía on cepo after the
    // Mac renamed it, before it hears of the rename; once it has, it puts
    // economía on ubuntu.
    @Test(
        "a card given the old name before its device hears of the rename is renamed then, and one given it after keeps it, as a tag with nothing of its own"
    )
    func aCardGivenTheOldNameBeforeOrAfterHearingOfTheRename() async throws {
        try mac.engine.create(card(.concept, front: "inflación", back: "Suben los precios.", tags: ["economía"]))
        try mac.engine.create(card(.concept, front: "cepo", back: "Un límite.", tags: ["Argentina"]))
        try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos.", tags: ["filosofía"]))
        try mac.engine.setColor(.green, of: "economía")
        try await syncBoth()

        iPhone.iCloud.isOffline = true
        time.advance(by: minutes(1))
        try mac.engine.renameTag("economía", to: "economics")
        try await mac.syncNow()
        time.advance(by: minutes(1))
        let iPhonesCepo = try iPhone.engine.card(fronted: "cepo")
        try iPhone.engine.edit(
            iPhonesCepo.id, with: card(.concept, front: "cepo", back: "Un límite.", tags: ["Argentina", "economía"]))
        iPhone.iCloud.isOffline = false
        try await syncBoth()
        time.advance(by: minutes(1))
        let iPhonesUbuntu = try iPhone.engine.card(fronted: "ubuntu")
        try iPhone.engine.edit(
            iPhonesUbuntu.id,
            with: card(.concept, front: "ubuntu", back: "Soy porque somos.", tags: ["filosofía", "economía"]))
        try await syncBoth()

        for device in [mac, iPhone] {
            #expect(try device.engine.card(fronted: "inflación").tags == ["economics"])
            #expect(try device.engine.card(fronted: "cepo").tags == ["Argentina", "economics"])
            #expect(try device.engine.card(fronted: "ubuntu").tags == ["filosofía", "economía"])
            #expect(try device.engine.allTags().first { $0.name == "economics" }?.color == .green)
            #expect(try device.engine.allTags().first { $0.name == "economía" }?.color == nil)
            #expect(try device.engine.changesToSend().isEmpty)
        }
    }

    // Every card syncs, and economía is orange. The iPhone, offline, puts
    // zulú on inflación after the Mac renamed economía, and before it hears
    // of the rename: its edit is the later one, which wins on both devices.
    @Test(
        "a card a device offline meanwhile gave another tag is renamed once it hears of the rename, on both devices, and the tag keeps its color"
    )
    func aCardGivenAnotherTagOfflineIsRenamed() async throws {
        try mac.engine.create(card(.concept, front: "inflación", back: "Suben los precios.", tags: ["economía"]))
        try mac.engine.setColor(.orange, of: "economía")
        try await syncBoth()

        iPhone.iCloud.isOffline = true
        time.advance(by: minutes(1))
        try mac.engine.renameTag("economía", to: "economics")
        try await mac.syncNow()
        time.advance(by: minutes(1))
        let iPhonesInflation = try iPhone.engine.card(fronted: "inflación")
        try iPhone.engine.edit(
            iPhonesInflation.id,
            with: card(.concept, front: "inflación", back: "Suben los precios.", tags: ["economía", "zulú"]))
        iPhone.iCloud.isOffline = false
        try await syncBoth()

        for device in [mac, iPhone] {
            let inflation = try device.engine.card(fronted: "inflación")
            #expect(inflation.tags == ["economics", "zulú"])
            #expect(try device.engine.allTags().map(\.color) == [.orange, nil])
            #expect(try device.engine.changesToSend().isEmpty)
        }
    }

    // Every card syncs, and economía has nothing of its own. The iPhone,
    // offline, gives economía a color after the Mac renamed it, and before it
    // hears of the rename.
    @Test(
        "a color a device offline meanwhile gave a tag moves with the rename once it hears of it"
    )
    func aTagColoredOfflineMovesWithTheRename() async throws {
        try mac.engine.create(card(.concept, front: "inflación", back: "Suben los precios.", tags: ["economía"]))
        try await syncBoth()

        iPhone.iCloud.isOffline = true
        time.advance(by: minutes(1))
        try mac.engine.renameTag("economía", to: "economics")
        try await mac.syncNow()
        time.advance(by: minutes(1))
        try iPhone.engine.setColor(.orange, of: "economía")
        iPhone.iCloud.isOffline = false
        try await syncBoth()

        for device in [mac, iPhone] {
            #expect(try device.engine.card(fronted: "inflación").tags == ["economics"])
            #expect(try device.engine.allTags() == [CardTag(name: "economics", color: .orange)])
            #expect(try device.engine.changesToSend().isEmpty)
        }
    }

    // Only Filosofía syncs, so cepo stays on the iPhone, and inflación syncs.
    // The Mac, offline, renames economía to economics, a tag inflación
    // carries; the iPhone then deletes economics, and hears of the rename
    // after, in a fetch of its own.
    @Test(
        "a rename heard in a fetch of its own after a later deletion of its new name follows it: the tag is gone from every card"
    )
    func aRenameHeardAfterALaterDeletion() async throws {
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Filosofía")
        try mac.engine.create(
            card(.concept, front: "inflación", back: "Suben los precios.", tags: ["filosofía", "economics"]),
            deck: "Filosofía")
        try await syncBoth()
        try iPhone.engine.create(card(.concept, front: "cepo", back: "Un límite.", tags: ["economía"]))
        try await syncBoth()

        mac.iCloud.isOffline = true
        time.advance(by: minutes(1))
        try mac.engine.renameTag("economía", to: "economics")
        time.advance(by: minutes(1))
        try iPhone.engine.deleteTags(["economics"])
        try await iPhone.syncNow()
        mac.iCloud.isOffline = false
        try await syncBoth()

        #expect(try iPhone.engine.card(fronted: "cepo").tags == [])
        for device in [mac, iPhone] {
            #expect(try device.engine.card(fronted: "inflación").tags == ["filosofía"])
            #expect(try device.engine.allTags().map(\.name) == ["filosofía"])
            #expect(try device.engine.changesToSend().isEmpty)
        }
    }

    // Only Filosofía syncs: inflación syncs, cepo stays on the Mac and ubuntu
    // on the iPhone. economía is orange. The Mac renames it to economics and
    // the iPhone, offline, to economy, before it hears of the Mac's.
    @Test(
        "two devices renaming one tag lose no card and no color: the synced cards take the later name, and each device's other cards keep its own"
    )
    func twoDevicesRenamingOneTag() async throws {
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Filosofía")
        try mac.engine.setColor(.orange, of: "economía")
        try mac.engine.create(
            card(.concept, front: "inflación", back: "Suben los precios.", tags: ["filosofía", "economía"]),
            deck: "Filosofía")
        try mac.engine.create(card(.concept, front: "cepo", back: "Un límite.", tags: ["economía"]))
        try await syncBoth()
        try iPhone.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos.", tags: ["economía"]))
        try await syncBoth()

        iPhone.iCloud.isOffline = true
        time.advance(by: minutes(1))
        try mac.engine.renameTag("economía", to: "economics")
        try await mac.syncNow()
        time.advance(by: minutes(1))
        try iPhone.engine.renameTag("economía", to: "economy")
        iPhone.iCloud.isOffline = false
        try await syncBoth()

        #expect(try mac.engine.card(fronted: "cepo").tags == ["economics"])
        #expect(try iPhone.engine.card(fronted: "ubuntu").tags == ["economy"])
        for device in [mac, iPhone] {
            #expect(try device.engine.card(fronted: "inflación").tags == ["filosofía", "economy"])
            #expect(
                try device.engine.allTags() == [
                    CardTag(name: "economics", color: .orange),
                    CardTag(name: "economy", color: .orange),
                    CardTag(name: "filosofía"),
                ])
            #expect(try device.engine.changesToSend().isEmpty)
        }
        #expect(try mac.engine.cards().count == 2)
        #expect(try iPhone.engine.cards().count == 2)
    }

    // Only Filosofía syncs, so each device's cards stay on it. The Mac drags
    // P › l2 › Y › l1 and Q › l2 into P at once, in All Tags, which moves
    // them in that order: Q › l2 › Y › l1 becomes P › l2 › Y › l1, which the
    // first move no longer reaches. iCloud's engine promises no order, so the
    // iPhone hears the two moves in either order, in one fetch or in one each.
    @Test(
        "tags moved at once reach the cards the other device holds and doesn't sync in the order they were moved, however it hears of them",
        arguments: [false, true], [false, true])
    func tagsMovedAtOnce(laterMoveSentFirst: Bool, heardInOneFetchEach: Bool) async throws {
        try mac.engine.syncOnlyChosenDecks(true)
        try mac.engine.setChosenToSync(true, ofDeck: "Filosofía")
        for device in [mac, iPhone] {
            try device.engine.create(card(.concept, front: "cepo", back: "Un límite.", tags: ["Q::l2::Y::l1"]))
            try device.engine.create(
                card(.concept, front: "ubuntu", back: "Soy porque somos.", tags: ["P::l2::Y::l1"]))
        }
        try await syncBoth()

        time.advance(by: minutes(1))
        try mac.engine.moveTags(["P::l2::Y::l1", "Q::l2"], into: "P")
        try await sendTheMacsTwoChanges(laterFirst: laterMoveSentFirst, oneFetchEach: heardInOneFetchEach)

        for device in [mac, iPhone] {
            #expect(try device.engine.card(fronted: "cepo").tags == ["P::l2::Y::l1"])
            #expect(try device.engine.card(fronted: "ubuntu").tags == ["P::l1"])
            #expect(try device.engine.changesToSend().isEmpty)
        }
    }

    /// Sends the two changes to tags the Mac's last write recorded, the later
    /// one first when `laterFirst` says so, as iCloud's engine promises no
    /// order; the iPhone hears them in one fetch, or in one fetch each when
    /// `oneFetchEach` says so, as the Mac goes offline after its first. Then
    /// both devices sync.
    private func sendTheMacsTwoChanges(laterFirst: Bool, oneFetchEach: Bool) async throws {
        let macsICloud = mac.iCloud
        try mac.sync.sendWhatChanged(to: macsICloud)
        let changes = macsICloud.pendingRecordZoneChanges
        try #require(changes.count == 2)
        if laterFirst {
            macsICloud.remove(pendingRecordZoneChanges: changes)
            macsICloud.add(pendingRecordZoneChanges: changes.reversed())
        }
        if oneFetchEach {
            macsICloud.recordsPerBatch = 1
            macsICloud.onceSaved { macsICloud.isOffline = true }
            await #expect(throws: FakeICloudError.offline) { try await macsICloud.sendChanges() }
            try await iPhone.syncNow()
            macsICloud.isOffline = false
        } else {
            try await macsICloud.sendChanges()
        }
        try await syncBoth()
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
