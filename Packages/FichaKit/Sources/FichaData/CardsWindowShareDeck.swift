import FichaCore
import Foundation

// Share Deck…, among the actions of a deck the user has added, Ficha's too
// (ADR 0044, #557): the window writes the deck's `.ficha` (`DeckFile.swift`),
// named after the deck, in a temporary folder of its own, and the app hands
// it to macOS's Share menu, through AppKit's `NSSharingServicePicker`, whose
// last item, the app's own Save to File…, saves it where the user picks. The
// file stays while a service of macOS's may still read it, as AirDrop does
// while it sends, and goes once nothing needs it: when the Share menu closes
// with nothing chosen, once Save to File… is done, or else when Share Deck…
// writes the next one; the system's temporary folder takes what a quit app
// leaves.

extension CardsWindowState {
    /// The deck's `.ficha` macOS's Share menu offers, while it's open: nil
    /// once it closed.
    public var deckFileToShare: URL? {
        isShareMenuOpen ? sharedDeckFile : nil
    }

    /// Chooses Share Deck… in the menu of the deck `deck`, by its whole name,
    /// or Default's by `Deck.defaultName`, while the menu offers it: the
    /// sidebar chooses the deck, as Description… does, so the Share menu
    /// opens from the Actions menu above its cards; the window lets go of the
    /// file it wrote before, writes the deck's `.ficha`, named after the
    /// deck, to a temporary folder of its own, opens the Share menu on it
    /// (`deckFileToShare`), and returns the file; or records why it
    /// couldn't, and returns nil.
    public mutating func shareDeck(_ deck: String) -> URL? {
        guard let menu = menu(forDeck: deck), menu.canShare else { return nil }
        choose(.cards(.deck(deck)))
        removeSharedDeckFile()
        let folder = URL.temporaryDirectory.appending(
            path: "Shared decks/\(UUID().uuidString)", directoryHint: .isDirectory)
        let file = folder.appending(path: "\(Self.fileName(ofDeck: deck)).\(DeckFile.fileExtension)")
        let written = perform(.shareDeck(deck: deck)) { engine throws(EngineError) in
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                logger.error("Couldn't make a shared deck's folder:\(String(describing: error), privacy: .public)")
                throw .unwritableFile(file.lastPathComponent)
            }
            _ = try engine.export(.deck(deck), to: file)
        }
        guard written else {
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
        sharedDeckFile = file
        isShareMenuOpen = true
        return file
    }

    /// The Share menu closed on a service of macOS's, such as AirDrop,
    /// Messages or Mail, which may still read the file: it stays until Share
    /// Deck… writes another, or Save to File…, which the menu closed on too,
    /// is done.
    public mutating func closeShareMenu() {
        isShareMenuOpen = false
    }

    /// Nothing needs the file Share Deck… wrote any longer: the Share menu
    /// closed with nothing chosen, or Save to File…'s save panel was
    /// cancelled. The file goes.
    public mutating func doneSharingDeck() {
        isShareMenuOpen = false
        removeSharedDeckFile()
    }

    /// Chooses Save in Save to File…'s save panel, at `file`: copies the
    /// deck's `.ficha` Share Deck… wrote there, in place of one there, and
    /// lets go of its own; or records why it couldn't, and keeps it.
    public mutating func saveSharedDeck(to file: URL) {
        guard let shared = sharedDeckFile else { return }
        let saved = perform(.saveSharedDeck(fileName: file.lastPathComponent)) { _ throws(EngineError) in
            // A file the user chose in a save panel, in an app with a
            // sandbox; outside one, there's nothing to start.
            let isAccessing = file.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    file.stopAccessingSecurityScopedResource()
                }
            }
            do {
                try Data(contentsOf: shared).write(to: file, options: .atomic)
            } catch {
                logger.error("Couldn't save a shared deck: \(String(describing: error), privacy: .public)")
                throw .unwritableFile(file.lastPathComponent)
            }
        }
        if saved {
            doneSharingDeck()
        }
    }

    /// Removes the folder of the file Share Deck… last wrote, if any.
    private mutating func removeSharedDeckFile() {
        guard let file = sharedDeckFile else { return }
        sharedDeckFile = nil
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    /// The name of the `.ficha` of the deck `deck`, without its extension:
    /// its whole name as the app shows it, with " › " between its levels, as
    /// in "Idiomas › Inglés", or Default's; a slash, which a file's name
    /// can't hold, written as a colon, which Finder and the save panel show
    /// as a slash.
    static func fileName(ofDeck deck: String) -> String {
        Deck.shownName(deck).replacingOccurrences(of: "/", with: ":")
    }
}
