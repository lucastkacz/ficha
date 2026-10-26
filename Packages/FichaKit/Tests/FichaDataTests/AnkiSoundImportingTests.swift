import AVFoundation
import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the sounds of a deck imported from an Anki package, of either
/// schema Anki writes, as `AnkiImageImportingTests` tests its images: which
/// sound each side of a card gets once the import is done, which cards stay
/// out for want of one, and what the preview reports, from packages the
/// tests write in a folder of their own, into an engine in memory on a Mac
/// in Buenos Aires. The tests make their own sounds, tones written as WAV
/// files, and a video with a tone.
final class AnkiSoundImportingTests {
    let time: ManualTimeSource
    let engine: Engine
    /// A folder of the test's own, for the packages it imports.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaAnkiSoundImportingTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    init() throws {
        let calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 23, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// The preview of `package`, written in the test's folder.
    private func preview(_ package: AnkiPackage) async throws -> ImportPreview {
        let file = folder.appending(path: "Ópera.apkg")
        try package.write(to: file)
        return try await engine.previewImport(of: file)
    }

    /// The name the Cards window's form keeps the sound in `data`, the file
    /// named `fileName`, by: what a sound that comes in from a package is
    /// kept by too.
    private func nameInTheForm(of data: Data, named fileName: String) async throws -> SoundName {
        try await Engine(location: .inMemory, time: time).addSound(data, named: fileName)
    }

    @Test(
        "a card with a sound on each side comes in with each side's sound, converted as the form converts it",
        arguments: [AnkiPackage.Format.supportOlderAnkiVersions, .current])
    func aSoundOnEachSideComesIn(format: AnkiPackage.Format) async throws {
        let la = try tone(seconds: 1, hertz: 440)
        let mi = try tone(seconds: 1, hertz: 330, channels: 2)
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(
                    type: .basic,
                    fields: ["coloratura [sound:la.wav]", "Los ornamentos rápidos del canto.<br>[sound:mi.wav]"])
            ],
            media: ["la.wav": la, "mi.wav": mi])

        let preview = try await preview(package)
        try engine.importCards(preview, choosing: ImportChoices())

        let card = try #require(try engine.cards().first)
        #expect([card.front, card.back] == ["coloratura", "Los ornamentos rápidos del canto."])
        #expect(card.frontSound == (try await nameInTheForm(of: la, named: "la.wav")))
        #expect(card.backSound == (try await nameInTheForm(of: mi, named: "mi.wav")))
        let back = try #require(card.backSound)
        #expect(try soundFormat(of: engine.sound(back)) == (kAudioFormatMPEG4AAC, 2))
    }

    // As a language deck's listening cards: the front plays a word, and the
    // back says which. Such a card stayed out before sounds came in.
    @Test(
        "a side with only a sound comes in with it", arguments: [AnkiPackage.Format.supportOlderAnkiVersions, .current])
    func aSideWithOnlyASoundComesIn(format: AnkiPackage.Format) async throws {
        let la = try tone(seconds: 1, hertz: 440)
        let mi = try tone(seconds: 1, hertz: 330)
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basic, fields: ["[sound:la.wav]", "La nota la."]),
                AnkiNote(type: .basic, fields: ["La nota mi.", "<div>[sound:mi.wav]</div>"]),
            ],
            media: ["la.wav": la, "mi.wav": mi])

        let preview = try await preview(package)
        try engine.importCards(preview, choosing: ImportChoices())

        #expect(preview.leftOut == [])
        let cards = try engine.cards()
        #expect(cards.map { [$0.front, $0.back] } == [["", "La nota la."], ["La nota mi.", ""]])
        #expect(cards.map(\.frontSound) == [try await nameInTheForm(of: la, named: "la.wav"), nil])
        #expect(cards.map(\.backSound) == [nil, try await nameInTheForm(of: mi, named: "mi.wav")])
    }

    // The same sound twice on a side drops none, as an image; Anki writes a
    // name with HTML's references, and a tag may run across lines.
    @Test(
        "a side with several sounds brings the first, and the preview counts the cards that drop the others",
        arguments: [AnkiPackage.Format.supportOlderAnkiVersions, .current])
    func aSideWithSeveralSoundsBringsTheFirst(format: AnkiPackage.Format) async throws {
        let la = try tone(seconds: 1, hertz: 440)
        let mi = try tone(seconds: 1, hertz: 330)
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basic, fields: ["¿Qué notas son?", "[sound:la &amp; mi.wav] y [sound:mi.wav]"]),
                AnkiNote(type: .basic, fields: ["[sound:mi.wav][sound:mi.wav]", "La nota mi, dos veces."]),
                AnkiNote(type: .basic, fields: ["Una nota", "[sound:la\n&amp; mi.wav]"]),
            ],
            media: ["la & mi.wav": la, "mi.wav": mi, "la\n& mi.wav": mi])

        let preview = try await preview(package)
        try engine.importCards(preview, choosing: ImportChoices())

        #expect(preview.cardsWithSoundsDropped == 1)
        let (laName, miName) = (
            try await nameInTheForm(of: la, named: "la.wav"), try await nameInTheForm(of: mi, named: "mi.wav")
        )
        let cards = try engine.cards()
        #expect(
            cards.map { [$0.front, $0.back] } == [
                ["¿Qué notas son?", "y"], ["", "La nota mi, dos veces."], ["Una nota", ""],
            ])
        #expect(cards.map(\.frontSound) == [nil, miName, nil])
        #expect(cards.map(\.backSound) == [laName, nil, miName])
    }

    // Anki plays a video with the same tag as a sound.
    @Test(
        "a video on a card comes in as its sound", arguments: [AnkiPackage.Format.supportOlderAnkiVersions, .current])
    func aVideoComesInAsItsSound(format: AnkiPackage.Format) async throws {
        let aria = try await video(seconds: 2, withSoundOf: 440)
        let package = AnkiPackage(
            format: format,
            notes: [AnkiNote(type: .basic, fields: ["aria", "Una canción para una voz. [sound:aria.mov]"])],
            media: ["aria.mov": aria])

        let preview = try await preview(package)
        try engine.importCards(preview, choosing: ImportChoices())

        let card = try #require(try engine.cards().first)
        #expect(card.back == "Una canción para una voz.")
        #expect(card.backSound == (try await nameInTheForm(of: aria, named: "aria.mov")))
        let sound = try #require(card.backSound)
        #expect(try soundFormat(of: engine.sound(sound)) == (kAudioFormatMPEG4AAC, 1))
    }

    // As images: a side with text comes in without it, and one with only it
    // keeps its card out, as does one with only a sound the package lacks,
    // as when Anki exports a deck without its media.
    @Test(
        "a sound Ficha can't read leaves its side without it, which the preview counts, and a card left with an empty side by it, or by a missing sound, stays out with its reason",
        arguments: [AnkiPackage.Format.supportOlderAnkiVersions, .current])
    func aSoundFichaCantReadStaysOut(format: AnkiPackage.Format) async throws {
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basic, fields: ["coloratura [sound:roto.mp3]", "Los ornamentos rápidos del canto."]),
                AnkiNote(type: .basic, fields: ["[sound:roto.mp3]", "Una nota rota."]),
                AnkiNote(type: .basic, fields: ["[sound:falta.mp3]", "Una nota que falta."]),
                AnkiNote(type: .basic, fields: ["tenor", "La voz masculina más aguda. [sound:falta.mp3]"]),
                AnkiNote(type: .basic, fields: ["Un video mudo [sound:mudo.mov]", "Un video sin sonido."]),
            ],
            media: [
                "roto.mp3": Data("Una nota, no un sonido.".utf8),
                "mudo.mov": try await video(seconds: 1, withSoundOf: nil),
            ],
            mediaMissingFromTheZip: ["falta.mp3"])

        let preview = try await preview(package)
        try engine.importCards(preview, choosing: ImportChoices())

        #expect(
            preview.leftOut == [
                LeftOutLine(line: 2, reason: .unreadableAnkiSound), LeftOutLine(line: 3, reason: .missingAnkiSound),
            ])
        #expect(preview.cardsWithUnreadableSoundsLeftOut == 2)
        let cards = try engine.cards()
        #expect(cards.map(\.front) == ["coloratura", "tenor", "Un video mudo"])
        #expect(cards.allSatisfy { $0.frontSound == nil && $0.backSound == nil })
    }

    // The front's sound goes with the front, as its image (#229's decision
    // 3).
    @Test(
        "a card the deck repeats takes the sound on Anki's back, or none, when it's updated, and keeps its front's",
        arguments: [AnkiPackage.Format.supportOlderAnkiVersions, .current])
    func anUpdatedCardTakesTheSoundOnAnkisBack(format: AnkiPackage.Format) async throws {
        let mine = try await addTone(262, to: engine)
        try engine.create(card(nil, front: "coloratura", back: "Un ornamento.", frontSound: mine, backSound: mine))
        try engine.create(card(nil, front: "tenor", back: "Una voz.", backSound: mine))
        let la = try tone(seconds: 1, hertz: 440)
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: .basic, fields: ["coloratura", "Los ornamentos rápidos del canto. [sound:la.wav]"]),
                AnkiNote(type: .basic, fields: ["tenor", "La voz masculina más aguda."]),
            ],
            media: ["la.wav": la])

        let preview = try await preview(package)
        try engine.importCards(preview, choosing: ImportChoices())

        let cards = try engine.cards()
        #expect(cards.map(\.back) == ["Los ornamentos rápidos del canto.", "La voz masculina más aguda."])
        #expect(cards.map(\.frontSound) == [mine, nil])
        #expect(cards.map(\.backSound) == [try await nameInTheForm(of: la, named: "la.wav"), nil])
    }

    // As Japanese Core 2000 plays a word above the line, and as Anki plays
    // the answer's sounds: without the question's that `{{FrontSide}}`
    // shows again, which it plays with the question (`qt/aqt/reviewer.py`,
    // `replay_audio`).
    @Test(
        "the back's sound is the first the answer side plays, above where the answer starts too, and not the front's that it shows again",
        arguments: [AnkiPackage.Format.supportOlderAnkiVersions, .current])
    func theBacksSoundIsTheAnswersOwn(format: AnkiPackage.Format) async throws {
        let la = try tone(seconds: 1, hertz: 440)
        let mi = try tone(seconds: 1, hertz: 330)
        let listening = AnkiNoteType(
            name: "Escucha", fields: ["Front", "Audio", "Back"],
            templates: [
                AnkiCardTemplate(
                    name: "Card 1", question: "{{Front}}",
                    answer: "{{FrontSide}}<div>{{Audio}}</div>\n\n<hr id=answer>\n\n{{Back}}")
            ])
        let package = AnkiPackage(
            format: format,
            notes: [
                AnkiNote(type: listening, fields: ["coloratura", "[sound:la.wav]", "Un ornamento."]),
                AnkiNote(type: listening, fields: ["[sound:mi.wav]", "", "La nota mi."]),
                AnkiNote(type: .basic, fields: ["[sound:mi.wav]", "La nota mi, otra vez. [sound:mi.wav]"]),
            ],
            media: ["la.wav": la, "mi.wav": mi])

        let preview = try await preview(package)
        try engine.importCards(preview, choosing: ImportChoices())

        let (laName, miName) = (
            try await nameInTheForm(of: la, named: "la.wav"), try await nameInTheForm(of: mi, named: "mi.wav")
        )
        let cards = try engine.cards()
        #expect(
            cards.map { [$0.front, $0.back] } == [
                ["coloratura", "Un ornamento."], ["", "La nota mi."], ["", "La nota mi, otra vez."],
            ])
        #expect(cards.map(\.frontSound) == [nil, miName, miName])
        #expect(cards.map(\.backSound) == [laName, nil, miName])
        #expect(preview.cardsWithSoundsDropped == 0)
    }
}
