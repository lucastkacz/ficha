import FichaCore
import Foundation
import Testing

// For the interface to iCloud's engine, which the fake implements, and for
// what waits to be sent.
@testable import FichaData

/// Tests on card types of the user's own across devices (#365): made,
/// renamed and deleted reaching the other device, a deletion winning
/// (ADR 0017), selective sync (ADR 0020) leaving them alone, and a restore,
/// on two devices, a Mac and an iPhone, in Buenos Aires on one clock, signed
/// into one account of a fake iCloud. The Mac keeps its cards in a data
/// folder, with its backups, as the app does.
final class UserTypesSyncTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let iCloud = FakeICloud()
    /// The Mac's data folder.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaUserTypesSyncTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    let mac: Device
    let iPhone: Device

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 21, in: calendar))
        mac = try Device(Engine(location: .folder(folder), time: time, calendar: calendar), syncingThrough: iCloud)
        iPhone = try Device(Engine(location: .inMemory, time: time, calendar: calendar), syncingThrough: iCloud)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("a type made, renamed, given an emoji and deleted on one device is so on the other, with its cards")
    func aTypeReachesTheOtherDevice() async throws {
        let formula = try mac.engine.makeUserType(named: "Fórmula")
        try mac.engine.create(card(.user(formula), front: "agua", back: "H₂O"))
        try await syncBoth()

        #expect(try iPhone.engine.userTypes() == [formula])
        #expect(try iPhone.engine.cards().map(\.type) == [.user(formula)])

        time.advance(by: minutes(1))
        let renamed = try mac.engine.renameUserType(formula.id, to: "Fórmula química")
        try iPhone.engine.setEmoji(TagEmoji("🧪"), ofUserType: formula.id)
        try await syncBoth()

        let both = UserType(id: formula.id, name: renamed.name, emoji: "🧪")
        for device in [mac, iPhone] {
            #expect(try device.engine.userTypes() == [both])
            #expect(try device.engine.cards().map(\.type) == [.user(both)])
        }

        time.advance(by: minutes(1))
        try iPhone.engine.deleteUserType(formula.id)
        try await syncBoth()

        for device in [mac, iPhone] {
            #expect(try device.engine.userTypes().isEmpty)
            #expect(try device.engine.cards().map(\.type) == [nil])
            #expect(try device.engine.cards().map(\.back) == ["H₂O"])
            #expect(try device.engine.changesToSend().isEmpty)
        }
    }

    // The iPhone, offline, gives sal the type and renames it after the Mac
    // deleted it; the Mac sends first.
    @Test("a deletion wins over a card given the type, and a rename, made offline on the other device")
    func aDeletionWinsOverACardGivenTheTypeOffline() async throws {
        let formula = try mac.engine.makeUserType(named: "Fórmula")
        try mac.engine.create(card(.user(formula), front: "agua", back: "H₂O"))
        try mac.engine.create(card(nil, front: "sal", back: "NaCl"))
        try await syncBoth()

        iPhone.iCloud.isOffline = true
        time.advance(by: minutes(1))
        try mac.engine.deleteUserType(formula.id)
        time.advance(by: minutes(1))
        try iPhone.engine.edit(
            iPhone.engine.card(fronted: "sal").id, with: card(.user(formula), front: "sal", back: "NaCl"))
        try iPhone.engine.renameUserType(formula.id, to: "Fórmula química")
        try await mac.syncNow()
        iPhone.iCloud.isOffline = false
        try await syncBoth()

        for device in [mac, iPhone] {
            #expect(try device.engine.userTypes().isEmpty)
            #expect(try device.engine.cards().map(\.type) == [nil, nil])
        }
        #expect(!iCloud.records.contains { $0.type == SyncedRow.RecordType.userType.rawValue })
    }

    @Test("while only chosen tags sync, every type syncs, also one whose cards stay on the device")
    func typesSyncWhileOnlyChosenTagsDo() async throws {
        try mac.engine.syncOnlyChosenTags(true)
        try mac.engine.chooseToSync("química", true)
        let formula = try mac.engine.makeUserType(named: "Fórmula", emoji: TagEmoji("🧪"))
        let law = try mac.engine.makeUserType(named: "Ley")
        let word = try mac.engine.makeUserType(named: "Palabra nueva")
        try mac.engine.create(card(.user(formula), front: "agua", back: "H₂O", tags: ["química"]))
        try mac.engine.create(card(.user(law), front: "gravedad", back: "Todo cae.", tags: ["física"]))
        try await syncBoth()

        #expect(try iPhone.engine.userTypes() == [formula, law, word])
        #expect(try iPhone.engine.cards().map(\.front) == ["agua"])
        #expect(try mac.engine.changesToSend().isEmpty)
    }

    // The Mac held its cards before it ever synced, and goes offline after
    // its first batch, as iCloud's engine sends in batches; the iPhone
    // fetches then, and edits the card it got before the rest comes.
    @Test("a first sync sends the types before the cards, so a card the other device edits early keeps its type")
    func aFirstSyncSendsTheTypesFirst() async throws {
        try mac.turnSyncOff()
        let formula = try mac.engine.makeUserType(named: "Fórmula")
        try mac.engine.create(card(.user(formula), front: "agua", back: "H₂O"))
        try mac.engine.create(card(.user(formula), front: "sal", back: "NaCl"))
        try mac.turnSyncOn()
        let macsICloud = mac.iCloud
        macsICloud.recordsPerBatch = 2
        macsICloud.onceSaved { macsICloud.isOffline = true }
        await #expect(throws: FakeICloudError.offline) { try await self.mac.syncNow() }
        try await iPhone.syncNow()
        time.advance(by: minutes(1))
        for early in try iPhone.engine.cards() {
            try iPhone.engine.edit(
                early.id, with: card(early.type, front: early.front, back: "\(early.back), en una fórmula"))
        }
        macsICloud.isOffline = false
        try await syncBoth()

        for device in [mac, iPhone] {
            #expect(try device.engine.cards().map(\.type) == [.user(formula), .user(formula)])
            #expect(try device.engine.card(fronted: "agua").back == "H₂O, en una fórmula")
        }
    }

    // Ley, made after the backup, goes; Fórmula takes back its name.
    @Test("a restore brings back the types of its copy on both devices, and drops those made since")
    func aRestoreBringsBackTheTypesOfItsCopy() async throws {
        let formula = try mac.engine.makeUserType(named: "Fórmula")
        try mac.engine.create(card(.user(formula), front: "agua", back: "H₂O"))
        try await syncBoth()
        let backup = try mac.engine.backUpNow(.defaults)
        time.advance(by: minutes(1))
        try mac.engine.renameUserType(formula.id, to: "Fórmula química")
        let law = try mac.engine.makeUserType(named: "Ley")
        try mac.engine.create(card(.user(law), front: "gravedad", back: "Todo cae."))
        try await syncBoth()

        try mac.engine.restore(backup.name)
        try mac.turnSyncOn()
        try await syncBoth()

        for device in [mac, iPhone] {
            #expect(try device.engine.userTypes() == [formula])
            #expect(try device.engine.cards().map(\.type) == [.user(formula)])
        }
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
