import FichaCore
import Foundation
import Testing

// For what waits to be sent.
@testable import FichaData

/// Tests on tags inside tags across devices (ADR 0021): a rename reaching the
/// other device, on two devices, a Mac and an iPhone, each an engine in
/// memory in Buenos Aires on one clock, syncing through a fake iCloud.
/// Selective sync chooses decks, and takes in the decks inside a chosen one
/// (ADR 0024, `SelectiveSyncTests`).
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

    /// Syncs the Mac, then the iPhone, three times, so that what one sends
    /// as it hears the other reaches it.
    private func syncBoth() async throws {
        for _ in 0..<3 {
            try await mac.syncNow()
            try await iPhone.syncNow()
        }
    }
}
