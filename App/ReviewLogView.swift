import Charts
import FichaCore
import FichaData
import SwiftUI

/// A card's review log in the Cards window's detail, under where the card
/// stands: a chart of the step it stood on after each first view and review,
/// and after the placement an import put it on its step with (ADR 0013),
/// each the step of the entry's way, with a key, and every entry under it,
/// the latest first. A new card says it has no reviews yet instead.
struct ReviewLogView: View {
    /// The card's review log, oldest first, each entry with the step its way
    /// stood on after it.
    let rows: [ReviewLogRow]
    /// The ladder Lucas set, whose steps the chart's vertical axis spans, all
    /// of them, so that every card's chart reads the same.
    let ladder: Ladder

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

    /// One point per entry, evenly spaced, at the step after it, counted from
    /// 1 as Settings counts them, in the color of what Lucas answered, which
    /// the key under the chart names. A line holds each step until the next
    /// entry, and the first and last entries' dates go under it.
    private var chart: some View {
        Chart(Array(rows.enumerated()), id: \.offset) { index, row in
            LineMark(x: .value(entryLabel, index), y: .value(stepLabel, row.stepNumber))
                .interpolationMethod(.stepEnd)
                .foregroundStyle(.gray.opacity(0.6))
                .accessibilityHidden(true)
            PointMark(x: .value(entryLabel, index), y: .value(stepLabel, row.stepNumber))
                .foregroundStyle(by: .value(answerLabel, row.entry.kind.name))
                .symbolSize(40)
                .accessibilityLabel(Text(row.entry.kind.name))
                .accessibilityValue(
                    Text(
                        "Step \(row.stepNumber)",
                        comment: "For VoiceOver, a point of the Cards window's chart: the step after Lucas's answer."))
        }
        .chartForegroundStyleScale(domain: keyKinds.map { $0.name }, range: keyKinds.map { $0.color })
        .chartLegend(position: .bottom, alignment: .leading)
        .chartXScale(domain: entryDomain, range: .plotDimension(padding: 10))
        // A ladder of one step gets the room of two, for its chart to have a
        // height.
        .chartYScale(domain: 1...max(steps.upperBound, 2), range: .plotDimension(padding: 8))
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
            AxisMarks(position: .leading, values: Array(steps)) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .frame(height: 170)
    }

    /// What Lucas can answer, in the order the chart's key names them.
    private static let answers: [ReviewLogEntry.Kind] = [.firstView, .review(.again), .review(.hard), .review(.good)]

    /// What the chart's key names, in its order: every answer, also those
    /// the card hasn't had yet, after the import that put the card on its
    /// step, when one did, which can only be its first entry.
    private var keyKinds: [ReviewLogEntry.Kind] {
        guard let first = rows.first?.entry.kind, case .placement = first else {
            return Self.answers
        }
        return [first] + Self.answers
    }

    /// The ladder's steps, counted from 1 as Settings counts them.
    private var steps: ClosedRange<Int> {
        1...ladder.waits.count
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
    private var stepLabel: Text {
        Text("Step", comment: "For VoiceOver, the Cards window's chart: the card's step after each entry.")
    }

    /// The name of what colors the chart's points, for VoiceOver.
    private var answerLabel: Text {
        Text(
            "Answer", comment: "For VoiceOver, the Cards window's chart: what Lucas answered, which colors each point.")
    }

    /// Every entry, the latest first: when Lucas answered, what he answered,
    /// marked when it was a review ahead, and how long he took; or when the
    /// import put the card on its step, and which.
    private var entries: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
            ForEach(Array(rows.enumerated().reversed()), id: \.offset) { _, row in
                GridRow {
                    Text(row.entry.answeredAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        AnswerDot(kind: row.entry.kind)
                        Text(row.entryName)
                        if row.entry.isAhead {
                            AheadBadge()
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
    /// The step the entry's way stood on after it, counted from 1 as
    /// Settings counts them.
    fileprivate var stepNumber: Int {
        step + 1
    }

    /// The entry as the review log's list names it: what the user answered,
    /// or for a placement, the step the import put the card on.
    fileprivate var entryName: String {
        guard case .placement = entry.kind else {
            return entry.kind.name
        }
        return String(
            localized: "Imported on step \(stepNumber)",
            comment:
                "In the Cards window's review log: an import from Anki put the card on this step of the user's ladder, counted from 1."
        )
    }
}

extension ReviewLogEntry.Kind {
    /// What the user answered, as the review log names it in the Cards window:
    /// "First view", or the rating as the review panel's buttons name it; or
    /// "Imported", for the placement an import put the card on its step with.
    fileprivate var name: String {
        switch self {
        case .firstView:
            String(
                localized: "First view",
                comment: "In the Cards window's review log and its chart's key: the first time Lucas saw the card.")
        case .placement:
            String(
                localized: "Imported",
                comment:
                    "In the Cards window's review log chart's key: an import from Anki put the card on a step of the user's ladder."
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
        }
    }

    /// The color of what Lucas answered: neutral for a first view, and red,
    /// orange and green for "Don't know", "Sort of" and "Know it"; and blue
    /// for a placement.
    fileprivate var color: Color {
        switch self {
        case .firstView: .gray
        case .placement: .blue
        case .review(.again): .red
        case .review(.hard): .orange
        case .review(.good): .green
        }
    }
}
