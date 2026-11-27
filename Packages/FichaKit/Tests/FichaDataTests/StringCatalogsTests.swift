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

    @Test("the app's String Catalog no longer holds the line under the panel's buttons on keys 2 and 4", .bug(id: 517))
    func theLineOnKeys2And4IsGone() throws {
        let catalog = try StringCatalog.read(at: "App/Localizable.xcstrings")
        #expect(
            catalog.strings["Also %@ Hard and %@ Easy, as in Anki"] == nil,
            """
            App/Localizable.xcstrings still holds the line under the review panel's buttons on keys 2 and 4, which \
            ADR 0039 takes out: delete it, and run the test again.
            """)
    }

    // The texts the app writes a card's detail with from FichaData's
    // `CardRow.Wording`: "Back on" a later day, as the system's date format
    // writes the day; "Seen" a count of times, with plural variations, one
    // and other at least; and a new card's words, as the desktop mock's card
    // pane says them (`mockups/desktop/index.html`). Each key is the text as
    // Xcode extracts it from the code, its value written in.
    @Test(
        "the app's String Catalog holds a card's Back on a day, its Seen N times with plural variations, and a new card's words",
        .bug(id: 537))
    func theCatalogHoldsACardsWords() throws {
        let catalog = try StringCatalog.read(at: "App/Localizable.xcstrings")
        let seen = catalog.strings["Seen %lld times"]?.localizations?["en"]?.variations?.plural ?? [:]

        #expect(
            catalog.strings["Back on %@"] != nil,
            """
            App/Localizable.xcstrings has no “Back on %@”, which a card's detail says of a card due on a later day \
            (#537): write it in the detail from CardRow.Wording, run make strings, and run the test again.
            """)
        #expect(
            Set(seen.keys).isSuperset(of: ["one", "other"]),
            """
            App/Localizable.xcstrings has no “Seen %lld times” with plural variations one and other, which a card's \
            detail says of a card seen that many times (#537): write it in the detail, run make strings, give it its \
            variations, and run the test again.
            """)
        #expect(
            catalog.strings["New: it waits its turn in the queue."] != nil,
            """
            App/Localizable.xcstrings has no “New: it waits its turn in the queue.”, which a card's detail says of a \
            new card, as the desktop mock does (#537): write it in the detail, run make strings, and run the test \
            again.
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

    /// A text, by the languages it has a value in, and whether the code still
    /// has it: `stale` when it no longer does.
    struct Entry: Decodable {
        let extractionState: String?
        let localizations: [String: Localization]?
    }

    /// A text's value in a language, when it has one of its own: one, or its
    /// plural variations, by their case, such as one and other.
    struct Localization: Decodable {
        let stringUnit: StringUnit?
        let variations: Variations?
    }

    /// A text's variations in a language, of which the tests read the plural
    /// ones.
    struct Variations: Decodable {
        let plural: [String: Variation]?
    }

    /// One variation of a text.
    struct Variation: Decodable {
        let stringUnit: StringUnit?
    }

    /// A text's value.
    struct StringUnit: Decodable {
        let value: String
    }

    /// The catalog at `path`, from the repo's folder.
    static func read(at path: String) throws -> StringCatalog {
        try JSONDecoder().decode(StringCatalog.self, from: Data(contentsOf: repo.appending(path: path)))
    }
}
