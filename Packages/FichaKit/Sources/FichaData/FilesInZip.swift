import FichaCore
import Foundation

/// The files of a kind, images or sounds, that a zip of cards or an Anki
/// package names for its cards' sides, as an import reads them: each name
/// looked up once, however many sides name it, the file by that name read
/// with `contents`, and brought in with the `bring` it's first looked up
/// with, by the name Ficha keeps it by. A name the zip holds nothing by is
/// missing. What isn't a file of its kind Ficha reads, or can't be read
/// whole, as in a damaged file, is one Ficha can't read, which the engine
/// logs: its side comes in without it, or its card stays out, saying why,
/// and the rest of the zip comes in. One module brings every kind, so a kind
/// never comes in from a zip its own way.
struct FilesInZip<File: CardFile> {
    /// The files found, by the names Ficha keeps them by.
    private(set) var found: [File.Name: File] = [:]
    /// What was found for each name looked up.
    private var lookups: [String: FileLookup<File.Name>] = [:]
    /// What the zip holds by a name, or nil when it holds nothing by it.
    private let contents: (String) throws -> Data?

    init(contents: @escaping (String) throws -> Data?) {
        self.contents = contents
    }

    /// What the zip holds by `name`: a file of its kind, as `bring` brings it
    /// in from its data; something Ficha can't read as one; or nothing.
    mutating func lookUp(_ name: String, bringing bring: (Data) throws(EngineError) -> File) -> FileLookup<File.Name> {
        if let lookup = lookups[name] {
            return lookup
        }
        return record(Result { try contents(name).map { data throws(EngineError) in try bring(data) } }, for: name)
    }

    /// What the zip holds by `name`, as `lookUp(_:bringing:)` says, with a
    /// `bring` that takes a while, as a sound's conversion does.
    mutating func lookUp(_ name: String, bringing bring: (Data) async throws(EngineError) -> File) async
        -> FileLookup<File.Name>
    {
        if let lookup = lookups[name] {
            return lookup
        }
        let outcome: Result<File?, any Error>
        do {
            if let data = try contents(name) {
                outcome = .success(try await bring(data))
            } else {
                outcome = .success(nil)
            }
        } catch {
            outcome = .failure(error)
        }
        return record(outcome, for: name)
    }

    /// Keeps what looking up `name` came to, `outcome`, the file found,
    /// nothing, or why it couldn't be read, and returns it as a lookup.
    private mutating func record(_ outcome: Result<File?, any Error>, for name: String) -> FileLookup<File.Name> {
        let lookup: FileLookup<File.Name>
        switch outcome {
        case .success(let file?):
            found[file.name] = file
            lookup = .found(file.name)
        case .success(nil):
            lookup = .missing
        case .failure(let error):
            if error as? EngineError != File.Name.notOfItsKind {
                logger.error(
                    "Couldn't read the \(File.Name.kind, privacy: .public) \(name) a zip names: \(String(describing: error), privacy: .public)"
                )
            }
            lookup = .unreadable
        }
        lookups[name] = lookup
        return lookup
    }
}
