import Foundation

extension FormatStyle where Self == Duration.UnitsFormatStyle {
    /// How the app shows an interval under a month, short, in days, hours
    /// and minutes, in `locale`'s language, the one Foundation writes it in:
    /// the app's `Locale.current`, which is the app's language, the one its
    /// catalogs give it, with the Mac's region. In English it's narrow, like
    /// "8d" and "2h 30m", as Anki's buttons show it. In every other language
    /// it's abbreviated, like "8 Tg." in German, "٨ أيام" in Arabic and "6小時"
    /// in Traditional Chinese, since narrow reads wrong in some, as Foundation
    /// writes it on macOS 26: Arabic's "٨يوم", with no space and one form for
    /// every count, Traditional Chinese's "6時", which reads as six o'clock,
    /// and German's "2d", English's unit. This rule is our own; the view
    /// keeps the text, and the rule is here so it's tested.
    public static func shortInterval(in locale: Locale) -> Self {
        let width: Duration.UnitsFormatStyle.UnitWidth =
            locale.language.languageCode == .english ? .narrow : .abbreviated
        return Duration.UnitsFormatStyle(allowedUnits: [.days, .hours, .minutes], width: width).locale(locale)
    }
}
