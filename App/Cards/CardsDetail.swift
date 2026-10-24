import FichaCore
import FichaData
import SwiftUI

/// The card's front, after a flag when it's flagged and a mark when it's
/// buried, as where it stands says, since a buried card keeps its flag, and
/// after a photo when the front has an image.
struct FrontCell: View {
    let card: Card
    /// Whether a long front goes on over more lines, as below a capture in
    /// its detail, rather than being cut short, as in a table's row.
    var wraps = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            switch card.standing {
            case .inReviews, .setAside:
                EmptyView()
            case .inInbox:
                FlagIcon()
            case .buried(_, let flag):
                if flag != nil {
                    FlagIcon()
                }
                BuriedIcon()
            }
            if card.frontImage != nil {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        Text(
                            "Image",
                            comment: "The icon beside a card's front in the Cards window, when it has an image.")
                    )
                    .help(
                        Text(
                            "The front has an image",
                            comment: "The tooltip of the icon beside a card's front, when it has an image."))
            }
            Text(card.front)
                .lineLimit(wraps ? nil : 1)
                .fixedSize(horizontal: false, vertical: wraps)
        }
    }
}

/// The flag beside a flagged card, in the table and the detail.
private struct FlagIcon: View {
    var body: some View {
        Image(systemName: "flag.fill")
            .foregroundStyle(.orange)
            .accessibilityLabel(Text("Flagged", comment: "The flag icon beside a flagged card, in the Cards window."))
            .help(Text("Flagged", comment: "The flag icon beside a flagged card, in the Cards window."))
    }
}

/// The mark beside a buried card, in the table and the detail: the icon the
/// review panel's Bury button has.
private struct BuriedIcon: View {
    var body: some View {
        Image(systemName: "eye.slash")
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("Buried", comment: "The icon beside a buried card, in the Cards window."))
            .help(Text("Buried", comment: "The icon beside a buried card, in the Cards window."))
    }
}

/// The mark beside a set-aside card in the detail.
private struct SetAsideIcon: View {
    var body: some View {
        Image(systemName: "tag.slash")
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}

/// The selected card, whole: Lucas's note on top when it's flagged, when he
/// buried it when it's buried, and its set-aside tags when it's set aside,
/// its type and tags, its front and back, each side's image above its text,
/// and its source, where it stands, and its review log, in a chart and in
/// full.
struct CardDetail: View {
    let row: CardRow
    /// The images the window shows, the card's among them.
    let images: ShownImages
    /// The engine's time, which the due time counts from.
    let now: Date
    /// The card's review log, oldest first, or why it couldn't be read, or
    /// nil until it's read.
    let reviewLog: Result<[ReviewLogRow], EngineError>?
    /// The ladder Lucas set, whose steps the chart spans.
    let ladder: Ladder

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FlagAndBurial(standing: row.cardStanding)
                TypeAndTags(card: row.card)
                if let image = row.card.frontImage {
                    SideImage(image: images[image], maximumHeight: 320)
                }
                if !row.card.front.isEmpty {
                    Text(row.card.front)
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if row.card.frontImage != nil || row.card.backImage != nil {
                    // Which side is which, once an image makes them more
                    // than two lines of text.
                    Divider()
                }
                if let image = row.card.backImage {
                    SideImage(image: images[image], maximumHeight: 320)
                }
                if !row.card.back.isEmpty {
                    Text(row.card.back)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let source = row.card.source {
                    Text(source)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                standing
                switch reviewLog {
                case .success(let rows):
                    Divider()
                    ReviewLogView(rows: rows, ladder: ladder)
                case .failure(let error):
                    Divider()
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                case nil:
                    EmptyView()
                }
            }
            .textSelection(.enabled)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Where the card stands: its step and wait, when it's due, when Lucas
    /// last saw it and when he approved it.
    private var standing: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                gridLabel(
                    Text("Step", comment: "In the Cards window's detail: the card's step on the ladder, and its wait."))
                Text(stepText(row))
            }
            if let due = row.due {
                GridRow {
                    gridLabel(Text("Due", comment: "In the Cards window's detail: when the card is due."))
                    HStack(spacing: 6) {
                        Text(dueText(row, at: now))
                        Text(due.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let lastSeen = row.lastSeen {
                GridRow {
                    gridLabel(
                        Text(
                            "Last seen",
                            comment:
                                "In the Cards window's detail: when Lucas last saw the card, in a first view or a review."
                        ))
                    Text(lastSeen.formatted(date: .abbreviated, time: .shortened))
                }
            }
            GridRow {
                gridLabel(Text("Created", comment: "In the Cards window's detail: when Lucas approved the card."))
                Text(row.card.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }
}

/// A word in a capsule of the window's tint, on top of a detail: a card's
/// type, or what kind of capture it is.
private struct Chip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.tint.opacity(0.15), in: .capsule)
    }
}

/// A card's type, when it has one, and its tags after it when it has any.
private struct TypeAndTags: View {
    let card: Card

    var body: some View {
        HStack(spacing: 8) {
            if let type = card.type {
                Chip(text: type.name)
            }
            if !card.tags.isEmpty {
                Label(card.tags.formatted(.list(type: .and, width: .narrow)), systemImage: "tag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The capture selected in the inbox, whole: what kind it is, its text, its
/// note and source, when Lucas captured it, and, for an expansion or a
/// follow-up, the card it's tied to.
struct CaptureDetail: View {
    /// The card a capture is tied to, which its detail shows below it.
    enum Tie {
        /// The card an expansion expands.
        case expands(Card)
        /// The card a follow-up was asked about, in the review panel.
        case followsUp(Card)

        var card: Card {
            switch self {
            case .expands(let card), .followsUp(let card): card
            }
        }
    }

    let capture: Capture
    /// What kind it is, as the inbox's Kind column says it.
    let kind: String
    /// The card it's tied to, when it's an expansion or a follow-up.
    let tie: Tie?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Chip(text: kind)
                Text(capture.text)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                    if let note = capture.note {
                        GridRow {
                            gridLabel(
                                Text("Note", comment: "In the Cards window's detail: what Lucas noted with a capture."))
                            Text(note)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let source = capture.source {
                        GridRow {
                            gridLabel(
                                Text(
                                    "Source",
                                    comment: "In the Cards window's detail: where Lucas came across a capture's text."))
                            Text(source)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    GridRow {
                        gridLabel(Text("Captured", comment: "In the Cards window's detail: when Lucas captured it."))
                        Text(capture.createdAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                if let tie {
                    Divider()
                    tied(tie)
                }
            }
            .textSelection(.enabled)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The card the capture is tied to, under what ties them.
    private func tied(_ tie: Tie) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch tie {
            case .expands:
                Text(
                    "Expands this card",
                    comment: "In the Cards window's detail of an expansion, above the card it's attached to."
                )
                .foregroundStyle(.secondary)
            case .followsUp:
                Text(
                    "Asked about this card",
                    comment:
                        "In the Cards window's detail of a follow-up, above the card it was asked about in the review panel."
                )
                .foregroundStyle(.secondary)
            }
            TiedCard(card: tie.card)
        }
    }
}

/// The card an expansion or a follow-up is tied to, in its detail: its type
/// and tags, its front, with the marks the table gives it, and its back.
private struct TiedCard: View {
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TypeAndTags(card: card)
            FrontCell(card: card, wraps: true)
                .font(.headline)
            Text(card.back)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: .rect(cornerRadius: 8))
    }
}

/// What the detail says on top of a card that's out of Lucas's reviews, as
/// where it stands says: his note when it's flagged, and when he buried it
/// when it's buried, after the note it keeps, or which of its tags are set
/// aside when it's set aside. While he edits a flagged card, the note also
/// says that saving fixes it.
struct FlagAndBurial: View {
    let standing: CardStanding
    /// Whether Lucas is editing the card.
    var isEditing = false

    var body: some View {
        switch standing {
        case .inReviews:
            EmptyView()
        case .inInbox(let flag):
            note(flag)
        case .buried(let buriedAt, let flag):
            if let flag {
                note(flag)
            }
            burial(at: buriedAt)
        case .setAside(let tags):
            setAside(by: tags)
        }
    }

    /// Which of the card's tags are set aside, which keep it out of Lucas's
    /// reviews.
    private func setAside(by tags: [String]) -> some View {
        Label {
            Text(
                "Set aside with \(tags.formatted(.list(type: .and)))",
                comment: """
                    In the Cards window's detail: the card is out of Lucas's reviews for now, since these tags of it \
                    are set aside, like “Set aside with filosofía and historia”.
                    """
            )
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            SetAsideIcon()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: .rect(cornerRadius: 8))
    }

    /// Lucas's note on the flagged card.
    private func note(_ flag: Flag) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(flag.note)
                if isEditing {
                    // The same whether the card is buried or not: whether it
                    // goes back to Lucas's reviews is FichaData's to say, and
                    // the burial shows below.
                    Text(
                        "Saving fixes it, and it keeps its step.",
                        comment: "In the Cards window, under Lucas's note on a flagged card, while he edits it."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            FlagIcon()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 8))
    }

    /// When Lucas buried the card.
    private func burial(at buriedAt: Date) -> some View {
        Label {
            Text(
                "Buried on \(buriedAt.formatted(date: .abbreviated, time: .shortened))",
                comment: "In the Cards window's detail: when Lucas buried the card, like Oct 14, 2026 at 9:00 AM."
            )
        } icon: {
            BuriedIcon()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: .rect(cornerRadius: 8))
    }
}

/// A label in one of the detail's grids, before what it names: secondary, and
/// aligned to the trailing edge of its column.
func gridLabel(_ text: Text) -> some View {
    text
        .foregroundStyle(.secondary)
        .gridColumnAlignment(.trailing)
}

/// The card's step counted from 1, as Settings counts them, with its wait,
/// like "4 · 5d", or "New" before its first view.
func stepText(_ row: CardRow) -> String {
    guard let step = row.step, let wait = row.wait else {
        return String(localized: "New", comment: "In the Cards window: a card that hasn't had its first view yet.")
    }
    let waitText = wait.formatted(.units(allowed: [.days, .hours, .minutes], width: .narrow))
    return String(
        localized: "\(step + 1) · \(waitText)",
        comment:
            "In the Cards window: the card's step on the ladder, counted from 1, and how long it waits, like 4 · 5d."
    )
}

/// When the card is due, counted from `now`: "now" once it's due, however
/// long ago, and before, as the Mac's locale words it, like "in 2h",
/// "tomorrow" or "in 5d" in US English. "set aside" while it's set aside,
/// and nothing while it's new, flagged or buried, since it won't show up
/// then.
func dueText(_ row: CardRow, at now: Date) -> String {
    let due: Date
    switch row.dueColumn {
    case .due(let date):
        due = date
    case .setAside:
        return String(
            localized: "set aside",
            comment: """
                In the Cards window's Due column: the card won't show up, since one of its tags is set aside. \
                Lowercase, like “now”.
                """)
    case .nothing:
        return ""
    }
    guard !row.isDue(at: now) else {
        return String(localized: "now", comment: "In the Cards window's Due column: the card is due.")
    }
    // In the ladder's units, days, hours and minutes, as Settings shows its
    // waits: "in 8d", never "next week".
    var style = Date.AnchoredRelativeFormatStyle(anchor: due, presentation: .named, unitsStyle: .narrow)
    style.allowedFields = [.day, .hour, .minute]
    return style.format(now)
}
