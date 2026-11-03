import AppKit

/// The width a table's column needs for its header and the texts of its cells
/// to show whole in the language the app shows, as `CODING_STANDARDS.md` asks
/// of a text that can't wrap: German's header "Hinzugefügt", Spanish's dates
/// or French's "En apprentissage" run longer than English's. Our own
/// measure, since a SwiftUI table sizes a column to the widths its code
/// gives, never to its texts: each text in the font AppKit draws it in, with
/// the room around it that `make render`'s pictures showed, beyond the 17
/// points between two columns that a column's width leaves out, and a few
/// more, which the last column loses beside the scroller. A column
/// takes it as its least width, since a table short of room narrows every
/// column down to its least.
enum ColumnWidth {
    /// The width that fits `header`, semibold and with the sort indicator
    /// after it as when the table is sorted by the column, if the column
    /// `sorts`, and each of `cells`. Every column that sorts has that room
    /// from the start, since a table keeps a column's width when its order
    /// changes.
    static func fitting(header: String, cells: [String] = [], sorts: Bool = true) -> CGFloat {
        let headerWidth =
            sorts
            ? width(of: header, in: .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)) + 24
            : width(of: header, in: .systemFont(ofSize: NSFont.smallSystemFontSize)) + 6
        let cellWidth = (cells.map { width(of: $0, in: .systemFont(ofSize: NSFont.systemFontSize)) }.max() ?? 0) + 6
        return max(headerWidth, cellWidth).rounded(.up)
    }

    /// `format`'s text of a day in each month of this year, late in the
    /// evening, so that the longest month's name and the longest hour are
    /// among them.
    static func inEachMonth(_ format: (Date) -> String) -> [String] {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: .now)
        return (1...12).compactMap { month in
            calendar.date(from: DateComponents(year: year, month: month, day: 28, hour: 22, minute: 30))
        }
        .map(format)
    }

    private static func width(of text: String, in font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}
