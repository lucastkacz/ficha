import AVFoundation
import FichaCore
import FichaData
import Foundation
import Testing
import ZIPFoundation

/// Tests on cards that travel with their sounds, as `ImagesInZipsTests` does
/// with images: an export of cards with sounds is a zip with the text file
/// and the sounds, and the import reads such a zip back, from engines in
/// memory on a Mac in Buenos Aires, into files in a folder of the test's own.
/// The tests make their own sounds, tones written as WAV files.
final class SoundsInZipsTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    /// A folder of the test's own, for the files it exports and imports.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaSoundsInZipsTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 23, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("cards with sounds export as a zip and import back with the same sounds on the same sides")
    func cardsWithSoundsExportAsAZipAndImportBack() async throws {
        let la = try await addTone(440, to: engine)
        let mi = try await engine.addSound(tone(seconds: 1, hertz: 330, channels: 2), named: "mi.wav")
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        let contents = [
            try card(
                .word, front: "coloratura", back: "Los ornamentos rápidos del canto.", tags: ["ópera"],
                source: "Un libro de ópera", backSound: la),
            try card(nil, front: "", back: "Un la.", frontSound: la),
            try card(.question, front: "¿Qué pájaro canta así?", back: "", backImage: bird, frontSound: mi),
            try card(.concept, front: "aria", back: "Una canción para una voz."),
        ]
        for content in contents {
            try engine.create(content)
        }
        let file = folder.appending(path: "Ópera.zip")

        let count = try engine.export(.all, to: file)

        #expect(count == 4)
        // Two cards play the la, which the zip holds once.
        let archive = try Archive(url: file, accessMode: .read)
        #expect(archive.map(\.path).sorted() == ["Ópera.txt", la.rawValue, mi.rawValue, bird.rawValue].sorted())
        let other = try Engine(location: .inMemory, time: time, calendar: calendar)
        let preview = try await other.previewImport(of: file)
        #expect(preview.leftOut == [])
        try other.importCards(preview, choosing: ImportChoices(tagNames: ["Ópera": ""]))
        #expect(try other.cards().map(content(of:)) == contents)
        #expect(try other.sound(la) == engine.sound(la))
        #expect(try other.sound(mi) == engine.sound(mi))
        #expect(try other.image(bird) == engine.image(bird))
    }

    @Test("cards with sounds and no images export a zip whose text file has the sound columns and not the image ones")
    func cardsWithSoundsAndNoImagesHaveOnlyTheSoundColumns() async throws {
        let la = try await addTone(440, to: engine)
        try engine.create(card(.word, front: "coloratura", back: "Un ornamento.", backSound: la))
        try engine.create(card(nil, front: "aria", back: "Una canción."))
        let file = folder.appending(path: "Ópera.zip")

        try engine.export(.all, to: file)

        let archive = try Archive(url: file, accessMode: .read)
        #expect(Set(archive.map(\.path)) == ["Ópera.txt", la.rawValue])
        let text = try contents(of: #require(archive["Ópera.txt"]), in: archive)
        #expect(
            String(decoding: text, as: UTF8.self) == """
                #separator:tab
                #html:false
                #columns:Front\tBack\tTags\tType\tSource\tFront sound\tBack sound
                #tags column:3
                coloratura\tUn ornamento.\t\tword\t\t\t\(la.rawValue)
                aria\tUna canción.\t\t\t\t\t

                """)
    }

    @Test(
        "a missing sound in a zip leaves its side without it, and a card left with an empty side stays out with its reason"
    )
    func aMissingSoundLeavesItsSideWithoutIt() async throws {
        let text = """
            #separator:tab
            #html:false
            #columns:Front\tBack\tFront sound\tBack sound
            coloratura\tLos ornamentos rápidos del canto.\t\tcoloratura.wav
            aria\tUna canción para una voz.\t\taria.mp3
            \tUn la.\tla.mp3\t
            ¿Qué nota es?\t\t\tmi.wav
            tenor\tLa voz masculina más aguda.\ttenor.wav\t

            """
        let file = try zip(
            [
                ("Ópera.txt", Data(text.utf8)),
                ("coloratura.wav", try tone(seconds: 2, hertz: 880)),
                ("mi.wav", Data("Una nota, no un sonido.".utf8)),
                ("tenor.wav", try tone(seconds: 1, hertz: 220)),
            ], named: "Ópera.zip")

        let preview = try await engine.previewImport(of: file)
        try engine.importCards(preview, choosing: ImportChoices(tagNames: ["Ópera": ""]))

        #expect(
            preview.leftOut == [
                LeftOutLine(line: 6, reason: .missingSound("la.mp3")),
                LeftOutLine(line: 7, reason: .notASound("mi.wav")),
            ])
        let cards = try engine.cards()
        #expect(cards.map(\.front) == ["coloratura", "aria", "tenor"])
        #expect(cards.map { $0.frontSound != nil } == [false, false, true])
        #expect(cards.map { $0.backSound != nil } == [true, false, false])
        // A WAV comes in converted, as from the Cards window's form.
        let coloratura = try #require(cards.first?.backSound)
        #expect(try soundFormat(of: engine.sound(coloratura)).id == kAudioFormatMPEG4AAC)
    }

    // The front's sound goes with the front, as its image (#229's decision 3).
    @Test(
        "a zip's cards update the cards they repeat with the back's sound the file gives, even none, keeping the front's"
    )
    func aZipsCardsUpdateTheBacksSound() async throws {
        let la = try await addTone(440, to: engine)
        let mi = try await addTone(330, to: engine)
        let sol = try await addTone(392, to: engine)
        let coloratura = try engine.create(
            card(.word, front: "coloratura", back: "Un ornamento.", frontSound: la, backSound: mi))
        let tenor = try engine.create(card(.word, front: "tenor", back: "Una voz.", backSound: sol))
        let text = """
            #columns:Front\tBack\tFront sound\tBack sound
            coloratura\tLos ornamentos rápidos del canto.\tdo.wav\tre.wav
            tenor\tLa voz masculina más aguda.\t\t

            """
        let file = try zip(
            [
                ("Ópera.txt", Data(text.utf8)),
                ("do.wav", try tone(seconds: 1, hertz: 262)),
                ("re.wav", try tone(seconds: 1, hertz: 294)),
            ], named: "Ópera.zip")

        let preview = try await engine.previewImport(of: file)
        let outcome = try engine.importCards(preview, choosing: ImportChoices(tagNames: ["Ópera": ""]))

        #expect(outcome == ImportOutcome(added: 0, updated: 2, skipped: 0, copyBeforeImport: nil))
        let cards = try engine.cards()
        #expect(cards.map(\.id) == [coloratura.id, tenor.id])
        #expect(cards.map(\.back) == ["Los ornamentos rápidos del canto.", "La voz masculina más aguda."])
        let re = try #require(cards[0].backSound)
        #expect(cards.map(\.frontSound) == [la, nil])
        #expect(cards.map(\.backSound) == [re, nil])
        // The sounds no card uses any more are gone, and so is the front's
        // the file gave, which came in for no card.
        let unused = try await Engine(location: .inMemory, time: time).addSound(
            tone(seconds: 1, hertz: 262), named: "do.wav")
        _ = try engine.sound(la)
        _ = try engine.sound(re)
        for gone in [mi, sol, unused] {
            #expect(throws: EngineError.soundsFolder) {
                try engine.sound(gone)
            }
        }
    }

    /// Writes a zip named `name` in the test's folder, holding `files`, and
    /// returns it.
    private func zip(_ files: [(path: String, data: Data)], named name: String) throws -> URL {
        let file = folder.appending(path: name)
        try writeZip(files, to: file)
        return file
    }

    /// What `entry` of `archive` holds, uncompressed.
    private func contents(of entry: Entry, in archive: Archive) throws -> Data {
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        return data
    }
}
