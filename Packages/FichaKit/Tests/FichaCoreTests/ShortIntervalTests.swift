import FichaCore
import Foundation
import Testing

/// The app's `Locale.current` is English, the one language its catalogs give
/// it (ADR 0036), with the Mac's region, such as `en_DE` for a Mac set to
/// Germany's formats. The other languages test `shortInterval(in:)` for any
/// locale it's given.
struct ShortIntervalTests {
    @Test("an interval under a month shows narrow in English, like 8d, as Anki's buttons show it, whatever the region")
    func englishIsNarrow() {
        for identifier in ["en_US", "en_GB", "en_DE"] {
            #expect(Duration.UnitsFormatStyle.shortInterval(in: Locale(identifier: identifier)).unitWidth == .narrow)
        }
        #expect(Duration.seconds(8 * 86_400).formatted(.shortInterval(in: Locale(identifier: "en_US"))) == "8d")
    }

    @Test("an interval under a month shows abbreviated in every other language, whatever the region")
    func otherLanguagesAreAbbreviated() {
        for identifier in ["de_DE", "de_US", "ar_EG", "zh_TW", "zh_CN", "es_AR", "fr_FR", "ja_JP"] {
            #expect(
                Duration.UnitsFormatStyle.shortInterval(in: Locale(identifier: identifier)).unitWidth == .abbreviated,
                "\(identifier)")
        }
    }
}
