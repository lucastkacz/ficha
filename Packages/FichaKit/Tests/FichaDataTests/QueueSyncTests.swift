import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on a deck's place in the queue new cards come from across devices
/// (ADR 0034, ADR 0017): a field of the deck, which syncs, and whose latest
/// change wins, on two devices, a Mac and an iPhone, each an engine in
/// memory in Buenos Aires on one clock, syncing through a fake iCloud.
final class QueueSyncTests {
    let time: ManualTimeSource
    let iCloud = FakeICloud()
    let mac: Device
    let iPhone: Device
    let settings = ReviewSettings.defaults

    init() throws {
        let calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 21, in: calendar))
        mac = try Device(Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: iCloud)
        iPhone = try Device(Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: iCloud)
    }

    // Arte comes in a minute before Historia, so it goes ahead of it on both
    // devices, until the Mac moves Historia first, and then the iPhone moves
    // Arte first again, later.
    @Test("a deck's place in the queue syncs to the other device, and its latest move wins", .bug(id: 490))
    func aDecksPlaceSyncs() async throws {
        try newCardInDeck("La Gioconda", deck: "Arte", in: mac.engine)
        time.advance(by: minutes(1))
        try newCardInDeck("Coliseo", deck: "Historia", in: mac.engine)
        try await syncBoth()
        let before = try iPhone.engine.queue(settings).map(\.deck)

        try mac.engine.moveInQueue(deck: "Historia", to: .first)
        try await syncBoth()
        let movedOnTheMac = try iPhone.engine.queue(settings).map(\.deck)
        time.advance(by: minutes(1))
        try iPhone.engine.moveInQueue(deck: "Arte", to: .first)
        try await syncBoth()

        #expect(before == ["Arte", "Historia"])
        #expect(movedOnTheMac == ["Historia", "Arte"])
        #expect(try mac.engine.queue(settings).map(\.deck) == ["Arte", "Historia"])
        #expect(try iPhone.engine.queue(settings).map(\.deck) == ["Arte", "Historia"])
    }

    // Historia and Arte come in on the Mac at once, Historia first, as an
    // import's decks do.
    @Test("decks that came in at once go in the same order on every device", .bug(id: 490))
    func decksThatCameInAtOnceGoAlike() async throws {
        try newCardInDeck("Coliseo", deck: "Historia", in: mac.engine)
        try newCardInDeck("La Gioconda", deck: "Arte", in: mac.engine)
        try await syncBoth()

        #expect(try mac.engine.queue(settings).map(\.deck) == ["Arte", "Historia"])
        #expect(try iPhone.engine.queue(settings).map(\.deck) == ["Arte", "Historia"])
    }

    /// Syncs the Mac and then the iPhone, three times over, so each has what
    /// the other sent.
    private func syncBoth() async throws {
        for _ in 0..<3 {
            try await mac.syncNow()
            try await iPhone.syncNow()
        }
    }
}
