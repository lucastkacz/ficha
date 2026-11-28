import AVFoundation
import FichaCore
import FichaData
import Foundation
import Testing
import ZIPFoundation

/// Tests on cards that travel with their sounds, as `ImagesInZipsTests` does
/// with images (#542): an export of a deck with sounds is its `.ficha`, a
/// zip with the text file and the sounds, and adding a deck reads such a zip
/// back, from engines in memory on a Mac in Buenos Aires, into files in a
/// folder of the test's own.
/// The tests make their own sounds, tones written as WAV files.
final class SoundsInZipsTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    /// A folder of the test's own, for the files it exports and adds.
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

    @Test(
        "a deck's cards with sounds export as a zip and come back with the same sounds on the same sides",
        .bug(id: 542))
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
            try engine.create(content, deck: "Ópera")
        }
        let file = folder.appending(path: "Ópera.ficha")

        let count = try engine.export(.deck("Ópera"), to: file)

        #expect(count == 4)
        // Two cards play the la, which the zip holds once.
        let archive = try Archive(url: file, accessMode: .read)
        #expect(
            archive.map(\.path).sorted()
                == ["Ópera.txt", "deck.json", la.rawValue, mi.rawValue, bird.rawValue].sorted())
        let other = try Engine(location: .inMemory, time: time, calendar: calendar)
        let deck = try await other.readDeckFile(at: file)
        #expect(deck.leftOut == [])
        try other.addDeck(deck)
        #expect(try other.cards().map(content(of:)) == contents)
        #expect(try other.sound(la) == engine.sound(la))
        #expect(try other.sound(mi) == engine.sound(mi))
        #expect(try other.image(bird) == engine.image(bird))
    }

    @Test(
        "a deck's cards with sounds and no images export a zip whose text file has the sound columns and not the image ones",
        .bug(id: 542))
    func cardsWithSoundsAndNoImagesHaveOnlyTheSoundColumns() async throws {
        let la = try await addTone(440, to: engine)
        try engine.create(card(.word, front: "coloratura", back: "Un ornamento.", backSound: la), deck: "Ópera")
        try engine.create(card(nil, front: "aria", back: "Una canción."), deck: "Ópera")
        let file = folder.appending(path: "Ópera.ficha")

        try engine.export(.deck("Ópera"), to: file)

        let archive = try Archive(url: file, accessMode: .read)
        #expect(Set(archive.map(\.path)) == ["Ópera.txt", "deck.json", la.rawValue])
        let text = try contents(of: #require(archive["Ópera.txt"]), in: archive)
        #expect(
            String(decoding: text, as: UTF8.self) == """
                #separator:tab
                #html:false
                #columns:Front\tBack\tTags\tType\tSource\tDeck\tFront sound\tBack sound
                #tags column:3
                #deck column:6
                coloratura\tUn ornamento.\t\tword\t\tÓpera\t\t\(la.rawValue)
                aria\tUna canción.\t\t\t\tÓpera\t\t

                """)
    }

    @Test(
        "a missing sound in a deck's .ficha leaves its side without it, and a card left with an empty side stays out with its reason",
        .bug(id: 542))
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
        let file = folder.appending(path: "Ópera.ficha")
        try writeDeckFile(
            at: file, text: text,
            files: [
                ("coloratura.wav", try tone(seconds: 2, hertz: 880)),
                ("mi.wav", Data("Una nota, no un sonido.".utf8)),
                ("tenor.wav", try tone(seconds: 1, hertz: 220)),
            ])

        let deck = try await engine.readDeckFile(at: file)
        try engine.addDeck(deck)

        #expect(
            deck.leftOut == [
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

    /// What `entry` of `archive` holds, uncompressed.
    private func contents(of entry: Entry, in archive: Archive) throws -> Data {
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        return data
    }
}
