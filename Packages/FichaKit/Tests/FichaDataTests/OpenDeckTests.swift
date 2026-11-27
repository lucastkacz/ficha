import FichaCore
import FichaData
import Foundation
import Testing
import ZIPFoundation

/// Tests on Open Deck…, in the Cards window's sidebar beside New Deck…, and
/// on a file opened from Finder, which the app opens through the same Open
/// Deck… (ADR 0044, #554): Ficha opens a deck's `.ficha` file alone. They
/// start at 9 in the morning in Buenos Aires, with an engine in memory, and
/// files in a folder of the test's own.
final class OpenDeckTests {
    let engine: Engine
    let scheduler = ReviewSettings.defaults.scheduler
    /// A folder of the test's own, for the files it opens.
    let folder = URL.temporaryDirectory.appending(
        path: "OpenDeckTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    init() throws {
        let calendar = try buenosAiresCalendar()
        engine = try Engine(
            location: .inMemory, time: ManualTimeSource(now: try morning(of: 14, in: calendar)),
            ids: CountingIDSource(), calendar: calendar)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    // Capitales.zip, .apkg and .colpkg hold what a .ficha holds, the deck's
    // text file of cards and its deck.json, under another name; Capitales.txt,
    // .csv and Capitales with no extension hold the text file alone, as
    // Export… wrote one before #542.
    @Test(
        "Open Deck… and a file opened from Finder refuse anything but a .ficha, a deck's own zip under another name too, at once, with an error that says Ficha opens a deck's .ficha file, and bring nothing in",
        .bug(id: 554),
        arguments: [
            "Capitales.zip", "Capitales.apkg", "Capitales.colpkg", "Capitales.txt", "Capitales.csv", "Capitales",
        ])
    func anythingButAFichaIsRefused(fileName: String) throws {
        let file = folder.appending(path: fileName)
        let text = Data("#separator:tab\n#html:false\n#columns:Front\tBack\tDeck\nPerú\tLima\tCapitales\n".utf8)
        if ["zip", "apkg", "colpkg"].contains(file.pathExtension) {
            let held = Data(#"{"emoji": "🌎", "description": "Las capitales de América del Sur."}"#.utf8)
            try makeZip(at: file, holding: [("Capitales.txt", text), ("deck.json", held)])
        } else {
            try text.write(to: file)
        }
        var window = engine.openCardsWindow(with: scheduler)
        window.read(with: scheduler)

        let started = window.openDeck(file) != nil

        #expect(!started)
        #expect(window.failure?.error.localizedDescription.contains(".ficha") == true)
        #expect(window.howFast == nil)
        #expect(try engine.cards() == [])
    }
}

/// Writes a zip to `file`, holding `files`, each a path in the zip and what
/// the file there holds, compressed: a test's own zip.
private func makeZip(at file: URL, holding files: [(path: String, data: Data)]) throws {
    let archive = try Archive(url: file, accessMode: .create, pathEncoding: nil)
    for (path, data) in files {
        try archive.addEntry(
            with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate
        ) { position, size in
            data.subdata(in: Int(position)..<Int(position) + size)
        }
    }
}
