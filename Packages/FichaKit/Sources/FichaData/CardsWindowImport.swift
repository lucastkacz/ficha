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

        public fileprivate(set) var step = Step.choosingFile
        /// A field for each tag the preview proposes, in its order.
        public fileprivate(set) var tagFields: [TagField] = []
        /// What happens to the file's cards that repeat the user's: Update,
        /// until the user chooses Skip.
        public fileprivate(set) var repeatedCards = ImportChoices.RepeatedCards.update
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
        /// brings in a card, or updates one, as the user chose.
        public var canImport: Bool {
            guard let preview else {
                return false
            }
            return preview.newCount > 0 || (repeatedCards == .update && preview.repeatedCount > 0)
        }

        /// What the user chose, for the import.
        fileprivate var choices: ImportChoices {
            ImportChoices(
                tagNames: Dictionary(tagFields.map { ($0.proposed, $0.name) }) { first, _ in first },
                repeatedCards: repeatedCards)
        }
    }

    /// The field that names a tag the preview proposes.
    public struct TagField: Sendable, Equatable {
        /// The tag as proposed, like the file's name, or an Anki deck's.
        public let proposed: String
        /// What the field holds: at first the proposed name. A blank one
        /// leaves the tag out.
        public fileprivate(set) var name: String

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

    /// Reads `file`, the one the user chose, and shows its preview, with the
    /// tags it proposes in their fields and its repeated cards updated, or
    /// says why it couldn't, and the sheet stays where it was.
    public mutating func previewImport(of file: URL) {
        guard importing != nil else { return }
        do throws(EngineError) {
            let preview = try engine.previewImport(of: file)
            importing = Importing(
                step: .preview(preview),
                tagFields: preview.proposedTags.map { TagField(proposed: $0, name: $0) })
        } catch {
            importing?.failure = ImportFailure(action: .preview, error: error)
        }
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

    /// Imports the file the sheet shows the preview of, as the user chose,
    /// while Import is on, and says what it did, or why it couldn't, and the
    /// preview stays. The table lists the cards as they are then.
    public mutating func importCards() {
        guard let importing, importing.canImport, let preview = importing.preview else { return }
        do throws(EngineError) {
            let outcome = try engine.importCards(preview, choosing: importing.choices)
            self.importing?.step = .done(outcome)
            read(on: ladder)
        } catch {
            self.importing?.failure = ImportFailure(action: .importCards, error: error)
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
