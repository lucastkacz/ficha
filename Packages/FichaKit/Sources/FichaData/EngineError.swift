import FichaCore
import Foundation

/// What can go wrong in the engine. Each message says what happened and what
/// to do about it, in English, and is looked up with `String(localized:)` in
/// the main bundle (ADR 0009). In the app, that's the app's bundle, whose
/// String Catalog can translate the messages. Xcode doesn't add them to it,
/// so a translation adds them by hand, keyed by their English text. The
/// `ficha` CLI's main bundle is its own folder in the app, Contents/Helpers,
/// which has no catalog, so the CLI always prints them in English.
public enum EngineError: Error, Equatable {
    /// The database has migrations this version doesn't know: a newer version
    /// of Ficha migrated it, so this one refuses to open it.
    case migratedByNewerVersion
    /// A capture's text was empty, so there was nothing to save.
    case emptyCapture
    /// The capture with this id isn't in the inbox, so it can't be approved or
    /// discarded: it already was, or it doesn't exist.
    case captureNotInInbox(Int64)
    /// A capture was approved into no cards. One that becomes no cards is
    /// discarded instead.
    case noCards
    /// There's no card with this id.
    case cardNotFound(Int64)
    /// The card with this id already had its first view, so it can't have
    /// another.
    case cardNotNew(Int64)
    /// The card with this id is still new, so it can't be reviewed before its
    /// first view.
    case cardStillNew(Int64)
    /// The card with this id isn't due yet, so it can't be reviewed.
    case cardNotDue(Int64)
    /// The review log of the card with this id doesn't start with its first
    /// view, or has a second one, so it isn't known where the card stands.
    /// The engine logs it.
    case unreadableReviewLog(Int64)
    /// SQLite couldn't open, read or write the database. The engine logs why.
    case storage
}

extension EngineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .migratedByNewerVersion:
            String(
                localized: """
                    A newer version of Ficha changed the database, and this version won't open it, so as not to \
                    damage your cards. Open it with the version that changed it, or a newer one.
                    """
            )
        case .emptyCapture:
            String(localized: "The capture is empty: write what you want to remember.")
        case .captureNotInInbox(let id):
            String(
                localized: """
                    Capture \(id) isn't in the inbox: it was already approved or discarded, or it doesn't exist. \
                    Check what's in the inbox.
                    """
            )
        case .noCards:
            String(
                localized:
                    "A capture is approved into one or more cards. To take it out of the inbox without cards, discard it."
            )
        case .cardNotFound(let id):
            String(localized: "There's no card with the id \(id). \(reopenReviewNow)")
        case .cardNotNew(let id):
            String(localized: "Card \(id) already had its first view. \(reopenReviewNow)")
        case .cardStillNew(let id):
            String(
                localized: "Card \(id) is new: it needs its first view before it can be reviewed. \(reopenReviewNow)")
        case .cardNotDue(let id):
            String(localized: "Card \(id) isn't due yet, so it can't be reviewed. \(reopenReviewNow)")
        case .unreadableReviewLog(let id):
            String(
                localized: """
                    Ficha can't make sense of the review log of card \(id), so it doesn't know which step the card \
                    is on. Your cards are still saved: report it.
                    """
            )
        case .storage:
            String(
                localized: "Ficha couldn't read or save its database. Try again, and if it keeps happening, report it.")
        }
    }
}

/// What to do when the review panel shows a card for an answer it can't take:
/// start over with the cards as they are now.
private var reopenReviewNow: String {
    String(localized: "Close the review panel and open “Review now” again.")
}

extension EngineError {
    /// The engine's error for an answer to the card with this id that the
    /// card's standing refused.
    init(refused answer: RefusedAnswer, cardID: Int64) {
        self =
            switch answer {
            case .notNew: .cardNotNew(cardID)
            case .stillNew: .cardStillNew(cardID)
            case .notDue: .cardNotDue(cardID)
            }
    }
}
