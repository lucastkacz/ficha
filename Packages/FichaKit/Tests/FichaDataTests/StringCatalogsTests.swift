import Foundation
import Testing

/// Tests that the String Catalogs hold English alone, since Ficha comes only
/// in English (ADR 0036): a text in another language is one that Xcode, or a
/// hand, brought in by mistake. And that they hold no text the code no longer
/// has, which `make strings` keeps, marked stale, when it holds a value of
/// its own, such as plural variations, and `make check`'s strings-check then
/// lets through. It reads the catalogs from the repo this file is in.
struct StringCatalogsTests {
    @Test("every String Catalog holds English alone", .bug(id: 488), arguments: StringCatalog.paths)
    func everyCatalogHoldsEnglishAlone(catalogPath: String) throws {
        let catalog = try StringCatalog.read(at: catalogPath)
        #expect(
            catalog.sourceLanguage == "en",
            """
            \(catalogPath)'s source language is \(catalog.sourceLanguage), and Ficha's texts are in English \
            (ADR 0036): make it en, and run the test again.
            """)
        let others = Set(catalog.strings.values.flatMap { $0.localizations?.keys.map { $0 } ?? [] })
            .subtracting(["en"])
        #expect(
            others.isEmpty,
            """
            \(catalogPath) has texts in \(others.sorted().joined(separator: ", ")), and Ficha comes only in \
            English (ADR 0036): delete them, and run the test again.
            """)
    }

    @Test("no String Catalog holds a text the code no longer has", .bug(id: 488), arguments: StringCatalog.paths)
    func noCatalogHoldsAStaleText(catalogPath: String) throws {
        let catalog = try StringCatalog.read(at: catalogPath)
        let stale = catalog.strings.filter { $0.value.extractionState == "stale" }.keys.sorted()
        #expect(
            stale.isEmpty,
            """
            \(catalogPath) holds texts the code no longer has, which make strings marked stale: \
            \(stale.map { "“\($0)”" }.joined(separator: ", ")). Delete each, after moving its plural variations to \
            the text that replaced it, if one did, and run the test again.
            """)
    }
}

/// The parts of a String Catalog FichaKit's tests read, from the repo.
struct StringCatalog: Decodable {
    /// The repo's folder, five folders up from this file.
    static let repo = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// Every String Catalog, from the repo's folder, as the `Makefile`'s
    /// `CATALOGS` lists them.
    static let paths = [
        "App/Localizable.xcstrings", "App/AppShortcuts.xcstrings", "Widget/Localizable.xcstrings",
        "iPhone/Localizable.xcstrings",
    ]

    let sourceLanguage: String
    let strings: [String: Entry]

    /// A text, by the languages it has a value in, of which the tests read
    /// only which, and whether the code still has it: `stale` when it no
    /// longer does.
    struct Entry: Decodable {
        let extractionState: String?
        let localizations: [String: Localization]?
    }

    struct Localization: Decodable {}

    /// The catalog at `path`, from the repo's folder.
    static func read(at path: String) throws -> StringCatalog {
        try JSONDecoder().decode(StringCatalog.self, from: Data(contentsOf: repo.appending(path: path)))
    }
}
