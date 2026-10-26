import FichaCore
import Foundation

extension CardsWindowState {
    /// The Cards window's Import sheet while it's open: before a file is
    /// chosen, then the preview of the one chosen, with what the user chooses
    /// for the import, and then what the import did; and what couldn't be
    /// done, while the sheet says so.
    public struct Importing: Sendable, Equatable {
        /// Where the sheet is.
        public enum Step: Sendable, Equatable {
            /// Before a file is chosen.
            case choosingFile
            /// The preview of the file chosen, which Import goes on from.
            case preview(ImportPreview)
            /// What the import did.
            case done(ImportOutcome)
        }

        /// What the sheet is busy with, away from the main actor, while it
        /// is.
        public enum Busy: Sendable, Equatable {
            /// Reading the file with this name, for its preview.
            case reading(String)
            /// Importing the preview's cards.
            case importing
        }

        public fileprivate(set) var step = Step.choosingFile
        /// What the sheet is busy with, while it is: until it's done, the
        /// sheet takes no other file and doesn't import.
        public fileprivate(set) var busy: Busy?
        /// The work the sheet waits for, while it's busy: what any other
        /// work did, as one the sheet started before it closed, it leaves
        /// alone.
        fileprivate var awaitedWork: UUID?
        /// A field for each tag the preview proposes, in its order.
        public fileprivate(set) var tagFields: [TagField] = []
        /// What happens to the file's cards that repeat the user's: Update,
        /// until the user chooses Skip.
        public fileprivate(set) var repeatedCards = ImportChoices.RepeatedCards.update
        /// Whether Bring progress is ticked: until the user unticks it, an
        /// Anki package's cards come in where they stood in Anki (ADR 0013).
        public fileprivate(set) var bringsProgress = true
        /// What couldn't be done, while the sheet says so.
        public fileprivate(set) var failure: ImportFailure?

        /// The preview of the file chosen, while the sheet shows it.
        public var preview: ImportPreview? {
            guard case .preview(let preview) = step else {
                return nil
            }
            return preview
        }

        /// Whether Import is on: while the sheet shows a preview whose import
        /// brings in a card, or updates one, as the user chose, and isn't
        /// busy.
        public var canImport: Bool {
            guard let preview, busy == nil else {
                return false
            }
            return preview.newCount > 0 || (repeatedCards == .update && preview.repeatedCount > 0)
        }

        /// Whether the sheet offers Bring progress: for the preview of an
        /// Anki package, whose cards stood somewhere in Anki.
        public var offersProgress: Bool {
            preview?.kind == .ankiPackage
        }

        /// How many of the file's cards come in, as the line under the
        /// preview's title says it.
        public enum CardsComingIn: Sendable, Equatable {
            /// This many, new, at the pace of the user's new cards per day.
            case new(Int)
            /// This many new, and this many on a step, as Anki had them.
            case newAndPlaced(new: Int, placed: Int)
        }

        /// How many of the file's cards come in, while the sheet shows a
        /// preview: those new to Ficha, and while Bring progress is ticked
        /// and some of them land on a step, how many do.
        public var cardsComingIn: CardsComingIn? {
            guard let preview else {
                return nil
            }
            guard offersProgress, bringsProgress, preview.placedCount > 0 else {
                return .new(preview.newCount)
            }
            return .newAndPlaced(new: preview.newCount - preview.placedCount, placed: preview.placedCount)
        }

        /// How many of the file's cards come in going both ways made of two
        /// of its cards, one for each way, as the preview says, so that the
        /// user sees why fewer cards come in than Anki had: an Anki package's
        /// notes that make a reversed card, but, while Bring progress is
        /// ticked, those whose reversed card alone Anki suspended, which come
        /// in one way (ADR 0016).
        public var notesComingInBothWays: Int {
            guard let preview else {
                return 0
            }
            let bringsProgress = offersProgress && bringsProgress
            return preview.cards.count {
                $0.backFirstProgress != nil && $0.goesBothWays(bringingProgress: bringsProgress)
            }
        }

        /// What the user chose, for the import, with the cards' progress
        /// brought onto `ladder`, the user's, when the sheet offers it and
        /// it's ticked.
        fileprivate func choices(on ladder: Ladder) -> ImportChoices {
            ImportChoices(
                tagNames: Dictionary(tagFields.map { ($0.proposed, $0.name) }) { first, _ in first },
                repeatedCards: repeatedCards,
                progress: offersProgress && bringsProgress ? .brought(onto: ladder) : .leftOut)
        }
    }

    /// The field that names a tag the preview proposes.
    public struct TagField: Sendable, Equatable {
        /// The tag as proposed, like the file's name, or an Anki deck's.
        public let proposed: String
        /// What the field holds: at first the proposed name. A blank one
        /// leaves the tag out.
        public fileprivate(set) var name: String

        /// Whether the field leaves the tag out, being blank, so that
        /// there's nothing for Leave Out to clear.
        public var isLeftOut: Bool {
            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        public init(proposed: String, name: String) {
            self.proposed = proposed
            self.name = name
        }
    }

    /// What couldn't be done in the Import sheet, and why.
    public struct ImportFailure: Sendable, Equatable {
        /// What the user did.
        public enum Action: Sendable, Equatable {
            /// They chose a file, which couldn't be read.
            case preview
            /// They chose Import, which couldn't import the cards.
            case importCards
        }

        public let action: Action
        public let error: EngineError

        public init(action: Action, error: EngineError) {
            self.action = action
            self.error = error
        }
    }

    /// Opens the Import sheet, before a file is chosen.
    public mutating func startImport() {
        importing = Importing()
    }

    /// Starts reading `file`, the one the user chose, while the sheet isn't
    /// busy, and returns the work, which the app runs away from the main
    /// actor and hands to `finishImportWork(_:)`: the sheet then shows the
    /// file's preview, with the tags it proposes in their fields, its
    /// repeated cards updated and Bring progress ticked, or says why it
    /// couldn't read it, and stays where it was.
    public mutating func previewImport(of file: URL) -> ImportWork? {
        startImportWork(.preview(file), busy: .reading(file.lastPathComponent))
    }

    /// Gives the field of the tag the preview proposes as `proposed` what
    /// the user typed in it, `name`.
    public mutating func nameImportTag(_ proposed: String, as name: String) {
        guard let index = importing?.tagFields.firstIndex(where: { $0.proposed == proposed }) else { return }
        importing?.tagFields[index].name = name
    }

    /// Leaves out the tag the preview proposes as `proposed`, clearing its
    /// field, where the user can type a name again.
    public mutating func removeImportTag(_ proposed: String) {
        nameImportTag(proposed, as: "")
    }

    /// Chooses what happens to the file's cards that repeat the user's.
    public mutating func chooseForRepeatedCards(_ choice: ImportChoices.RepeatedCards) {
        guard importing?.preview != nil else { return }
        importing?.repeatedCards = choice
    }

    /// Ticks or unticks Bring progress, while the sheet offers it.
    public mutating func chooseToBringProgress(_ brings: Bool) {
        guard importing?.offersProgress == true else { return }
        importing?.bringsProgress = brings
    }

    /// Starts importing the file the sheet shows the preview of, as the user
    /// chose, while Import is on, and returns the work, which the app runs
    /// away from the main actor and hands to `finishImportWork(_:)`: the
    /// sheet then says what the import did, or why it couldn't import the
    /// cards, and the preview stays. An Anki package's cards bring their
    /// progress onto the window's ladder while Bring progress is ticked.
    public mutating func importCards() -> ImportWork? {
        guard let importing, importing.canImport, let preview = importing.preview else { return nil }
        return startImportWork(.importCards(preview, importing.choices(on: ladder)), busy: .importing)
    }

    /// Starts `job` while the sheet is open and isn't busy, and returns its
    /// work, which the sheet is `busy` with until it's done.
    private mutating func startImportWork(_ job: ImportWork.Job, busy: Importing.Busy) -> ImportWork? {
        guard importing != nil, importing?.busy == nil else { return nil }
        let work = ImportWork(id: UUID(), engine: engine, job: job)
        importing?.busy = busy
        importing?.awaitedWork = work.id
        return work
    }

    /// Takes what the work the sheet started did, once the app ran it: the
    /// preview it read, or what the import did, or why it couldn't, as
    /// `previewImport(of:)` and `importCards()` say. The table lists the
    /// cards as they are once an import is done, even after the sheet
    /// closed. What other work did, which the sheet doesn't wait for, it
    /// leaves alone.
    public mutating func finishImportWork(_ done: ImportWork.Done) {
        if case .imported(.success) = done.result {
            read(on: ladder)
        }
        guard importing?.awaitedWork == done.id else { return }
        importing?.busy = nil
        importing?.awaitedWork = nil
        switch done.result {
        case .preview(.success(let preview)):
            importing = Importing(
                step: .preview(preview),
                tagFields: preview.proposedTags.map { TagField(proposed: $0, name: $0) })
        case .preview(.failure(let error)):
            importing?.failure = ImportFailure(action: .preview, error: error)
        case .imported(.success(let outcome)):
            importing?.step = .done(outcome)
        case .imported(.failure(let error)):
            importing?.failure = ImportFailure(action: .importCards, error: error)
        }
    }

    /// Clears what failed in the Import sheet, once the sheet said so and
    /// the user closed it.
    public mutating func dismissImportFailure() {
        importing?.failure = nil
    }

    /// Closes the Import sheet.
    public mutating func closeImport() {
        importing = nil
    }
}

/// Work the Import sheet starts: reading a file for its preview, or
/// importing the cards. A big file takes a while, so the app runs it away
/// from the main actor, and hands what it did to the window's
/// `finishImportWork(_:)`.
public struct ImportWork: Sendable {
    fileprivate enum Job: Sendable {
        case preview(URL)
        case importCards(ImportPreview, ImportChoices)
    }

    /// What the work did.
    public struct Done: Sendable {
        fileprivate enum Result: Sendable {
            case preview(Swift.Result<ImportPreview, EngineError>)
            case imported(Swift.Result<ImportOutcome, EngineError>)
        }

        fileprivate let id: UUID
        fileprivate let result: Result
    }

    fileprivate let id: UUID
    fileprivate let engine: Engine
    fileprivate let job: Job

    /// Does the work, away from the caller's actor, and says what it did.
    public func run() async -> Done {
        switch job {
        case .preview(let file):
            do {
                return Done(id: id, result: .preview(.success(try await engine.previewImport(of: file))))
            } catch {
                return Done(id: id, result: .preview(.failure(error)))
            }
        case .importCards(let preview, let choices):
            return Done(
                id: id,
                result: .imported(
                    Result { () throws(EngineError) in try engine.importCards(preview, choosing: choices) }))
        }
    }
}
