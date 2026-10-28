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

        #expect(tab.status == .off(.user, sending: nil))
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

        #expect(tab.status == .off(.user, sending: nil))

        let flag = try heavyImage(weighing: 1, named: "b", in: mac.engine)
        try mac.engine.create(card(nil, front: "¿De qué país es?", back: "De la Argentina.", frontImage: flag))
        tab.read()

        #expect(tab.status == .off(.user, sending: 100_000_000))
    }

    // What turning it on then does is the line's, by the reason: the view's.
    @Test("after a purge of Ficha's data in iCloud, the switch shows off, for that reason, and can be turned on")
    func afterAPurge() async throws {
        try mac.engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try await mac.syncNow()

        iCloud.purge()
        try await mac.syncNow()
        var tab = mac.engine.openSyncTab()

        #expect(tab.status == .off(.purge, sending: nil))
        #expect(!tab.switchIsOn)
        #expect(tab.canTurnSwitch)

        tab.turnSync(on: true)

        #expect(tab.status == .on(lastSynced: try mac.engine.syncStatus().lastSynced))
        #expect(tab.switchIsOn)
    }

    // The app asks iCloud at launch, which a database only the CLI opened
    // never heard: the switch shows as it was left, and the user can turn it.
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
/// would be, though it holds only zeros, which take no memory until read: what
/// goes up to iCloud is weighed, never read. Its name is `digit`, a
/// hexadecimal digit, 64 times, which tells it from the test's other images.
func heavyImage(weighing bytes: Int, named digit: Character, in engine: Engine) throws -> ImageName {
    let name = try #require(ImageName(rawValue: String(repeating: digit, count: 64) + ".jpg"))
    try engine.images.keep(Data(count: bytes), as: name)
    return name
}
