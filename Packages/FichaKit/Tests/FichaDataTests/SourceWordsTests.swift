import Foundation
import Testing

/// Tests on what the sources no longer name once ADR 0041's nodes take it out
/// of the app, as the words each test lists find it. They read the Swift files
/// from the repo this file is in, as `StringCatalogsTests` reads the String
/// Catalogs, and each fails with the lines that still name it.
struct SourceWordsTests {
    // The words: "column" and "columns", alone or in a name, such as
    // `IntervalColumn` and `dueColumn`, since a column is what the table had
    // and the grid has none. In the code alone: a comment that still says what
    // a column was is the docs' to keep up (`CODING_STANDARDS.md`, Docs).
    // Exempt: All Tags' columns, which go with All Tags in #538, whose own
    // test covers that file once it's gone.
    @Test("the Cards window's state keeps nothing for a table's columns, since the grid has none", .bug(id: 536))
    func theCardsWindowsStateKeepsNoColumns() throws {
        let files = try SourceFile.cardsWindowState()
            .filter { $0.name != "CardsWindowAllTags.swift" }
        let hits = try SourceFile.hits(
            of: [#"(?<![A-Za-z])[Cc]olumns?(?![a-z])|(?<=[a-z])Columns?(?![a-z])"#], in: files, codeOnly: true)
        #expect(
            hits.isEmpty,
            """
            The Cards window's state still keeps something for a table's columns, which the grid doesn't have \
            (#536). Say it as the grid or the detail does, and run the test again. \(SourceHit.list(hits))
            """)
    }

    // The words, in the code alone, as with the columns: "tag" and "tags",
    // alone or in a name, such as `CardTag`, `allTags` and `chosenDeckTag`;
    // and a card type's names, "Type" or "Types" in a name after a lowercase
    // letter, such as `CardType`, `UserTypes` and `editedType`, a name that
    // starts with "type" or "Type", such as `typeGroups`, and `.type`, a
    // card's type read, or a group's. Not "type" alone, which also names what
    // the user types and a pasteboard's types of data.
    // Taken out of each line first: `TagPath` with its member, and
    // `TagColor`, since decks reuse a tag's path and its colors (ADR 0024);
    // `tags: []` and `type: nil`, a card made with neither, as `CardContent`
    // still takes both, which the database keeps, unread (ADR 0041); and
    // `UniformTypeIdentifiers`, `typeIdentifiers` and `ofType`, which name a
    // pasteboard's types of data.
    // Exempt: the Import sheet (`CardsWindowImport.swift`), whose tags are
    // those an import's file proposes for its cards, and which ADR 0041 takes
    // out with text files and Anki's packages (Mac › Cards › Import).
    @Test("no window's state reads tags or card types", .bug(id: 538))
    func noWindowsStateReadsTagsOrCardTypes() throws {
        let files = try SourceFile.windowStates().filter { $0.name != "CardsWindowImport.swift" }
        let hits = try SourceFile.hits(
            of: [
                #"(?<![A-Za-z])[Tt]ags?(?![a-z])|(?<=[a-z])Tags?(?![a-z])"#,
                #"(?<=[a-z])Types?(?![a-z])|(?<![A-Za-z])[Tt]ypes?(?=[A-Z])|\.type\b"#,
            ],
            in: files,
            ignoring: [
                #"\bTagPath(\.[a-z]\w*)?"#, #"\bTagColor\b"#, #"\btags: \[\]"#, #"\btype: nil\b"#,
                #"\bUniformTypeIdentifiers\b"#, #"\btypeIdentifiers\b"#, #"\bofType\b"#,
            ],
            codeOnly: true)
        #expect(
            hits.isEmpty,
            """
            A window's state still reads tags or card types, which leave the app's face (#538): the database keeps \
            them, unread, and the CLI's tag and type commands stay. Take them out of the state, and run the test \
            again. \(SourceHit.list(hits))
            """)
    }
}

/// A Swift file of the repo, by its path from the repo's folder, with its
/// lines, as the tests on what the sources name read it.
struct SourceFile {
    let path: String
    let lines: [String]

    /// Its name, the last part of its path.
    var name: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    /// The Swift files in `folders`, each a path from the repo's folder, every
    /// level down but inside hidden folders, such as `.build`, in their paths'
    /// order. A folder that isn't there throws, as a list gone stale.
    static func swift(in folders: [String]) throws -> [SourceFile] {
        try folders.flatMap { folder throws -> [SourceFile] in
            let base = StringCatalog.repo.appending(path: folder, directoryHint: .isDirectory)
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: base.path(percentEncoded: false), isDirectory: &isFolder),
                isFolder.boolValue,
                let found = FileManager.default.enumerator(
                    at: base, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            else {
                throw MissingFolder(path: folder)
            }
            let baseComponents = base.resolvingSymlinksInPath().pathComponents
            var files: [SourceFile] = []
            for case let url as URL in found where url.pathExtension == "swift" {
                let components = url.resolvingSymlinksInPath().pathComponents
                guard components.starts(with: baseComponents) else {
                    throw MissingFolder(path: folder)
                }
                let path = ([folder] + components.dropFirst(baseComponents.count)).joined(separator: "/")
                let text = try String(contentsOf: url, encoding: .utf8)
                files.append(SourceFile(path: path, lines: text.components(separatedBy: "\n")))
            }
            return files.sorted { $0.path < $1.path }
        }
    }

    /// FichaData's files that hold the Cards window's state: those named
    /// `CardsWindow…`, and those that declare or extend `CardsWindowState`
    /// itself, such as `CardForm.swift` and `HowFast.swift`.
    static func cardsWindowState() throws -> [SourceFile] {
        try fichaData(declaringOrExtending: #"^(public )?(struct|extension) CardsWindowState\b"#)
    }

    /// FichaData's files that hold a window's state: those named
    /// `CardsWindow…`, and those that declare or extend a type whose name ends
    /// in `State`, as `CardsWindowState`, `ReviewPanelState`, `SyncTabState`
    /// and `BackupsState` do.
    static func windowStates() throws -> [SourceFile] {
        try fichaData(declaringOrExtending: #"^(public )?(struct|extension) \w+State\b"#)
    }

    /// FichaData's files named `CardsWindow…`, and those with a line that
    /// matches `declaration`.
    private static func fichaData(declaringOrExtending declaration: String) throws -> [SourceFile] {
        let expression = try NSRegularExpression(pattern: declaration)
        return try swift(in: ["Packages/FichaKit/Sources/FichaData"]).filter { file in
            file.name.hasPrefix("CardsWindow") || file.lines.contains { expression.matches($0) }
        }
    }

    /// The lines of `files` that name any of `words`, each a regular
    /// expression, once each of `ignored`, regular expressions too, is taken
    /// out of the line; in the code alone when `codeOnly` says so, leaving
    /// out everything from a line's `//` on, its comment, and a string's own
    /// `//` with it, such as a URL's.
    static func hits(of words: [String], in files: [SourceFile], ignoring ignored: [String] = [], codeOnly: Bool)
        throws -> [SourceHit]
    {
        let wordExpressions = try words.map { try NSRegularExpression(pattern: $0) }
        let ignoredExpressions = try ignored.map { try NSRegularExpression(pattern: $0) }
        var hits: [SourceHit] = []
        for file in files {
            for (index, line) in file.lines.enumerated() {
                var text = line
                if codeOnly, let comment = text.range(of: "//") {
                    text = String(text[..<comment.lowerBound])
                }
                for expression in ignoredExpressions {
                    text = expression.stringByReplacingMatches(
                        in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
                }
                if wordExpressions.contains(where: { $0.matches(text) }) {
                    hits.append(
                        SourceHit(
                            path: file.path, line: index + 1, text: line.trimmingCharacters(in: .whitespaces)))
                }
            }
        }
        return hits
    }
}

/// A line of a source that names what a test looks for.
struct SourceHit: CustomStringConvertible {
    let path: String
    let line: Int
    let text: String

    var description: String {
        "\(path):\(line): \(text)"
    }

    /// `hits` as a test's failure says them: how many, and the first 60, a
    /// line each.
    static func list(_ hits: [SourceHit]) -> String {
        let shown = hits.prefix(60).map(\.description).joined(separator: "\n")
        let more = hits.count > 60 ? "\n… and \(hits.count - 60) more." : ""
        return "The \(hits.count) lines:\n\(shown)\(more)"
    }
}

/// A folder a test reads the sources of that isn't in the repo.
struct MissingFolder: Error, CustomStringConvertible {
    let path: String

    var description: String {
        "\(path) isn't a folder of the repo, which a test reads the sources of: fix the test's list, and run it again."
    }
}

extension NSRegularExpression {
    /// Whether it matches some of `text`.
    func matches(_ text: String) -> Bool {
        firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
