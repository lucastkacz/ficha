import Charts
import FichaCore
import FichaData
import SwiftUI

/// A card's review log in the Cards window's detail, under where the card
/// stands: a chart of the interval it waited after each review, and after
/// the placement an import brought it in with (ADR 0013), each the interval
/// of the entry's way, a line for each way, with a key, and every entry
/// under it, the latest first, each back-first one marked. A new card says
/// it has no reviews yet instead.
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

    /// One point per entry, evenly spaced, at the interval after it, in days
    /// on a logarithmic scale, so an hour and a year both fit, in the color
    /// of what Lucas answered, which the key under the chart names. A line
    /// for each way holds its interval until its next entry: solid front
    /// first and dashed back first, which the key names too once the card has
    /// a back-first entry. The first and last entries' dates go under it.
    private var chart: some View {
        Chart(Array(rows.enumerated()), id: \.offset) { index, row in
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
                        "Interval \(intervalText(row.interval))",
                        comment:
                            "For VoiceOver, a point of the Cards window's chart: how long the card waited after Lucas's answer, like “Interval 5d”."
                    ))
        }
        .chartForegroundStyleScale(domain: keyKinds.map { $0.name }, range: keyKinds.map { $0.color })
        .chartLineStyleScale(domain: keyWays.map(\.name), range: keyWays.map(\.lineStyle))
        .chartLegend(position: .bottom, alignment: .leading)
        // The key draws the ways' lines in the chart's default style: gray,
        // as the lines are.
        .foregroundStyle(.gray)
        .chartXScale(domain: entryDomain, range: .plotDimension(padding: 10))
        .chartYScale(range: .plotDimension(padding: 8), type: .log)
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
            AxisMarks(position: .leading) { value in
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

    /// What Lucas can answer, in the order the chart's key names them.
    private static let answers: [ReviewLogEntry.Kind] = [.review(.again), .review(.hard), .review(.good)]

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

    /// What the chart's key names, in its order: every answer, also those
    /// the card hasn't had yet, after the import that brought the card in
    /// with its progress, when one did, which can only be its first entry.
    private var keyKinds: [ReviewLogEntry.Kind] {
        guard let first = rows.first?.entry.kind, case .placement = first else {
            return Self.answers
        }
        return [first] + Self.answers
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
    /// marked when it was a review ahead and when it went back first, and how
    /// long he took; or when the import brought the card in.
    private var entries: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
            ForEach(Array(rows.enumerated().reversed()), id: \.offset) { _, row in
                GridRow {
                    Text(row.entry.answeredAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        AnswerDot(kind: row.entry.kind)
                        Text(row.entry.kind.name)
                        if row.entry.isAhead {
                            AheadBadge()
                        }
                        if row.entry.way == .backFirst {
                            BackFirstBadge()
                        }
                    }
                    ResponseTime(entry: row.entry)
                        .gridColumnAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .font(.callout)
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
        if case .placement = entry.kind {
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
    /// placement an import gives a card Anki was learning holds.
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
                    "For VoiceOver, a point of the Cards window's chart: what Lucas answered, in a review that went back first, like “Know it, back first”."
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
    /// What the user answered, as the review log names it in the Cards window:
    /// the rating as the review panel's buttons name it, and "Easy", which no
    /// button gives yet; or "Imported", for the placement an import brought
    /// the card in with.
    fileprivate var name: String {
        switch self {
        case .placement:
            String(
                localized: "Imported",
                comment:
                    "In the Cards window's review log and its chart's key: an import from Anki brought the card in with its progress."
            )
        case .review(.again):
            String(
                localized: "Don't know",
                comment: "A rating, as the review panel's button names it and the Cards window's review log shows it.")
        case .review(.hard):
            String(
                localized: "Sort of",
                comment: "A rating, as the review panel's button names it and the Cards window's review log shows it.")
        case .review(.good):
            String(
                localized: "Know it",
                comment: "A rating, as the review panel's button names it and the Cards window's review log shows it.")
        case .review(.easy):
            String(
                localized: "Easy",
                comment:
                    "A rating, Anki's fourth: Lucas knew the card at once. The Cards window's review log shows it.")
        }
    }

    /// The color of what Lucas answered: red, orange, green and blue for
    /// "Don't know", "Sort of", "Know it" and "Easy", as Anki colors its
    /// ratings; and blue for a placement too.
    fileprivate var color: Color {
        switch self {
        case .placement: .blue
        case .review(.again): .red
        case .review(.hard): .orange
        case .review(.good): .green
        case .review(.easy): .blue
        }
    }
}
