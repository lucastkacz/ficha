import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on pinned tags across devices (ADR 0022): which tags are pinned, and
/// in what order, is one choice for all the user's devices, whatever
/// selective sync chooses, on two devices, a Mac and an iPhone, each an
/// engine in memory in Buenos Aires on one clock, syncing through a fake
/// iCloud.
final class PinnedTagsSyncTests {
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

    // lenguaje's card, in Default, doesn't sync while only Economía does, and
    // historia has none: their pins reach the iPhone all the same, as tags'
    // rows always sync.
    @Test(
        "pins and their order reach the other device, and so does a move or an unpin there, while only chosen decks sync too",
        arguments: [false, true])
    func pinsAndTheirOrderReachTheOtherDevice(onlyChosenDecks: Bool) async throws {
        try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia.", tags: ["lenguaje"]))
        try mac.engine.create(
            card(.concept, front: "cepo", back: "Un límite a la compra de dólares.", tags: ["economía::Argentina"]),
            deck: "Economía")
        if onlyChosenDecks {
            try mac.engine.syncOnlyChosenDecks(true)
            try mac.engine.setChosenToSync(true, ofDeck: "Economía")
        }
        for tag in ["lenguaje", "economía::Argentina", "historia"] {
            try mac.engine.pin(tag)
        }
        try await syncBoth()
        let pinnedOnTheIPhone = try iPhone.engine.pinnedTags().map(\.name)

        time.advance(by: minutes(1))
        try iPhone.engine.pin("historia", at: 0)
        try iPhone.engine.unpin("lenguaje")
        try await syncBoth()

        #expect(pinnedOnTheIPhone == ["lenguaje", "economía::Argentina", "historia"])
        #expect(try mac.engine.pinnedTags().map(\.name) == ["historia", "economía::Argentina"])
        #expect(try iPhone.engine.pinnedTags() == mac.engine.pinnedTags())
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
