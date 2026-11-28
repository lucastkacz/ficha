import Foundation
import Testing

/// What the repo's files say, read from the repo this file is in, for the
/// tests on what its sources hold, such as a word no source writes any
/// longer: each test names its words, and why each is there.
enum RepoText {
    /// The repo's folder, five folders up from this file.
    static let repo = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// The folders that hold Ficha's Swift sources, from the repo's folder:
    /// the apps', the CLI's and the SVG drawer's executables, FichaKit's
    /// sources and the scripts' tools. FichaKit's tests aren't sources, and
    /// they name what the sources mustn't, as the files Open Deck… refuses or
    /// the emoji a deck's file holds.
    static let swiftSourceFolders = [
        "App", "CLI", "Widget", "iPhone", "SVGDrawer", "Packages/FichaKit/Sources", "scripts",
    ]

    /// The path of every Swift source, from the repo's folder, sorted: each
    /// `.swift` file in `swiftSourceFolders`, but in a folder whose name
    /// starts with a dot, such as the tools' `.build`, or in a DerivedData,
    /// which hold what a build fetched or made.
    static func swiftSources() throws -> [String] {
        var paths: [String] = []
        for folder in swiftSourceFolders {
            let path = repo.appending(path: folder, directoryHint: .isDirectory).path(percentEncoded: false)
            try #require(
                FileManager.default.fileExists(atPath: path),
                "\(folder) isn't in the repo: take it out of RepoText.swiftSourceFolders, or bring it back.")
            guard let files = FileManager.default.enumerator(atPath: path) else {
                Issue.record("Couldn't list the files in \(folder): check that the folder can be read.")
                continue
            }
            while let file = files.nextObject() as? String {
                let name = file.split(separator: "/").last.map(String.init) ?? file
                if name.hasPrefix(".") || name == "DerivedData" {
                    files.skipDescendants()
                } else if name.hasSuffix(".swift") {
                    paths.append("\(folder)/\(file)")
                }
            }
        }
        return paths.sorted()
    }

    /// Each line of the files at `paths`, from the repo's folder, that holds
    /// one of `words`, ignoring case, as "path:line", in the order of the
    /// paths, then of the lines. A word is looked for scalar by scalar of
    /// Unicode, so that 🖼 is found in 🖼️ too, which adds a variation
    /// selector to it, after both are composed alike.
    static func lines(holding words: [String], in paths: [String]) throws -> [String] {
        let wanted = words.map(scalars(of:))
        var found: [String] = []
        for path in paths {
            let text = try String(contentsOf: repo.appending(path: path), encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let held = scalars(of: String(line))
                if wanted.contains(where: { holds(held, $0) }) {
                    found.append("\(path):\(index + 1)")
                }
            }
        }
        return found
    }

    /// The Unicode scalars of `text`, composed as Unicode composes them, in
    /// lowercase.
    private static func scalars(of text: String) -> [Unicode.Scalar] {
        Array(text.precomposedStringWithCanonicalMapping.lowercased().unicodeScalars)
    }

    /// Whether `text` holds `word`, one scalar after another.
    private static func holds(_ text: [Unicode.Scalar], _ word: [Unicode.Scalar]) -> Bool {
        guard !word.isEmpty, word.count <= text.count else {
            return false
        }
        return (0...(text.count - word.count)).contains { start in
            text[start..<(start + word.count)].elementsEqual(word)
        }
    }
}
