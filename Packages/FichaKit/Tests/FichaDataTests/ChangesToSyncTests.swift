import FichaCore
import Foundation
import Testing

// For what waits to be sent to iCloud, which only sync's rules read.
@testable import FichaData

/// Tests on what Ficha keeps track of to sync (ADR 0017): every row that
/// syncs has an ID unique across devices, and each write, the app's or the
/// CLI's, leaves its change waiting to be sent, with when each field last
/// changed, on an engine in memory on a Mac in Buenos Aires.
final class ChangesToSyncTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    /// A data folder of the test's own, for the app and the CLI to share.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaChangesToSyncTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 21, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    @Test(
        "a new card waits to be sent under an ID unique across devices, as do the capture it came from and its first view"
    )
    func aNewCardWaitsToBeSent() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let ubuntu = try engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        try engine.meet(ubuntu)

        let waiting = try engine.waiting()

        #expect(waiting.map(\.row.recordType) == [.capture, .card, .card, .reviewLogEntry])
        #expect(waiting.map(\.kind) == [.saved, .saved, .saved, .saved])
        #expect(waiting[1].row == (try engine.syncedRow(ofCard: serendipia.id)))
        #expect(waiting[2].row == (try engine.syncedRow(ofCard: ubuntu.id)))
        #expect(Set(waiting.map(\.row)).count == 4)
    }

    @Test(
        "editing a card records which of its parts changed and when, and an edit that changes nothing records nothing")
    func editingRecordsThePartsThatChanged() throws {
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let hornero = try engine.create(card(.word, front: "hornero", back: "Un pájaro."))
        let row = try engine.syncedRow(ofCard: hornero.id)
        let edited = time.now + hours(1)
        let editedAgain = edited + hours(1)

        time.move(to: edited)
        let afterEdit = try engine.recorded {
            try engine.edit(
                hornero.id,
                with: card(.word, front: "hornero", back: "Un pájaro que hace su nido de barro.", tags: ["aves"]))
        }
        time.move(to: editedAgain)
        let afterSecondEdit = try engine.recorded {
            try engine.edit(
                hornero.id,
                with: card(
                    .concept, front: "hornero", back: "Un pájaro que hace su nido de barro.", tags: ["aves"],
                    source: "Un libro de aves", frontImage: bird),
                bothWays: true)
        }
        let afterSameEdit = try engine.recorded {
            try engine.edit(
                hornero.id,
                with: card(
                    .concept, front: "hornero", back: "Un pájaro que hace su nido de barro.", tags: ["aves"],
                    source: "Un libro de aves", frontImage: bird),
                bothWays: true)
        }

        #expect(afterEdit == [Waiting(row: row, kind: .saved, fieldTimes: [.back: edited, .tags: edited])])
        #expect(
            afterSecondEdit == [
                Waiting(
                    row: row, kind: .saved,
                    fieldTimes: [
                        .back: edited, .tags: edited, .type: editedAgain, .source: editedAgain,
                        .frontImage: editedAgain, .bothWays: editedAgain,
                    ])
            ])
        #expect(afterSameEdit.isEmpty)
    }

    @Test("flagging, fixing, burying and unburying a card record when its flag and its burial changed")
    func flagsAndBurialsRecordTheirChanges() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        let row = try engine.syncedRow(ofCard: ubuntu.id)
        let flagged = time.now + minutes(1)
        let fixed = flagged + minutes(1)
        let buried = fixed + minutes(1)
        let unburied = buried + minutes(1)

        time.move(to: flagged)
        let afterFlag = try engine.recorded { try engine.flag(ubuntu.id, note: note("Falta un ejemplo")) }
        time.move(to: fixed)
        let afterFix = try engine.recorded {
            try engine.fix(ubuntu.id, with: card(.word, front: "ubuntu", back: "Soy porque somos. Por ejemplo…"))
        }
        time.move(to: buried)
        let afterBurial = try engine.recorded { try engine.bury(ubuntu.id) }
        time.move(to: unburied)
        let afterUnburial = try engine.recorded { try engine.unbury(ubuntu.id) }

        #expect(afterFlag == [Waiting(row: row, kind: .saved, fieldTimes: [.flag: flagged])])
        #expect(afterFix == [Waiting(row: row, kind: .saved, fieldTimes: [.flag: fixed, .back: fixed])])
        #expect(
            afterBurial == [Waiting(row: row, kind: .saved, fieldTimes: [.flag: fixed, .back: fixed, .burial: buried])])
        #expect(
            afterUnburial == [
                Waiting(row: row, kind: .saved, fieldTimes: [.flag: fixed, .back: fixed, .burial: unburied])
            ])
    }

    @Test("each first view and review waits to be sent, and an answer taken back waits as a deletion")
    func answersWaitToBeSent() throws {
        let petricor = try engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        let firstView = try #require(try engine.recorded { try engine.meet(petricor) }.only)
        let review = try #require(
            try engine.recorded { try engine.reviewWhenDue(petricor, .good, movingForward: time) }.only)

        let takenBack = try engine.recorded { try engine.takeBackAnswer(of: petricor.id, way: .frontFirst) }

        #expect(firstView.row.recordType == .reviewLogEntry)
        #expect(review.row.recordType == .reviewLogEntry)
        #expect(firstView.row != review.row)
        #expect([firstView.kind, review.kind] == [.saved, .saved])
        #expect(takenBack == [Waiting(row: review.row, kind: .deleted)])
    }

    @Test("a tag's color, emoji, priority and set aside each record when they changed, also once it has nothing left")
    func aTagRecordsWhenEachOfItsFieldsChanged() throws {
        try engine.create(card(.word, front: "Waterloo", back: "1815.", tags: ["historia"]))
        let colored = time.now + minutes(1)
        let prioritized = colored + minutes(1)
        let setAside = prioritized + minutes(1)
        let cleared = setAside + minutes(1)

        time.move(to: colored)
        let afterColor = try engine.recorded {
            try engine.setColor(.red, of: "historia")
            try engine.setEmoji(TagEmoji("🏛️"), of: "historia")
        }
        time.move(to: prioritized)
        let afterPriority = try engine.recorded { try engine.togglePriority(of: "historia") }
        time.move(to: setAside)
        let afterSettingAside = try engine.recorded { try engine.setAside("historia") }
        time.move(to: cleared)
        let afterClearing = try engine.recorded {
            try engine.setColor(nil, of: "historia")
            try engine.setEmoji(nil, of: "historia")
            try engine.stopSettingAside("historia")
        }

        #expect(
            afterColor == [
                Waiting(row: .tag("historia"), kind: .saved, fieldTimes: [.color: colored, .emoji: colored])
            ])
        #expect(
            afterPriority == [
                Waiting(
                    row: .tag("historia"), kind: .saved,
                    fieldTimes: [.color: colored, .emoji: colored, .switchedOn: prioritized])
            ])
        #expect(
            afterSettingAside == [
                Waiting(
                    row: .tag("historia"), kind: .saved,
                    fieldTimes: [.color: colored, .emoji: colored, .switchedOn: setAside])
            ])
        #expect(
            afterClearing == [
                Waiting(
                    row: .tag("historia"), kind: .saved,
                    fieldTimes: [.color: cleared, .emoji: cleared, .switchedOn: cleared])
            ])
        #expect(try engine.sidebarTags() == [CardTag(name: "historia")])
    }

    @Test("capturing, editing, discarding, expanding and approving record the captures' changes and the cards'")
    func capturesRecordTheirChanges() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let cardRow = try engine.syncedRow(ofCard: serendipia.id)
        let edited = time.now + minutes(1)
        let discarded = edited + minutes(1)
        let approved = discarded + minutes(1)

        let captured = try #require(try engine.recorded { try engine.newCapture("ojalá") }.only)
        time.move(to: edited)
        let capture = try #require(try engine.inbox().captures.first)
        let afterEdit = try engine.recorded {
            try engine.editCapture(capture.id, text: "ojalá", note: "Del árabe", source: "Un podcast")
        }
        time.move(to: discarded)
        let afterDiscard = try engine.recorded { try engine.discard(capture.id) }
        let expanded = try #require(
            try engine.recorded { try engine.expand(text: "Serendipia", note: nil, source: nil) }.only)
        time.move(to: approved)
        let expansion = try #require(try engine.inbox().expansions.first)
        let afterApproval = try engine.recorded {
            try engine.approveExpansion(
                expansion.capture.id,
                into: card(.word, front: "serendipia", back: "Un hallazgo valioso por casualidad."))
        }

        #expect(captured.row.recordType == .capture)
        #expect(captured.kind == .saved)
        #expect(
            afterEdit == [
                Waiting(row: captured.row, kind: .saved, fieldTimes: [.note: edited, .source: edited])
            ])
        #expect(
            afterDiscard == [
                Waiting(
                    row: captured.row, kind: .saved,
                    fieldTimes: [.note: edited, .source: edited, .refined: discarded])
            ])
        #expect(expanded.row.recordType == .capture)
        #expect(expanded.row != captured.row)
        #expect(
            afterApproval == [
                Waiting(row: expanded.row, kind: .saved, fieldTimes: [.refined: approved]),
                Waiting(row: cardRow, kind: .saved, fieldTimes: [.back: approved]),
            ])
    }

    @Test("a follow-up waits to be sent, and one taken back waits as a deletion")
    func followUpsRecordTheirChanges() throws {
        let ubuntu = try approveCard("ubuntu", in: engine)
        let followUp = try #require(
            try engine.recorded { try engine.followUp(ubuntu.id, text: "¿De qué lengua viene?") }.only)

        let takenBack = try engine.recorded {
            let capture = try #require(try engine.inbox().followUps.first?.capture)
            try engine.takeBackFollowUp(capture.id, of: ubuntu.id)
        }

        #expect(followUp.row.recordType == .capture)
        #expect(followUp.kind == .saved)
        #expect(takenBack == [Waiting(row: followUp.row, kind: .deleted)])
    }

    @Test("deleting a card waits as its deletion and its review log's, and its expansion lets go of it")
    func deletingWaitsAsDeletions() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        let cardRow = try engine.syncedRow(ofCard: serendipia.id)
        let firstView = try #require(try engine.recorded { try engine.meet(serendipia) }.only)
        let expansion = try #require(
            try engine.recorded { try engine.expand(text: "Serendipia", note: nil, source: nil) }.only)
        try engine.edit(serendipia.id, with: card(.word, front: "serendipia", back: "Un hallazgo."))
        let deleted = time.now + minutes(1)

        time.move(to: deleted)
        let afterDeletion = try engine.recorded { try engine.delete([serendipia.id]) }

        #expect(
            afterDeletion == [
                Waiting(row: firstView.row, kind: .deleted),
                Waiting(row: expansion.row, kind: .saved, fieldTimes: [.expandedCard: deleted]),
                Waiting(row: cardRow, kind: .deleted),
            ])
    }

    @Test("an import's cards wait to be sent")
    func importedCardsWaitToBeSent() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "vocabulario.txt")
        try Data("serendipia\tUn hallazgo por casualidad.\npetricor\tEl olor de la lluvia.\n".utf8).write(to: file)

        try engine.forget(engine.changesToSend())
        try await engine.importCards(engine.previewImport(of: file), choosing: ImportChoices())

        let cards = try engine.cards()
        #expect(
            try engine.waiting() == [
                Waiting(row: try engine.syncedRow(ofCard: cards[0].id), kind: .saved),
                Waiting(row: try engine.syncedRow(ofCard: cards[1].id), kind: .saved),
            ])
    }

    @Test("what the CLI writes waits to be sent for the app, which shares its database and syncs alone")
    func theCLIsWritesWaitForTheApp() async throws {
        let app = try Engine(location: .folder(folder), time: time, calendar: calendar)
        let cli = try Engine(location: .folder(folder), time: time, calendar: calendar)
        let sound = try await app.addSound(tone(seconds: 1, hertz: 440), named: "la.wav")
        let capture = try cli.newCapture("ojalá")
        let approved = time.now + minutes(1)
        let detached = approved + minutes(1)

        time.move(to: approved)
        let ojala = try #require(
            try await cli.approve(
                capture.id,
                into: [draft(.word, front: "ojalá", back: "Que Dios quiera.", frontSound: .put(.sound(sound)))]
            ).first)
        time.move(to: detached)
        try cli.detach(.sound, from: .front, of: ojala.id)

        let waiting = try app.waiting()
        #expect(waiting.map(\.row.recordType) == [.capture, .card])
        #expect(waiting.map(\.kind) == [.saved, .saved])
        #expect(waiting.first?.fieldTimes == [.refined: approved])
        #expect(waiting.last?.row == (try app.syncedRow(ofCard: ojala.id)))
        #expect(waiting.last?.fieldTimes == [.frontSound: detached])
    }

    // What comes from iCloud is applied this way (#312), and must never be
    // sent back.
    @Test("a change applied without recording leaves nothing to send, and a row it deletes no longer waits")
    func changesAppliedWithoutRecordingLeaveNothingToSend() throws {
        let ubuntu = try engine.create(card(.word, front: "ubuntu", back: "Soy porque somos."))
        try engine.forget(engine.changesToSend())
        try engine.flag(ubuntu.id, note: note("Falta un ejemplo"))
        let now = time.now

        try engine.writeWithoutRecording { db in
            let petricor = try insertCard(
                card(.word, front: "petricor", back: "El olor de la lluvia."), capturedAs: nil, at: now, in: db)
            _ = try replaceContent(
                of: petricor, with: card(.word, front: "petricor", back: "El olor de la tierra mojada."), at: now,
                in: db)
            try save(CardTag(name: "lenguaje", color: .blue), in: db)
            _ = try deleteCard(ubuntu.id, in: db)
        }

        #expect(try engine.changesToSend().isEmpty)
        #expect(try engine.cards().map(\.front) == ["petricor"])
        try engine.setEmoji(TagEmoji("🗣️"), of: "lenguaje")
        #expect(try engine.waiting() == [Waiting(row: .tag("lenguaje"), kind: .saved, fieldTimes: [.emoji: now])])
    }

    @Test(
        "with sync off, nothing waits to be sent, and turning it on leaves everything waiting, with when each field changed"
    )
    func turningSyncOnSendsEverything() throws {
        let serendipia = try approveCard("serendipia", in: engine)
        try engine.setColor(.green, of: "lenguaje")
        try engine.setColor(nil, of: "lenguaje")

        try engine.turnSyncOff()
        let offAtFirst = try engine.waiting()
        let flagged = time.now + minutes(1)
        time.move(to: flagged)
        try engine.flag(serendipia.id, note: note("Falta un ejemplo"))
        try engine.meet(try engine.create(card(.word, front: "petricor", back: "El olor de la lluvia.")))
        let whileOff = try engine.waiting()
        try engine.turnSyncOn()

        #expect(offAtFirst.isEmpty)
        #expect(whileOff.isEmpty)
        #expect(try engine.syncIsOn())
        let waiting = try engine.waiting()
        #expect(waiting.map(\.row.recordType) == [.card, .card, .capture, .reviewLogEntry, .tag])
        #expect(waiting.allSatisfy { $0.kind == .saved })
        #expect(
            waiting.first
                == Waiting(row: try engine.syncedRow(ofCard: serendipia.id), kind: .saved, fieldTimes: [.flag: flagged])
        )
        #expect(waiting.last?.row == .tag("lenguaje"))
    }

    @Test("sync is on until the user turns it off")
    func syncIsOnByDefault() throws {
        #expect(try engine.syncIsOn())

        try engine.turnSyncOff()

        #expect(try !engine.syncIsOn())
    }

    @Test("a change that was sent no longer waits, but the row's change made while it was sent does")
    func aChangeSentIsForgottenButALaterOneWaits() throws {
        let ubuntu = try engine.create(card(.word, front: "ubuntu", back: "Soy porque somos."))
        let sent = try engine.changesToSend()
        let buried = time.now + minutes(1)

        time.move(to: buried)
        try engine.bury(ubuntu.id)
        try engine.forget(sent)

        #expect(
            try engine.waiting() == [
                Waiting(row: try engine.syncedRow(ofCard: ubuntu.id), kind: .saved, fieldTimes: [.burial: buried])
            ])
        try engine.forget(engine.changesToSend())
        #expect(try engine.changesToSend().isEmpty)
    }

    @Test("the state iCloud's sync engine saved stays on the device, across launches, until it's forgotten")
    func theSyncEngineStateStays() throws {
        let app = try Engine(location: .folder(folder), time: time, calendar: calendar)
        let state = Data("an engine's state".utf8)
        #expect(try app.savedSyncEngineState() == nil)

        try app.saveSyncEngineState(state)
        let relaunched = try Engine(location: .folder(folder), time: time, calendar: calendar)
        let kept = try relaunched.savedSyncEngineState()
        try relaunched.saveSyncEngineState(nil)

        #expect(kept == state)
        #expect(try relaunched.savedSyncEngineState() == nil)
    }
}

/// A change waiting to be sent, without its place in the order, which a
/// test can't know.
struct Waiting: Equatable {
    let row: SyncedRow
    let kind: ChangeToSend.Kind
    var fieldTimes: [SyncedField: Date] = [:]
}

extension Engine {
    /// What waits to be sent, oldest first.
    func waiting() throws -> [Waiting] {
        try changesToSend().map { Waiting(row: $0.row, kind: $0.kind, fieldTimes: $0.fieldTimes) }
    }

    /// What `work` leaves waiting to be sent, once what waited before is
    /// forgotten, as sent.
    func recorded(by work: () throws -> Void) throws -> [Waiting] {
        try forget(changesToSend())
        try work()
        return try waiting()
    }
}

extension Array {
    /// Its only element, or nil when it has none or more than one.
    var only: Element? {
        count == 1 ? first : nil
    }
}
