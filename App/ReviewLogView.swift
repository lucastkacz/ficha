import Charts
import FichaCore
import FichaData
import SwiftUI

/// A card's review log in the Cards window's detail, under where the card
/// stands: a chart of the interval it waited after each review, and after
/// each placement an import gave it (ADR 0013), where Anki's reviews of it
/// start, or after them, each the interval of the entry's way, a line for
/// each way, with a key, and every entry under it, the latest first, each
/// back-first one marked, with the interval it set. A new card says it has
/// no reviews yet instead.
struct ReviewLogView: View {
    /// The card's review log, oldest first, each entry with the interval its
    /// way waited after it.
    let rows: [ReviewLogRow]

    var body: some View {
        if rows.isEmpty {
            Text(
                "No reviews yet",
                comment: "In the Cards window's detail, in place of the review log of a card not seen yet."
            )
            .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                chart
                entries
            }
        }
    }

    /// One point per entry, evenly spaced, at the interval after it, on a
    /// logarithmic scale of time from minutes to years, so an hour and a year
    /// both fit, marked at round spans of time from the one under the
    /// shortest interval to the one over the longest, in the color of what
    /// Lucas answered, Anki's colors for its four ratings, or gray for a
    /// placement an import gave, which the key under the chart names. A
    /// line for each way holds its interval until its next entry: solid
    /// front first and dashed back first, which the key names too once the
    /// card has a back-first entry. The first and last entries' dates go
    /// under it.
    private var chart: some View {
        let scale = IntervalScale(plotting: rows.map(\.days))
        return Chart(Array(rows.enumerated()), id: \.offset) { index, row in
            let line = LineMark(
                x: .value(entryLabel, index), y: .value(intervalLabel, row.days),
                series: .value(wayLabel, row.entry.way.name)
            )
            .interpolationMethod(.stepEnd)
            .foregroundStyle(.gray.opacity(0.6))
            .accessibilityHidden(true)
            if hasBackFirstEntries {
                line.lineStyle(by: .value(wayLabel, row.entry.way.name))
            } else {
                line
            }
            PointMark(x: .value(entryLabel, index), y: .value(intervalLabel, row.days))
                .foregroundStyle(by: .value(answerLabel, row.entry.kind.name))
                .symbolSize(40)
                .accessibilityLabel(Text(row.pointName))
                .accessibilityValue(
                    Text(
                        "Interval \(spokenIntervalText(row.interval))",
                        comment:
                            "For VoiceOver, a point of the Cards window's chart: how long the card waited after Lucas's answer, like “Interval 5 days”."
                    ))
        }
        .chartForegroundStyleScale(domain: keyItems.map(\.name), range: keyItems.map(\.color))
        .chartLineStyleScale(domain: keyWays.map(\.name), range: keyWays.map(\.lineStyle))
        // A key of our own, whose names wrap: Swift Charts' cut the last
        // one in German.
        .chartLegend(position: .bottom, alignment: .leading) {
            ChartKey(items: keyItems, ways: keyWays)
        }
        .chartXScale(domain: entryDomain, range: .plotDimension(padding: 10))
        .chartYScale(domain: scale.domain, range: .plotDimension(padding: 8), type: .log)
        .chartXAxis {
            AxisMarks(values: datedIndices) { value in
                AxisValueLabel(anchor: dateAnchor(for: value)) {
                    if let index = value.as(Int.self), rows.indices.contains(index) {
                        Text(rows[index].entry.answeredAt.formatted(date: .abbreviated, time: .omitted))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: scale.marks) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let days = value.as(Double.self) {
                        Text(intervalText(Duration(days: days)))
                    }
                }
            }
        }
        .frame(height: 170)
    }

    /// Whether the card has an entry that went back first, so that the chart
    /// draws each way's line apart and names them in its key.
    private var hasBackFirstEntries: Bool {
        rows.contains { $0.entry.way == .backFirst }
    }

    /// The ways whose lines the chart's key names, in its order: both, once
    /// the card has an entry that went back first, and none before.
    private var keyWays: [Way] {
        hasBackFirstEntries ? [.frontFirst, .backFirst] : []
    }

    /// What the chart's key names, with each one's color, in its order: the
    /// import that brought the card in with its progress, when one did, and
    /// then Anki's four ratings, also those the card hasn't had yet.
    private var keyItems: [(name: String, color: Color)] {
        let ratings = Rating.allCases.map { (name: $0.name, color: $0.color) }
        guard let placement = rows.first(where: \.entry.isPlacement)?.entry.kind else {
            return ratings
        }
        return [(placement.name, placement.color)] + ratings
    }

    /// The entries the chart spans, by their place in the review log: one
    /// entry goes in the middle.
    private var entryDomain: ClosedRange<Int> {
        rows.count > 1 ? 0...(rows.count - 1) : -1...1
    }

    /// The places in the review log of the entries whose dates go under the
    /// chart: the first and the last.
    private var datedIndices: [Int] {
        rows.count > 1 ? [0, rows.count - 1] : [0]
    }

    /// Where a date under the chart hangs from its entry: the first one's
    /// starts there and the last one's ends there, so both stay inside the
    /// chart, and a lone entry's sits under it.
    private func dateAnchor(for value: AxisValue) -> UnitPoint {
        if value.count == 1 {
            .top
        } else if value.index == 0 {
            .topLeading
        } else {
            .topTrailing
        }
    }

    /// The name of the chart's horizontal values, for VoiceOver.
    private var entryLabel: Text {
        Text(
            "Entry", comment: "For VoiceOver, the Cards window's chart: an entry of the review log, by its place in it."
        )
    }

    /// The name of the chart's vertical values, for VoiceOver.
    private var intervalLabel: Text {
        Text(
            "Interval",
            comment: "For VoiceOver, the Cards window's chart: how long the card waited after each entry.")
    }

    /// The name of what colors the chart's points, for VoiceOver.
    private var answerLabel: Text {
        Text(
            "Answer", comment: "For VoiceOver, the Cards window's chart: what Lucas answered, which colors each point.")
    }

    /// The name of what draws each of the chart's lines, for VoiceOver.
    private var wayLabel: Text {
        Text(
            "Way",
            comment:
                "For VoiceOver, the Cards window's chart: which way each entry went, front first or back first, which has a line of its own."
        )
    }

    /// Every entry, the latest first: when Lucas answered, what he answered,
    /// marked when it was a review ahead and when it went back first, the
    /// interval it set and how long he took; or when the import brought the
    /// card in, and when it said the card was due. Each on one line while
    /// every entry fits the detail's width that way, as in English, and
    /// otherwise each date above what Lucas answered: in German, the badge
    /// "Rückseite zuerst", which can't wrap, leaves the date no room beside
    /// it.
    private var entries: some View {
        ViewThatFits(in: .horizontal) {
            entryGrid(datesAbove: false)
            entryGrid(datesAbove: true)
        }
        .font(.callout)
    }

    /// The entries in columns, each date beside what Lucas answered, or above
    /// it when `datesAbove`, where the badges go on a line of their own when
    /// they don't fit beside the answer.
    private func entryGrid(datesAbove: Bool) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: datesAbove ? 10 : 6) {
            ForEach(Array(rows.enumerated().reversed()), id: \.offset) { _, row in
                GridRow {
                    if datesAbove {
                        VStack(alignment: .leading, spacing: 3) {
                            entryDate(row)
                            WrappingRow(spacing: 6) {
                                answer(row)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        entryDate(row)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 6) {
                            answer(row)
                        }
                    }
                    EntryInterval(row: row)
                        .gridColumnAlignment(.trailing)
                    ResponseTime(entry: row.entry)
                        .gridColumnAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// When Lucas answered `row`'s entry, or the import brought the card in.
    private func entryDate(_ row: ReviewLogRow) -> some View {
        Text(row.entry.answeredAt.formatted(date: .abbreviated, time: .shortened))
            .foregroundStyle(.secondary)
    }

    /// What Lucas answered in `row`'s entry, after its dot, then its badges,
    /// each a view of its own for the row that lays them out.
    @ViewBuilder
    private func answer(_ row: ReviewLogRow) -> some View {
        HStack(spacing: 6) {
            AnswerDot(kind: row.entry.kind)
            Text(row.entry.kind.entryName)
        }
        if row.entry.isAhead {
            AheadBadge()
        }
        if row.entry.way == .backFirst {
            BackFirstBadge()
        }
    }
}

/// The key under the review log's chart: a dot in each color the points
/// take, with what it means, then, once the card went back first, each
/// way's line, gray as the chart draws it, with its name, side by side, in
/// lines that wrap when they don't fit the chart's width.
private struct ChartKey: View {
    /// What each color means, in the key's order.
    let items: [(name: String, color: Color)]
    /// The ways whose lines the key names, in its order.
    let ways: [Way]

    var body: some View {
        WrappingRow(spacing: 10) {
            ForEach(items, id: \.name) { item in
                HStack(spacing: 4) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 7, height: 7)
                    Text(item.name)
                }
            }
            ForEach(ways, id: \.self) { way in
                HStack(spacing: 4) {
                    // A level line, the same mirrored.
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 1))
                        path.addLine(to: CGPoint(x: 16, y: 1))
                    }
                    .stroke(.gray, style: way.lineStyle)
                    .frame(width: 16, height: 2)
                    Text(way.name)
                }
            }
        }
        .font(.caption)
        // The secondary label color, as Swift Charts' key has it, not the
        // chart's own style, which is the accent color.
        .foregroundStyle(Color.secondary)
    }
}

/// The interval a review set, in the review log's list, short, as the
/// Interval column shows it, and in words for VoiceOver. A placement, whose
/// due date its name says, has nothing there.
private struct EntryInterval: View {
    let row: ReviewLogRow

    var body: some View {
        if row.entry.isPlacement {
            Text(verbatim: "")
        } else {
            Text(intervalText(row.interval))
                .monospacedDigit()
                .accessibilityLabel(spokenIntervalText(row.interval))
        }
    }
}

/// The chart's vertical scale, in days, logarithmic, a scale of time from
/// minutes to years: from the round span of time at or under the shortest
/// interval it plots to the one at or over the longest, and one more each
/// way when they're the same, as for a card with one entry, so that it
/// always spans two marks at least; and the marks, at each round span in it.
private struct IntervalScale {
    /// The round spans of time the scale can mark, in days: a minute, 10
    /// minutes, an hour, a day, a week, a month and a year as Anki counts
    /// them, which `intervalText` labels "1mo" and "1y", 10 years, and the
    /// longest interval Ficha gives, 100 years.
    private static let spans: [Double] = [
        1.0 / (24 * 60), 10.0 / (24 * 60), 1.0 / 24, 1, 7, daysInAMonth, daysInAYear, 10 * daysInAYear,
        Double(Scheduler.longestIntervalsInDays.upperBound),
    ]

    /// The intervals the scale spans, in days.
    let domain: ClosedRange<Double>
    /// The intervals the scale marks, in days.
    let marks: [Double]

    /// The scale for intervals of `days`, each above zero: the chart plots
    /// a minute at least.
    init(plotting days: [Double]) {
        let spans = Self.spans
        let shortest = days.min() ?? spans[0]
        let longest = days.max() ?? spans[0]
        var lower = spans.lastIndex { $0 <= shortest } ?? 0
        var upper = spans.firstIndex { $0 >= longest } ?? spans.count - 1
        if lower == upper {
            lower = max(0, lower - 1)
            upper = min(spans.count - 1, upper + 1)
        }
        domain = min(spans[lower], shortest)...max(spans[upper], longest)
        marks = Array(spans[lower...upper])
    }
}

/// A dot in the color of what Lucas answered, as the chart's points have it.
private struct AnswerDot: View {
    let kind: ReviewLogEntry.Kind

    var body: some View {
        Circle()
            .fill(kind.color)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }
}

/// How long the user took to answer, in seconds, or a dash when nothing
/// measured it: an answer from a card notification has no time. A placement,
/// which the user didn't answer, has nothing there.
private struct ResponseTime: View {
    let entry: ReviewLogEntry

    var body: some View {
        if entry.isPlacement {
            Text(verbatim: "")
        } else if let duration = entry.responseTime {
            Text(duration.formatted(.units(allowed: [.seconds], width: .narrow)))
                .monospacedDigit()
        } else {
            Text(
                "—",
                comment:
                    "In the Cards window's review log, in place of the seconds Lucas took, when nothing measured them."
            )
            .help(
                Text(
                    "Not measured: you answered from a card notification.",
                    comment: "The tooltip of the dash in place of the seconds in the Cards window's review log.")
            )
            .accessibilityLabel(
                Text(
                    "Not measured",
                    comment: "For VoiceOver, the dash in place of the seconds in the Cards window's review log."))
        }
    }
}

extension ReviewLogRow {
    /// The interval the entry's way waited after it, in days, as the chart
    /// plots it: a minute at least, below the shortest learning step, since a
    /// logarithmic scale has no zero, and Swift Charts traps on one, which a
    /// placement an import gives a card Anki was learning holds when the
    /// settings have no learning steps.
    fileprivate var days: Double {
        max(interval, .seconds(60)).inDays
    }

    /// The entry's point in the chart, as VoiceOver names it: what the user
    /// answered, and that it went back first when it did.
    fileprivate var pointName: String {
        switch entry.way {
        case .frontFirst:
            entry.kind.name
        case .backFirst:
            String(
                localized: "\(entry.kind.name), back first",
                comment:
                    "For VoiceOver, a point of the Cards window's chart: what Lucas answered, in a review that went back first, like “Good, back first”."
            )
        }
    }
}

extension Way {
    /// The way, as the key of the Cards window's chart names its line.
    fileprivate var name: String {
        switch self {
        case .frontFirst:
            String(
                localized: "Front first",
                comment:
                    "In the key of the Cards window's review log chart: the line of the card's usual way, its front first."
            )
        case .backFirst:
            String(
                localized: "Back first",
                comment:
                    "In the key of the Cards window's review log chart: the line of a card that goes both ways, back first."
            )
        }
    }

    /// How the chart draws the way's line: solid front first, and dashed back
    /// first.
    fileprivate var lineStyle: StrokeStyle {
        switch self {
        case .frontFirst: StrokeStyle(lineWidth: 2)
        case .backFirst: StrokeStyle(lineWidth: 2, dash: [4, 3])
        }
    }
}

extension ReviewLogEntry.Kind {
    /// What the user answered, as the chart's key names it, and VoiceOver
    /// each of the chart's points: the rating as the review panel's buttons
    /// name it, or "Imported", for a placement an import gave the card.
    fileprivate var name: String {
        switch self {
        case .placement:
            String(
                localized: "Imported",
                comment: """
                    In the key of the Cards window's review log chart, and for VoiceOver, the name of the chart's \
                    point: an import from Anki brought the card in with its progress.
                    """)
        case .review(let rating):
            rating.name
        }
    }

    /// What the user answered, as the review log's list names it: the rating
    /// as the review panel's buttons name it, or, for a placement an import
    /// gave the card, when the import said it was due.
    fileprivate var entryName: String {
        switch self {
        case .placement(let placement):
            String(
                localized: "Imported, due on \(placement.due.formatted(date: .abbreviated, time: .omitted))",
                comment: """
                    In the Cards window's review log: an import from Anki brought the card in with its progress, due \
                    on this day, as Anki had it, like “Imported, due on Oct 20, 2026”.
                    """)
        case .review(let rating):
            rating.name
        }
    }

    /// The color of what Lucas answered, as Anki colors its ratings, or gray
    /// for a placement, which isn't an answer.
    fileprivate var color: Color {
        switch self {
        case .placement: .gray
        case .review(let rating): rating.color
        }
    }
}

extension Rating {
    /// The rating's color, as Anki colors its ratings: red for again, orange
    /// for hard, green for good and blue for easy.
    fileprivate var color: Color {
        switch self {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
        }
    }
}
