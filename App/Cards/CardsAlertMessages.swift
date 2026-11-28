import FichaData
import Foundation

extension EngineError {
    /// Why an action on `count` cards in the Cards window failed, as its alert
    /// says it. An error that says a card isn't as the window showed it means
    /// the card changed outside the window meanwhile, since the window offers
    /// each action only to the cards it works on. The engine's message for it
    /// names the card by its id, which the window doesn't show, and says what
    /// to do in the CLI or the review panel.
    func messageInCardsWindow(actingOn count: Int) -> String {
        switch self {
        case .cardNotFound, .cardFlagged, .cardNotFlagged, .cardBuried, .cardNotBuried:
            String(
                localized: """
                    One of the \(count) cards changed outside this window meanwhile, in the review panel or through \
                    the ficha command, so nothing was saved. The window now shows them as they are: check them and \
                    try again.
                    """,
                comment: "An alert's message in the Cards window, under what couldn't be done with the selected cards."
            )
        case .migratedByNewerVersion, .blankSideOnNewCard, .sideLeftBlank, .noFileOnSide, .cardNotDue,
            .cardNotInAppearance, .placementIsNotAnAnswer, .cardSetAside, .notOneEmoji, .tagInsideItself, .blankTagName,
            .tagNotPinned, .deckSetAside, .blankDeckName, .defaultDeckName, .deckInsideItself, .deckInsideDefault,
            .defaultDeckStays, .deckNotFound, .blankTypeName, .builtInTypeName, .typeNameTaken, .userTypeNotFound,
            .cannotUndo, .unreadableReviewLog, .schedulerFailed, .storage, .copyNotFound,
            .copyMigratedByNewerVersion, .backupsFolder, .notAnImage, .notASound, .soundConversion,
            .unreadableFileForSide, .noSuchFile, .fileNotInDownloads, .fileNotAnImage, .fileNotASound,
            .notAnImageOrSound, .noFileNamed, .imagesFolder, .soundsFolder, .unreadableFile, .unwritableFile,
            .fichaDeckMissing, .descriptionTooLong:
            localizedDescription
        }
    }
}
