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
    /// The capture with this id doesn't expand a card, so it can't be approved
    /// as an expansion: it's approved into cards instead, or discarded.
    case notAnExpansion(Int64)
    /// A capture was approved into no cards. One that becomes no cards is
    /// discarded instead.
    case noCards
    /// There's no card with this id: it was deleted, or it never existed.
    case cardNotFound(Int64)
    /// The card with this id already had its first view, or an import placed
    /// it on a step, so it can't have a first view.
    case cardNotNew(Int64)
    /// The card with this id is still new, so it can't be reviewed before its
    /// first view.
    case cardStillNew(Int64)
    /// The card with this id isn't due yet, so it can't be reviewed.
    case cardNotDue(Int64)
    /// The card with this id isn't one of the cards its appearance brought,
    /// so its answer from a card notification can't be recorded.
    case cardNotInAppearance(Int64)
    /// A placement was recorded as an answer to the card with this id, and
    /// refused: only an import places a card on a step, as it comes in.
    case placementIsNotAnAnswer(Int64)
    /// The card with this id is flagged, so it waits in the inbox: it can't be
    /// answered or flagged again until it's fixed.
    case cardFlagged(Int64)
    /// The card with this id isn't flagged, so there's no flag to fix: it was
    /// already fixed, or it was never flagged.
    case cardNotFlagged(Int64)
    /// The card with this id is buried, so it can't be answered, flagged,
    /// expanded or buried again, nor fixed in a refine session, until it's
    /// unburied. The Cards window edits it all the same.
    case cardBuried(Int64)
    /// The card with this id isn't buried, so it can't be unburied.
    case cardNotBuried(Int64)
    /// The card with this id is set aside by these tags of it, in
    /// alphabetical order, so it can't be answered until none of them is set
    /// aside. Everything else treats it as a card in Lucas's reviews.
    case cardSetAside(Int64, tags: [String])
    /// What Lucas gave a tag as its emoji isn't one emoji: a word, two
    /// emoji, a letter or nothing.
    case notOneEmoji
    /// The card with this id changed outside the review panel, as a refine
    /// session can change it, so ⌘Z can't undo what Lucas did with it.
    case cannotUndo(Int64)
    /// The review log of the card with this id doesn't start with its first
    /// view or a placement, or has a second one later, so it isn't known
    /// where the card stands. The engine logs it.
    case unreadableReviewLog(Int64)
    /// SQLite couldn't open, read or write the database. The engine logs why.
    case storage
    /// There's no copy with this name in the Backups folder, so it can't be
    /// restored or moved to the Trash: it was, or it was moved by hand.
    case copyNotFound(String)
    /// A newer version of Ficha migrated the copy with this name, so this one
    /// refuses to restore it, as it refuses such a database.
    case copyMigratedByNewerVersion(String)
    /// A copy in the Backups folder couldn't be listed, named, moved or
    /// removed, or the images the copies share couldn't be kept or weighed.
    /// The engine logs why.
    case backupsFolder
    /// What came in for a side of a card, dragged or pasted, isn't an image
    /// the system can read.
    case notAnImage
    /// An image in the Images folder couldn't be read, saved, brought back
    /// from the Backups folder or removed, or isn't there. The engine logs
    /// why.
    case imagesFolder
    /// The file of cards with this name can't be imported, for the reason
    /// the problem gives, so nothing was read from it.
    case unreadableFile(String, CardsFileProblem)
    /// The file with this name couldn't be written, so the cards weren't
    /// exported to it. The engine logs why.
    case unwritableFile(String)
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
        case .notAnExpansion(let id):
            String(
                localized: "Capture \(id) doesn't expand a card. Approve it into cards, or discard it.")
        case .noCards:
            String(
                localized:
                    "A capture is approved into one or more cards. To take it out of the inbox without cards, discard it."
            )
        case .cardNotFound(let id):
            String(
                localized:
                    "There's no card with the id \(id): it was deleted, or it never existed. Check the card's id.")
        case .cardNotNew(let id):
            String(
                localized: "Card \(id) isn't new: it already had its first view, or came in on a step. \(reopenReviewNow)")
        case .cardStillNew(let id):
            String(
                localized: "Card \(id) is new: it needs its first view before it can be reviewed. \(reopenReviewNow)")
        case .cardNotDue(let id):
            String(localized: "Card \(id) isn't due yet, so it can't be reviewed. \(reopenReviewNow)")
        case .cardNotInAppearance(let id):
            String(
                localized: """
                    Card \(id) isn't one of the cards its appearance brought, so its answer wasn't recorded. \
                    Report it.
                    """
            )
        case .placementIsNotAnAnswer(let id):
            String(
                localized: """
                    Card \(id) can't be placed on a step as an answer: only an import places a card. Nothing was \
                    recorded. Report it.
                    """
            )
        case .cardFlagged(let id):
            String(localized: "Card \(id) is flagged: it waits in the inbox to be fixed. \(reopenReviewNow)")
        case .cardNotFlagged(let id):
            String(
                localized: """
                    Card \(id) isn't flagged, so there's nothing to fix: it was already fixed, or it was never \
                    flagged. Check what's in the inbox.
                    """
            )
        case .cardBuried(let id):
            String(localized: "Card \(id) is buried. To bring it back, unbury it.")
        case .cardNotBuried(let id):
            String(localized: "Card \(id) isn't buried, so there's nothing to unbury. Check the card's id.")
        case .cardSetAside(let id, let tags) where tags.count == 1:
            String(
                localized: """
                    Card \(id) is set aside with its tag “\(tags[0])”. To bring it back, untick Set Aside on that \
                    tag in the Cards window.
                    """
            )
        case .cardSetAside(let id, let tags):
            String(
                localized: """
                    Card \(id) is set aside with its tags \(quotedList(tags)). To bring it back, untick Set Aside \
                    on each of them in the Cards window.
                    """
            )
        case .notOneEmoji:
            String(localized: "A tag's emoji is one emoji. Pick just one, or leave the field empty for none.")
        case .cannotUndo(let id):
            String(
                localized: "Card \(id) changed outside the review panel, so ⌘Z can't undo it. \(reopenReviewNow)")
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
        case .copyNotFound(let name):
            String(
                localized: """
                    There's no copy named “\(name)” in Ficha's Backups folder: it was moved or deleted. Check which \
                    copies are there.
                    """
            )
        case .copyMigratedByNewerVersion(let name):
            String(
                localized: """
                    A newer version of Ficha saved the copy “\(name)”, and this version won't restore it, so as \
                    not to damage your cards. Restore it with that version, or a newer one.
                    """
            )
        case .backupsFolder:
            String(
                localized: """
                    Ficha couldn't read or change its Backups folder. Check that the disk has room and try again, \
                    and if it keeps happening, report it.
                    """
            )
        case .notAnImage:
            String(
                localized: """
                    That isn't an image Ficha can read. Drag or paste a picture instead, such as a JPEG or a PNG.
                    """
            )
        case .imagesFolder:
            String(
                localized: """
                    Ficha couldn't read or save an image in its Images folder. Check that the disk has room and try \
                    again, and if it keeps happening, report it.
                    """
            )
        case .unreadableFile(let name, let problem):
            problem.message(forFileNamed: name)
        case .unwritableFile(let name):
            String(
                localized: """
                    Ficha couldn't save “\(name)”. Check that the disk has room and that you can save in that \
                    folder, or choose another one, and try again.
                    """
            )
        }
    }
}

extension CardsFileProblem {
    /// What happened to the file named `name`, and what to do about it.
    fileprivate func message(forFileNamed name: String) -> String {
        switch self {
        case .cannotOpen:
            String(localized: "Ficha couldn't open “\(name)”. Check that the file is still there, and try again.")
        case .notUTF8:
            String(
                localized: """
                    “\(name)” isn't UTF-8 text, which is what Ficha reads. Save it again as UTF-8 text, or from a \
                    spreadsheet as “CSV UTF-8”, and import that.
                    """
            )
        case .unknownSeparator(let separator):
            String(
                localized: """
                    The #separator line of “\(name)” says “\(separator)”, which Ficha can't separate columns by. Make \
                    it Tab, Comma or Semicolon, or remove it.
                    """
            )
        case .unknownHTML(let value):
            String(
                localized: """
                    The #html line of “\(name)” says “\(value)”: make it true when the file holds HTML, or false when \
                    it doesn't.
                    """
            )
        case .unknownColumnNumber(let header, let value):
            String(
                localized: """
                    The #\(header) line of “\(name)” says “\(value)”, which isn't a column's number. Make it the \
                    number of the column, counting the first one as 1.
                    """
            )
        case .missingColumn(let column):
            String(
                localized: """
                    The #columns line of “\(name)” names no \(column.rawValue) column, which every card needs. Name \
                    its columns Front, Back, Tags, Type and Source, or remove the line.
                    """
            )
        case .unreadableZip:
            String(
                localized: """
                    Ficha couldn't open “\(name)” as a zip: it may be damaged. Zip the text file of cards and its \
                    images again, and import that.
                    """
            )
        case .noTextFileInZip:
            String(
                localized: """
                    “\(name)” holds no text file of cards: Ficha looks for one ending in .txt, .csv or .tsv beside \
                    the images. Add it, zip them again, and import that.
                    """
            )
        case .severalTextFilesInZip(let files):
            String(
                localized: """
                    “\(name)” holds several text files of cards, \(quotedList(files)), and Ficha imports one at a \
                    time. Zip each with its images on its own, and import them one by one.
                    """
            )
        case .unreadableAnkiPackage:
            String(
                localized: """
                    Ficha couldn't read “\(name)” as an Anki package: it may be damaged. Export the deck from Anki \
                    again, and import that.
                    """
            )
        case .ankiPackageNotReadableYet:
            String(
                localized: """
                    “\(name)” is in the format current Anki exports by default, which Ficha can't read yet. In \
                    Anki, export the deck again with “Support older Anki versions” ticked, and import that.
                    """
            )
        case .ankiPackageTooNew:
            String(
                localized: """
                    “\(name)” was exported by an Anki newer than Ficha knows. In Anki, export the deck again with \
                    “Support older Anki versions” ticked, and import that.
                    """
            )
        }
    }
}

/// `words` in quotes, listed as the Mac's language lists them, like “ética”
/// and “filosofía” in English.
private func quotedList(_ words: [String]) -> String {
    words.map { "“\($0)”" }.formatted(.list(type: .and))
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
            case .notAnAnswer: .placementIsNotAnAnswer(cardID)
            }
    }
}
