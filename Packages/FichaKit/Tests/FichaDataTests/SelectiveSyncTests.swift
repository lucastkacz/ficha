import FichaCore
import Foundation
import GRDB
import Testing

// For the interface to iCloud's engine, which the fake implements, and for
// what waits to be sent.
@testable import FichaData

/// Tests on selective sync (ADR 0020, #355): which cards go up to iCloud, as
/// the user chooses every card or only those with the tags they tick, on
/// two devices, a Mac and an iPhone, each an engine in memory in Buenos
/// Aires on one clock, syncing through a fake iCloud.
final class SelectiveSyncTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let iCloud = FakeICloud()
    let mac: Device
    let iPhone: Device
    /// A data folder of the test's own, for an app and the CLI to share.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaSelectiveSyncTests-\(UUID().uuidString)",
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

    @Test(
        "while only the cards with a chosen tag sync, one goes up with its review log, flag and burial, and one with no chosen tag, or no tag, stays on its device"
    )
    func onlyTheCardsWithAChosenTagSync() async throws {
        let ubuntu = try mac.engine.create(
            card(.concept, front: "ubuntu", back: "Soy porque somos.", tags: ["filosofía", "zulú"]))
        try mac.engine.meet(ubuntu)
        try mac.engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        try mac.engine.bury(ubuntu.id)
        let petricor = try mac.engine.create(
            card(.word, front: "petricor", back: "El olor de la lluvia.", tags: ["lenguaje"]))
        try mac.engine.meet(petricor)
        try mac.engine.create(card(.word, front: "saudade", back: "Nostalgia de lo que se fue."))
        try mac.engine.syncOnlyChosenTags(true)
        try mac.engine.chooseToSync("filosofía", true)

        try await mac.syncNow()
        try await iPhone.syncNow()

        #expect(try iPhone.cardsAsSeen() == [try mac.engine.card(fronted: "ubuntu").asSeen])
        #expect(try iPhone.logAsSeen().map(\.uuid) == [try ubuntusEntry(on: mac)])
        #expect(records(ofType: .card).count == 1)
        #expect(records(ofType: .reviewLogEntry).count == 1)
        #expect(try mac.engine.changesToSend().isEmpty)
    }

    // The Mac chooses first, the iPhone after; then the iPhone unticks
    // filosofía, and the Mac, later still, has every card sync again.
    @Test("the choice of what syncs travels, and each of its parts keeps its latest change, whichever device made it")
    func theChoiceTravels() async throws {
        try mac.engine.syncOnlyChosenTags(true)
        try mac.engine.chooseToSync("filosofía", true)
        time.advance(by: minutes(1))
        try iPhone.engine.chooseToSync("lenguaje", true)
        try await syncBoth()

        for device in [mac, iPhone] {
            #expect(try device.engine.syncsOnlyChosenTags())
            #expect(try chosenTags(on: device) == ["filosofía", "lenguaje"])
        }

        time.advance(by: minutes(1))
        try iPhone.engine.chooseToSync("filosofía", false)
        time.advance(by: minutes(1))
        try mac.engine.syncOnlyChosenTags(false)
        try await syncBoth()

        for device in [mac, iPhone] {
            #expect(try !device.engine.syncsOnlyChosenTags())
            #expect(try chosenTags(on: device) == ["lenguaje"])
        }
    }

    // Chosen on the iPhone, which has no card with the tag: the Mac hears it,
    // and sends its card, which never went up, with its first view and image.
    @Test("a card that starts syncing goes up whole, with its review log and its images")
    func aCardThatStartsSyncingGoesUpWhole() async throws {
        let bird = try mac.engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let hornero = try mac.engine.create(
            card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", tags: ["aves"], frontImage: bird))
        try mac.engine.meet(hornero)
        try mac.engine.syncOnlyChosenTags(true)
        try await syncBoth()

        #expect(try iPhone.engine.cards().isEmpty)
        #expect(!iCloud.records.contains { $0.id == SyncedFile(bird).recordID })

        time.advance(by: minutes(1))
        try iPhone.engine.chooseToSync("aves", true)
        try await syncBoth()

        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
        #expect(try iPhone.logAsSeen() == mac.logAsSeen())
        #expect(try iPhone.engine.keptImages() == [bird])
    }

    // filosofía is chosen, and the card carries aves alone: the Mac adds
    // filosofía to it, or has every card sync.
    @Test(
        "a card starts syncing, and goes up whole, as a chosen tag is added to it, or as every card syncs again",
        arguments: [true, false])
    func aCardStartsSyncingInEachWay(addingAChosenTag: Bool) async throws {
        let hornero = try mac.engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", tags: ["aves"]))
        try mac.engine.meet(hornero)
        try mac.engine.syncOnlyChosenTags(true)
        try mac.engine.chooseToSync("filosofía", true)
        try await syncBoth()

        #expect(try iPhone.engine.cards().isEmpty)

        time.advance(by: minutes(1))
        if addingAChosenTag {
            try mac.engine.edit(
                hornero.id, with: card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", tags: ["aves", "filosofía"]))
        } else {
            try mac.engine.syncOnlyChosenTags(false)
        }
        try await syncBoth()

        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
        #expect(try iPhone.logAsSeen() == mac.logAsSeen())
    }

    // The file proposes Himnos, which no device chose.
    @Test("a card an import brings with a new tag stays on its device, as a new tag isn't chosen")
    func aNewTagIsntChosen() async throws {
        try mac.engine.syncOnlyChosenTags(true)
        try mac.engine.chooseToSync("filosofía", true)
        let read = [
            ImportedCard(
                content: try card(.concept, front: "ubuntu", back: "Soy porque somos.", tags: ["filosofía"]),
                fields: [], line: 1),
            ImportedCard(
                content: try card(nil, front: "¿Qué himno es?", back: "El de la Argentina."), fields: [], line: 2,
                proposedTags: ["Himnos"]),
        ]
        let preview = try mac.engine.preview(
            ImportReading(cards: read, leftOut: []), of: "Himnos.txt", kind: .cardsFile, images: [:], sounds: [:])
        try mac.engine.importCards(preview, choosing: ImportChoices())
        try await syncBoth()

        #expect(try mac.engine.card(fronted: "¿Qué himno es?").tags == ["Himnos"])
        #expect(try iPhone.engine.cards().map(\.front) == ["ubuntu"])
        for device in [mac, iPhone] {
            #expect(try chosenTags(on: device) == ["filosofía"])
        }
    }

    @Test(
        "a card that stops syncing leaves iCloud, with its review log and images, and every device keeps its copy, without sending it again"
    )
    func aCardThatStopsSyncingLeavesICloud() async throws {
        let bird = try mac.engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let hornero = try mac.engine.create(
            card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", tags: ["aves"], frontImage: bird))
        try mac.engine.meet(hornero)
        try mac.engine.syncOnlyChosenTags(true)
        try mac.engine.chooseToSync("aves", true)
        try await syncBoth()
        let asSeen = try mac.cardsAsSeen()

        time.advance(by: minutes(1))
        try iPhone.engine.chooseToSync("aves", false)
        try await syncBoth()
        let saves = iCloud.saves
        try await syncBoth()

        for device in [mac, iPhone] {
            #expect(try device.cardsAsSeen() == asSeen)
            #expect(try device.logAsSeen().map(\.kind) == [.firstView])
            #expect(try device.engine.keptImages() == [bird])
            #expect(try device.engine.changesToSend().isEmpty)
        }
        expectOnlyLeft(records(ofType: .card), keeping: [.tags])
        expectOnlyLeft(records(ofType: .reviewLogEntry), keeping: [])
        #expect(!iCloud.records.contains { $0.id == SyncedFile(bird).recordID })
        #expect(iCloud.saves == saves)
    }

    // The Mac unticks aves, and sends why, then the card as one that left.
    // The iPhone hears them in either order, each in a fetch of its own.
    @Test(
        "a card that stops syncing stays on a device that hears it left before it hears why, and on one that hears why first",
        arguments: [true, false])
    func whicheverArrivesFirst(leftFirst: Bool) async throws {
        try mac.engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", tags: ["aves"]))
        try mac.engine.syncOnlyChosenTags(true)
        try mac.engine.chooseToSync("aves", true)
        try await syncBoth()
        let asSeen = try mac.cardsAsSeen()

        time.advance(by: minutes(1))
        try mac.engine.chooseToSync("aves", false)
        try await mac.syncNow()
        try await mac.syncNow()
        let left = try #require(records(ofType: .card).only)
        let why = try #require(records(ofType: .tag).only)
        #expect(left.hasLeft)
        let stretch = try #require(try iPhone.engine.syncStretch())
        for record in leftFirst ? [left, why] : [why, left] {
            try iPhone.sync.handle(
                .fetchedRecordZoneChanges(.init(modifications: [record], deletions: [])), from: iPhone.iCloud,
                startedIn: stretch)
            try iPhone.sync.handle(.didFetchChanges, from: iPhone.iCloud, startedIn: stretch)
            #expect(try iPhone.cardsAsSeen() == asSeen)
        }
        try await syncBoth(times: 3)

        for device in [mac, iPhone] {
            #expect(try device.cardsAsSeen() == asSeen)
            #expect(try chosenTags(on: device).isEmpty)
            #expect(try device.engine.changesToSend().isEmpty)
        }
        expectOnlyLeft(records(ofType: .card), keeping: [.tags])
    }

    // The tag lenguaje isn't chosen: the card leaves as it takes it in place
    // of filosofía, and the record that left carries why.
    @Test("a card that stops syncing as its tags change leaves iCloud, and the other device takes its new tags")
    func aCardThatLeavesAsItsTagsChange() async throws {
        let ubuntu = try mac.engine.create(
            card(.concept, front: "ubuntu", back: "Soy porque somos.", tags: ["filosofía"]))
        try mac.engine.syncOnlyChosenTags(true)
        try mac.engine.chooseToSync("filosofía", true)
        try await syncBoth()

        time.advance(by: minutes(1))
        try mac.engine.edit(ubuntu.id, with: card(.concept, front: "ubuntu", back: "Soy porque somos.", tags: ["zulú"]))
        try await syncBoth()

        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
        #expect(try iPhone.engine.card(fronted: "ubuntu").tags == ["zulú"])
        expectOnlyLeft(records(ofType: .card), keeping: [.tags])
    }

    @Test("a card deleted while it doesn't sync is deleted on that device alone, and one that never synced too")
    func aCardDeletedWhileItDoesntSyncStaysElsewhere() async throws {
        let ubuntu = try mac.engine.create(
            card(.concept, front: "ubuntu", back: "Soy porque somos.", tags: ["filosofía"]))
        let petricor = try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try mac.engine.syncOnlyChosenTags(true)
        try mac.engine.chooseToSync("filosofía", true)
        try await syncBoth()
        time.advance(by: minutes(1))
        try mac.engine.chooseToSync("filosofía", false)
        try await syncBoth()

        try mac.engine.delete([ubuntu.id, petricor.id])
        try await syncBoth()

        #expect(try mac.engine.cards().isEmpty)
        #expect(try iPhone.engine.cards().map(\.front) == ["ubuntu"])
        expectOnlyLeft(records(ofType: .card), keeping: [.tags])
        #expect(try mac.engine.changesToSend().isEmpty)
    }

    // Each device reviews the card while it doesn't sync, the Mac first.
    @Test("ticking a tag again joins the copies on both devices, with the reviews each made meanwhile")
    func tickingAgainJoins() async throws {
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos.", tags: ["zulú"]))
        try mac.engine.meet(ubuntu)
        try mac.engine.syncOnlyChosenTags(true)
        try mac.engine.chooseToSync("zulú", true)
        try await syncBoth()
        let ubuntuOnIPhone = try iPhone.engine.card(fronted: "ubuntu")
        time.advance(by: minutes(1))
        try mac.engine.chooseToSync("zulú", false)
        try await syncBoth()
        let ladder = ReviewSettings.defaults.ladder

        time.move(to: try #require(try mac.engine.standing(of: ubuntu.id, on: ladder).due))
        try mac.engine.review(ubuntu, .good)
        time.advance(by: minutes(30))
        try iPhone.engine.review(ubuntuOnIPhone, .good)
        try await syncBoth()

        #expect(try mac.logAsSeen().count == 2)
        #expect(try iPhone.logAsSeen().count == 2)

        time.advance(by: minutes(1))
        try iPhone.engine.chooseToSync("zulú", true)
        try await syncBoth(times: 3)

        #expect(try mac.logAsSeen().map(\.kind) == [.firstView, .review(.good), .review(.good)])
        #expect(try iPhone.logAsSeen() == mac.logAsSeen())
        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
        #expect(
            try iPhone.engine.standing(of: ubuntuOnIPhone.id, on: ladder)
                == mac.engine.standing(of: ubuntu.id, on: ladder))
        #expect(records(ofType: .card).allSatisfy { !$0.hasLeft && $0.value(of: "front") == .string("ubuntu") })
    }

    @Test("an expansion or a follow-up of a card that doesn't sync stays on its device, and every other capture syncs")
    func capturesFollowTheirCards() async throws {
        let ubuntu = try approve(
            card(.concept, front: "ubuntu", back: "Soy porque somos.", tags: ["filosofía"]), in: mac.engine)
        let petricor = try approve(card(.word, front: "petricor", back: "El olor de la lluvia."), in: mac.engine)
        try mac.engine.syncOnlyChosenTags(true)
        try mac.engine.chooseToSync("filosofía", true)
        try mac.engine.newCapture("saudade")
        try mac.engine.followUp(ubuntu.id, text: "¿Quién lo dijo primero?")
        try mac.engine.followUp(petricor.id, text: "¿De qué idioma viene?")
        try mac.engine.expand(text: "petricor", note: "Del griego", source: nil)

        try await syncBoth()

        #expect(
            try iPhone.engine.inbox().asSeen
                == InboxAsSeen(captures: ["saudade"], expansions: [], followUps: ["¿Quién lo dijo primero? → ubuntu"]))
        #expect(try mac.engine.changesToSend().isEmpty)
    }

    @Test("what the CLI writes follows the choice, as the app's own changes do")
    func whatTheCLIWritesFollowsTheChoice() async throws {
        let cli = try Engine(location: .folder(folder), time: time, calendar: calendar)
        let app = try Device(Engine(location: .folder(folder), time: time, calendar: calendar), syncingThrough: iCloud)
        try cli.syncOnlyChosenTags(true)
        try cli.chooseToSync("filosofía", true)
        try cli.create(card(.concept, front: "ubuntu", back: "Soy porque somos.", tags: ["filosofía"]))
        try cli.create(card(.word, front: "petricor", back: "El olor de la lluvia.", tags: ["lenguaje"]))

        try await app.syncNow()
        try await iPhone.syncNow()

        #expect(try iPhone.engine.cards().map(\.front) == ["ubuntu"])
        #expect(try chosenTags(on: iPhone) == ["filosofía"])
    }

    /// Syncs the Mac, then the iPhone, `times` times, so that what one sends
    /// as it hears the other reaches it: a device sends what a fetch had it
    /// note at its next sync.
    private func syncBoth(times: Int = 3) async throws {
        for _ in 0..<times {
            try await mac.syncNow()
            try await iPhone.syncNow()
        }
    }

    /// The records of `type` iCloud holds.
    private func records(ofType type: SyncedRow.RecordType) -> [ICloudRecord] {
        iCloud.records.filter { $0.type == type.rawValue }
    }

    /// Checks that each of `records` is one that left iCloud, holding the
    /// fields `kept` and nothing else but when each last changed, for those
    /// that ever changed.
    private func expectOnlyLeft(_ records: [ICloudRecord], keeping kept: [SyncedField]) {
        #expect(!records.isEmpty)
        let keys = Set(kept.flatMap { [$0.rawValue, $0.timeKey] }).union(["left"])
        for record in records {
            let held = Set(record.fields.compactMap { $0.value == nil ? nil : $0.key })
            #expect(record.hasLeft)
            #expect(held.isSubset(of: keys))
            #expect(held.isSuperset(of: kept.map(\.rawValue)))
        }
    }

    /// The tags chosen to sync on `device`.
    private func chosenTags(on device: Device) throws -> Set<String> {
        try device.engine.read(WhatSyncs.init(in:)).chosenTags
    }

    /// The ID of ubuntu's only entry in `device`'s review log.
    private func ubuntusEntry(on device: Device) throws -> UUID? {
        let ubuntu = try device.engine.card(fronted: "ubuntu")
        return try #require(try device.engine.reviewLog().filter { $0.cardID == ubuntu.id }.only).uuid
    }
}
