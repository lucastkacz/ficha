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
    // Mac renamed it, as ADR 0021 says.
    @Test(
        "a card that syncs, to which a device offline meanwhile put the old name, keeps it, as a tag with nothing of its own"
    )
    func aCardGivenTheOldNameLaterKeepsIt() async throws {
        try mac.engine.create(card(.concept, front: "inflación", back: "Suben los precios.", tags: ["economía"]))
        try mac.engine.create(card(.concept, front: "cepo", back: "Un límite.", tags: ["Argentina"]))
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

        for device in [mac, iPhone] {
            #expect(try device.engine.card(fronted: "inflación").tags == ["economics"])
            #expect(try device.engine.card(fronted: "cepo").tags == ["Argentina", "economía"])
            #expect(try device.engine.allTags().first { $0.name == "economics" }?.color == .green)
            #expect(try device.engine.allTags().first { $0.name == "economía" }?.color == nil)
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
