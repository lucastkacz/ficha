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
                    One of the \(count) cards changed outside this window meanwhile, in the review panel or a \
                    refine session, so nothing was saved. The window now shows them as they are: check them and \
                    try again.
                    """,
                comment: "An alert's message in the Cards window, under what couldn't be done with the selected cards."
            )
        case .migratedByNewerVersion, .emptyCapture, .captureNotInInbox, .notAnExpansion, .noCards, .cardNotNew,
            .cardStillNew, .cardNotDue, .cardNotInAppearance, .placementIsNotAnAnswer, .cardSetAside, .notOneEmoji,
            .cannotUndo, .unreadableReviewLog, .storage, .copyNotFound, .copyMigratedByNewerVersion, .backupsFolder,
            .notAnImage, .imagesFolder, .unreadableFile, .unwritableFile:
            localizedDescription
        }
    }

    /// Why an action on a capture in the Cards window's inbox failed, as its
    /// alert says it: `message` when the error says the capture isn't in the
    /// inbox, which means a refine session took it out meanwhile, since the
    /// window offers its actions only to what waits there. The engine's
    /// message for it names the capture by its id, which the window doesn't
    /// show.
    func messageForCaptureInCardsWindow(ifItLeft message: String) -> String {
        switch self {
        case .captureNotInInbox:
            message
        case .migratedByNewerVersion, .emptyCapture, .notAnExpansion, .noCards, .cardNotFound, .cardNotNew,
            .cardStillNew, .cardNotDue, .cardNotInAppearance, .placementIsNotAnAnswer, .cardFlagged, .cardNotFlagged,
            .cardBuried, .cardNotBuried, .cardSetAside, .notOneEmoji, .cannotUndo, .unreadableReviewLog, .storage,
            .copyNotFound, .copyMigratedByNewerVersion, .backupsFolder, .notAnImage, .imagesFolder, .unreadableFile,
            .unwritableFile:
            localizedDescription
        }
    }
}
