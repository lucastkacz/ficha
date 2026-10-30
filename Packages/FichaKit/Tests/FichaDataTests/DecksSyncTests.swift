import FichaCore
import Foundation
import Testing

// For what a deck has of its own, which the engine stores and syncs before
// the user has actions that set it, its color and emoji: `changeOwnDecks`,
// the loop those actions go through.
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
    // while only chosen decks sync: their rows reach the iPhone all the same,
    // but under selective sync the iPhone lists only the decks that sync, so
    // not Historia, which it neither made nor holds cards of.
    @Test(
        "a deck made on one device reaches the other with what it has of its own, one with no card too, while only chosen decks sync too",
        arguments: [false, true])
    func aDeckReachesTheOtherDevice(onlyChosenDecks: Bool) async throws {
        let gioconda = try mac.engine.create(card(.concept, front: "La Gioconda", back: "De Leonardo.", tags: ["arte"]))
        let coliseo = try mac.engine.create(card(.concept, front: "Coliseo", back: "Un anfiteatro."))
        if onlyChosenDecks {
            try mac.engine.syncOnlyChosenDecks(true)
        }
        try mac.engine.changeDeck(of: [gioconda.id], to: "Arte::Pintura")
        try mac.engine.changeDeck(of: [coliseo.id], to: "Historia")
        try mac.engine.makeDeck(named: "Arte::Escultura")
        try mac.engine.setPriority(true, ofDeck: "Arte")
        try mac.engine.setChosenToSync(true, ofDeck: "Arte")
        try mac.engine.write { db in
            try changeOwnDecks(["Arte"], in: db) { deck in
                deck.color = .orange
                deck.emoji = "🎨"
            }
        }
        try await syncBoth()

        let arte = Deck(name: "Arte", switchedOn: .priority, color: .orange, emoji: "🎨", chosenToSync: true)
        let artes = [
            arte, Deck(name: "Arte::Escultura", inheritedColor: .orange, inheritedEmoji: "🎨"),
            Deck(name: "Arte::Pintura", inheritedColor: .orange, inheritedEmoji: "🎨"),
        ]
        #expect(try mac.engine.decks() == artes + [Deck(name: "Historia")])
        #expect(try iPhone.engine.decks() == artes + (onlyChosenDecks ? [] : [Deck(name: "Historia")]))
        #expect(
            try Set(iPhone.engine.cards().map(\.deck))
                == (onlyChosenDecks ? ["Arte::Pintura"] : ["Arte::Pintura", "Historia"]))
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

    // The iPhone, offline, prioritizes Historia first; the Mac sets it aside
    // later, and sends first, so the latest change is the one the iPhone
    // hears of.
    @Test(
        "a deck's switch reaches the other device, which sets its cards aside or brings them first there, and the latest change wins"
    )
    func aDecksSwitchReachesTheOtherDevice() async throws {
        let coliseo = try mac.engine.create(card(.concept, front: "Coliseo", back: "Un anfiteatro."))
        let petricor = try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try mac.engine.changeDeck(of: [coliseo.id], to: "Historia::Roma")
        try await syncBoth()

        try mac.engine.togglePriority(ofDeck: Deck.defaultName)
        try await syncBoth()
        #expect(try iPhone.engine.prioritizeMenu().priorityDeckNames == [Deck.defaultName])

        iPhone.iCloud.isOffline = true
        time.advance(by: minutes(1))
        try iPhone.engine.togglePriority(ofDeck: "Historia")
        time.advance(by: minutes(1))
        try mac.engine.setAside(deck: "Historia")
        try await mac.syncNow()
        iPhone.iCloud.isOffline = false
        try await syncBoth()

        for device in [mac, iPhone] {
            #expect(try device.engine.decks().map(\.switchedOn) == [.priority, .setAside, nil])
            #expect(try device.engine.card(fronted: "Coliseo").standing == .setAside(by: ["Historia"]))
            #expect(try device.engine.card(fronted: "petricor").standing == .inReviews)
            #expect(try device.engine.changesToSend().isEmpty)
        }
        #expect(petricor.deck == Deck.defaultName)
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
