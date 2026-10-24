import FichaCore
import Foundation

/// The images a file of cards names for its cards' sides, as an import reads
/// them from a zip of cards or an Anki package: each name looked up once,
/// however many sides name it, the file by that name read with `contents`,
/// and brought in with `bring`, by the name Ficha keeps it by. A name the
/// file holds nothing by is missing. What isn't an image Ficha reads, or
/// can't be read whole, as in a damaged file, is an image Ficha can't read,
/// which the engine logs: its side comes in without it, or its card stays
/// out, saying why, and the rest of the file comes in.
struct ImagesComingIn {
    /// The images found, by the names Ficha keeps them by.
    private(set) var found: [ImageName: CardImage] = [:]
    /// What was found for each name looked up.
    private var lookups: [String: ImageLookup] = [:]
    /// What the file holds by a name, or nil when it holds nothing by it.
    private let contents: (String) throws -> Data?
    /// The image in what the file holds by a name, as it comes in.
    private let bring: (Data, String) throws(EngineError) -> CardImage

    init(contents: @escaping (String) throws -> Data?, bring: @escaping (Data, String) throws(EngineError) -> CardImage)
    {
        self.contents = contents
        self.bring = bring
    }

    /// What the file holds by `name`: an image, as it comes in; something
    /// Ficha can't read as one; or nothing.
    mutating func lookUp(_ name: String) -> ImageLookup {
        if let lookup = lookups[name] {
            return lookup
        }
        let lookup: ImageLookup
        do {
            if let data = try contents(name) {
                let image = try bring(data, name)
                found[image.name] = image
                lookup = .found(image.name)
            } else {
                lookup = .missing
            }
        } catch EngineError.notAnImage {
            lookup = .notAnImage
        } catch {
            logger.error(
                "Couldn't read the image \(name) a file of cards names: \(String(describing: error), privacy: .public)")
            lookup = .notAnImage
        }
        lookups[name] = lookup
        return lookup
    }
}
