import Foundation

/// A side of an Anki card as Ficha brings it in, from the HTML Anki renders
/// for it: its plain text, without its sounds, `[sound:…]`, and its images,
/// which the HTML's tags are; and its image, the first of the package's
/// files the HTML shows, when the package has it and Ficha can read it. The
/// side's other images are dropped, since a side holds one image at most,
/// and so are images on the web, which Ficha never fetches.
struct AnkiSide {
    let text: String
    let image: ImageName?
    /// Whether the HTML shows other files of the package as images, which
    /// the side drops.
    let dropsImages: Bool
    /// What was found for the image the side shows, or nil when it shows
    /// none.
    private let lookup: ImageLookup?

    /// The side Anki renders as `html`, with its image as `images` finds it
    /// by the name the HTML gives it.
    init(html: String, images: (String) -> ImageLookup) {
        text = plainText(fromHTML: html.replacing(/\[sound:.+?\]/, with: ""))
        let names = fileNames(shownIn: html)
        dropsImages = names.count > 1
        lookup = names.first.map { name in
            // Some decks keep a name percent-encoded, as a browser's address
            // has it, though Anki writes it as it is.
            let lookup = images(name)
            guard lookup == .missing, let decoded = name.removingPercentEncoding, decoded != name else {
                return lookup
            }
            return images(decoded)
        }
        if case .found(let image) = lookup {
            self.image = image
        } else {
            image = nil
        }
    }

    /// Why a card with this side stays out, when the side is left with
    /// neither text nor an image: the image it shows isn't in the package,
    /// or Ficha can't read it, or it shows none. Nil when it isn't blank.
    var reasonItsCardStaysOut: LeftOutLine.Reason? {
        guard CardContent.isBlank(text, image: image, sound: nil) else {
            return nil
        }
        return switch lookup {
        case .missing?: .missingAnkiImage
        case .notAnImage?: .unreadableAnkiImage
        case .found?, nil: .emptyAnkiSide
        }
    }
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
    // Each ends where `plainText(fromHTML:)` ends it, whatever the case of
    // its closing tag, which a backreference would compare.
    let shown = html.replacing(
        #/(?is)<!--.*?(?:-->|\z)|<script\b.*?(?:</script[^>]*>|\z)|<style\b.*?(?:</style[^>]*>|\z)/#, with: "")
    return shown.matches(of: #/(?i)<img\b((?:[^>"']|"[^"]*"|'[^']*')*)/#)
        .compactMap { match -> String? in
            let attributes = tagAttributes(in: String(match.output.1))
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

/// The attributes of a tag, by their names in lowercase, from `text`, what
/// follows the tag's name: each one's value, double-quoted, single-quoted or
/// bare, or an empty value for one without, such as `hidden`. An attribute
/// the tag repeats keeps its first value, as in a browser.
private func tagAttributes(in text: String) -> [String: String] {
    Dictionary(
        text.matches(of: #/([^\s"'>/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?/#).map { match in
            (match.output.1.lowercased(), String(match.output.2 ?? match.output.3 ?? match.output.4 ?? ""))
        }
    ) { first, _ in first }
}
