import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the instructions for an AI, `docs/instructions-for-an-ai.md`,
/// which the app bundles and its Import sheet copies, read from the repo this
/// file is in: their example is a file Ficha imports.
final class InstructionsForAnAITests {
    /// The document, five folders up from this file, in the repo's `docs`.
    let document = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "docs/instructions-for-an-ai.md")
    /// A folder of the test's own, for the example's file.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaInstructionsForAnAITests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("the instructions' example file imports as the cards it describes")
    func theExampleFileImportsAsTheCardsItDescribes() async throws {
        let example = try fencedBlock(after: "## An example", in: String(contentsOf: document, encoding: .utf8))
        let file = folder.appending(path: "Example.txt")
        try Data(example.utf8).write(to: file)
        let calendar = try buenosAiresCalendar()
        let engine = try Engine(
            location: .inMemory, time: ManualTimeSource(now: try morning(of: 23, in: calendar)), calendar: calendar)

        let preview = try await engine.previewImport(of: file)
        try engine.importCards(preview, choosing: ImportChoices(tagNames: ["Example": ""]))

        #expect(preview.leftOut == [])
        #expect(
            try engine.cards().map(content(of:)) == [
                try card(
                    .word, front: "serendipity", back: "Finding something good without looking for it.",
                    tags: ["vocabulary"]),
                try card(
                    .concept, front: "mitochondria",
                    back: "The part of a cell that turns food into the energy the cell uses.",
                    tags: ["biology", "cell biology"], source: "An introductory biology course"),
                try card(
                    .quote, front: "\"I think, therefore I am.\"",
                    back: "René Descartes, in Discourse on the Method (1637).", tags: ["philosophy"]),
                try card(
                    .question, front: "What is the capital of Mongolia?", back: "Ulaanbaatar.", tags: ["geography"]),
                try card(
                    nil, front: "photosynthesis",
                    back: "How plants make their food:\nwater + carbon dioxide + light → sugar + oxygen.",
                    tags: ["biology"]),
            ])
    }

    @Test("the instructions' example with images imports from a zip with the images it names")
    func theExampleWithImagesImportsFromAZip() async throws {
        let example = try fencedBlock(
            after: "### An example with images", in: String(contentsOf: document, encoding: .utf8))
        let file = folder.appending(path: "Birds.zip")
        try writeZip(
            [
                ("Birds.txt", Data(example.utf8)),
                ("hornero.jpg", try picture(width: 800, height: 600, red: 0.8)),
                ("lapwing.jpg", try picture(width: 800, height: 600, red: 0.2)),
            ], to: file)
        let calendar = try buenosAiresCalendar()
        let engine = try Engine(
            location: .inMemory, time: ManualTimeSource(now: try morning(of: 23, in: calendar)), calendar: calendar)

        let preview = try await engine.previewImport(of: file)
        try engine.importCards(preview, choosing: ImportChoices(tagNames: ["Birds": ""]))

        #expect(preview.leftOut == [])
        let cards = try engine.cards()
        #expect(cards.map(\.front) == ["What bird is this?", ""])
        #expect(
            cards.map(\.back) == [
                "The rufous hornero, which builds its nest of mud.",
                "The southern lapwing, which shouts when anyone nears its nest.",
            ])
        #expect(cards.map(\.type) == [.question, nil])
        #expect(cards.map(\.tags) == [["birds"], ["birds"]])
        #expect(cards.allSatisfy { $0.frontImage != nil && $0.backImage == nil })
    }

    @Test("the instructions' example with sounds imports from a zip with the sounds it names")
    func theExampleWithSoundsImportsFromAZip() async throws {
        let example = try fencedBlock(
            after: "### An example with sounds", in: String(contentsOf: document, encoding: .utf8))
        let calendar = try buenosAiresCalendar()
        let time = ManualTimeSource(now: try morning(of: 23, in: calendar))
        let engine = try Engine(location: .inMemory, time: time, calendar: calendar)
        // Songs in M4A files, as another Ficha keeps them.
        let another = try Engine(location: .inMemory, time: time, calendar: calendar)
        let hornero = try another.sound(try await addTone(440, to: another))
        let lapwing = try another.sound(try await addTone(330, to: another))
        let file = folder.appending(path: "Birds.zip")
        try writeZip(
            [("Birds.txt", Data(example.utf8)), ("hornero.m4a", hornero), ("lapwing.m4a", lapwing)], to: file)

        let preview = try await engine.previewImport(of: file)
        try engine.importCards(preview, choosing: ImportChoices(tagNames: ["Birds": ""]))

        #expect(preview.leftOut == [])
        let cards = try engine.cards()
        #expect(cards.map(\.front) == ["What bird sings like this?", ""])
        #expect(
            cards.map(\.back) == [
                "The rufous hornero, which builds its nest of mud.",
                "The southern lapwing, which shouts when anyone nears its nest.",
            ])
        #expect(cards.map(\.type) == [.question, nil])
        #expect(cards.map(\.tags) == [["birds"], ["birds"]])
        #expect(cards.allSatisfy { $0.frontSound != nil && $0.backSound == nil })
    }

    /// The lines of the first fenced code block after the line `heading` in
    /// `text`, each ending in a line break.
    private func fencedBlock(after heading: String, in text: String) throws -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let start = try #require(lines.firstIndex { $0 == heading })
        let opening = try #require(lines[start...].firstIndex { $0.hasPrefix("```") })
        let closing = try #require(lines[(opening + 1)...].firstIndex { $0.hasPrefix("```") })
        return lines[(opening + 1)..<closing].map { "\($0)\n" }.joined()
    }
}
