import FichaCore
import Foundation

/// An interval as the review panel's buttons and the Cards window show it,
/// short, as Anki's buttons do: in days, hours and minutes under a month,
/// like "5d" or "2h 30m", then in months, like "1.5mo", and from a year on in
/// years, like "2.1y", with a decimal. A year is 365 days and a month a
/// twelfth of it, about 30.4 days, as Anki counts them
/// (`rslib/src/scheduler/timespan.rs`), so 30 days are still "30d".
func intervalText(_ interval: Duration) -> String {
    let days = interval.inDays
    guard days >= daysInAMonth else {
        return interval.formatted(.units(allowed: [.days, .hours, .minutes], width: .narrow))
    }
    let tenths = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))
    guard days >= daysInAYear else {
        return String(
            localized: "\((days / daysInAMonth).formatted(tenths))mo",
            comment: """
                An interval of this many months, a month counted as a twelfth of a year of 365 days, about 30.4 \
                days, with a decimal, like “1.5mo”: short, as Anki's buttons show it, on the review panel's \
                buttons and in the Cards window. Anki's own short unit in each language.
                """)
    }
    return String(
        localized: "\((days / daysInAYear).formatted(tenths))y",
        comment: """
            An interval of this many years, a year counted as 365 days, with a decimal, like “2.1y”: short, as \
            Anki's buttons show it, on the review panel's buttons and in the Cards window. Anki's own short unit \
            in each language.
            """)
}

/// An interval as VoiceOver reads it, in whole words: in days, hours and
/// minutes, like "45 days" or "2 hours, 30 minutes", whatever its length,
/// as the Mac's language says them.
func spokenIntervalText(_ interval: Duration) -> String {
    interval.formatted(.units(allowed: [.days, .hours, .minutes], width: .wide))
}

/// Anki's year, in days, as the intervals' text and the review log's chart
/// count it.
let daysInAYear = 365.0

/// Anki's month, a twelfth of its year, in days.
let daysInAMonth = daysInAYear / 12
