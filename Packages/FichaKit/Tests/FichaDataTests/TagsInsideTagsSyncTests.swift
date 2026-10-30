import FichaCore
import Foundation
import Testing

// For what waits to be sent.
@testable import FichaData

/// Tests on tags inside tags across devices (ADR 0021): a rename reaching the
/// other device, and selective sync (ADR 0020) taking in the tags inside a
/// chosen tag, on two devices, a Mac and an iPhone, each an engine in memory
/// in Buenos Aires on one clock, syncing through a fake iCloud.
final class TagsInsideTagsSyncTests {
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

    @Test("a rename reaches the other device, with the tags inside the tag and what each has of its own")
    func aRenameReachesTheOtherDevice() async throws {
        try mac.engine.create(card(.concept, front: "inflación", back: "Suben los precios.", tags: ["economía"]))
        try mac.engine.create(
            card(.concept, front: "cepo", back: "Un límite a la compra de dólares.", tags: ["economía::Argentina"]))
        try mac.engine.setColor(.green, of: "economía")
        try mac.engine.setEmoji(Emoji("🇦🇷"), of: "economía::Argentina")
        try await syncBoth()

        time.advance(by: minutes(1))
        try mac.engine.renameTag("economía", to: "economics")
        try await syncBoth()

        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
        #expect(
            try iPhone.engine.cards().map(\.tags).sorted { $0[0] < $1[0] } == [["economics"], ["economics::Argentina"]])
        #expect(try iPhone.engine.allTags() == mac.engine.allTags())
        #expect(
            try iPhone.engine.allTags() == [
                CardTag(name: "economics", color: .green),
                CardTag(name: "economics::Argentina", emoji: "🇦🇷", inheritedColor: .green),
            ])
    }

    // inflación's tag is made on the Mac once economía is chosen, a level in.
    @Test("while only chosen tags sync, a chosen parent syncs the cards of the tags inside it, a new one's too")
    func aChosenParentSyncsItsChildrensCards() async throws {
        try mac.engine.create(
            card(.concept, front: "cepo", back: "Un límite a la compra de dólares.", tags: ["economía::Argentina"]))
        try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia.", tags: ["lenguaje"]))
        try mac.engine.syncOnlyChosenTags(true)
        try mac.engine.chooseToSync("economía", true)
        try mac.engine.create(
            card(.concept, front: "arancel", back: "Un impuesto a lo que entra.", tags: ["economía::mundial::comercio"])
        )
        try await syncBoth()

        #expect(try iPhone.engine.cards().map(\.front).sorted() == ["arancel", "cepo"])
        #expect(try mac.engine.changesToSend().isEmpty)
    }

    @Test("a tag moved out of a chosen parent takes its cards out of iCloud, and both devices keep them")
    func aTagMovedOutOfAChosenParent() async throws {
        try mac.engine.create(
            card(.concept, front: "cepo", back: "Un límite a la compra de dólares.", tags: ["economía::Argentina"]))
        try mac.engine.create(card(.concept, front: "inflación", back: "Suben los precios.", tags: ["economía"]))
        try mac.engine.syncOnlyChosenTags(true)
        try mac.engine.chooseToSync("economía", true)
        try await syncBoth()
        #expect(try iPhone.engine.cards().count == 2)

        time.advance(by: minutes(1))
        try iPhone.engine.renameTag("economía::Argentina", to: "Argentina")
        try await syncBoth()

        for device in [mac, iPhone] {
            #expect(try device.engine.cards().map(\.front).sorted() == ["cepo", "inflación"])
            #expect(try device.engine.card(fronted: "cepo").tags == ["Argentina"])
            #expect(try device.engine.changesToSend().isEmpty)
        }
        let cards = iCloud.records.filter { $0.type == SyncedRow.RecordType.card.rawValue }
        #expect(cards.filter(\.hasLeft).map { try? $0.text(SyncedField.tags.rawValue) } == [#"["Argentina"]"#])
        #expect(cards.count == 2)
    }

    // The Mac's keyboard writes í as one character, and text from elsewhere
    // can write it as an i and an accent, which Swift takes for the same
    // name and the database's SQL doesn't.
    @Test("while only chosen tags sync, a tag whose accent is written apart syncs with the chosen tag it sits inside")
    func aTagWithItsAccentWrittenApartSyncs() async throws {
        try mac.engine.create(
            card(
                .concept, front: "cepo", back: "Un límite a la compra de dólares.",
                tags: ["economi\u{301}a::Argentina"]))
        try mac.engine.syncOnlyChosenTags(true)
        try mac.engine.chooseToSync("econom\u{ED}a", true)
        try await syncBoth()

        #expect(try iPhone.engine.cards().map(\.front) == ["cepo"])
    }

    // cepo's tag is moved into economía on the Mac once economía is chosen,
    // as dragging it there does.
    @Test("while only chosen tags sync, a tag moved into a chosen parent takes its cards up to iCloud")
    func aTagMovedIntoAChosenParent() async throws {
        try mac.engine.create(
            card(.concept, front: "cepo", back: "Un límite a la compra de dólares.", tags: ["Argentina"]))
        try mac.engine.create(card(.concept, front: "inflación", back: "Suben los precios.", tags: ["economía"]))
        try mac.engine.syncOnlyChosenTags(true)
        try mac.engine.chooseToSync("economía", true)
        try await syncBoth()
        #expect(try iPhone.engine.cards().map(\.front) == ["inflación"])

        time.advance(by: minutes(1))
        try mac.engine.renameTag("Argentina", to: "economía::Argentina")
        try await syncBoth()

        #expect(try iPhone.engine.cards().map(\.front).sorted() == ["cepo", "inflación"])
        #expect(try iPhone.engine.card(fronted: "cepo").tags == ["economía::Argentina"])
        #expect(try mac.engine.changesToSend().isEmpty)
    }

    // The deletion is recorded as the card goes, by the database's triggers,
    // with what syncs then.
    @Test("while only chosen tags sync, deleting a card of a tag inside a chosen tag deletes it on every device")
    func deletingACardInsideAChosenTag() async throws {
        let cepo = try mac.engine.create(
            card(.concept, front: "cepo", back: "Un límite a la compra de dólares.", tags: ["economía::Argentina"]))
        try mac.engine.syncOnlyChosenTags(true)
        try mac.engine.chooseToSync("economía", true)
        try await syncBoth()
        #expect(try iPhone.engine.cards().map(\.front) == ["cepo"])

        try mac.engine.delete([cepo.id])
        try await syncBoth()

        #expect(try iPhone.engine.cards().isEmpty)
        #expect(!iCloud.records.contains { $0.type == SyncedRow.RecordType.card.rawValue })
    }

    /// Syncs the Mac, then the iPhone, three times, so that what one sends
    /// as it hears the other reaches it.
    private func syncBoth() async throws {
        for _ in 0..<3 {
            try await mac.syncNow()
            try await iPhone.syncNow()
        }
    }
}
