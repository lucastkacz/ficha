import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on sounds in the Cards window: the card form and the card editor
/// put a sound file on a side, converted away from the window, replace it or
/// remove it, the detail shows a card's sounds, the table which sides have
/// an image or a sound and what a front without text holds, and one sound
/// plays at a time, on the default ladder.
final class CardsWindowSoundTests {
    let time = ManualTimeSource(now: Date(timeIntervalSince1970: 1_760_000_000))
    let engine: Engine
    let ladder = ReviewSettings.defaults.ladder
    /// A folder of the test's own, for the files dropped on a side.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaCardsWindowSoundTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    init() throws {
        engine = try Engine(location: .inMemory, time: time)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Opens the Cards window and reads the cards, as the window does once
    /// it listens for the reasons to read them again.
    private func openWindow() -> CardsWindowState {
        var window = engine.openCardsWindow(on: ladder)
        window.read(on: ladder)
        return window
    }

    /// A file named `name` in the test's folder holding `data`, as Finder
    /// drags it.
    private func file(_ name: String, holding data: Data) throws -> URL {
        let file = folder.appending(path: name)
        try data.write(to: file)
        return file
    }

    @Test("a sound file on a side comes in once converted, with its length, and a side with only a sound turns Add on")
    func aSoundFileComesInWithItsLength() async throws {
        var window = openWindow()
        window.openNewCardForm()
        window.typeInForm(back: "La.")
        let la = try file("la.wav", holding: tone(seconds: 2, hertz: 440))

        let putting = window.putSoundInForm(la, on: .front)
        let work = try #require(putting)
        let converting = try #require(window.cardForm)
        window.finishSoundWork(await work.run())
        let withSound = try #require(window.cardForm)
        let sound = try #require(withSound.draft.front.sound)
        let length = try #require(try window.sounds[sound]?.get().length)
        window.removeSoundFromForm(on: .front)
        let withoutSound = try #require(window.cardForm)

        #expect(converting.isSoundComingIn(on: .front))
        #expect(!converting.isSoundComingIn(on: .back))
        #expect(!converting.canAdd)
        #expect(!withSound.isSoundComingIn(on: .front))
        #expect(withSound.canAdd)
        #expect(length > .milliseconds(1_950) && length < .milliseconds(2_050))
        #expect(!withoutSound.canAdd)
        #expect(withoutSound.draft.front.sound == nil)
    }

    @Test("Add saves the sounds on the form's sides, which Ficha keeps from then on, and clears them for the next card")
    func addSavesTheSoundsOnTheSides() async throws {
        var window = openWindow()
        window.openNewCardForm()
        window.typeInForm(front: "¿Qué notas son?", back: "La, y después mi.")
        for (name, hertz, side) in [("la.wav", 440.0, CardSide.front), ("sol.wav", 392, .back), ("mi.wav", 330, .back)]
        {
            // Dropping another sound on a side replaces its sound.
            let putting = window.putSoundInForm(try file(name, holding: tone(seconds: 1, hertz: hertz)), on: side)
            let work = try #require(putting)
            window.finishSoundWork(await work.run())
        }
        let la = try #require(window.cardForm?.draft.front.sound)
        let mi = try #require(window.cardForm?.draft.back.sound)
        let shownLa = try #require(try window.sounds[la]?.get().data)
        let notKeptYet = Result { try engine.sound(la) }

        window.addCard()

        let added = try #require(try engine.cards().first)
        #expect(added.frontSound == la)
        #expect(added.backSound == mi)
        #expect(throws: EngineError.soundsFolder) { try notKeptYet.get() }
        #expect(try engine.sound(la) == shownLa)
        #expect(throws: Never.self) { try engine.sound(mi) }
        #expect(window.cardForm?.draft.front.sound == nil)
        #expect(window.cardForm?.draft.back.sound == nil)
        #expect(window.sounds[la] == nil)
    }

    @Test("a file with no sound, or one that can't be read, stays off the side, and the window says why")
    func whatIsntASoundStaysOff() async throws {
        var window = openWindow()
        window.openNewCardForm()
        window.typeInForm(front: "¿Qué nota es?", back: "La.")

        let putting = window.putSoundInForm(try file("la.mp3", holding: Data("la".utf8)), on: .front)
        let notASound = try #require(putting)
        window.finishSoundWork(await notASound.run())
        let afterNotASound = window.failure
        window.dismissFailure()
        // Gone from its folder before it was read.
        let gone = window.putSoundInForm(folder.appending(path: "mi.mp3"), on: .back)

        #expect(window.cardForm?.draft.front.sound == nil)
        #expect(window.cardForm?.isSoundComingIn(on: .front) == false)
        #expect(window.cardForm?.canAdd == true)
        #expect(afterNotASound?.action == .putSound)
        #expect(afterNotASound?.error == .notASound)
        #expect(gone == nil)
        #expect(window.cardForm?.isSoundComingIn(on: .back) == false)
        #expect(window.failure?.action == .putSound)
        #expect(window.failure?.error == .unreadableFileForSide("mi.mp3"))
    }

    @Test("a sound that comes in once another replaced it, or once the form closed, is let go")
    func aSoundThatComesInLateIsLetGo() async throws {
        var window = openWindow()
        window.openNewCardForm()
        window.typeInForm(front: "¿Qué nota es?", back: "Mi.")
        let la = try file("la.wav", holding: tone(seconds: 1, hertz: 440))
        let mi = try file("mi.wav", holding: tone(seconds: 1, hertz: 330))

        let puttingLa = window.putSoundInForm(la, on: .front)
        let puttingMi = window.putSoundInForm(mi, on: .front)
        let first = try #require(puttingLa)
        let second = try #require(puttingMi)
        window.finishSoundWork(await second.run())
        let replaced = window.cardForm?.draft.front.sound
        window.finishSoundWork(await first.run())
        let afterTheFirst = window.cardForm?.draft.front.sound
        let puttingLate = window.putSoundInForm(la, on: .back)
        let late = try #require(puttingLate)
        window.closeCardForm()
        window.finishSoundWork(await late.run())
        window.openNewCardForm()

        #expect(replaced != nil)
        #expect(afterTheFirst == replaced)
        #expect(window.cardForm?.draft.back.sound == nil)
        #expect(window.cardForm?.isSoundComingIn(on: .back) == false)
        #expect(window.failure == nil)
    }

    @Test("Save gives the edited card the sounds put on it, replaced or removed, and Cancel leaves it as it was")
    func editingACardChangesItsSounds() async throws {
        let la = try await addTone(440, to: engine)
        let mi = try await addTone(330, to: engine)
        let notes = try engine.create(
            card(nil, front: "¿Qué notas son?", back: "La y mi.", frontSound: la, backSound: mi))
        var window = openWindow()
        window.select([notes.id])

        window.startEditing()
        window.removeSoundFromEditor(on: .front)
        window.cancelEditing()
        window.startEditing()
        let editing = window.editedSounds
        let putting = window.putSoundInEditor(try file("sol.wav", holding: tone(seconds: 1, hertz: 392)), on: .front)
        let work = try #require(putting)
        let canSaveWhileConverting = window.canSaveCard
        window.finishSoundWork(await work.run())
        window.removeSoundFromEditor(on: .back)
        let sol = try #require(window.editedSounds.front)
        window.saveCard(try card(nil, front: "¿Qué nota es?", back: "Sol.", frontSound: sol, backSound: nil))

        #expect(editing.front == la && editing.back == mi)
        #expect(!canSaveWhileConverting)
        let edited = try #require(try engine.cards().first)
        #expect(edited.frontSound == sol)
        #expect(edited.backSound == nil)
        #expect(window.editing == nil)
        #expect(throws: EngineError.soundsFolder) { try engine.sound(la) }
        #expect(throws: EngineError.soundsFolder) { try engine.sound(mi) }
        #expect(try window.sounds[sol]?.get().data == engine.sound(sol))
        #expect(window.sounds[la] == nil)
    }

    @Test("the detail shows the selected card's sounds with their length")
    func theDetailShowsTheSounds() async throws {
        let la = try await addTone(440, to: engine)
        let notes = try engine.create(card(nil, front: "", back: "La.", frontSound: la))
        _ = try engine.create(card(nil, front: "petricor", back: "El olor de la lluvia."))
        var window = openWindow()

        window.select([notes.id])

        let shown = try #require(try window.sounds[la]?.get())
        #expect(shown.data == (try engine.sound(la)))
        #expect(shown.length > .milliseconds(950) && shown.length < .milliseconds(1_050))
    }

    @Test("the table says which sides of each card have an image, and which have a sound")
    func theTableSaysWhichSidesHaveMedia() async throws {
        let la = try await addTone(440, to: engine)
        let mi = try await addTone(330, to: engine)
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let nest = try engine.addImage(picture(width: 800, height: 600, red: 0.3))
        let cards = try [
            card(nil, front: "petricor", back: "El olor de la lluvia."),
            card(nil, front: "", back: "La.", frontSound: la),
            card(nil, front: "¿Qué nota es?", back: "Mi.", backSound: mi),
            card(
                nil, front: "¿Qué ave canta así?", back: "El hornero.", frontImage: bird, frontSound: la, backSound: mi),
            card(nil, front: "¿Qué ave es?", back: "El hornero, en su nido.", frontImage: bird, backImage: nest),
            card(nil, front: "¿De quién es este nido?", back: "Del hornero.", backImage: nest),
        ].map { try engine.create($0) }
        let window = openWindow()

        guard case .success(.cards(let rows)) = window.listing else {
            Issue.record("The table lists no cards")
            return
        }
        let listed = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.card) })
        #expect(cards.map { listed[$0.id]?.sidesWithImages } == [nil, nil, nil, .front, .both, .back])
        #expect(cards.map { listed[$0.id]?.sidesWithSounds } == [nil, .front, .back, .both, nil, nil])
    }

    @Test("the table names a front without text by its image, or else by its sound")
    func theTableNamesAFrontWithoutText() async throws {
        let la = try await addTone(440, to: engine)
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let cards = try [
            card(nil, front: "¿Qué ave es?", back: "El hornero.", frontImage: bird),
            card(nil, front: "", back: "El hornero.", frontImage: bird),
            card(nil, front: "", back: "La.", frontSound: la),
            card(nil, front: "", back: "El hornero, que canta.", frontImage: bird, frontSound: la),
        ].map { try engine.create($0) }
        let window = openWindow()

        guard case .success(.cards(let rows)) = window.listing else {
            Issue.record("The table lists no cards")
            return
        }
        let listed = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.card) })
        #expect(cards.map { listed[$0.id]?.frontWithoutText } == [nil, .image, .sound, .image])
    }

    @Test(
        "one sound plays at a time, ■ stops it, and selecting another card, ending an edit or closing the form does too"
    )
    func oneSoundPlaysAtATime() async throws {
        let la = try await addTone(440, to: engine)
        let mi = try await addTone(330, to: engine)
        let notes = try engine.create(
            card(nil, front: "¿Qué notas son?", back: "La y mi.", frontSound: la, backSound: mi))
        let petricor = try engine.create(card(nil, front: "petricor", back: "El olor de la lluvia."))
        var window = openWindow()
        window.select([notes.id])

        window.playOrStopSound(at: .detail(cardID: notes.id, .front))
        let front = window.playingSound
        window.playOrStopSound(at: .detail(cardID: notes.id, .back))
        let back = window.playingSound
        window.playOrStopSound(at: .detail(cardID: notes.id, .back))
        let stopped = window.playingSound
        window.playOrStopSound(at: .detail(cardID: notes.id, .back))
        window.select([petricor.id])
        let afterSelecting = window.playingSound
        window.select([notes.id])
        window.playOrStopSound(at: .detail(cardID: notes.id, .front))
        let playing = try #require(window.playingSound)
        window.soundEnded(playing)
        let afterItEnded = window.playingSound
        window.startEditing()
        window.playOrStopSound(at: .editor(.back))
        let inEditor = window.playingSound
        window.cancelEditing()
        let afterCancelling = window.playingSound
        window.openNewCardForm()
        let putting = window.putSoundInForm(try file("sol.wav", holding: tone(seconds: 1, hertz: 392)), on: .front)
        let work = try #require(putting)
        window.finishSoundWork(await work.run())
        window.playOrStopSound(at: .form(.front))
        let inForm = window.playingSound
        window.closeCardForm()

        #expect(front == PlayingSound(place: .detail(cardID: notes.id, .front), name: la))
        #expect(back == PlayingSound(place: .detail(cardID: notes.id, .back), name: mi))
        #expect(window.isPlaying(at: .detail(cardID: notes.id, .back)) == false)
        #expect(stopped == nil)
        #expect(afterSelecting == nil)
        #expect(afterItEnded == nil)
        #expect(inEditor == PlayingSound(place: .editor(.back), name: mi))
        #expect(afterCancelling == nil)
        #expect(inForm?.place == .form(.front))
        #expect(window.playingSound == nil)
    }
}
