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

    // Only filosofía syncs, so ubuntu and cepo stay on the iPhone; economía
    // is set aside on the Mac, which holds no card of it.
    @Test(
        "a rename reaches a card the other device holds and doesn't sync, and a set-aside tag's cards stay set aside there"
    )
    func aRenameReachesACardThatDoesntSync() async throws {
        try mac.engine.syncOnlyChosenTags(true)
        try mac.engine.chooseToSync("filosofía", true)
        try mac.engine.setAside("economía")
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
        #expect(try iPhone.engine.card(fronted: "ubuntu").standing == .setAside(by: ["economics"]))
        #expect(try iPhone.engine.card(fronted: "cepo").standing == .setAside(by: ["economics"]))
        let iPhonesTags = try iPhone.engine.allTags()
        #expect(
            iPhonesTags == [
                CardTag(name: "economics", switchedOn: .setAside),
                CardTag(name: "economics::Argentina"),
                CardTag(name: "filosofía", chosenToSync: true),
            ])
        #expect(records(ofType: .card).isEmpty)
        for device in [mac, iPhone] {
            #expect(try device.engine.changesToSend().isEmpty)
        }
    }

    @Test("a deletion reaches a card the other device holds and doesn't sync, and deletes no card there")
    func aDeletionReachesACardThatDoesntSync() async throws {
        try mac.engine.syncOnlyChosenTags(true)
        try mac.engine.chooseToSync("filosofía", true)
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
        #expect(iPhonesTags == ["filosofía", "zulú"])
        for device in [mac, iPhone] {
            #expect(try device.engine.changesToSend().isEmpty)
        }
    }

    // The Mac deletes literatura and renames economía while the iPhone is
    // offline, and syncs again meanwhile.
    @Test("each change reaches the other device once it comes back online")
    func aChangeHeardAfterComingBackOnline() async throws {
        try mac.engine.syncOnlyChosenTags(true)
        try mac.engine.chooseToSync("filosofía", true)
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

    // cepo carries filosofía alone of the chosen tags; inflación carries
    // economía too, which is chosen.
    @Test("a deletion makes a card left with no chosen tag stop syncing, and each device keeps it")
    func aDeletionMakesACardStopSyncing() async throws {
        try mac.engine.create(
            card(.concept, front: "cepo", back: "Un límite a la compra de dólares.", tags: ["filosofía", "zulú"]))
        try mac.engine.create(
            card(.concept, front: "inflación", back: "Suben los precios.", tags: ["filosofía", "economía"]))
        try mac.engine.syncOnlyChosenTags(true)
        try mac.engine.chooseToSync("filosofía", true)
        try mac.engine.chooseToSync("economía", true)
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
        #expect(cards.filter(\.hasLeft).map { try? $0.text(SyncedField.tags.rawValue) } == [#"["zulú"]"#])
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

    // Every card syncs, and economía is set aside. The iPhone, offline, puts
    // zulú on inflación after the Mac renamed economía, and before it hears
    // of the rename: its edit is the later one, which wins on both devices.
    @Test(
        "a card a device offline meanwhile gave another tag is renamed once it hears of the rename, on both devices, and stays set aside"
    )
    func aCardGivenAnotherTagOfflineIsRenamed() async throws {
        try mac.engine.create(card(.concept, front: "inflación", back: "Suben los precios.", tags: ["economía"]))
        try mac.engine.setAside("economía")
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
            #expect(inflation.standing == .setAside(by: ["economics"]))
            #expect(try device.engine.changesToSend().isEmpty)
        }
    }

    // Every card syncs, and economía has nothing of its own. The iPhone,
    // offline, sets economía aside after the Mac renamed it, and before it
    // hears of the rename.
    @Test(
        "a tag a device offline meanwhile set aside moves with the rename once it hears of it, and its cards stay set aside"
    )
    func aTagSetAsideOfflineMovesWithTheRename() async throws {
        try mac.engine.create(card(.concept, front: "inflación", back: "Suben los precios.", tags: ["economía"]))
        try await syncBoth()

        iPhone.iCloud.isOffline = true
        time.advance(by: minutes(1))
        try mac.engine.renameTag("economía", to: "economics")
        try await mac.syncNow()
        time.advance(by: minutes(1))
        try iPhone.engine.setAside("economía")
        iPhone.iCloud.isOffline = false
        try await syncBoth()

        for device in [mac, iPhone] {
            #expect(try device.engine.card(fronted: "inflación").standing == .setAside(by: ["economics"]))
            #expect(try device.engine.allTags() == [CardTag(name: "economics", switchedOn: .setAside)])
            #expect(try device.engine.changesToSend().isEmpty)
        }
    }

    // Only filosofía syncs, so cepo stays on the iPhone, and inflación syncs.
    // The Mac, offline, renames economía to economics, a tag inflación
    // carries; the iPhone then deletes economics, and hears of the rename
    // after, in a fetch of its own.
    @Test(
        "a rename heard in a fetch of its own after a later deletion of its new name follows it: the tag is gone from every card"
    )
    func aRenameHeardAfterALaterDeletion() async throws {
        try mac.engine.syncOnlyChosenTags(true)
        try mac.engine.chooseToSync("filosofía", true)
        try mac.engine.create(
            card(.concept, front: "inflación", back: "Suben los precios.", tags: ["filosofía", "economics"]))
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

    // Only filosofía syncs: inflación syncs, cepo stays on the Mac and ubuntu
    // on the iPhone. economía is set aside. The Mac renames it to economics
    // and the iPhone, offline, to economy, before it hears of the Mac's.
    @Test(
        "two devices renaming one tag lose no card and no switch: the synced cards take the later name, and each device's other cards keep its own"
    )
    func twoDevicesRenamingOneTag() async throws {
        try mac.engine.syncOnlyChosenTags(true)
        try mac.engine.chooseToSync("filosofía", true)
        try mac.engine.setAside("economía")
        try mac.engine.create(
            card(.concept, front: "inflación", back: "Suben los precios.", tags: ["filosofía", "economía"]))
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
            #expect(try device.engine.cards().allSatisfy { $0.standing != .inReviews })
            #expect(
                try device.engine.allTags() == [
                    CardTag(name: "economics", switchedOn: .setAside),
                    CardTag(name: "economy", switchedOn: .setAside),
                    CardTag(name: "filosofía", chosenToSync: true),
                ])
            #expect(try device.engine.changesToSend().isEmpty)
        }
        #expect(try mac.engine.cards().count == 2)
        #expect(try iPhone.engine.cards().count == 2)
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
