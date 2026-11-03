import Foundation

/// One of Ficha's languages, a line of `scripts/languages.txt`: English, the
/// base the code writes every text in, or one of the eleven Ficha comes in
/// (ADR 0027). The render tool and FichaKit's test of the engine's messages
/// compile this file through a link to it, so that both read the list by the
/// same rules, which `scripts/languages.sh` follows for the scripts.
nonisolated struct FichaLanguage {
    /// The list, from the repo's folder, as its messages name it.
    static let listPath = "scripts/languages.txt"

    /// The language's code, as the String Catalogs name it.
    let code: String
    /// The region of the device the render tools draw for, whose formats the
    /// dates, numbers and durations take.
    let region: String
    /// Whether it reads right to left, like Arabic, which mirrors the window.
    let isRightToLeft: Bool
    /// Its plural categories, as Unicode's CLDR rules give them.
    let pluralCategories: [String]
    /// Its name in English, for messages.
    let name: String

    /// The device's locale: the language with its region, as macOS keeps it.
    var locale: String { "\(code)_\(region)" }

    /// The languages in the list at `url`, in its order. Each line that isn't
    /// blank, and whose first character after any spaces isn't `#`, is a
    /// language's code, region, direction, `ltr` or `rtl`, plural categories,
    /// other among them, and name. A missing list, a line of another shape or
    /// a list of no language throws, saying what's wrong and what to do, its
    /// last words "and `again`.".
    static func read(at url: URL, again: String) throws(FichaLanguagesError) -> [FichaLanguage] {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw FichaLanguagesError(
                description: """
                    There's no \(listPath), Ficha's languages: restore it with git restore \(listPath), and \(again).
                    """)
        }
        let pluralCategories: Set<Substring> = ["zero", "one", "two", "few", "many", "other"]
        var languages: [FichaLanguage] = []
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let content = line.drop(while: \.isWhitespace)
            if content.isEmpty || content.hasPrefix("#") {
                continue
            }
            let fields = content.split(maxSplits: 4, whereSeparator: \.isWhitespace)
            let categories = fields.count == 5 ? fields[3].split(separator: ",", omittingEmptySubsequences: false) : []
            guard fields.count == 5, ["ltr", "rtl"].contains(fields[2]),
                categories.allSatisfy(pluralCategories.contains),
                categories.contains("other")
            else {
                throw FichaLanguagesError(
                    description: """
                        \(listPath):\(index + 1) isn't a language's code, region, direction, plural categories and \
                        name, as in 'es AR ltr one,many,other Spanish': write it so, with ltr or rtl for the \
                        direction it reads in and the categories Unicode's CLDR gives it, other among them, and \
                        \(again).
                        """)
            }
            languages.append(
                FichaLanguage(
                    code: String(fields[0]), region: String(fields[1]), isRightToLeft: fields[2] == "rtl",
                    pluralCategories: categories.map(String.init),
                    name: fields[4].trimmingCharacters(in: .whitespaces)))
        }
        guard !languages.isEmpty else {
            throw FichaLanguagesError(
                description: """
                    \(listPath) lists no language: write a line for each of Ficha's languages, as in \
                    'es AR ltr one,many,other Spanish', and \(again).
                    """)
        }
        return languages
    }
}

/// Why `scripts/languages.txt` couldn't be read, and what to do about it.
nonisolated struct FichaLanguagesError: Error, CustomStringConvertible {
    let description: String
}
