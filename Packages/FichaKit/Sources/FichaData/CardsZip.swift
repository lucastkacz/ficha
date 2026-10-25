import CryptoKit
import FichaCore
import Foundation
import ImageIO
import UniformTypeIdentifiers
internal import ZIPFoundation

// A zip of cards, as Ficha exports cards with images and imports them: a
// text file of cards, as `CardsTextFile` reads and writes it, with the image
// files its lines name beside it. ZIPFoundation reads and writes the zip
// (ADR 0014).

/// The extensions of the text file of cards a zip of cards holds, as the
/// Import sheet opens one: plain text, or a spreadsheet's CSV or TSV.
private let textFileExtensions: Set = ["txt", "csv", "tsv"]

/// Whether `data` is a zip: it starts as every zip does, with an entry's
/// header, or, for an empty one, with the record that ends a zip.
private func isZip(_ data: Data) -> Bool {
    data.starts(with: [0x50, 0x4B, 0x03, 0x04]) || data.starts(with: [0x50, 0x4B, 0x05, 0x06])
}

/// The zip at `file`, open to read its files as they're needed, or nil when
/// `file` isn't a zip, by how it starts.
func zipArchive(at file: URL) throws(CardsFileProblem) -> Archive? {
    guard isZip(try fileContents(of: file, upTo: 4)) else {
        return nil
    }
    do {
        return try Archive(url: file, accessMode: .read, pathEncoding: nil)
    } catch {
        logger.error("Couldn't open a zip to import: \(String(describing: error), privacy: .public)")
        throw .unreadableZip
    }
}

/// What `file` holds, or its first `count` bytes, as many as it has.
func fileContents(of file: URL, upTo count: Int? = nil) throws(CardsFileProblem) -> Data {
    do {
        guard let count else {
            return try Data(contentsOf: file)
        }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        return try handle.read(upToCount: count) ?? Data()
    } catch {
        // Private, as the error names the file, which says who the user is.
        logger.error("Couldn't read a file to import: \(String(describing: error))")
        throw .cannotOpen
    }
}

/// A zip that holds `text`, a text file of cards named `textFileName`, and
/// `images` beside it, each in a file named as Ficha keeps it, which the
/// text's image columns name, every file dated `date`. The text is
/// compressed, and the images aren't, as zip tools leave a JPEG or a PNG,
/// which is compressed already.
func zipOfCards(text: String, named textFileName: String, images: [CardImage], at date: Date) throws -> Data {
    let archive = try Archive(data: Data(), accessMode: .create, pathEncoding: nil)
    let files =
        [(textFileName, Data(text.utf8), CompressionMethod.deflate)]
        + images.map { ($0.name.rawValue, $0.data, CompressionMethod.none) }
    for (path, data, compression) in files {
        try archive.addEntry(
            with: path, type: .file, uncompressedSize: Int64(data.count), modificationDate: date,
            compressionMethod: compression
        ) { position, size in
            data.subdata(in: Int(position)..<Int(position) + size)
        }
    }
    guard let data = archive.data else {
        throw unreadable("ZIPFoundation made a zip in memory without its data")
    }
    return data
}

/// What a zip of cards holds: its text file, read as `CardsTextFile` reads
/// one, and each image a line names, by its name, from the zip's file by
/// that name beside the text file, as it comes in, by the name Ficha keeps
/// it by. The text file is the zip's one file ending in .txt, .csv or .tsv,
/// at its top or in a folder, as Finder zips one, leaving out the files
/// Finder adds, in `__MACOSX` or named with a leading dot. An image's name
/// is found in any case, as a Mac finds a file. Each image is read on its
/// own, and one the zip holds damaged is one Ficha can't read.
func readZipOfCards(_ archive: Archive) throws(CardsFileProblem) -> (
    reading: ImportReading, images: [ImageName: CardImage]
) {
    let files = archive.filter { $0.type == .file && !isAddedByFinder($0.path) }
    let textFiles = files.filter { textFileExtensions.contains(pathExtension(of: $0.path)) }
    guard let textFile = textFiles.first else {
        throw .noTextFileInZip
    }
    guard textFiles.count == 1 else {
        throw .severalTextFilesInZip(textFiles.map(\.path).sorted())
    }
    // The text file's folder in the zip, ending in a slash, or empty at its
    // top.
    let folder = textFile.path.split(separator: "/").dropLast().map { "\($0)/" }.joined()
    let filesByPath = Dictionary(files.map { ($0.path.lowercased(), $0) }) { first, _ in first }
    let text: Data
    do {
        text = try contents(of: textFile, in: archive)
    } catch {
        logger.error("Couldn't read the text file of a zip to import: \(String(describing: error), privacy: .public)")
        throw .unreadableZip
    }
    var images = ImagesComingIn { name in
        try filesByPath[(folder + name).lowercased()].map { try contents(of: $0, in: archive) }
    } bring: { data, name throws(EngineError) in
        try CardImage(fromZip: data, named: name)
    }
    let reading = try CardsTextFile.read(text) { images.lookUp($0) }
    return (reading, images.found)
}

/// Whether the file at `path` in a zip is one Finder adds when it zips
/// files, which a zip of cards leaves out: one in `__MACOSX`, or any whose
/// name, or a folder's in its path, starts with a dot.
private func isAddedByFinder(_ path: String) -> Bool {
    let parts = path.split(separator: "/")
    return parts.first == "__MACOSX" || parts.contains { $0.hasPrefix(".") }
}

/// The extension of the file at `path`, in lowercase, or empty without one.
func pathExtension(of path: String) -> String {
    URL(filePath: path).pathExtension.lowercased()
}

/// What `entry` of `archive` holds, uncompressed, checked against its
/// checksum.
func contents(of entry: Entry, in archive: Archive) throws -> Data {
    var data = Data()
    _ = try archive.extract(entry) { chunk in
        data.append(chunk)
    }
    return data
}

extension CardImage {
    /// The image `data`, which a zip of cards holds by `name`: as it is when
    /// it's an image Ficha shrank and named, as a zip Ficha exported holds
    /// them, so that cards passed on keep their images byte for byte and the
    /// same names; shrunk, as every image that comes in, otherwise.
    init(fromZip data: Data, named name: String) throws(EngineError) {
        if let image = CardImage(asFichaKeepsIt: data, named: name) {
            self = image
        } else {
            try self.init(shrinking: data)
        }
    }

    /// `data`, named `fileName`, as Ficha keeps it, when it's an image Ficha
    /// already shrank: its name is an image's name, which the SHA-256 of
    /// `data` makes, and it's a JPEG or a PNG, as its name says, upright, no
    /// longer than `longestImageSide` on its long side, without saying where
    /// it was taken. Nil otherwise.
    private init?(asFichaKeepsIt data: Data, named fileName: String) {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard let name = ImageName(rawValue: fileName), fileName.hasPrefix("\(hash).") else {
            return nil
        }
        let type = fileName.hasSuffix(".png") ? UTType.png : UTType.jpeg
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetType(source) as String? == type.identifier,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            max(width, height) <= longestImageSide,
            (properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1,
            properties[kCGImagePropertyGPSDictionary] == nil
        else {
            return nil
        }
        self.init(name: name, data: data)
    }
}
