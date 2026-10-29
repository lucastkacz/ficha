import FichaCore
import Foundation
import Testing

// For the interface to iCloud's engine, which the fake implements.
@testable import FichaData

/// Tests on Settings' Sync tab and the menu's line while iCloud is full (ADR
/// 0017, #317): what the switch shows and the status line says, as a Mac in
/// Buenos Aires syncs through a fake iCloud, signed into it, beside an
/// iPhone.
final class SyncTabTests {
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

    @Test("the status line says when the device last synced, or that it hasn't yet, under the switch on")
    func theLineSaysWhenTheDeviceLastSynced() async throws {
        #expect(mac.engine.openSyncTab().status == .on(lastSynced: nil))

        let synced = time.now
        try await mac.syncNow()
        time.advance(by: minutes(5))
        let tab = mac.engine.openSyncTab()

        #expect(tab.status == .on(lastSynced: synced))
        #expect(tab.switchIsOn)
        #expect(tab.canTurnSwitch)
        #expect(!tab.saysICloudIsFull)
    }

    // On by default when the Mac has an iCloud account: without one, nothing
    // syncs, whatever the switch was left at, which it shows again once the
    // device is signed in.
    @Test("with no iCloud account the line says so, and the switch shows off and can't be turned until signed in")
    func noICloudAccount() throws {
        try mac.signOut()
        var tab = mac.engine.openSyncTab()

        #expect(tab.status == .noAccount)
        #expect(!tab.switchIsOn)
        #expect(!tab.canTurnSwitch)

        tab.turnSync(on: false)
        try mac.signIn(to: iCloud)
        tab.read()

        #expect(tab.status == .on(lastSynced: nil))
        #expect(tab.switchIsOn)
    }

    @Test("while iCloud is full the line and the menu say so, until there's room")
    func aFullICloud() async throws {
        try await mac.syncNow()
        iCloud.fillUp()

        try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try await mac.syncNow()
        var tab = mac.engine.openSyncTab()

        #expect(tab.status == .iCloudFull)
        #expect(tab.saysICloudIsFull)
        #expect(tab.switchIsOn)

        iCloud.makeRoom()
        let synced = time.now
        try await mac.syncNow()
        tab.read()

        #expect(tab.status == .on(lastSynced: synced))
        #expect(!tab.saysICloudIsFull)
    }

    @Test("turning the switch off stops sync, with nothing heavy to send, and turning it on syncs again")
    func turningTheSwitch() async throws {
        try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try await mac.syncNow()
        var tab = mac.engine.openSyncTab()

        tab.turnSync(on: false)
        try mac.engine.create(card(.word, front: "saudade", back: "Nostalgia de lo que se fue."))
        try await mac.syncNow()
        try await iPhone.syncNow()

        #expect(tab.status == .off(turningOn: nil, sending: nil))
        #expect(!tab.switchIsOn)
        #expect(tab.canTurnSwitch)
        #expect(try iPhone.engine.cards().map(\.front) == ["ubuntu"])

        tab.turnSync(on: true)
        try mac.relaunch()
        try await mac.syncNow()
        try await iPhone.syncNow()

        #expect(tab.switchIsOn)
        #expect(try iPhone.engine.cards().map(\.front).sorted() == ["saudade", "ubuntu"])
    }

    // The bird's image went up while sync was on, so iCloud holds it, and it
    // doesn't count: one byte less than 100 MB to send says nothing.
    @Test("while sync is off, the line says what turning it on sends from 100 MB, counting only what iCloud lacks")
    func theOffLineSaysWhatTurningItOnSends() async throws {
        let bird = try mac.engine.addImage(picture(width: 800, height: 600, red: 0.8))
        try mac.engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        try await mac.syncNow()
        var tab = mac.engine.openSyncTab()
        tab.turnSync(on: false)

        let map = try heavyImage(weighing: 99_999_999, named: "a", in: mac.engine)
        try mac.engine.create(card(nil, front: "¿Qué país es?", back: "La Argentina.", frontImage: map))
        tab.read()

        #expect(tab.status == .off(turningOn: nil, sending: nil))

        let flag = try heavyImage(weighing: 1, named: "b", in: mac.engine)
        try mac.engine.create(card(nil, front: "¿De qué país es?", back: "De la Argentina.", frontImage: flag))
        tab.read()

        #expect(tab.status == .off(turningOn: nil, sending: 100_000_000))
    }

    // Turned off by the user, the switch says all there is: turning it on
    // syncs again. After a purge, it sends the cards that sync again, which
    // the line says; and the sync from before the purge, of what iCloud no
    // longer holds, isn't one, so the line says none until the Mac syncs
    // again.
    @Test(
        "after a purge, the line says turning sync on sends the cards again, every one or those with chosen tags, and then no sync from before it"
    )
    func afterAPurge() async throws {
        try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try await mac.syncNow()

        iCloud.purge()
        time.advance(by: minutes(5))
        try await mac.syncNow()
        var tab = mac.engine.openSyncTab()

        #expect(tab.status == .off(turningOn: .sendsCardsAgain(onlyChosenTags: false), sending: nil))
        #expect(!tab.switchIsOn)
        #expect(tab.canTurnSwitch)

        tab.syncOnlyChosenTags(true)

        #expect(tab.status == .off(turningOn: .sendsCardsAgain(onlyChosenTags: true), sending: nil))

        tab.syncOnlyChosenTags(false)
        tab.turnSync(on: true)

        #expect(tab.status == .on(lastSynced: nil))
        #expect(tab.switchIsOn)

        try mac.relaunch()
        time.advance(by: minutes(5))
        let synced = time.now
        try await mac.syncNow()
        tab.read()

        #expect(tab.status == .on(lastSynced: synced))
    }

    // The map and the flag went up to iCloud, so turning sync off says
    // nothing of them. The purge takes them from iCloud: turning sync on
    // sends them again, and the line says so.
    @Test("after a purge, the off line counts every file the cards use, those iCloud held before it too")
    func afterAPurgeEveryFileCounts() async throws {
        let map = try heavyImage(weighing: 60_000_000, named: "a", in: mac.engine)
        let flag = try heavyImage(weighing: 40_000_000, named: "b", in: mac.engine)
        try mac.engine.create(card(nil, front: "¿Qué país es?", back: "La Argentina.", frontImage: map))
        try mac.engine.create(card(nil, front: "¿De qué país es?", back: "De la Argentina.", frontImage: flag))
        try await mac.syncNow()
        var tab = mac.engine.openSyncTab()
        tab.turnSync(on: false)

        #expect(tab.status == .off(turningOn: nil, sending: nil))

        tab.turnSync(on: true)
        try mac.relaunch()
        iCloud.purge()
        try await mac.syncNow()
        tab.read()

        #expect(tab.status == .off(turningOn: .sendsCardsAgain(onlyChosenTags: false), sending: 100_000_000))
    }

    // The app asks iCloud at launch, which a database only the CLI opened
    // never heard: the switch shows as it was left, and the user can turn it.
    // The map is on two of geografía's cards, and counts once; lenguaje's
    // card has no file; historia is chosen while no card carries it.
    @Test(
        "while only the cards with chosen tags sync, the tab lists every tag, a new one not chosen, with what its cards' files weigh, and none while every card syncs"
    )
    func theTabListsTheTagsToChoose() throws {
        let map = try heavyImage(weighing: 1_500_000, named: "a", in: mac.engine)
        try mac.engine.create(
            card(nil, front: "¿Qué país es?", back: "La Argentina.", tags: ["geografía"], frontImage: map))
        try mac.engine.create(
            card(
                nil, front: "¿De qué país es?", back: "De la Argentina.", tags: ["geografía", "mapas"], frontImage: map)
        )
        try mac.engine.create(card(.word, front: "petricor", back: "El olor de la lluvia.", tags: ["lenguaje"]))
        var tab = mac.engine.openSyncTab()

        #expect(!tab.onlyChosenTags)
        #expect(tab.tags.isEmpty)
        #expect(tab.canChoose)

        tab.syncOnlyChosenTags(true)
        tab.choose("historia", true)

        #expect(tab.onlyChosenTags)
        #expect(
            tab.tags == [
                TagToChoose(name: "geografía", isChosen: false, weight: 1_500_000),
                TagToChoose(name: "historia", isChosen: true, weight: nil),
                TagToChoose(name: "lenguaje", isChosen: false, weight: nil),
                TagToChoose(name: "mapas", isChosen: false, weight: 1_500_000),
            ])
        #expect(tab.failure == nil)
    }

    // The map is on Argentina's card and on banderas', and counts once in
    // geografía. Argentina is ticked, then América, which it sits inside, so
    // unticking Argentina changes nothing while América is, nor does Chile,
    // never ticked, which syncs with América. historia::Roma is chosen while
    // no card carries it, and historia isn't listed.
    @Test(
        "the tab lists the tags as a tree, a tag inside a chosen one as syncing, which can't be unticked, a parent's weight counting the tags inside it, and a tag whose parent isn't listed by its whole name"
    )
    func theTabListsTheTagsAsATree() throws {
        let map = try heavyImage(weighing: 1_500_000, named: "a", in: mac.engine)
        let flag = try heavyImage(weighing: 500_000, named: "b", in: mac.engine)
        try mac.engine.create(
            card(
                nil, front: "¿Qué país es?", back: "La Argentina.", tags: ["geografía::América::Argentina"],
                frontImage: map))
        try mac.engine.create(
            card(nil, front: "¿Cuál es su capital?", back: "Santiago.", tags: ["geografía::América::Chile"]))
        try mac.engine.create(
            card(
                nil, front: "¿De qué país es?", back: "De la Argentina.", tags: ["geografía::banderas"],
                frontImage: flag, backImage: map))
        var tab = mac.engine.openSyncTab()
        tab.syncOnlyChosenTags(true)

        tab.choose("geografía::América::Argentina", true)
        tab.choose("geografía::América", true)
        tab.choose("historia::Roma", true)
        tab.choose("geografía::América::Argentina", false)
        tab.choose("geografía::América::Chile", false)

        #expect(
            tab.tagRows.map(\.title) == ["geografía", "América", "Argentina", "Chile", "banderas", "historia › Roma"])
        #expect(tab.tagRows.map(\.level) == [0, 1, 2, 2, 1, 0])
        #expect(tab.tagRows.map(\.tag.isTicked) == [false, true, true, true, false, true])
        #expect(tab.tagRows.map(\.tag.canChoose) == [true, true, false, false, true, true])
        #expect(tab.tagRows.map(\.tag.isChosen) == [false, true, true, false, false, true])
        #expect(tab.tagRows.map(\.tag.weight) == [2_000_000, 1_500_000, 1_500_000, nil, 2_000_000, nil])
        #expect(tab.failure == nil)
    }

    @Test("while sync is off, the line counts only the files of the cards that sync")
    func theOffLineCountsOnlyTheCardsThatSync() throws {
        var tab = mac.engine.openSyncTab()
        tab.turnSync(on: false)
        let map = try heavyImage(weighing: 100_000_000, named: "a", in: mac.engine)
        try mac.engine.create(
            card(nil, front: "¿Qué país es?", back: "La Argentina.", tags: ["geografía"], frontImage: map))
        tab.syncOnlyChosenTags(true)

        #expect(tab.status == .off(turningOn: nil, sending: nil))

        tab.choose("geografía", true)

        #expect(tab.status == .off(turningOn: nil, sending: 100_000_000))
    }

    // As Lucas's Mac migrates: it held cards, and never synced (#355).
    @Test(
        "on a Mac that held cards before it ever synced, the off line says turning sync on sends its cards, every one or those with chosen tags"
    )
    func theFirstSyncLine() throws {
        let folder = URL.temporaryDirectory.appending(
            path: "FichaSyncTabTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try saveDatabaseBeforeSelectiveSync(
            at: folder.appending(path: "Ficha.sqlite"), holdsCards: true, synced: false, at: time.now)
        let macFromBefore = try Device(
            Engine(location: .folder(folder), time: time, calendar: calendar), syncingThrough: iCloud)
        var tab = macFromBefore.engine.openSyncTab()

        #expect(tab.status == .off(turningOn: .sendsCardsForTheFirstTime(onlyChosenTags: false), sending: nil))
        #expect(!tab.switchIsOn)

        tab.syncOnlyChosenTags(true)

        #expect(tab.status == .off(turningOn: .sendsCardsForTheFirstTime(onlyChosenTags: true), sending: nil))

        tab.turnSync(on: true)

        #expect(tab.status == .on(lastSynced: nil))
    }

    @Test("until the app knows whether the Mac has an iCloud account, the line says it's checking")
    func checkingTheAccount() throws {
        let opened = try Engine(location: .inMemory, time: time, calendar: calendar)
        var tab = opened.openSyncTab()

        #expect(tab.status == .checkingAccount)
        #expect(tab.switchIsOn)

        tab.turnSync(on: false)

        #expect(tab.status == .checkingAccount)
        #expect(!tab.switchIsOn)
        #expect(try opened.syncStatus().offBecause == .user)
    }
}

/// An image of `bytes` bytes that `engine` keeps, as an image Ficha shrank
/// would be, though it holds only zeros, which take no memory until read,
/// named as `imageName(of:)` names it.
func heavyImage(weighing bytes: Int, named digit: Character, in engine: Engine) throws -> ImageName {
    let name = try imageName(of: digit)
    try engine.images.keep(Data(count: bytes), as: name)
    return name
}
