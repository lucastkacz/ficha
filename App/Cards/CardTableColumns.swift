import AppKit
import FichaCore

/// The Cards window's table of cards' columns, each with its header and its
/// widths in the app's language, which the table draws them at and its pane
/// opens to fit. Each is measured with the texts its cells draw: the date
/// columns' in `.tableDay`, Interval's from `WayIntervalText` and Due's from
/// `DueText`. Front, Type, Tags and Source narrow below their texts when the
/// table is short of room, as once Lucas narrows the window: a front, a type
/// of the user's own, a tag and a source are the user's texts, often too long
/// for any width. Their headers fit, and the app's own texts in every column.
struct CardTableColumns {
    let front: FittedColumn
    let media: FittedColumn
    let interval: FittedColumn
    let due: FittedColumn
    let backFirstInterval: FittedColumn
    let backFirstDue: FittedColumn
    let type: FittedColumn
    let tags: FittedColumn
    let source: FittedColumn
    let lastSeen: FittedColumn
    let created: FittedColumn
    let edited: FittedColumn

    /// The columns, with the texts of their cells as they show them at `now`.
    init(now: Date) {
        front = FittedColumn(
            String(localized: "Front", comment: "A column of the Cards window: the card's front."), min: 60)
        media = FittedColumn(
            String(
                localized: "Media",
                comment: "A column of the Cards window: whether the card's sides have an image or a sound."),
            min: 48, ideal: 56, max: 80)
        let intervals = [WayIntervalText.new, WayIntervalText.learning]
        interval = FittedColumn(
            String(
                localized: "Interval",
                comment: "A column of the Cards window: how long the card waits after its last review."
            ),
            cells: intervals, min: 56, ideal: 64, max: 100)
        let dues = DueText.samples(from: now)
        due = FittedColumn(
            String(localized: "Due", comment: "A column of the Cards window: when the card is due."),
            cells: dues, min: 60, ideal: 72, max: 110)
        backFirstInterval = FittedColumn(
            String(
                localized: "Back-first interval",
                comment:
                    "A column of the Cards window: how long a card that goes both ways waits after its last review back first."
            ),
            cells: intervals, min: 56, ideal: 120, max: 150)
        backFirstDue = FittedColumn(
            String(
                localized: "Back-first due",
                comment: "A column of the Cards window: when a card that goes both ways is due back first."),
            cells: dues, min: 60, ideal: 120, max: 150)
        type = FittedColumn(
            String(localized: "Type", comment: "A column of the Cards window: the card's type."),
            cells: CardType.builtIn.map(\.title), min: 60, ideal: 76, max: 110)
        tags = FittedColumn(
            String(localized: "Tags", comment: "A column of the Cards window: the card's tags."), min: 60, ideal: 120)
        source = FittedColumn(
            String(
                localized: "Source",
                comment: "A column of the Cards window: where Lucas came across the card's content."),
            min: 60, ideal: 120)
        let days = ColumnWidth.dateTexts(.tableDay, inEachMonthOf: now)
        lastSeen = FittedColumn(
            String(
                localized: "Last seen", comment: "A column of the Cards window: when Lucas last reviewed the card."),
            cells: days, min: 80, ideal: 96, max: 140)
        created = FittedColumn(
            String(localized: "Created", comment: "A column of the Cards window: when Lucas approved the card."),
            cells: days, min: 80, ideal: 96, max: 140)
        edited = FittedColumn(
            String(
                localized: "Edited",
                comment: "A column of the Cards window: when the card's front or back last changed."),
            cells: days, min: 80, ideal: 96, max: 140)
    }

    /// How wide the table's pane opens: 440 points, as in English, or wide
    /// enough for the columns the table starts with, Front, Media, Interval
    /// and Due, each at its least width, where they need more, as in
    /// Spanish, so that the table doesn't scroll sideways; the detail beside
    /// it gives up those points. The columns and the room the table takes
    /// besides them, in its inset style, with a scroller that takes room, as
    /// it does with a mouse (`ColumnWidth.tableSpacing`).
    var openingPaneWidth: CGFloat {
        let columns = [front, media, interval, due].map(\.min)
        let table =
            columns.reduce(0, +) + ColumnWidth.tableSpacing(columns: columns.count, edges: 16.5, scroller: true)
        return max(440, table.rounded(.up))
    }
}
