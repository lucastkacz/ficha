import Foundation

/// The text file of cards Ficha imports, in the shape of Anki's "Notes in
/// Plain Text": UTF-8 text, one card per line, its columns separated by
/// tabs, commas or semicolons, with a field in quotes when it holds the
/// separator, a quote or a line break, and a quote inside it doubled. Its
/// columns are, in order, the card's front, back, tags, type and source, of
/// which a line may leave out the last three. A line starting with `#` is a
/// comment, and so is a blank one. In a zip with the images and the sounds
/// of its cards, a column for each side and each kind, which the `#columns`
/// header names, names its image or its sound.
public enum CardsTextFile {
    /// A column of the file.
    public enum Column: String, Sendable, CaseIterable {
        case front = "Front"
        case back = "Back"
        case tags = "Tags"
        case type = "Type"
        case source = "Source"
        /// The name of the front's image, a file in the zip beside the text
        /// file, or blank for none.
        case frontImage = "Front image"
        /// The name of the back's image, as the front's.
        case backImage = "Back image"
        /// The name of the front's sound, a file in the zip beside the text
        /// file, or blank for none.
        case frontSound = "Front sound"
        /// The name of the back's sound, as the front's.
        case backSound = "Back sound"

        /// Whether it names a side's image.
        var isImage: Bool {
            self == .frontImage || self == .backImage
        }

        /// Whether it names a side's sound.
        var isSound: Bool {
            self == .frontSound || self == .backSound
        }

        /// Whether it names a side's file, an image or a sound: a column that
        /// a file has only when its `#columns` header names it, and an export
        /// writes only with a file of its kind.
        var isFile: Bool {
            isImage || isSound
        }
    }

    /// The cards in the file `data` holds, in its order, and the lines it
    /// left out, with why, or why it can't be read at all. `images` and
    /// `sounds` look up each image and each sound a line names for a side,
    /// by the name it gives: a side left with neither text, an image nor a
    /// sound by a file that isn't found leaves the line out, and one with
    /// something else comes in without that file. Without them, as for a
    /// text file alone, no file is found. A sound takes a while to come in,
    /// so `sounds` may wait.
    public static func read(
        _ data: Data, images: (String) -> ImageLookup = { _ in .missing },
        sounds: (String) async -> SoundLookup = { _ in .missing }
    ) async throws(CardsFileProblem) -> ImportReading {
        guard let text = String(validating: data, as: UTF8.self) else {
            throw .notUTF8
        }
        var file = Lines(text)
        let headers = try Headers(file.headerLines())
        let separator = headers.separator ?? file.guessedSeparator()
        let columns = try ColumnMap(headers, separatedBy: separator)
        var cards: [ImportedCard] = []
        var leftOut: [LeftOutLine] = []
        while let record = file.nextRecord(separatedBy: separator) {
            switch record {
            case .fields(let fields, let line):
                do throws(LeftOut) {
                    cards.append(
                        try await card(
                            in: fields, on: line, columns: columns, isHTML: headers.isHTML, images: images,
                            sounds: sounds))
                } catch {
                    leftOut.append(error.line)
                }
            case .leftOut(let line):
                leftOut.append(line)
            }
        }
        return ImportReading(cards: cards, leftOut: leftOut)
    }

    /// The tags a tags column holds: separated by spaces, as Anki separates
    /// them, with an underscore standing for a space inside a tag, since a
    /// tag in Ficha can hold one. A tag repeated is the tag once.
    public static func tags(inColumn text: String) -> [String] {
        var tags: [String] = []
        for word in text.split(whereSeparator: \.isWhitespace) {
            let tag = word.replacingOccurrences(of: "_", with: " ")
            if !tags.contains(tag) {
                tags.append(tag)
            }
        }
        return tags
    }

    /// The text of a file holding `cards`, in their order, as Ficha exports
    /// them: `read` reads it back as the same cards, and Anki as notes with a
    /// front, a back and tags. Its headers say that tabs separate its
    /// columns, that its fields hold no HTML, which columns it has, by their
    /// names, and which one holds the tags; then each card has a line with
    /// its front, back, tags, type and source, and a blank field for what it
    /// lacks. When a card has an image, every line also names the image of
    /// its front and of its back, by the name Ficha keeps it by, which is
    /// the name of its file in the zip the text goes in; and when a card has
    /// a sound, the sound of each side, the same way.
    public static func text(of cards: [CardContent]) -> String {
        let hasImages = cards.contains { !$0.images.isEmpty }
        let hasSounds = cards.contains { !$0.sounds.isEmpty }
        let columns = Column.allCases.filter { (hasImages || !$0.isImage) && (hasSounds || !$0.isSound) }
        var lines = [
            "#separator:tab",
            "#html:false",
            "#columns:" + columns.map(\.rawValue).joined(separator: "\t"),
        ]
        if let tags = columns.firstIndex(of: .tags) {
            lines.append("#tags column:\(tags + 1)")
        }
        for card in cards {
            lines.append(columns.map { written(field($0, of: card)) }.joined(separator: "\t"))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// What `card` holds in `column`, before it's written.
    private static func field(_ column: Column, of card: CardContent) -> String {
        switch column {
        case .front: card.front
        case .back: card.back
        case .tags: tagsColumn(holding: card.tags)
        case .type: card.type?.rawValue ?? ""
        case .source: card.source ?? ""
        case .frontImage: card.frontImage?.rawValue ?? ""
        case .backImage: card.backImage?.rawValue ?? ""
        case .frontSound: card.frontSound?.rawValue ?? ""
        case .backSound: card.backSound?.rawValue ?? ""
        }
    }

    /// What a tags column holds for `tags`, which `tags(inColumn:)` reads
    /// back: the tags separated by spaces, with an underscore for each space
    /// inside a tag.
    private static func tagsColumn(holding tags: [String]) -> String {
        tags.map { tag in String(tag.map { $0.isWhitespace ? "_" : $0 }) }.joined(separator: " ")
    }

    /// `field` as a line of the file holds it: in quotes, with each quote in
    /// it doubled, when it holds a tab, a quote or a line break, or starts
    /// with `#`, which would make the line a comment; as it is otherwise.
    private static func written(_ field: String) -> String {
        let needsQuotes =
            field.unicodeScalars.first == "#"
            || field.unicodeScalars.contains { ["\t", "\"", "\n", "\r"].contains($0) }
        guard needsQuotes else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// The card that `fields`, the columns of the record on `line`, make,
    /// each the column `columns` says, and as plain text when `isHTML`, but
    /// its tags and its files' names, with the images `images` finds and the
    /// sounds `sounds` finds; or the line left out, with why it makes none.
    private static func card(
        in fields: [String], on line: Int, columns: ColumnMap, isHTML: Bool, images: (String) -> ImageLookup,
        sounds: (String) async -> SoundLookup
    ) async throws(LeftOut) -> ImportedCard {
        guard fields.count > 1 else {
            throw LeftOut(line: line, reason: .oneColumn)
        }
        var values: [Column: String] = [:]
        for (index, field) in fields.enumerated() {
            if let column = columns.column(at: index), values[column] == nil {
                values[column] = isHTML && column != .tags && !column.isFile ? plainText(fromHTML: field) : field
            }
        }
        var type: CardType?
        if let typeName = values[.type]?.trimmingCharacters(in: .whitespacesAndNewlines), !typeName.isEmpty {
            guard let known = CardType(rawValue: typeName.lowercased()) else {
                throw LeftOut(line: line, reason: .unknownType(typeName))
            }
            type = known
        }
        let front = values[.front] ?? ""
        let back = values[.back] ?? ""
        let (frontImage, frontSound) = try await files(
            beside: front, image: values[.frontImage], sound: values[.frontSound], on: line, images: images,
            sounds: sounds)
        let (backImage, backSound) = try await files(
            beside: back, image: values[.backImage], sound: values[.backSound], on: line, images: images,
            sounds: sounds)
        guard
            let content = CardContent(
                type: type, front: front, back: back, tags: tags(inColumn: values[.tags] ?? ""),
                source: values[.source], frontImage: frontImage, backImage: backImage, frontSound: frontSound,
                backSound: backSound)
        else {
            throw LeftOut(
                line: line,
                reason: CardContent.isBlank(front, image: frontImage, sound: frontSound) ? .blankFront : .blankBack)
        }
        let given: [(Column, CardField)] = [
            (.tags, .tags), (.type, .type), (.source, .source), (.backImage, .backImage), (.backSound, .backSound),
        ]
        return ImportedCard(
            content: content, fields: Set(given.filter { values[$0.0] != nil }.map(\.1)), line: line)
    }

    /// The image and the sound a side with `text` gets from what its image
    /// and sound columns hold, if anything, `imageName` and `soundName`,
    /// which `images` and `sounds` look up: each file found, or none when its
    /// column is blank or it isn't found. A side left with neither text, an
    /// image nor a sound by a file that isn't found leaves the line on
    /// `line` out, saying why for its image, or else for its sound.
    private static func files(
        beside text: String, image imageName: String?, sound soundName: String?, on line: Int,
        images: (String) -> ImageLookup, sounds: (String) async -> SoundLookup
    ) async throws(LeftOut) -> (image: ImageName?, sound: SoundName?) {
        let imageName = nonBlank(imageName)
        let soundName = nonBlank(soundName)
        let imageLookup = imageName.map(images)
        var soundLookup: SoundLookup?
        if let soundName {
            soundLookup = await sounds(soundName)
        }
        let image: ImageName? = if case .found(let image)? = imageLookup { image } else { nil }
        let sound: SoundName? = if case .found(let sound)? = soundLookup { sound } else { nil }
        guard CardContent.isBlank(text, image: image, sound: sound) else {
            return (image, sound)
        }
        // A side left blank found neither file its columns name.
        if let imageName, let imageLookup {
            throw LeftOut(
                line: line, reason: imageLookup == .unreadable ? .notAnImage(imageName) : .missingImage(imageName))
        }
        if let soundName, let soundLookup {
            throw LeftOut(
                line: line, reason: soundLookup == .unreadable ? .notASound(soundName) : .missingSound(soundName))
        }
        return (nil, nil)
    }
}

/// A line left out, as reading it throws it, on its way to the list of lines
/// left out.
private struct LeftOut: Error {
    let line: LeftOutLine

    init(line: Int, reason: LeftOutLine.Reason) {
        self.line = LeftOutLine(line: line, reason: reason)
    }
}

/// Why a file of cards can't be read at all, rather than some of its lines.
public enum CardsFileProblem: Error, Sendable, Equatable {
    /// It couldn't be opened or read, as the engine finds when it opens it.
    case cannotOpen
    /// It isn't UTF-8 text.
    case notUTF8
    /// Its `#separator` header names this, which isn't a separator.
    case unknownSeparator(String)
    /// Its `#html` header says this, which is neither true nor false.
    case unknownHTML(String)
    /// Its header `header`, like `tags column`, which says which column
    /// holds something, says `value`, which isn't a column's number.
    case unknownColumnNumber(header: String, value: String)
    /// Its `#columns` header names no column `column`, which every card
    /// needs: a front or a back.
    case missingColumn(CardsTextFile.Column)
    /// It's a zip that can't be read as one: it's damaged, or not a zip.
    case unreadableZip
    /// It's a zip that holds no text file of cards.
    case noTextFileInZip
    /// It's a zip that holds several text files of cards, these, of which
    /// Ficha wouldn't know which to import.
    case severalTextFilesInZip([String])
    /// It's an Anki package that can't be read: it's damaged, or it doesn't
    /// hold what Anki writes.
    case unreadableAnkiPackage
    /// It's an Anki package in a format newer than any Ficha knows.
    case ankiPackageTooNew
}

/// The separators a `#separator` header can name, by the names it takes for
/// them, as Anki's: a tab, a comma or a semicolon, which Ficha also tells
/// apart without a header, and a space, a pipe or a colon.
private let separatorNames: [String: Unicode.Scalar] = [
    "tab": "\t", "comma": ",", "semicolon": ";", "space": " ", "pipe": "|", "colon": ":",
]

/// What the file's headers say, the `#key:value` lines at its top, as Anki
/// writes and reads them: its keys in any case, and each other `#` line a
/// comment.
private struct Headers {
    /// The separator `#separator` names, or nil without it.
    var separator: Unicode.Scalar?
    /// Whether `#html` says its fields hold HTML, which isn't so without it.
    var isHTML = false
    /// What `#columns` says, the columns' names separated by the file's
    /// separator, or nil without it.
    var columnNames: String?
    /// The column, from 0, that `#tags column` says holds the tags, or nil
    /// without it.
    var tagsColumn: Int?
    /// The columns, from 0, that `#guid column`, `#notetype column` and
    /// `#deck column` say hold an Anki note's id, note type and deck, which
    /// Ficha leaves out.
    var skippedColumns: Set<Int> = []

    init(_ lines: [String]) throws(CardsFileProblem) {
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else {
                continue
            }
            let key = line[line.index(after: line.startIndex)..<colon].trimmingCharacters(in: .whitespaces)
                .lowercased()
            let value = String(line[line.index(after: colon)...])
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            switch key {
            case "separator":
                let literal = value.unicodeScalars.count == 1 ? value.unicodeScalars.first : nil
                guard
                    let separator = separatorNames[trimmed.lowercased()]
                        ?? literal.flatMap({ literal in separatorNames.values.first { $0 == literal } })
                else {
                    throw .unknownSeparator(trimmed)
                }
                self.separator = separator
            case "html":
                switch trimmed.lowercased() {
                case "true": isHTML = true
                case "false": isHTML = false
                default: throw .unknownHTML(trimmed)
                }
            case "columns":
                columnNames = value
            case "tags column":
                tagsColumn = try Self.column(trimmed, in: key)
            case "guid column", "notetype column", "deck column":
                if let column = try Self.column(trimmed, in: key) {
                    skippedColumns.insert(column)
                }
            default:
                break
            }
        }
    }

    /// The column, from 0, that `text` numbers, counted from 1, as the
    /// header `header` says it, or nil for 0, which names none.
    private static func column(_ text: String, in header: String) throws(CardsFileProblem) -> Int? {
        guard let number = Int(text), number >= 0 else {
            throw .unknownColumnNumber(header: header, value: text)
        }
        return number == 0 ? nil : number - 1
    }
}

/// Which column of the file each column of a line is, by its place: the
/// tags where `#tags column` puts them, nothing where the other column
/// headers put what Ficha leaves out, and the others as `#columns` names
/// them, or else, in order, the front, the back, the tags, the type and the
/// source, without the tags when a header puts them elsewhere. A column
/// beyond those, or one `#columns` names otherwise, is left out: the image
/// and sound columns come only by name, so a file without headers reads as
/// before images and sounds.
private struct ColumnMap {
    private let tagsColumn: Int?
    private let skippedColumns: Set<Int>
    /// The columns `#columns` names, by their place, or nil without it.
    private let named: [CardsTextFile.Column?]?
    /// The columns that go by their place, in order, without `#columns`.
    private let unplaced: [CardsTextFile.Column]

    init(_ headers: Headers, separatedBy separator: Unicode.Scalar) throws(CardsFileProblem) {
        tagsColumn = headers.tagsColumn
        skippedColumns = headers.skippedColumns
        unplaced = CardsTextFile.Column.allCases.filter {
            !$0.isFile && ($0 != .tags || headers.tagsColumn == nil)
        }
        guard let columnNames = headers.columnNames else {
            named = nil
            return
        }
        var names = Lines(columnNames)
        var named: [CardsTextFile.Column?] = []
        if case .fields(let fields, _)? = names.nextRecord(separatedBy: separator) {
            for name in fields {
                let column = CardsTextFile.Column.allCases.first {
                    $0.rawValue.lowercased() == name.trimmingCharacters(in: .whitespaces).lowercased()
                }
                // A column named twice is the first one.
                let isLeftOut = column.map { named.contains($0) || ($0 == .tags && headers.tagsColumn != nil) } ?? true
                named.append(isLeftOut ? nil : column)
            }
        }
        for needed in [CardsTextFile.Column.front, .back] where !named.contains(needed) {
            throw .missingColumn(needed)
        }
        self.named = named
    }

    /// The column of the file a line's column at `index`, from 0, is, or nil
    /// when Ficha leaves it out.
    func column(at index: Int) -> CardsTextFile.Column? {
        if index == tagsColumn {
            return .tags
        }
        if skippedColumns.contains(index) {
            return nil
        }
        if let named {
            return index < named.count ? named[index] : nil
        }
        let placedBefore = skippedColumns.count { $0 < index } + ((tagsColumn ?? index) < index ? 1 : 0)
        let place = index - placedBefore
        return place < unplaced.count ? unplaced[place] : nil
    }
}

/// A record of the file: a line's columns, or a line left out, with why.
private enum Record {
    /// The fields of the record that starts on `line`.
    case fields([String], line: Int)
    case leftOut(LeftOutLine)
}

/// The file's text, read from its start: its comments, its blank lines and
/// its records, each a line or several, when a quoted field holds a line
/// break.
private struct Lines {
    private let scalars: [Unicode.Scalar]
    private var index = 0
    /// The line `index` is on, counted from 1.
    private var line = 1

    /// The file's text, without the byte order mark a file may start with,
    /// and with its line breaks as `\n`, whether they were `\r\n` or `\r`.
    init(_ text: String) {
        var scalars = Array(
            text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
                .unicodeScalars)
        if scalars.first == "\u{FEFF}" {
            scalars.removeFirst()
        }
        self.scalars = scalars
    }

    private var current: Unicode.Scalar? {
        index < scalars.count ? scalars[index] : nil
    }

    private mutating func advance() {
        if current == "\n" {
            line += 1
        }
        index += 1
    }

    /// The header lines at the file's top, each starting with `#`, up to the
    /// first line that doesn't, which it moves to.
    mutating func headerLines() -> [String] {
        var lines: [String] = []
        while current == "#" {
            var header = String.UnicodeScalarView()
            while let scalar = current, scalar != "\n" {
                header.append(scalar)
                advance()
            }
            advance()
            lines.append(String(header))
        }
        return lines
    }

    /// Moves to the start of the next line.
    private mutating func skipLine() {
        while let scalar = current, scalar != "\n" {
            advance()
        }
        advance()
    }

    /// Skips comments and blank lines, up to the next record, if there's one.
    private mutating func skipToRecord() {
        while let scalar = current {
            if scalar == "#" {
                skipLine()
                continue
            }
            var next = index
            while next < scalars.count, scalars[next] != "\n", scalars[next].properties.isWhitespace {
                next += 1
            }
            guard next == scalars.count || scalars[next] == "\n" else {
                return
            }
            while index < next {
                advance()
            }
            advance()
        }
    }

    /// The separator the file's first record uses, outside its quoted
    /// fields: a tab if it has one, else a semicolon, else a comma. A record
    /// with none of them has one column, whatever separates the file's.
    func guessedSeparator() -> Unicode.Scalar {
        var lines = self
        lines.skipToRecord()
        var isQuoted = false
        var found: Set<Unicode.Scalar> = []
        while let scalar = lines.current, isQuoted || scalar != "\n" {
            if scalar == "\"" {
                isQuoted.toggle()
            } else if !isQuoted {
                found.insert(scalar)
            }
            lines.advance()
        }
        return ["\t", ";", ","].first { found.contains($0) } ?? "\t"
    }

    /// The next record, with its fields separated by `separator`, or nil at
    /// the end of the file. A record whose quoted field is never closed is
    /// left out, and the next record starts on the line after it; one with a
    /// stray quote is left out up to the end of the line the quote is on.
    mutating func nextRecord(separatedBy separator: Unicode.Scalar) -> Record? {
        skipToRecord()
        guard current != nil else {
            return nil
        }
        let start = (index: index, line: line)
        var fields: [String] = []
        var field = String.UnicodeScalarView()
        while true {
            if current == "\"" {
                advance()
                var isClosed = false
                while let scalar = current {
                    advance()
                    if scalar != "\"" {
                        field.append(scalar)
                    } else if current == "\"" {
                        field.append("\"")
                        advance()
                    } else {
                        isClosed = true
                        break
                    }
                }
                guard isClosed else {
                    (index, line) = start
                    skipLine()
                    return .leftOut(LeftOutLine(line: start.line, reason: .unclosedQuote))
                }
                guard current == nil || current == "\n" || current == separator else {
                    skipLine()
                    return .leftOut(LeftOutLine(line: start.line, reason: .strayQuote))
                }
            } else {
                while let scalar = current, scalar != separator, scalar != "\n" {
                    field.append(scalar)
                    advance()
                }
            }
            fields.append(String(field))
            field = String.UnicodeScalarView()
            let end = current
            advance()
            if end != separator {
                return .fields(fields, line: start.line)
            }
        }
    }
}
