import AppKit

/// The columns of the Backups tab's table of copies, each with its header and
/// its widths in the app's language, which the table draws them at. Saved is
/// as wide as its dates and Size as its sizes, and Kind takes what they leave
/// it, down to its header, its texts wrapping, so that every column shows
/// whole within the width the tab names give Settings, in every language.
struct CopyTableColumns {
    let saved: FittedColumn
    let kind: FittedColumn
    let size: FittedColumn

    /// How the Saved column shows when a copy was saved, which its width
    /// measures too.
    static let savedAt = Date.FormatStyle(date: .abbreviated, time: .shortened)

    /// The columns of a table `tableWidth` wide, with Saved's dates as they
    /// show at `now`. Size is 80 points, as in English, or as wide as its
    /// header and the longest size, such as 999.9 MB, need.
    init(now: Date, tableWidth: CGFloat) {
        saved = FittedColumn(
            String(localized: "Saved", comment: "Settings, under Backups: the column of when a copy was saved."),
            cells: ColumnWidth.inEachMonth(Self.savedAt, of: now), sorts: false)
        size = FittedColumn(
            String(localized: "Size", comment: "Settings, under Backups: the column of what each copy weighs."),
            cells: [Int64(999_900_000).formatted(.byteCount(style: .file))], sorts: false, min: 80, max: 80)
        // What Size leaves Saved and Kind, in the full-width style of a table
        // in a grouped form, which has no scroller there, even with a mouse.
        let room = tableWidth - ColumnWidth.tableSpacing(columns: 3, edges: 6, scroller: false) - size.min
        // SwiftUI starts a column at its ideal width, or at its least without
        // one, as Saved, and widens the columns alike to fill the table, but
        // doesn't narrow them to fit it as it opens: a table short of room
        // then pushes its last column out of sight. So Kind starts as wide as
        // Saved, and the two share the room equally, as in English; or, where
        // Saved's dates need more than half of it, as Spanish's do, Kind takes
        // what they leave.
        kind = FittedColumn(
            String(localized: "Kind", comment: "Settings, under Backups: the column of each copy's kind."),
            sorts: false, ideal: min(saved.min, room - saved.min))
    }
}
