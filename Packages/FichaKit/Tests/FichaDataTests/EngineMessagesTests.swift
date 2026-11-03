import FichaCore
import Foundation
import Testing

@testable import FichaData

/// Tests that every message `EngineError` can show is in the String Catalogs
/// of the Mac's app, its widget and the iPhone app, translated into every
/// language of `scripts/languages.txt`. Xcode adds no text of a package to
/// them, so each message is added by hand (CODING_STANDARDS.md), and this
/// catches one that wasn't. It reads the catalogs and the list from the repo
/// this file is in.
struct EngineMessagesTests {
    /// The repo's folder, five folders up from this file.
    static let repo = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// One of each case, with sample values, nested ones included.
    static let samples: [EngineError] = [
        .migratedByNewerVersion, .emptyCapture, .captureNotInInbox(7), .notAnExpansion(7), .noCards,
        .blankSideOnNewCard(position: 1), .sideLeftBlank(7),
        .noFileOnSide(7, .image, .front), .noFileOnSide(7, .image, .back),
        .noFileOnSide(7, .sound, .front), .noFileOnSide(7, .sound, .back),
        .cardNotFound(7), .cardNotDue(7), .cardNotInAppearance(7), .placementIsNotAnAnswer(7), .cardFlagged(7),
        .cardNotFlagged(7), .cardBuried(7), .cardNotBuried(7),
        .cardSetAside(7, decks: ["Historia"]), .cardSetAside(7, decks: ["Historia", "Historia::Roma"]),
        .notOneEmoji, .tagInsideItself("países"), .blankTagName, .tagNotPinned("países"), .deckSetAside("Historia"),
        .blankDeckName, .defaultDeckName("Default"), .deckInsideItself("Historia"), .deckInsideDefault("Historia"),
        .defaultDeckStays, .deckNotFound("Historia"), .blankTypeName, .builtInTypeName("Word"),
        .typeNameTaken("Ley"), .userTypeNotFound, .cannotUndo(7), .cannotUndoFollowUp(7), .unreadableReviewLog(7),
        .schedulerFailed, .storage, .copyNotFound("Ficha 2026-10-14"), .copyMigratedByNewerVersion("Ficha 2026-10-14"),
        .backupsFolder, .notAnImage, .notASound, .soundConversion, .unreadableFileForSide("bandera.png"),
        .noSuchFile("~/bandera.png"), .fileNotInDownloads("bandera.png"), .fileNotAnImage("himno.mp3"),
        .fileNotASound("bandera.png"), .notAnImageOrSound("notas.txt"), .noFileNamed("bandera.png"), .imagesFolder,
        .soundsFolder, .unreadableFile("cards.txt", .cannotOpen), .unreadableFile("cards.txt", .notUTF8),
        .unreadableFile("cards.txt", .unknownSeparator("dash")), .unreadableFile("cards.txt", .unknownHTML("maybe")),
        .unreadableFile("cards.txt", .unknownColumnNumber(header: "tags column", value: "x")),
        .unreadableFile("cards.txt", .missingColumn(.back)), .unreadableFile("cards.zip", .unreadableZip),
        .unreadableFile("cards.zip", .noTextFileInZip),
        .unreadableFile("cards.zip", .severalTextFilesInZip(["a.txt", "b.txt"])),
        .unreadableFile("deck.apkg", .unreadableAnkiPackage), .unreadableFile("deck.apkg", .ankiPackageTooNew),
        .unwritableFile("cards.txt"),
    ]

    @Test("the samples hold every case of the engine's errors, nested ones included")
    func theSamplesHoldEveryCase() {
        #expect(Set(Self.samples.map(ErrorCase.init)) == Set(ErrorCase.allCases))
    }

    @Test(
        "every message of the engine is in the catalog, translated into every language",
        arguments: ["App/Localizable.xcstrings", "Widget/Localizable.xcstrings", "iPhone/Localizable.xcstrings"])
    func everyMessageIsTranslated(catalogPath: String) throws {
        let catalog = try JSONDecoder().decode(
            Catalog.self, from: Data(contentsOf: Self.repo.appending(path: catalogPath)))
        let languages = try Self.languages()

        for error in Self.samples {
            let key = error.message.key
            let entry = catalog.strings[key]
            #expect(entry != nil, "\(catalogPath) has no “\(key)”: add it by hand, translated, as \(error) shows it.")
            for language in languages {
                let unit = entry?.localizations?[language.code]?.stringUnit
                #expect(
                    unit?.state == "translated" && unit?.value.isEmpty == false,
                    """
                    \(catalogPath)'s “\(key)” has no \(language.name) (\(language.code)) translation: translate it, \
                    with the words in docs/terms.md, mark it translated, and run the test again.
                    """)
            }
        }
    }

    /// The languages `scripts/languages.txt` lists, read by the rules
    /// `scripts/check-translations.sh` reads it by: a line that's blank, or
    /// whose first character after any spaces is `#`, is skipped, and every
    /// other one is a language's code, its plural categories, other among
    /// them, and its name. A missing file, a line of another shape or a list
    /// of no language fails the test, as each fails the check.
    static func languages() throws -> [(code: String, name: String)] {
        let path = "scripts/languages.txt"
        let text = try #require(
            try? String(contentsOf: repo.appending(path: path), encoding: .utf8),
            "There's no \(path), the languages every catalog is translated into: restore it with git restore, and run the test again."
        )
        let category = "(zero|one|two|few|many|other)"
        let categories = try Regex("^\(category)(,\(category))*$")
        var languages: [(code: String, name: String)] = []
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let content = line.drop(while: \.isWhitespace)
            if content.isEmpty || content.hasPrefix("#") { continue }
            let fields = content.split(maxSplits: 2, whereSeparator: \.isWhitespace)
            try #require(
                fields.count == 3 && fields[1].wholeMatch(of: categories) != nil
                    && fields[1].split(separator: ",").contains("other"),
                """
                \(path):\(index + 1) isn't a language's code, its plural categories and its name, as in \
                'es one,many,other Spanish': write it so, with the categories Unicode's CLDR gives the language, \
                other among them, and run the test again.
                """)
            languages.append((String(fields[0]), String(fields[2].trimmingCharacters(in: .whitespaces))))
        }
        try #require(
            !languages.isEmpty,
            "\(path) lists no language: write a line for each language, as in 'es one,many,other Spanish', and run the test again."
        )
        return languages
    }
}

/// The parts of a String Catalog this test reads.
private struct Catalog: Decodable {
    let strings: [String: Entry]

    struct Entry: Decodable {
        let localizations: [String: Localization]?
    }

    struct Localization: Decodable {
        let stringUnit: StringUnit?
    }

    struct StringUnit: Decodable {
        let state: String
        let value: String
    }
}

/// Each case of `EngineError` by name, nested ones included. `init(_:)` has no
/// default, so a new case doesn't compile until it has a name here, and the
/// test above fails until `samples` holds one of it.
private enum ErrorCase: CaseIterable {
    case migratedByNewerVersion, emptyCapture, captureNotInInbox, notAnExpansion, noCards, blankSideOnNewCard
    case sideLeftBlank, noImageOnFront, noImageOnBack, noSoundOnFront, noSoundOnBack, cardNotFound, cardNotDue
    case cardNotInAppearance, placementIsNotAnAnswer, cardFlagged, cardNotFlagged, cardBuried, cardNotBuried
    case cardSetAsideByOneDeck, cardSetAsideByDecks, notOneEmoji, tagInsideItself, blankTagName, tagNotPinned
    case deckSetAside, blankDeckName, defaultDeckName, deckInsideItself, deckInsideDefault, defaultDeckStays
    case deckNotFound, blankTypeName, builtInTypeName, typeNameTaken, userTypeNotFound, cannotUndo
    case cannotUndoFollowUp, unreadableReviewLog, schedulerFailed, storage, copyNotFound, copyMigratedByNewerVersion
    case backupsFolder, notAnImage, notASound, soundConversion, unreadableFileForSide, noSuchFile, fileNotInDownloads
    case fileNotAnImage, fileNotASound, notAnImageOrSound, noFileNamed, imagesFolder, soundsFolder
    case cannotOpen, notUTF8, unknownSeparator, unknownHTML, unknownColumnNumber, missingColumn, unreadableZip
    case noTextFileInZip, severalTextFilesInZip, unreadableAnkiPackage, ankiPackageTooNew, unwritableFile

    init(_ error: EngineError) {
        self =
            switch error {
            case .migratedByNewerVersion: .migratedByNewerVersion
            case .emptyCapture: .emptyCapture
            case .captureNotInInbox: .captureNotInInbox
            case .notAnExpansion: .notAnExpansion
            case .noCards: .noCards
            case .blankSideOnNewCard: .blankSideOnNewCard
            case .sideLeftBlank: .sideLeftBlank
            case .noFileOnSide(_, .image, .front): .noImageOnFront
            case .noFileOnSide(_, .image, .back): .noImageOnBack
            case .noFileOnSide(_, .sound, .front): .noSoundOnFront
            case .noFileOnSide(_, .sound, .back): .noSoundOnBack
            case .cardNotFound: .cardNotFound
            case .cardNotDue: .cardNotDue
            case .cardNotInAppearance: .cardNotInAppearance
            case .placementIsNotAnAnswer: .placementIsNotAnAnswer
            case .cardFlagged: .cardFlagged
            case .cardNotFlagged: .cardNotFlagged
            case .cardBuried: .cardBuried
            case .cardNotBuried: .cardNotBuried
            case .cardSetAside(_, let decks) where decks.count == 1: .cardSetAsideByOneDeck
            case .cardSetAside: .cardSetAsideByDecks
            case .notOneEmoji: .notOneEmoji
            case .tagInsideItself: .tagInsideItself
            case .blankTagName: .blankTagName
            case .tagNotPinned: .tagNotPinned
            case .deckSetAside: .deckSetAside
            case .blankDeckName: .blankDeckName
            case .defaultDeckName: .defaultDeckName
            case .deckInsideItself: .deckInsideItself
            case .deckInsideDefault: .deckInsideDefault
            case .defaultDeckStays: .defaultDeckStays
            case .deckNotFound: .deckNotFound
            case .blankTypeName: .blankTypeName
            case .builtInTypeName: .builtInTypeName
            case .typeNameTaken: .typeNameTaken
            case .userTypeNotFound: .userTypeNotFound
            case .cannotUndo: .cannotUndo
            case .cannotUndoFollowUp: .cannotUndoFollowUp
            case .unreadableReviewLog: .unreadableReviewLog
            case .schedulerFailed: .schedulerFailed
            case .storage: .storage
            case .copyNotFound: .copyNotFound
            case .copyMigratedByNewerVersion: .copyMigratedByNewerVersion
            case .backupsFolder: .backupsFolder
            case .notAnImage: .notAnImage
            case .notASound: .notASound
            case .soundConversion: .soundConversion
            case .unreadableFileForSide: .unreadableFileForSide
            case .noSuchFile: .noSuchFile
            case .fileNotInDownloads: .fileNotInDownloads
            case .fileNotAnImage: .fileNotAnImage
            case .fileNotASound: .fileNotASound
            case .notAnImageOrSound: .notAnImageOrSound
            case .noFileNamed: .noFileNamed
            case .imagesFolder: .imagesFolder
            case .soundsFolder: .soundsFolder
            case .unreadableFile(_, .cannotOpen): .cannotOpen
            case .unreadableFile(_, .notUTF8): .notUTF8
            case .unreadableFile(_, .unknownSeparator): .unknownSeparator
            case .unreadableFile(_, .unknownHTML): .unknownHTML
            case .unreadableFile(_, .unknownColumnNumber): .unknownColumnNumber
            case .unreadableFile(_, .missingColumn): .missingColumn
            case .unreadableFile(_, .unreadableZip): .unreadableZip
            case .unreadableFile(_, .noTextFileInZip): .noTextFileInZip
            case .unreadableFile(_, .severalTextFilesInZip): .severalTextFilesInZip
            case .unreadableFile(_, .unreadableAnkiPackage): .unreadableAnkiPackage
            case .unreadableFile(_, .ankiPackageTooNew): .ankiPackageTooNew
            case .unwritableFile: .unwritableFile
            }
    }
}
