import FichaCore
import Foundation
import Testing

/// The locales are as `Locale.current` comes in the app: the app's language,
/// the one its catalogs give it, with the Mac's region, such as `de_US` for
/// a Mac in German set to the United States' formats, or `zh_TW` for one in
/// Traditional Chinese.
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
