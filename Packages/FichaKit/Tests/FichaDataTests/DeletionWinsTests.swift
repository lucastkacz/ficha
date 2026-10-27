import FichaCore
import Foundation
import Testing

// For the interface to iCloud's engine, which the fake implements.
@testable import FichaData

/// Tests on a deletion that syncs (ADR 0017): a row deleted on one device is
/// deleted on the others, and wins over what they changed of it meanwhile.
/// Two devices, a Mac and an iPhone, each an engine in memory in Buenos Aires
/// on one clock, syncing through a fake iCloud.
final class DeletionWinsTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let iCloud = FakeICloud()
    let mac: Device
    let iPhone: Device
    /// A data folder of the test's own, for a device whose backups matter.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaDeletionWinsTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 21, in: calendar))
        mac = try Device(Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: iCloud)
        iPhone = try Device(Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: iCloud)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    // ubuntu's deletion reaches iCloud before the iPhone's edit, which iCloud
    // refuses; petricor's edit reaches iCloud before the iPhone's deletion.
    // Once iCloud takes a deletion, it no longer waits, before the device
    // fetches anything.
    @Test("a card deleted on one device and edited on the other is gone from both, whichever sends first")
    func aCardDeletedAndEditedIsGone() async throws {
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        let petricor = try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try await mac.syncNow()
        try await iPhone.syncNow()

        time.advance(by: minutes(1))
        try mac.engine.delete([ubuntu.id])
        try mac.engine.edit(petricor.id, with: card(.word, front: "petricor", back: "Huele a lluvia."))
        try iPhone.engine.edit(
            iPhone.engine.card(fronted: "ubuntu").id, with: card(.concept, front: "ubuntu", back: "Somos."))
        try iPhone.engine.flag(iPhone.engine.card(fronted: "ubuntu").id, note: note("Falta un ejemplo"))
        try iPhone.engine.delete([iPhone.engine.card(fronted: "petricor").id])
        try await mac.sendNow()
        #expect(try mac.engine.changesToSend().isEmpty)
        try await mac.syncNow()
        try await iPhone.syncNow()
        try await mac.syncNow()

        for device in [mac, iPhone] {
            #expect(try device.engine.cards().isEmpty)
            #expect(try device.engine.changesToSend().isEmpty)
        }
        #expect(iCloud.records.isEmpty)
    }

    // iCloud's engine may fetch before it sends, as it does at launch.
    @Test("a card deleted on one device stays deleted when the other's edit comes before the deletion leaves")
    func anEditThatComesBeforeTheDeletionLeavesLoses() async throws {
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try await mac.syncNow()
        try await iPhone.syncNow()

        time.advance(by: minutes(1))
        try mac.engine.delete([ubuntu.id])
        time.advance(by: minutes(1))
        try iPhone.engine.edit(
            iPhone.engine.card(fronted: "ubuntu").id, with: card(.concept, front: "ubuntu", back: "Somos."))
        try await iPhone.syncNow()
        try await mac.iCloud.fetchChanges()

        #expect(try mac.engine.cards().isEmpty)
        try await mac.syncNow()
        try await iPhone.syncNow()
        #expect(try mac.engine.cards().isEmpty)
        #expect(try iPhone.engine.cards().isEmpty)
    }

    // The iPhone's first good reaches iCloud before the Mac's deletion, which
    // the Mac makes without having fetched it; its again, made offline,
    // reaches iCloud after. Each device sends what it changes as it takes the
    // other's changes once the database changes, as the app does.
    @Test(
        "a card deleted on one device and reviewed on the other is gone from both, with every review, and from iCloud")
    func aCardDeletedAndReviewedIsGoneWithEveryReview() async throws {
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try mac.engine.meet(ubuntu)
        try await mac.syncNow()
        try await iPhone.syncNow()
        let ubuntuOnIPhone = try iPhone.engine.card(fronted: "ubuntu")

        try iPhone.engine.reviewWhenDue(ubuntuOnIPhone, .good, movingForward: time)
        try await iPhone.syncNow()
        try mac.engine.delete([ubuntu.id])
        iPhone.iCloud.isOffline = true
        try iPhone.engine.reviewWhenDue(ubuntuOnIPhone, .again, movingForward: time)
        try await mac.syncNow()
        iPhone.iCloud.isOffline = false
        try await iPhone.syncNow()
        try await iPhone.syncNow()
        try await mac.syncNow()

        for device in [mac, iPhone] {
            #expect(try device.engine.cards().isEmpty)
            #expect(try device.engine.reviewLog().isEmpty)
        }
        #expect(iCloud.records.isEmpty)
    }

    // The iPhone expands the card and follows it up offline, while the Mac
    // deletes it: the iPhone's reach iCloud tied to a card that's gone.
    @Test("a deleted card's expansions and follow-ups stay in both inboxes as captures, those made meanwhile too")
    func aDeletedCardsExpansionsAndFollowUpsStayAsCaptures() async throws {
        let ubuntu = try approve(card(.concept, front: "ubuntu", back: "Soy porque somos."), in: mac.engine)
        try mac.engine.expand(text: "ubuntu", note: "En zulú", source: nil)
        try mac.engine.followUp(ubuntu.id, text: "¿Quién lo dijo primero?")
        try await mac.syncNow()
        try await iPhone.syncNow()

        iPhone.iCloud.isOffline = true
        time.advance(by: minutes(1))
        try iPhone.engine.expand(text: "Ubuntu", note: "Lo decía Mandela", source: nil)
        try iPhone.engine.followUp(iPhone.engine.card(fronted: "ubuntu").id, text: "¿De qué idioma viene?")
        try mac.engine.delete([ubuntu.id])
        try await mac.syncNow()
        iPhone.iCloud.isOffline = false
        try await iPhone.syncNow()
        try await iPhone.syncNow()
        try await mac.syncNow()

        for device in [mac, iPhone] {
            let inbox = try device.engine.inbox()
            #expect(inbox.expansions.isEmpty)
            #expect(inbox.followUps.isEmpty)
            #expect(
                inbox.captures.map(\.text).sorted()
                    == ["ubuntu", "Ubuntu", "¿Quién lo dijo primero?", "¿De qué idioma viene?"].sorted())
            #expect(inbox.captures.compactMap(\.note).sorted() == ["En zulú", "Lo decía Mandela"])
        }
    }

    // petricor is discarded first and approved later, saudade the other way.
    @Test("a capture discarded on one device and approved on the other leaves both inboxes, and its cards stay on both")
    func aCaptureDiscardedAndApprovedLeavesTheInbox() async throws {
        try mac.engine.newCapture("petricor")
        try mac.engine.newCapture("saudade")
        try await mac.syncNow()
        try await iPhone.syncNow()
        let onIPhone = try iPhone.engine.inbox().captures

        time.advance(by: minutes(1))
        try mac.engine.discard(try #require(try mac.engine.inbox().captures.first { $0.text == "petricor" }).id)
        try iPhone.engine.approve(
            try #require(onIPhone.first { $0.text == "saudade" }).id,
            into: [
                card(.word, front: "saudade", back: "Nostalgia de lo que no volverá."),
                card(.question, front: "¿De qué idioma viene «saudade»?", back: "Del portugués."),
            ])
        time.advance(by: minutes(1))
        try iPhone.engine.approve(
            try #require(onIPhone.first { $0.text == "petricor" }).id,
            into: [card(.word, front: "petricor", back: "El olor de la lluvia.")])
        try mac.engine.discard(try #require(try mac.engine.inbox().captures.first { $0.text == "saudade" }).id)
        try await mac.syncNow()
        try await iPhone.syncNow()
        try await mac.syncNow()

        for device in [mac, iPhone] {
            #expect(try device.engine.inbox().captures.isEmpty)
            #expect(
                try device.engine.cards().map(\.front).sorted()
                    == ["petricor", "saudade", "¿De qué idioma viene «saudade»?"])
        }
        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
    }

    // The review panel's ⌘Z deletes a follow-up outright, as one undone never
    // was: the iPhone approves the second meanwhile. The deletion wins, so
    // the card approved from it is from no capture.
    @Test(
        "a follow-up taken back on one device leaves the other's inbox, and one approved there meanwhile leaves its cards on both"
    )
    func aFollowUpTakenBackLeavesTheOtherInbox() async throws {
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        let first = try mac.engine.followUp(ubuntu.id, text: "¿De qué idioma viene?")
        let second = try mac.engine.followUp(ubuntu.id, text: "¿Quién lo dijo primero?")
        try await mac.syncNow()
        try await iPhone.syncNow()

        try mac.engine.takeBackFollowUp(second.id, of: ubuntu.id)
        try mac.engine.takeBackFollowUp(first.id, of: ubuntu.id)
        time.advance(by: minutes(1))
        try iPhone.engine.approve(
            try #require(try iPhone.engine.inbox().followUps.first { $0.capture.text == second.text }).capture.id,
            into: [card(.question, front: "¿Quién dijo «ubuntu» primero?", back: "Nadie: es un proverbio zulú.")])
        try await mac.syncNow()
        try await iPhone.syncNow()
        try await iPhone.syncNow()
        try await mac.syncNow()

        for device in [mac, iPhone] {
            #expect(try device.engine.inbox().asSeen == InboxAsSeen(captures: [], expansions: [], followUps: []))
            #expect(try device.engine.cards().map(\.front).sorted() == ["ubuntu", "¿Quién dijo «ubuntu» primero?"])
            #expect(try device.engine.cards().map(\.captureID) == [nil, nil])
        }
        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
    }

    @Test(
        "an answer taken back on one device after it synced leaves the other's review log, and the card's step with it")
    func anAnswerTakenBackLeavesTheOtherLog() async throws {
        let ladder = ReviewSettings.defaults.ladder
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try mac.engine.meet(ubuntu)
        let afterTheFirstView = try mac.engine.standing(of: ubuntu.id, on: ladder)
        try mac.engine.reviewWhenDue(ubuntu, .good, movingForward: time)
        try await mac.syncNow()
        try await iPhone.syncNow()

        try mac.engine.takeBackAnswer(of: ubuntu.id, way: .frontFirst)
        try await mac.syncNow()
        try await iPhone.syncNow()

        #expect(try iPhone.logAsSeen().map(\.kind) == [.firstView])
        #expect(
            try iPhone.engine.standing(of: iPhone.engine.card(fronted: "ubuntu").id, on: ladder) == afterTheFirstView)
    }

    // The Mac keeps its cards in a data folder, with its backups.
    @Test("a card deleted on another device leaves this one with its image, and a backup made before still holds both")
    func aBackupKeepsACardDeletedElsewhere() async throws {
        let macOnDisk = try Device(
            Engine(location: .folder(folder), time: time, calendar: calendar), syncingThrough: iCloud)
        let bird = try macOnDisk.engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let hornero = try macOnDisk.engine.create(
            card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        try macOnDisk.engine.meet(hornero)
        try await macOnDisk.syncNow()
        try await iPhone.syncNow()
        let backup = try macOnDisk.engine.backUpNow(.defaults)

        time.advance(by: hours(1))
        try iPhone.engine.delete([iPhone.engine.card(fronted: "¿Qué pájaro es?").id])
        try await iPhone.syncNow()
        try await macOnDisk.syncNow()
        // The image leaves the Mac once it leaves iCloud, which the iPhone,
        // in sync, deletes at its next send (#314).
        try await iPhone.syncNow()
        try await macOnDisk.syncNow()

        #expect(try macOnDisk.engine.cards().isEmpty)
        #expect(try macOnDisk.engine.keptImages().isEmpty)
        try macOnDisk.engine.restore(backup.name)
        #expect(try macOnDisk.engine.cards() == [hornero])
        #expect(try macOnDisk.engine.reviewLog().map(\.kind) == [.firstView])
        #expect(try macOnDisk.engine.keptImages() == [bird])
    }
}

extension Device {
    /// Sends what changed, without fetching what the other devices changed,
    /// as iCloud's engine may.
    fileprivate func sendNow() async throws {
        try sync.sendWhatChanged(to: iCloud)
        try await iCloud.sendChanges()
    }
}
