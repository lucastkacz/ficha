import FichaCore
import Foundation
import Testing

// For the interface to iCloud's engine, which the fake implements, and for
// what waits to be sent.
@testable import FichaData

/// Tests on sync (ADR 0017): two devices, a Mac and an iPhone, each an engine
/// in memory in Buenos Aires on one clock, syncing through a fake iCloud.
final class SyncTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let iCloud = FakeICloud()
    let mac: Device
    let iPhone: Device
    /// A data folder of the test's own, for an app and the CLI to share.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaSyncTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 21, in: calendar))
        mac = try Device(
            Engine(location: .inMemory, time: time, ids: CountingIDSource(device: 1), calendar: calendar),
            syncingThrough: iCloud)
        iPhone = try Device(
            Engine(location: .inMemory, time: time, ids: CountingIDSource(device: 2), calendar: calendar),
            syncingThrough: iCloud)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("a card created on one device appears on the other, as it is there")
    func aCardCreatedOnOneDeviceAppearsOnTheOther() async throws {
        let ubuntu = try mac.engine.create(
            card(.concept, front: "ubuntu", back: "Soy porque somos.", tags: ["filosofía"], source: "Desmond Tutu"),
            bothWays: true)
        time.advance(by: minutes(1))
        try mac.engine.flag(ubuntu.id, note: note("Falta un ejemplo"))

        try await mac.syncNow()
        try await iPhone.syncNow()

        #expect(try iPhone.engine.cards().map(\.asSeen) == mac.engine.cards().map(\.asSeen))
        #expect(try iPhone.engine.cards().count == 1)
    }

    @Test("edits to different parts of a card on two devices both survive, on both")
    func editsToDifferentPartsBothSurvive() async throws {
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try await mac.syncNow()
        try await iPhone.syncNow()
        let ubuntuOnIPhone = try #require(try iPhone.engine.cards().only)

        time.advance(by: minutes(1))
        try mac.engine.edit(ubuntu.id, with: card(.concept, front: "ubuntu", back: "Soy porque somos, en zulú."))
        time.advance(by: minutes(1))
        try iPhone.engine.edit(
            ubuntuOnIPhone.id,
            with: card(
                .concept, front: "ubuntu", back: "Soy porque somos.", tags: ["filosofía"], source: "Desmond Tutu"))
        try iPhone.engine.bury(ubuntuOnIPhone.id)
        try await mac.syncNow()
        try await iPhone.syncNow()
        try await mac.syncNow()

        let both = try card(
            .concept, front: "ubuntu", back: "Soy porque somos, en zulú.", tags: ["filosofía"], source: "Desmond Tutu")
        #expect(try mac.engine.cards().map { content(of: $0) } == [both])
        #expect(try mac.engine.cards().first?.buriedAt == time.now)
        #expect(try iPhone.engine.cards().map(\.asSeen) == mac.engine.cards().map(\.asSeen))
    }

    // The Mac sends its edits first: of ubuntu, the earlier one, which the
    // iPhone's later edit replaces; of petricor, the later one, which the
    // iPhone's earlier edit, sent after it, doesn't replace.
    @Test("the same part edited on two devices keeps the latest edit on both, whichever device sends last")
    func theSamePartEditedOnBothKeepsTheLatest() async throws {
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        let petricor = try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        try await mac.syncNow()
        try await iPhone.syncNow()
        let ubuntuOnIPhone = try iPhone.engine.card(fronted: "ubuntu")
        let petricorOnIPhone = try iPhone.engine.card(fronted: "petricor")
        let editedFirst = time.now + minutes(1)
        let editedLast = editedFirst + minutes(1)

        time.move(to: editedFirst)
        try mac.engine.edit(ubuntu.id, with: card(.concept, front: "ubuntu", back: "Soy porque somos, en zulú."))
        try mac.engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        try iPhone.engine.edit(petricorOnIPhone.id, with: card(.word, front: "petricor", back: "Huele a lluvia."))
        time.move(to: editedLast)
        try iPhone.engine.edit(ubuntuOnIPhone.id, with: card(.concept, front: "ubuntu", back: "Yo soy porque somos."))
        try iPhone.engine.flag(ubuntuOnIPhone.id, note: note("Falta de dónde viene"))
        try mac.engine.edit(petricor.id, with: card(.word, front: "petricor", back: "El olor de la tierra mojada."))
        try await mac.syncNow()
        try await iPhone.syncNow()
        try await mac.syncNow()

        let onMac = try mac.engine.cards()
        #expect(onMac.map(\.back) == ["Yo soy porque somos.", "El olor de la tierra mojada."])
        #expect(onMac.map(\.flag) == [Flag(note: "Falta de dónde viene", flaggedAt: editedLast), nil])
        #expect(onMac.map(\.editedAt) == [editedLast, editedLast])
        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
    }

    @Test("a side edited on another device restarts a card's count of “Again” answers, as an edit here does")
    func aSideEditedOnAnotherDeviceRestartsTheForgottenOftenCount() async throws {
        var settings = ReviewSettings.defaults
        settings.forgottenOftenAfter = 2
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try mac.engine.meet(ubuntu)
        time.advance(by: hours(1))
        try mac.engine.record(
            .review(.again), of: ubuntu.id, responseTime: .seconds(3), trigger: .reviewNow, settings: settings)
        try await mac.syncNow()
        try await iPhone.syncNow()

        time.advance(by: minutes(1))
        try iPhone.engine.edit(
            iPhone.engine.card(fronted: "ubuntu").id,
            with: card(.concept, front: "ubuntu", back: "Yo soy porque somos."))
        try await iPhone.syncNow()
        try await mac.syncNow()
        time.advance(by: hours(1))
        let forgotten = try mac.engine.record(
            .review(.again), of: ubuntu.id, responseTime: .seconds(3), trigger: .reviewNow, settings: settings)

        #expect(forgotten == nil)
    }

    @Test("captures, expansions and follow-ups travel, and what's refined on one device leaves the inbox on both")
    func theInboxTravels() async throws {
        let ubuntu = try approve(card(.concept, front: "ubuntu", back: "Soy porque somos."), in: mac.engine)
        try mac.engine.newCapture("petricor", note: "Lo leí en un libro", source: "Borges")
        try mac.engine.expand(text: "ubuntu", note: "En zulú", source: nil)
        try mac.engine.followUp(ubuntu.id, text: "¿Quién lo dijo primero?")
        try await mac.syncNow()
        try await iPhone.syncNow()

        let inboxOnIPhone = try iPhone.engine.inbox()
        #expect(try inboxOnIPhone.asSeen == mac.engine.inbox().asSeen)
        #expect(
            inboxOnIPhone.asSeen
                == InboxAsSeen(
                    captures: ["petricor"], expansions: ["ubuntu → ubuntu"],
                    followUps: ["¿Quién lo dijo primero? → ubuntu"]))
        time.advance(by: minutes(1))
        try iPhone.engine.approveExpansion(
            try #require(inboxOnIPhone.expansions.only).capture.id,
            into: card(.concept, front: "ubuntu", back: "Soy porque somos, en zulú."))
        try iPhone.engine.approve(
            try #require(inboxOnIPhone.captures.only).id,
            into: [card(.word, front: "petricor", back: "El olor de la lluvia.", source: "Borges")])
        try await iPhone.syncNow()
        try await mac.syncNow()

        #expect(
            try mac.engine.inbox().asSeen
                == InboxAsSeen(captures: [], expansions: [], followUps: ["¿Quién lo dijo primero? → ubuntu"]))
        #expect(try mac.cardsAsSeen().map(\.content?.back) == ["El olor de la lluvia.", "Soy porque somos, en zulú."])
        #expect(try mac.cardsAsSeen() == iPhone.cardsAsSeen())
    }

    // Each answer comes at a time that isn't a whole millisecond, as a real
    // clock's does: both devices must still order the joined log alike. The
    // iPhone's good answered the first review, as the Mac's did, so it's
    // spaced again after the Mac's: a good on the last learning step, which
    // graduates the card.
    @Test("reviews made offline on both devices join, and the card stands alike on both after them")
    func reviewsMadeOfflineJoin() async throws {
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        time.advance(by: 0.123_456_7)
        try mac.engine.meet(ubuntu)
        try await mac.syncNow()
        try await iPhone.syncNow()
        let ubuntuOnIPhone = try iPhone.engine.card(fronted: "ubuntu")
        let scheduler = ReviewSettings.defaults.scheduler

        mac.iCloud.isOffline = true
        iPhone.iCloud.isOffline = true
        time.move(to: try #require(try mac.engine.standing(of: ubuntu.id, with: scheduler).due) + 0.234_567_8)
        try mac.engine.review(ubuntu, .good)
        time.advance(by: minutes(30) + 0.000_432_1)
        try iPhone.engine.review(ubuntuOnIPhone, .good)
        await #expect(throws: FakeICloudError.self) { try await self.mac.syncNow() }
        mac.iCloud.isOffline = false
        iPhone.iCloud.isOffline = false
        try await mac.syncNow()
        try await iPhone.syncNow()
        try await mac.syncNow()

        let onMac = try mac.engine.standing(of: ubuntu.id, with: scheduler)
        #expect(onMac.stage == .graduated)
        #expect(try iPhone.engine.standing(of: ubuntuOnIPhone.id, with: scheduler) == onMac)
        #expect(try mac.logAsSeen().map(\.kind) == [.review(.again), .review(.good), .review(.good)])
        #expect(try iPhone.logAsSeen() == mac.logAsSeen())
    }

    // A new card's again waits the first learning step's hour, good the
    // second step's 4 hours, hard repeats that step, and again goes back to
    // the first step's hour.
    @Test("each review keeps the interval it set, which reaches the other device with it")
    func eachReviewKeepsItsInterval() async throws {
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try mac.engine.meet(ubuntu)
        try mac.engine.reviewWhenDue(ubuntu, .good, movingForward: time)
        try mac.engine.reviewWhenDue(ubuntu, .hard, movingForward: time)
        try mac.engine.reviewWhenDue(ubuntu, .again, movingForward: time)

        try await mac.syncNow()
        try await iPhone.syncNow()

        #expect(
            try mac.logAsSeen().map(\.interval) == [
                .seconds(hours(1)), .seconds(hours(4)), .seconds(hours(4)), .seconds(hours(1)),
            ])
        #expect(try iPhone.logAsSeen() == mac.logAsSeen())
    }

    // The Mac's again came first, and the iPhone's good five minutes later,
    // before the iPhone knew of it: the joined log spaces the good from where
    // the again left the card, relearning, so the good never erases the
    // again (ADR 0017, #404).
    @Test("a good one device gave before it knew of the other's again is spaced after the again, which stays")
    func aGoodBeforeKnowingOfAnAgainNeverErasesIt() async throws {
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try mac.engine.climb(ubuntu, goods: 2, movingForward: time)
        try await mac.syncNow()
        try await iPhone.syncNow()
        let ubuntuOnIPhone = try iPhone.engine.card(fronted: "ubuntu")
        let scheduler = ReviewSettings.defaults.scheduler

        mac.iCloud.isOffline = true
        iPhone.iCloud.isOffline = true
        time.move(to: try #require(try mac.engine.standing(of: ubuntu.id, with: scheduler).due))
        try mac.engine.review(ubuntu, .again)
        time.advance(by: minutes(5))
        try iPhone.engine.review(ubuntuOnIPhone, .good)
        let keptOnTheIPhone = try #require(
            try iPhone.engine.standing(of: ubuntuOnIPhone.id, with: scheduler).interval)
        mac.iCloud.isOffline = false
        iPhone.iCloud.isOffline = false
        try await mac.syncNow()
        try await iPhone.syncNow()
        try await mac.syncNow()

        let onMac = try mac.engine.standing(of: ubuntu.id, with: scheduler)
        #expect(onMac.stage == .graduated)
        #expect(try #require(onMac.interval) < keptOnTheIPhone)
        #expect(try iPhone.engine.standing(of: ubuntuOnIPhone.id, with: scheduler) == onMac)
        #expect(try mac.logAsSeen().suffix(2).map(\.kind) == [.review(.again), .review(.good)])
        #expect(try iPhone.logAsSeen() == mac.logAsSeen())
    }

    // A device still on a Ficha before FSRS sends a new card's first view,
    // and each review without the interval it set: the device that takes
    // them carries them over as the migration does (#407), the first view as
    // a first review rated again, and each review with the interval the
    // scheduler gives it. iCloud gives them in any order, here the latest
    // first, as the fake does, and all before their card: a review that
    // comes before the entry it answered is carried over again as that entry
    // comes, so both devices hold the log alike.
    @Test("a first view and reviews without an interval, from an older Ficha, are carried over as they arrive")
    func recordsFromAnOlderFichaAreCarriedOverOnArrival() async throws {
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try mac.engine.climb(ubuntu, goods: 2, movingForward: time)
        try await mac.syncNow()
        let entries = try iCloud.records.filter { $0.type == SyncedRow.RecordType.reviewLogEntry.rawValue }
            .sorted { try $0.time("answeredAt") ?? .distantPast < $1.time("answeredAt") ?? .distantPast }
        for entry in entries {
            var fields = entry.fields
            fields["interval"] = .some(nil)
            if entry.value(of: "answeredEntry") == nil {
                fields["kind"] = .string("firstView")
                fields["rating"] = .some(nil)
            }
            iCloud.saveFromANewerFicha(
                ICloudRecord(id: entry.id, type: entry.type, fields: fields, systemFields: entry.systemFields))
        }

        try await iPhone.syncNow()

        let scheduler = ReviewSettings.defaults.scheduler
        let ubuntuOnIPhone = try iPhone.engine.card(fronted: "ubuntu")
        let onTheIPhone = try iPhone.engine.reviewLogRows(of: ubuntuOnIPhone.id, with: scheduler)
        let onTheMac = try mac.engine.reviewLogRows(of: ubuntu.id, with: scheduler)
        #expect(onTheIPhone.map(\.entry.kind) == [.review(.again), .review(.good), .review(.good)])
        #expect(onTheIPhone.map(\.entry.uuid) == onTheMac.map(\.entry.uuid))
        #expect(onTheIPhone.map(\.interval) == onTheMac.map(\.interval))
        #expect(try iPhone.logAsSeen() == mac.logAsSeen())
        #expect(
            try iPhone.engine.standing(of: ubuntuOnIPhone.id, with: scheduler)
                == mac.engine.standing(of: ubuntu.id, with: scheduler))
    }

    // The iPhone holds the card when an older Ficha's entries come, each
    // carried over as it arrives. Whichever comes first, each review ends up
    // answering the entry before it, with the interval the carry-over gives
    // it there, as the migration carries over the Mac's: the Mac recorded
    // them with Ficha's settings, which the carry-over uses.
    @Test(
        "an older Ficha's log carried over as it arrives ends up as the migration carries it over, in any order",
        arguments: [[2, 1, 0], [0, 1, 2], [1, 2, 0], [0, 2, 1]])
    func anOlderFichasLogIsCarriedOverInAnyOrder(arrival: [Int]) async throws {
        let ubuntu = try await receiveAnOlderFichasLog(goods: 2, arrivingInOrder: arrival)

        let log = try iPhone.logAsSeen()
        #expect(log == (try mac.logAsSeen()))
        #expect(log.map(\.answeredEntry) == [nil] + log.dropLast().map(\.uuid))
        #expect(
            try iPhone.engine.standing(of: iPhone.engine.card(fronted: "ubuntu").id, with: .standard)
                == mac.engine.standing(of: ubuntu.id, with: .standard))
    }

    // The new cards a day count a new way's first review, which answers no
    // entry: ubuntu's three entries, which came latest first, make one, so a
    // second new card still comes today.
    @Test("a card an older Ficha's log brings counts once toward the new cards a day")
    func aCardFromAnOlderFichaCountsOnceTowardTheNewCardsADay() async throws {
        try await receiveAnOlderFichasLog(goods: 2, arrivingInOrder: [2, 1, 0])
        let petricor = try iPhone.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        var settings = ReviewSettings.defaults
        settings.newCardsPerDay = 2

        #expect(try iPhone.engine.reviewNow(settings) == [.new(petricor)])
    }

    // Each review an older Ficha sent keeps the interval the carry-over gave
    // it, since it answers the entry before it: settings with other steps, a
    // lower retention, under which ubuntu's last good would wait 19 days in
    // place of 2, and a shorter longest interval leave it due when it was.
    @Test("a change to the scheduling settings leaves an older Ficha's reviews, carried over as they arrive, due alike")
    func aSettingsChangeLeavesCarriedOverReviewsDueAlike() async throws {
        let ubuntu = try await receiveAnOlderFichasLog(goods: 3, arrivingInOrder: [3, 2, 1, 0])
        let changed = try #require(
            Scheduler.standard.replacing(
                learningSteps: [.seconds(minutes(30)), .seconds(hours(2))], relearningSteps: [.seconds(minutes(20))],
                desiredRetention: 0.7, longestIntervalInDays: 365, parameters: []))

        #expect(
            try iPhone.engine.standing(of: iPhone.engine.card(fronted: "ubuntu").id, with: changed).due
                == mac.engine.standing(of: ubuntu.id, with: .standard).due)
    }

    /// Has a card reach the iPhone, and then the review log the Mac gives it,
    /// met and rated good `goods` times, each when due, as a device still on
    /// a Ficha before FSRS sends it (#407): each entry without the interval
    /// it set, and the first review, which answers no entry, as a first view.
    /// The entries arrive in `order`, each by when it was answered, counted
    /// from 0. Returns the card, as the Mac holds it.
    @discardableResult
    private func receiveAnOlderFichasLog(goods: Int, arrivingInOrder order: [Int]) async throws -> Card {
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try await mac.syncNow()
        try await iPhone.syncNow()
        try mac.engine.climb(ubuntu, goods: goods, movingForward: time)
        try await mac.syncNow()
        let entries = try iCloud.records.filter { $0.type == SyncedRow.RecordType.reviewLogEntry.rawValue }
            .sorted { try $0.time("answeredAt") ?? .distantPast < $1.time("answeredAt") ?? .distantPast }
        // The fake gives a zone's records newest first.
        for position in order.reversed() {
            let entry = entries[position]
            var fields = entry.fields
            fields["interval"] = .some(nil)
            if entry.value(of: "answeredEntry") == nil {
                fields["kind"] = .string("firstView")
                fields["rating"] = .some(nil)
            }
            iCloud.saveFromANewerFicha(
                ICloudRecord(id: entry.id, type: entry.type, fields: fields, systemFields: entry.systemFields))
        }
        try await iPhone.syncNow()
        return ubuntu
    }

    // The Mac's update carried over serendipia's first view and its good 10
    // minutes later. Then a hard from the iPhone, still on a Ficha before
    // FSRS, comes, given 5 minutes after the first view: the good, which
    // the migration carried over, now answers the hard, and waits the
    // second learning step's 4 hours after it, as both would have been
    // carried over had the hard come before the update.
    @Test("a review the migration carried over is carried over again when an older Ficha's review comes before it")
    func aReviewTheMigrationCarriedOverIsCarriedOverAgain() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let before = time.now - days(1)
        try saveDatabaseBeforeTheSchedulerReplacedTheLadder(at: folder.appending(path: "Ficha.sqlite"), at: before)
        let macFromBefore = try Device(
            Engine(location: .folder(folder), time: time, calendar: calendar), syncingThrough: iCloud)
        try macFromBefore.turnSyncOn()
        try await macFromBefore.syncNow()
        let serendipia = try macFromBefore.engine.card(fronted: "serendipia")
        let firstView = try #require(try macFromBefore.engine.reviewLog().first { $0.cardID == serendipia.id })
        let card = try #require(
            iCloud.records.first {
                $0.type == SyncedRow.RecordType.card.rawValue && $0.value(of: "front") == .string("serendipia")
            })
        let hard = UUID()
        iCloud.saveFromANewerFicha(
            ICloudRecord(
                id: ICloudRecordID(name: hard.uuidString, zone: card.id.zone),
                type: SyncedRow.RecordType.reviewLogEntry.rawValue,
                fields: [
                    "card": .string(card.id.name), "way": .string(Way.frontFirst.rawValue), "kind": .string("review"),
                    "rating": .string(Rating.hard.rawValue),
                    "answeredAt": .int((before + minutes(5)).wholeMilliseconds), "responseTime": .double(2),
                    "trigger": .string(Trigger.reviewNow.rawValue), "isAhead": .int(0),
                    "answeredEntry": .string(try #require(firstView.uuid).uuidString),
                ],
                systemFields: nil))

        try await macFromBefore.syncNow()

        let log = try macFromBefore.logAsSeen().filter { $0.way == .frontFirst }
        #expect(log.map(\.kind) == [.review(.again), .review(.hard), .review(.good)])
        #expect(log.map(\.answeredEntry) == [nil, firstView.uuid, hard])
        #expect(
            log.map(\.interval) == [.seconds(hours(1)), .seconds(hours(2) + minutes(30)), .seconds(hours(4))])
    }

    // An import that brings Anki's progress places a card Anki was reviewing
    // every 10 days with that interval, Anki's due date and its ease.
    @Test("a placement reaches the other device with its interval, due time and ease")
    func aPlacementReachesTheOtherDevice() async throws {
        try await importOnTheMac([
            AnkiNote(type: .basic, fields: ["corazón", "heart"], progress: .review(due: 30, interval: 10))
        ])

        try await mac.syncNow()
        try await iPhone.syncNow()

        #expect(
            try iPhone.logAsSeen().map(\.kind) == [
                .placement(Placement(interval: .seconds(days(10)), due: try october(31, at: 4), ease: 2.5))
            ])
        #expect(try iPhone.logAsSeen() == mac.logAsSeen())
    }

    // A device still on a Ficha before FSRS sends a placement on a step of
    // its ladder, without an interval or an ease: the device that takes it
    // gives it that step's wait on the ladder Ficha shipped, and, for a wait
    // of a day or more, Anki's starting ease, as the migration does with the
    // ladder Ficha shipped. corazón was on the second step, of 4 hours, and
    // pulmón on the fourth, of 5 days.
    @Test("a placement on a step of the ladder, from an older Ficha, is carried over as it arrives")
    func aPlacementFromAnOlderFichaIsCarriedOverOnArrival() async throws {
        try await importOnTheMac([
            AnkiNote(type: .basic, fields: ["corazón", "heart"], progress: .review(due: 30, interval: 10)),
            AnkiNote(type: .basic, fields: ["pulmón", "lung"], progress: .review(due: 25, interval: 400)),
        ])
        try await mac.syncNow()
        for entry in iCloud.records where entry.type == SyncedRow.RecordType.reviewLogEntry.rawValue {
            var fields = entry.fields
            fields["step"] = .int(entry.value(of: "interval") == .double(days(10)) ? 1 : 3)
            fields["interval"] = .some(nil)
            fields["ease"] = .some(nil)
            iCloud.saveFromANewerFicha(
                ICloudRecord(id: entry.id, type: entry.type, fields: fields, systemFields: entry.systemFields))
        }

        try await iPhone.syncNow()

        let corazon = try iPhone.engine.card(fronted: "corazón")
        let pulmon = try iPhone.engine.card(fronted: "pulmón")
        let log = try iPhone.engine.reviewLog()
        #expect(
            log.filter { $0.cardID == corazon.id }.map(\.kind) == [
                .placement(Placement(interval: .seconds(hours(4)), due: try october(31, at: 4)))
            ])
        #expect(
            log.filter { $0.cardID == pulmon.id }.map(\.kind) == [
                .placement(Placement(interval: .seconds(days(5)), due: try october(26, at: 4), ease: 2.5))
            ])
        #expect(
            try iPhone.engine.standing(of: corazon.id, with: .standard).stageAndDue
                == learning(step: 0, due: try october(31, at: 4)))
        #expect(
            try iPhone.engine.standing(of: pulmon.id, with: .standard).stageAndDue
                == graduated(due: try october(26, at: 4)))
    }

    /// Imports on the Mac an Anki package with `notes`, bringing their
    /// progress. The package's collection was created on 1 October 2026 at 4
    /// in the morning, so Anki's day 30 is 31 October.
    private func importOnTheMac(_ notes: [AnkiNote]) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "Mazo.apkg")
        try AnkiPackage(notes: notes).write(to: file)
        try await mac.engine.importCards(
            mac.engine.previewImport(of: file), choosing: ImportChoices(progress: .brought))
    }

    /// `hour` o'clock on `day` October 2026, in Buenos Aires.
    private func october(_ day: Int, at hour: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour)))
    }

    @Test("a review rated easy is kept as easy, and reaches the other device as easy")
    func easyIsKeptAndReachesTheOtherDevice() async throws {
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try mac.engine.meet(ubuntu)
        try mac.engine.reviewWhenDue(ubuntu, .easy, movingForward: time)

        try await mac.syncNow()
        try await iPhone.syncNow()

        #expect(try mac.logAsSeen().map(\.kind) == [.review(.again), .review(.easy)])
        #expect(try iPhone.logAsSeen() == mac.logAsSeen())
    }

    @Test("⌘Z takes back the answer given on this device, never one that came from another device since")
    func takingBackAnAnswerLeavesAnotherDevicesAlone() async throws {
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try mac.engine.meet(ubuntu)
        try await mac.syncNow()
        try await iPhone.syncNow()
        time.move(to: try #require(try mac.engine.standing(of: ubuntu.id, with: ReviewSettings.defaults.scheduler).due))
        try mac.engine.review(ubuntu, .again)
        time.advance(by: minutes(1))
        try iPhone.engine.review(iPhone.engine.card(fronted: "ubuntu"), .good)
        try await iPhone.syncNow()
        try await mac.syncNow()

        try mac.engine.takeBackAnswer(of: ubuntu.id, way: .frontFirst)

        #expect(try mac.logAsSeen().map(\.kind) == [.review(.again), .review(.good)])
    }

    // The iPhone gets the Mac's three entries in one go, in iCloud's order,
    // and then the Mac's again after its own good, which came later. The
    // Mac's again keeps its relearning step's hour, and the iPhone's good,
    // which answered the review before it, is spaced again after the again:
    // a good on the last relearning step, which graduates the card again.
    @Test(
        "the Cards window lists a review log joined from two devices in the order it happened, each with its interval, alike on both"
    )
    func theCardsWindowListsAJoinedLogInOrder() async throws {
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try mac.engine.climb(ubuntu, goods: 2, movingForward: time)
        try await mac.syncNow()
        try await iPhone.syncNow()
        let ubuntuOnIPhone = try iPhone.engine.card(fronted: "ubuntu")
        let scheduler = ReviewSettings.defaults.scheduler

        time.move(to: try #require(try mac.engine.standing(of: ubuntu.id, with: scheduler).due))
        try mac.engine.review(ubuntu, .again)
        time.advance(by: minutes(10))
        try iPhone.engine.review(ubuntuOnIPhone, .good)
        try await iPhone.syncNow()
        try await mac.syncNow()
        try await iPhone.syncNow()

        var intervalsOnEach: [[Duration]] = []
        for (device, cardID) in [(mac, ubuntu.id), (iPhone, ubuntuOnIPhone.id)] {
            let rows = try device.engine.reviewLogRows(of: cardID, with: scheduler)
            #expect(
                rows.map(\.entry.kind) == [
                    .review(.again), .review(.good), .review(.good), .review(.again), .review(.good),
                ])
            intervalsOnEach.append(rows.map(\.interval))
        }
        let intervals = try #require(intervalsOnEach.first)
        #expect(intervalsOnEach.last == intervals)
        #expect(intervals.map { $0 >= .seconds(days(1)) } == [false, false, true, false, true])
        #expect(
            [intervals[0], intervals[1], intervals[3]] == [.seconds(hours(1)), .seconds(hours(4)), .seconds(hours(1))])
    }

    @Test("what each device had before they first synced joins on both, and nothing is lost")
    func theFirstSyncJoinsWhatEachDeviceHad() async throws {
        let ubuntu = try approve(
            card(.concept, front: "ubuntu", back: "Soy porque somos.", tags: ["filosofía"]), in: mac.engine)
        try mac.engine.setColor(.blue, of: "filosofía")
        try mac.engine.meet(ubuntu)
        try mac.engine.newCapture("petricor")
        time.advance(by: minutes(1))
        let serendipia = try approve(
            card(.word, front: "serendipia", back: "Un hallazgo por azar.", tags: ["filosofía"]), in: iPhone.engine)
        try iPhone.engine.setEmoji(Emoji("🦉"), of: "filosofía")
        try iPhone.engine.climb(serendipia, goods: 1, movingForward: time)
        try iPhone.engine.newCapture("saudade", note: "De una canción")

        try await mac.syncNow()
        try await iPhone.syncNow()
        try await mac.syncNow()

        #expect(try mac.cardsAsSeen().map(\.content?.front) == ["serendipia", "ubuntu"])
        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
        #expect(try mac.engine.inbox().captures.map(\.text).sorted() == ["petricor", "saudade"])
        #expect(try iPhone.engine.inbox().captures.map(\.text).sorted() == ["petricor", "saudade"])
        #expect(try mac.logAsSeen().count == 3)
        #expect(try iPhone.logAsSeen() == mac.logAsSeen())
        let filosofia = CardTag(name: "filosofía", switchedOn: nil, color: .blue, emoji: "🦉")
        #expect(try mac.engine.allTags() == [filosofia])
        #expect(try iPhone.engine.allTags() == [filosofia])
    }

    // Ficha kept no time for a tag's color before it recorded changes to
    // sync, so neither device has one for this color: the iPhone's tag never
    // had one, and the Mac's had it from before. The Mac held cards and never
    // synced, so the user turns sync on (#355).
    @Test("a first sync keeps a tag's color from before Ficha recorded its changes, against a tag that never had one")
    func aFirstSyncKeepsATagsColorFromBefore() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try saveDatabaseBeforeIDs(at: folder.appending(path: "Ficha.sqlite"), at: time.now)
        let macFromBefore = try Device(
            Engine(location: .folder(folder), time: time, calendar: calendar), syncingThrough: iCloud)
        try macFromBefore.turnSyncOn()
        time.advance(by: minutes(1))
        try iPhone.engine.create(card(.word, front: "palabra", back: "Lo que se dice.", tags: ["lenguaje"]))
        try iPhone.engine.setEmoji(Emoji("🗣️"), of: "lenguaje")

        try await iPhone.syncNow()
        try await macFromBefore.syncNow()
        try await iPhone.syncNow()

        let lenguaje = CardTag(name: "lenguaje", switchedOn: nil, color: .blue, emoji: "🗣️")
        #expect(try macFromBefore.engine.allTags().filter { $0.name == "lenguaje" } == [lenguaje])
        #expect(try iPhone.engine.allTags().filter { $0.name == "lenguaje" } == [lenguaje])
    }

    // The app hands iCloud's engine each change as the database changes, so
    // the first review waits there when ⌘Z takes it back.
    @Test("an answer taken back before it was sent stops waiting to be sent, and never reaches the other device")
    func anAnswerTakenBackBeforeItWasSentStopsWaiting() async throws {
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try mac.engine.meet(ubuntu)
        try mac.sync.sendWhatChanged(to: mac.iCloud)
        try mac.engine.takeBackAnswer(of: ubuntu.id, way: .frontFirst)

        try await mac.syncNow()
        try await iPhone.syncNow()

        #expect(mac.iCloud.pendingRecordZoneChanges.isEmpty)
        #expect(try iPhone.engine.cards().map(\.front) == ["ubuntu"])
        #expect(try iPhone.logAsSeen().isEmpty)
    }

    @Test("a record of a kind a newer Ficha saved waits, and what came with it is applied")
    func aRecordFromANewerFichaWaits() async throws {
        try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try await mac.syncNow()
        iCloud.saveFromANewerFicha(
            ICloudRecord(
                id: ICloudRecordID(name: "a-kind-to-come", zone: .cards), type: "AKindToCome", fields: [:],
                systemFields: nil))

        try await iPhone.syncNow()
        try await iPhone.syncNow()

        #expect(try iPhone.engine.cards().map(\.front) == ["ubuntu"])
    }

    @Test("what a device takes from another is never sent back")
    func whatComesFromAnotherDeviceIsNeverSentBack() async throws {
        let ubuntu = try approve(
            card(.concept, front: "ubuntu", back: "Soy porque somos.", tags: ["filosofía"]), in: mac.engine)
        try mac.engine.setColor(.blue, of: "filosofía")
        try mac.engine.meet(ubuntu)
        try mac.engine.expand(text: "ubuntu", note: "En zulú", source: nil)
        try await mac.syncNow()
        let savesFromTheMac = iCloud.saves

        try await iPhone.syncNow()
        try await iPhone.syncNow()

        #expect(iCloud.saves == savesFromTheMac)
        #expect(try iPhone.engine.changesToSend().isEmpty)
        #expect(try iPhone.cardsAsSeen() == mac.cardsAsSeen())
    }

    @Test("a device keeps working offline, and what changed meanwhile syncs once it's back online")
    func whatChangedOfflineSyncsLater() async throws {
        iPhone.iCloud.isOffline = true
        let ubuntu = try iPhone.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        await #expect(throws: FakeICloudError.self) { try await self.iPhone.syncNow() }
        time.advance(by: minutes(1))
        try iPhone.engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        try await mac.syncNow()
        #expect(try mac.engine.cards().isEmpty)

        iPhone.iCloud.isOffline = false
        try await iPhone.syncNow()
        try await mac.syncNow()

        #expect(try mac.cardsAsSeen().map(\.flag?.note) == ["Falta un ejemplo"])
        #expect(try mac.cardsAsSeen() == iPhone.cardsAsSeen())
    }

    @Test("a change that lost to a later one from another device isn't sent again")
    func aChangeThatLostIsntSentAgain() async throws {
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try await mac.syncNow()
        try await iPhone.syncNow()
        time.advance(by: minutes(1))
        try iPhone.engine.edit(
            iPhone.engine.card(fronted: "ubuntu").id, with: card(.concept, front: "ubuntu", back: "Somos."))
        time.advance(by: minutes(1))
        try mac.engine.edit(ubuntu.id, with: card(.concept, front: "ubuntu", back: "Yo soy porque somos."))
        try await mac.syncNow()
        let savesFromTheMac = iCloud.saves

        try await iPhone.syncNow()

        #expect(try iPhone.engine.card(fronted: "ubuntu").back == "Yo soy porque somos.")
        #expect(iCloud.saves == savesFromTheMac)
    }

    @Test("what the CLI writes, before the app syncs or while it does, reaches the other device once the app syncs")
    func whatTheCLIWritesSyncs() async throws {
        let cli = try Engine(location: .folder(folder), time: time, calendar: calendar)
        try approveCard("petricor", in: cli)
        let app = try Device(Engine(location: .folder(folder), time: time, calendar: calendar), syncingThrough: iCloud)
        try await app.syncNow()
        try cli.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try await app.syncNow()
        try await iPhone.syncNow()

        #expect(try iPhone.engine.cards().map(\.front).sorted() == ["petricor", "ubuntu"])
        #expect(try iPhone.cardsAsSeen() == app.cardsAsSeen())
        #expect(try iPhone.engine.inbox().captures.isEmpty)
    }

    @Test("a tag's color and emoji travel, and two tags made with the same name are one")
    func aTagTravelsAndTwoWithTheSameNameAreOne() async throws {
        try mac.engine.create(card(.question, front: "¿Waterloo?", back: "1815.", tags: ["historia"]))
        try mac.engine.setColor(.red, of: "historia")
        time.advance(by: minutes(1))
        try iPhone.engine.create(card(.question, front: "¿Caseros?", back: "1852.", tags: ["historia"]))
        try iPhone.engine.setEmoji(Emoji("🏛️"), of: "historia")

        try await mac.syncNow()
        try await iPhone.syncNow()
        try await mac.syncNow()

        let historia = CardTag(name: "historia", color: .red, emoji: "🏛️")
        for device in [mac, iPhone] {
            #expect(try device.engine.allTags() == [historia])
            #expect(try device.engine.cards().map(\.front).sorted() == ["¿Caseros?", "¿Waterloo?"])
        }
    }
}

/// A card as the user sees it on a device, without the ids each device gives
/// its own rows.
struct CardAsSeen: Equatable {
    let content: CardContent?
    let createdAt: Date
    let editedAt: Date?
    let flag: Flag?
    let buriedAt: Date?
    let setAsideBy: [String]?
    let bothWays: Bool
}

extension Card {
    /// The card as the user sees it.
    var asSeen: CardAsSeen {
        CardAsSeen(
            content: content(of: self), createdAt: createdAt, editedAt: editedAt, flag: flag, buriedAt: buriedAt,
            setAsideBy: setAsideBy, bothWays: bothWays)
    }
}

/// What waits in a device's inbox, as the user sees it: each capture's text,
/// and each expansion's and follow-up's with its card's front.
struct InboxAsSeen: Equatable {
    let captures: [String]
    let expansions: [String]
    let followUps: [String]
}

extension Inbox {
    /// What waits in it, as the user sees it.
    var asSeen: InboxAsSeen {
        InboxAsSeen(
            captures: captures.map(\.text), expansions: expansions.map { "\($0.capture.text) → \($0.card.front)" },
            followUps: followUps.map { "\($0.capture.text) → \($0.card.front)" })
    }
}

/// An entry of a device's review log, without the id its device gives its
/// card.
struct LogEntryAsSeen: Equatable {
    let uuid: UUID?
    let answeredEntry: UUID?
    let way: Way
    let kind: ReviewLogEntry.Kind
    let answeredAt: Date
    let responseTime: Duration?
    let trigger: Trigger?
    let isAhead: Bool
    let interval: Duration?
}

extension Device {
    /// Its cards as the user sees them, by their fronts, since each device
    /// numbers its cards as they come to it.
    func cardsAsSeen() throws -> [CardAsSeen] {
        try engine.cards().sorted { $0.front < $1.front }.map(\.asSeen)
    }

    /// Its review log, in the order the scheduler replays it.
    func logAsSeen() throws -> [LogEntryAsSeen] {
        try engine.reviewLog().sorted { $0.precedes($1) }.map {
            LogEntryAsSeen(
                uuid: $0.uuid, answeredEntry: $0.answeredEntry, way: $0.way, kind: $0.kind, answeredAt: $0.answeredAt,
                responseTime: $0.responseTime, trigger: $0.trigger, isAhead: $0.isAhead, interval: $0.interval)
        }
    }
}

extension Engine {
    /// The card with this front, which the test made the only one.
    func card(fronted front: String) throws -> Card {
        try #require(try cards().filter { $0.front == front }.only)
    }
}
