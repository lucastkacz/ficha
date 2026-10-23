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
    func theExampleFileImportsAsTheCardsItDescribes() throws {
        let example = try fencedBlock(after: "## An example", in: String(contentsOf: document, encoding: .utf8))
        let file = folder.appending(path: "Example.txt")
        try Data(example.utf8).write(to: file)
        let calendar = try buenosAiresCalendar()
        let engine = try Engine(
            location: .inMemory, time: ManualTimeSource(now: try morning(of: 23, in: calendar)), calendar: calendar)

        let preview = try engine.previewImport(of: file)
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
