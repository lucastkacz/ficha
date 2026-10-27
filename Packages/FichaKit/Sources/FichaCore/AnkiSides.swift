import Foundation

/// A side of an Anki card as Ficha brings it in, from the HTML Anki renders
/// for it, without its sounds, and the sounds it plays: its plain text,
/// without its images, which the HTML's tags are, and with each run of
/// empty lines folded into one empty line; its image, the first of the
/// package's files the HTML shows, when the package has it and Ficha can
/// read it; and its sound, the first it plays, a video's sound included,
/// when the package has it and Ficha can read it. The side's other images
/// and sounds are dropped, since a side holds one of each at most, and so
/// are images on the web, which Ficha never fetches. A side that is one of
/// Anki's formulas alone is the picture Anki drew of it, without text, when
/// the package has it and Ficha can read it.
struct AnkiSide {
    let text: String
    let image: ImageName?
    let sound: SoundName?
    /// Whether the HTML shows other files of the package as images, which
    /// the side drops.
    let dropsImages: Bool
    /// Whether the HTML plays other sounds, which the side drops.
    let dropsSounds: Bool
    /// What was found for the image the side shows, or nil when it shows
    /// none.
    private let imageLookup: ImageLookup?
    /// What was found for the sound the side plays, or nil when it plays
    /// none.
    private let soundLookup: SoundLookup?

    /// The side Anki renders as `html`, without its sounds, which plays the
    /// sounds named `soundNames`, in order: with its image as `images` finds
    /// it by the name the HTML gives it, or by the name of Anki's picture of
    /// its formula, after the SHA-1 digest `sha1` gives as lowercase hex: a
    /// PNG's, or an SVG's when the package has no PNG by that name; and with
    /// its first sound as `sounds` finds it.
    init(
        html: String, playing soundNames: [String], images: (String) -> ImageLookup, sounds: (String) -> SoundLookup,
        sha1: (String) -> String
    ) {
        dropsSounds = soundNames.count > 1
        if let name = soundNames.first {
            soundLookup = sounds(name)
        } else {
            soundLookup = nil
        }
        if case .found(let sound) = soundLookup {
            self.sound = sound
        } else {
            sound = nil
        }
        let names = fileNames(shownIn: html)
        dropsImages = names.count > 1
        let formula =
            names.isEmpty
            ? pictureOfFormula(shownAloneIn: html, sha1: sha1).map { picture in
                let png = images("\(picture).png")
                return png == .missing ? images("\(picture).svg") : png
            } : nil
        if case .found? = formula {
            text = ""
            imageLookup = formula
        } else {
            text = runsOfEmptyLinesFolded(in: plainText(fromHTML: html))
            imageLookup = names.first.map { name in
                // Some decks keep a name percent-encoded, as a browser's
                // address has it, though Anki writes it as it is.
                let lookup = images(name)
                guard lookup == .missing, let decoded = name.removingPercentEncoding, decoded != name else {
                    return lookup
                }
                return images(decoded)
            }
        }
        if case .found(let image) = imageLookup {
            self.image = image
        } else {
            image = nil
        }
    }

    /// Whether the sound the side plays is one Ficha can't read, which the
    /// side comes in without.
    var leavesOutAnUnreadableSound: Bool {
        soundLookup == .unreadable
    }

    /// Why a card with this side stays out, when the side is left with
    /// neither text, an image nor a sound: the image it shows isn't in the
    /// package, or Ficha can't read it; or else the sound it plays isn't, or
    /// Ficha can't read it; or it shows and plays none. Nil when it isn't
    /// blank.
    var reasonItsCardStaysOut: LeftOutLine.Reason? {
        guard CardContent.isBlank(text, image: image, sound: sound) else {
            return nil
        }
        return switch (imageLookup, soundLookup) {
        case (.missing?, _): .missingAnkiImage
        case (.unreadable?, _): .unreadableAnkiImage
        case (_, .missing?): .missingAnkiSound
        case (_, .unreadable?): .unreadableAnkiSound
        case (.found?, _), (nil, .found?), (nil, nil): .emptyAnkiSide
        }
    }
}

/// `text`, a side's plain text, with each run of empty lines folded into one
/// empty line, and a single one kept (#229). Where Anki shows a sound's
/// button, the line is left empty once the sound is apart from the text, as
/// the five lines between each Core 2000 front's part of speech and its
/// sentence. A file's text keeps its runs, which its writer typed.
private func runsOfEmptyLinesFolded(in text: String) -> String {
    var folded = String.UnicodeScalarView()
    var lineBreaksInARow = 0
    for scalar in text.unicodeScalars {
        lineBreaksInARow = scalar == "\n" ? lineBreaksInARow + 1 : 0
        if lineBreaksInARow <= 2 {
            folded.append(scalar)
        }
    }
    return String(folded)
}

/// The names of the sounds `html` plays, each once, in its order, and `html`
/// without them: the name in each `[sound:…]` tag, as Anki finds a field's
/// sounds (`rslib/src/text.rs`, `AV_TAGS`), from after its colon to the
/// first `]` after at least one character, across lines too, with its
/// character references decoded. A video plays this way too. Read from the
/// HTML's UTF-8 bytes by hand, as `holdsBox(_:)` reads a side, since a regex
/// on every side of a big deck slowed its preview.
func soundTags(in html: String) -> (names: [String], rest: String) {
    let opening = "[sound:".utf8
    let bytes = html.utf8
    var names: [String] = []
    var rest = ""
    var copied = bytes.startIndex
    var searched = bytes[...]
    while let bracket = searched.firstIndex(of: UInt8(ascii: "[")) {
        searched = bytes[bytes.index(after: bracket)...]
        guard bytes[bracket...].starts(with: opening) else {
            continue
        }
        let nameStart = bytes.index(bracket, offsetBy: opening.count)
        guard nameStart < bytes.endIndex,
            let close = bytes[bytes.index(after: nameStart)...].firstIndex(of: UInt8(ascii: "]"))
        else {
            break
        }
        let name = characterReferencesDecoded(in: String(decoding: bytes[nameStart..<close], as: UTF8.self))
        if !names.contains(name) {
            names.append(name)
        }
        rest += String(decoding: bytes[copied..<bracket], as: UTF8.self)
        copied = bytes.index(after: close)
        searched = bytes[copied...]
    }
    guard !names.isEmpty else {
        return ([], html)
    }
    return (names, rest + String(decoding: bytes[copied...], as: UTF8.self))
}

/// The names of the package's files `html` shows as images, each once, in
/// its order: the `src` of each `<img>` tag, as Anki finds a field's images
/// (`rslib/src/text.rs`, `HTML_MEDIA_TAGS`), double-quoted, single-quoted or
/// bare, with its character references decoded. The quoted values of a
/// tag's other attributes are skipped whole, so that a `src=` inside one
/// isn't taken. A `src` with a colon is an address, such as an image's on
/// the web, and names no file of the package, since Anki keeps colons out
/// of its media's names (`rslib/src/media/files.rs`). An image the HTML
/// hides shows nothing, as in Anki's reviewer: one in a comment, a
/// `<script>` or a `<style>`, as `plainText(fromHTML:)` leaves their text
/// out, and one whose own tag hides it, with `hidden` or `display: none`,
/// such as an icon a template's script shows now and then.
private func fileNames(shownIn html: String) -> [String] {
    imageTags(in: htmlWithoutHiddenMarkup(html))
        .compactMap { attributes -> String? in
            guard attributes["hidden"] == nil, attributes["style"]?.contains(/(?i)display\s*:\s*none/) != true else {
                return nil
            }
            return attributes["src"].map(characterReferencesDecoded(in:))
        }
        .reduce(into: []) { names, name in
            if !name.isEmpty, !name.contains(":"), !names.contains(name) {
                names.append(name)
            }
        }
}

/// The attributes of each `<img>` tag in `html`, in its order, by their
/// names in lowercase: each one's value, double-quoted, single-quoted or
/// bare, or an empty value for one without, such as `hidden`. A tag ends at
/// its first `>` outside a quoted value, or at a quote it never closes. An
/// attribute the tag repeats keeps its first value, as in a browser. Read by
/// hand, since Swift's regexes took a second on a deck's 6,000 images.
private func imageTags(in html: String) -> [[String: String]] {
    let html = Array(html.unicodeScalars)
    var tags: [[String: String]] = []
    var index = 0
    while index + 4 <= html.count {
        guard startsImageTag(html, at: index) else {
            index += 1
            continue
        }
        let end = endOfTag(html, from: index + 4)
        tags.append(attributes(in: html[(index + 4)..<end]))
        index = end
    }
    return tags
}

/// Whether an `<img>` tag starts at `index` of `html`: `<img`, in any case,
/// then neither a letter, a digit nor `_`.
private func startsImageTag(_ html: [Unicode.Scalar], at index: Int) -> Bool {
    guard html[index] == "<", String(String.UnicodeScalarView(html[(index + 1)..<(index + 4)])).lowercased() == "img"
    else {
        return false
    }
    guard index + 4 < html.count else {
        return true
    }
    let next = html[index + 4]
    return !(next.properties.isAlphabetic || next.properties.numericType != nil || next == "_")
}

/// Where the tag whose name ends at `start` ends: at its first `>` outside a
/// quoted value, at a quote it never closes, or at the HTML's end.
private func endOfTag(_ html: [Unicode.Scalar], from start: Int) -> Int {
    var index = start
    while index < html.count, html[index] != ">" {
        if html[index] == "\"" || html[index] == "'" {
            guard let close = html[(index + 1)...].firstIndex(of: html[index]) else {
                return index
            }
            index = close
        }
        index += 1
    }
    return index
}

/// The attributes in `text`, what follows a tag's name, by their names in
/// lowercase, each with the first value the tag gives it.
private func attributes(in text: ArraySlice<Unicode.Scalar>) -> [String: String] {
    var attributes: [String: String] = [:]
    var index = text.startIndex
    while index < text.endIndex {
        guard !endsAttributeName(text[index]) else {
            index += 1
            continue
        }
        let nameEnd = text[index...].firstIndex(where: endsAttributeName) ?? text.endIndex
        let name = String(String.UnicodeScalarView(text[index..<nameEnd])).lowercased()
        let (value, valueEnd) = attributeValue(in: text, after: nameEnd) ?? ("", nameEnd)
        if attributes[name] == nil {
            attributes[name] = value
        }
        index = valueEnd
    }
    return attributes
}

/// Whether `scalar` ends an attribute's name: a space, a quote, `>`, `/` or
/// `=`.
private func endsAttributeName(_ scalar: Unicode.Scalar) -> Bool {
    scalar.properties.isWhitespace || "\"'>/=".unicodeScalars.contains(scalar)
}

/// The value an attribute whose name ends at `nameEnd` of `text` is given,
/// after an `=` and any spaces around it, double-quoted, single-quoted or
/// bare, and where it ends; nil when it's given none.
private func attributeValue(in text: ArraySlice<Unicode.Scalar>, after nameEnd: Int) -> (String, Int)? {
    let isSpace = { (scalar: Unicode.Scalar) in scalar.properties.isWhitespace }
    guard let equals = text[nameEnd...].firstIndex(where: { !isSpace($0) }), text[equals] == "=",
        let start = text[(equals + 1)...].firstIndex(where: { !isSpace($0) })
    else {
        return nil
    }
    let quote = text[start]
    if quote == "\"" || quote == "'" {
        return text[(start + 1)...].firstIndex(of: quote).map { close in
            (String(String.UnicodeScalarView(text[(start + 1)..<close])), close + 1)
        }
    }
    let end = text[start...].firstIndex { isSpace($0) || "\"'>".unicodeScalars.contains($0) } ?? text.endIndex
    return (String(String.UnicodeScalarView(text[start..<end])), end)
}
