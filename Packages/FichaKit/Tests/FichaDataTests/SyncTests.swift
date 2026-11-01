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
        mac = try Device(Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: iCloud)
        iPhone = try Device(Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: iCloud)
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

    @Test("a side edited on another device restarts a card's count of “Don't know” answers, as an edit here does")
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
    // clock's does: both devices must still order the joined log alike.
    @Test("reviews made offline on both devices join, and two answers to one wait climb one step on both")
    func reviewsMadeOfflineJoin() async throws {
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        time.advance(by: 0.123_456_7)
        try mac.engine.meet(ubuntu)
        try await mac.syncNow()
        try await iPhone.syncNow()
        let ubuntuOnIPhone = try iPhone.engine.card(fronted: "ubuntu")
        let ladder = ReviewSettings.defaults.ladder

        mac.iCloud.isOffline = true
        iPhone.iCloud.isOffline = true
        time.move(to: try #require(try mac.engine.standing(of: ubuntu.id, on: ladder).due) + 0.234_567_8)
        try mac.engine.review(ubuntu, .good)
        time.advance(by: minutes(30) + 0.000_432_1)
        try iPhone.engine.review(ubuntuOnIPhone, .good)
        await #expect(throws: FakeICloudError.self) { try await self.mac.syncNow() }
        mac.iCloud.isOffline = false
        iPhone.iCloud.isOffline = false
        try await mac.syncNow()
        try await iPhone.syncNow()
        try await mac.syncNow()

        let onMac = try mac.engine.standing(of: ubuntu.id, on: ladder)
        let macsGood = try #require(try mac.logAsSeen().first { $0.kind == .review(.good) })
        #expect(onMac == .onLadder(step: 1, due: macsGood.answeredAt + hours(4)))
        #expect(try iPhone.engine.standing(of: ubuntuOnIPhone.id, on: ladder) == onMac)
        #expect(try mac.logAsSeen().map(\.kind) == [.firstView, .review(.good), .review(.good)])
        #expect(try iPhone.logAsSeen() == mac.logAsSeen())
    }

    // Until #407, the ladder spaces cards, so a review keeps the wait of the
    // step it leaves the card on: good climbs to the second step's 4 hours,
    // hard stays there, and again goes back to the first step's hour.
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
            try mac.logAsSeen().map(\.interval) == [nil, .seconds(hours(4)), .seconds(hours(4)), .seconds(hours(1))])
        #expect(try iPhone.logAsSeen() == mac.logAsSeen())
    }

    @Test("a review rated easy is kept as easy, and reaches the other device as easy")
    func easyIsKeptAndReachesTheOtherDevice() async throws {
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try mac.engine.meet(ubuntu)
        try mac.engine.reviewWhenDue(ubuntu, .easy, movingForward: time)

        try await mac.syncNow()
        try await iPhone.syncNow()

        #expect(try mac.logAsSeen().map(\.kind) == [.firstView, .review(.easy)])
        #expect(try iPhone.logAsSeen() == mac.logAsSeen())
    }

    @Test("⌘Z takes back the answer given on this device, never one that came from another device since")
    func takingBackAnAnswerLeavesAnotherDevicesAlone() async throws {
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try mac.engine.meet(ubuntu)
        try await mac.syncNow()
        try await iPhone.syncNow()
        time.move(to: try #require(try mac.engine.standing(of: ubuntu.id, on: ReviewSettings.defaults.ladder).due))
        try mac.engine.review(ubuntu, .again)
        time.advance(by: minutes(1))
        try iPhone.engine.review(iPhone.engine.card(fronted: "ubuntu"), .good)
        try await iPhone.syncNow()
        try await mac.syncNow()

        try mac.engine.takeBackAnswer(of: ubuntu.id, way: .frontFirst)

        #expect(try mac.logAsSeen().map(\.kind) == [.firstView, .review(.good)])
    }

    // The iPhone gets the Mac's three entries in one go, in iCloud's order,
    // and then the Mac's again after its own good, which came later.
    @Test("the Cards window lists a review log joined from two devices in the order it happened, each with its step")
    func theCardsWindowListsAJoinedLogInOrder() async throws {
        let ubuntu = try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try mac.engine.climb(ubuntu, to: 2, movingForward: time)
        try await mac.syncNow()
        try await iPhone.syncNow()
        let ubuntuOnIPhone = try iPhone.engine.card(fronted: "ubuntu")
        let ladder = ReviewSettings.defaults.ladder

        time.move(to: try #require(try mac.engine.standing(of: ubuntu.id, on: ladder).due))
        try mac.engine.review(ubuntu, .again)
        time.advance(by: minutes(10))
        try iPhone.engine.review(ubuntuOnIPhone, .good)
        try await iPhone.syncNow()
        try await mac.syncNow()
        try await iPhone.syncNow()

        for (device, cardID) in [(mac, ubuntu.id), (iPhone, ubuntuOnIPhone.id)] {
            let rows = try device.engine.reviewLogRows(of: cardID, on: ladder)
            #expect(
                rows.map(\.entry.kind) == [.firstView, .review(.good), .review(.good), .review(.again), .review(.good)])
            #expect(rows.map(\.step) == [0, 1, 2, 0, 1])
        }
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
        try iPhone.engine.climb(serendipia, to: 1, movingForward: time)
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
    // the first view waits there when ⌘Z takes it back.
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

    /// Its review log, in the order the ladder replays it.
    func logAsSeen() throws -> [LogEntryAsSeen] {
        try engine.reviewLog().sorted { $0.isReplayed(before: $1) }.map {
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
