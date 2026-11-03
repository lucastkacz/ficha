import AppKit
import SwiftUI

/// The width a table's column needs for its header and the texts of its cells
/// to show whole in the language the app shows, as `CODING_STANDARDS.md` asks
/// of a text that can't wrap: German's header "Hinzugefügt", Spanish's dates
/// or French's "En apprentissage" run longer than English's. Our own
/// measure, since a SwiftUI table sizes a column to the widths its code
/// gives, never to its texts: each text in the font AppKit draws it in, with
/// the room around it that `make render`'s pictures showed, beyond the 17
/// points between two columns that a column's width leaves out, and a few
/// more, which the last column loses beside the scroller.
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

    /// `style`'s text of a day in each month of `now`'s year, late in the
    /// evening, so that the longest month's name and the longest hour are
    /// among them: the texts of a column that shows dates in `style`.
    static func inEachMonth(_ style: Date.FormatStyle, of now: Date) -> [String] {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        return (1...12).compactMap { month in
            calendar.date(from: DateComponents(year: year, month: month, day: 28, hour: 22, minute: 30))
        }
        .map(style.format)
    }

    /// How wide `text` is in `font`, as AppKit draws it.
    static func width(of text: String, in font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// The points an AppKit table takes besides the widths of its `count`
    /// columns: the 17 between two columns, `edges` at each of its sides,
    /// which its style decides, and, if it has a `scroller`, a legacy
    /// scroller's width, which the scroller takes beside the columns with a
    /// mouse. Our own sum, as `make render`'s pictures and AppKit's frames
    /// measure it: 16.5 at each edge in the inset style the Cards window's
    /// table has, and 6 in the full-width one SwiftUI gives a table in a
    /// grouped form.
    static func tableSpacing(columns count: Int, edges: CGFloat, scroller: Bool) -> CGFloat {
        let scrollerWidth = scroller ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
        return 17 * CGFloat(count - 1) + 2 * edges + scrollerWidth
    }
}

/// A table column's header, in the app's language, and its widths: the ones
/// it has in English, each raised to the width `ColumnWidth` measures for the
/// header and the texts of its cells where that's more. A column takes them
/// with `width(fitting:)`, its least width among them, since a table short
/// of room narrows every column down to its least.
struct FittedColumn {
    let header: String
    let min: CGFloat
    let ideal: CGFloat?
    let max: CGFloat?

    /// `header`'s column, whose cells show `cells`, the longest texts they
    /// show in the app's language, and which `sorts` or not, with English's
    /// widths, `min`, `ideal` and `max`: a width not given stays SwiftUI's,
    /// but the least, which is the fitted width then.
    init(
        _ header: String, cells: [String] = [], sorts: Bool = true, min: CGFloat = 0, ideal: CGFloat? = nil,
        max: CGFloat? = nil
    ) {
        let fitted = ColumnWidth.fitting(header: header, cells: cells, sorts: sorts)
        self.header = header
        self.min = Swift.max(min, fitted)
        self.ideal = ideal.map { Swift.max($0, fitted) }
        self.max = max.map { Swift.max($0, fitted) }
    }
}

extension TableColumn {
    /// The column at `column`'s widths.
    func width(fitting column: FittedColumn) -> TableColumn<RowValue, Sort, Content, Label> {
        width(min: column.min, ideal: column.ideal, max: column.max)
    }
}
