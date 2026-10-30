import FichaCore
import Foundation
import Testing

// For what a deck has of its own, which the engine stores and syncs before
// the user has actions that set it: `changeOwnDecks`, the loop those actions
// go through.
@testable import FichaData

/// Tests on decks across devices (ADR 0024, ADR 0017): a deck reaching the
/// other device with what it has of its own, whatever selective sync chooses
/// (ADR 0020), and a card's deck, whose latest change wins, on two devices, a
/// Mac and an iPhone, each an engine in memory in Buenos Aires on one clock,
/// syncing through a fake iCloud.
final class DecksSyncTests {
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

    // Arte::Escultura has no card, and Historia's only card stays on the Mac
    // while only chosen tags sync: their rows reach the iPhone all the same,
    // as a tag's row does.
    @Test(
        "a deck made on one device reaches the other with what it has of its own, one with no card too, while only chosen tags sync too",
        arguments: [false, true])
    func aDeckReachesTheOtherDevice(onlyChosenTags: Bool) async throws {
        let gioconda = try mac.engine.create(card(.concept, front: "La Gioconda", back: "De Leonardo.", tags: ["arte"]))
        let coliseo = try mac.engine.create(card(.concept, front: "Coliseo", back: "Un anfiteatro."))
        if onlyChosenTags {
            try mac.engine.syncOnlyChosenTags(true)
            try mac.engine.chooseToSync("arte", true)
        }
        try mac.engine.changeDeck(of: [gioconda.id], to: "Arte::Pintura")
        try mac.engine.changeDeck(of: [coliseo.id], to: "Historia")
        try mac.engine.makeDeck(named: "Arte::Escultura")
        try mac.engine.write { db in
            try changeOwnDecks(["Arte"], in: db) { deck in
                deck.switchedOn = .priority
                deck.color = .orange
                deck.emoji = "🎨"
                deck.chosenToSync = true
            }
        }
        try await syncBoth()

        let arte = Deck(name: "Arte", switchedOn: .priority, color: .orange, emoji: "🎨", chosenToSync: true)
        #expect(
            try iPhone.engine.decks() == [
                arte, Deck(name: "Arte::Escultura", inheritedColor: .orange, inheritedEmoji: "🎨"),
                Deck(name: "Arte::Pintura", inheritedColor: .orange, inheritedEmoji: "🎨"), Deck(name: "Historia"),
            ])
        #expect(
            try Set(iPhone.engine.cards().map(\.deck))
                == (onlyChosenTags ? ["Arte::Pintura"] : ["Arte::Pintura", "Historia"]))
        #expect(try iPhone.engine.decks() == mac.engine.decks())
    }

    // The iPhone, offline, moves petricor first; the Mac moves it later, and
    // sends first, so the latest change is the one the iPhone hears of.
    @Test(
        "a card's deck changed on both devices ends with the latest change, and one back to Default reaches the other")
    func aCardsDeckKeepsTheLatestChange() async throws {
        let petricor = try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try await syncBoth()
        let onTheIPhone = try iPhone.engine.card(fronted: "petricor")

        iPhone.iCloud.isOffline = true
        time.advance(by: minutes(1))
        try iPhone.engine.changeDeck(of: [onTheIPhone.id], to: "Música")
        time.advance(by: minutes(1))
        try mac.engine.changeDeck(of: [petricor.id], to: "Lenguaje::Palabras")
        try await mac.syncNow()
        iPhone.iCloud.isOffline = false
        try await syncBoth()

        for device in [mac, iPhone] {
            #expect(try device.engine.cards().map(\.deck) == ["Lenguaje::Palabras"])
            #expect(try device.engine.decks().map(\.name) == ["Lenguaje", "Lenguaje::Palabras", "Música"])
        }

        time.advance(by: minutes(1))
        try iPhone.engine.changeDeck(of: [onTheIPhone.id], to: Deck.defaultName)
        try await syncBoth()

        for device in [mac, iPhone] {
            #expect(try device.engine.cards().map(\.deck) == [Deck.defaultName])
            #expect(try device.engine.changesToSend().isEmpty)
        }
    }

    @Test("a deck made while sync is off reaches the other device once it's on")
    func aDeckMadeWhileSyncIsOff() async throws {
        try mac.turnSyncOff()
        try mac.engine.makeDeck(named: "Idiomas::Inglés")
        try mac.turnSyncOn()
        try await syncBoth()

        #expect(try iPhone.engine.decks().map(\.name) == ["Idiomas", "Idiomas::Inglés"])
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
