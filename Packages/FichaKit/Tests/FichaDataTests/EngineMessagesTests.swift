import FichaCore
import Foundation
import Testing

@testable import FichaData

/// Tests that every message `EngineError` can show is in the String Catalogs
/// of the Mac's app, its widget and the iPhone app. Xcode adds no text of a
/// package to them, so each message is added by hand (CODING_STANDARDS.md),
/// and this catches one that wasn't. It reads the catalogs from the repo this
/// file is in.
struct EngineMessagesTests {
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
        .soundsFolder, .unreadableFile("Capitales.ficha", .cannotOpen),
        .unreadableFile("Capitales.zip", .notADeckFile), .unreadableFile("Capitales.ficha", .damagedDeckFile),
        .unwritableFile("Capitales.ficha"), .fichaDeckMissing("Arte argentino"), .descriptionTooLong,
    ]

    @Test("the samples hold every case of the engine's errors, nested ones included")
    func theSamplesHoldEveryCase() {
        #expect(Set(Self.samples.map(ErrorCase.init)) == Set(ErrorCase.allCases))
    }

    @Test(
        "every message of the engine is in the catalog",
        arguments: ["App/Localizable.xcstrings", "Widget/Localizable.xcstrings", "iPhone/Localizable.xcstrings"])
    func everyMessageIsInTheCatalog(catalogPath: String) throws {
        let catalog = try StringCatalog.read(at: catalogPath)

        // Each message, and the quotes each name of a list in one takes, since
        // a message takes the list as one value.
        let texts =
            Self.samples.map { (key: $0.message.key, shownBy: "as \($0) shows it") }
            + [(key: EngineError.quotedName("Historia").key, shownBy: "as each name of a list in a message shows")]
        for (key, shownBy) in texts {
            #expect(catalog.strings[key] != nil, "\(catalogPath) has no “\(key)”: add it by hand, \(shownBy).")
        }
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
    case cannotOpen, notADeckFile, damagedDeckFile, unwritableFile, fichaDeckMissing, descriptionTooLong

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
            case .unreadableFile(_, .notADeckFile): .notADeckFile
            case .unreadableFile(_, .damagedDeckFile): .damagedDeckFile
            case .unwritableFile: .unwritableFile
            case .fichaDeckMissing: .fichaDeckMissing
            case .descriptionTooLong: .descriptionTooLong
            }
    }
}
