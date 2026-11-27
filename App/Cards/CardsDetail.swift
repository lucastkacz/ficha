import FichaCore
import FichaData
import SwiftUI

/// The card's front, after a flag when it's flagged and a mark when it's set
/// aside on its own, as where it stands says, since a card set aside keeps
/// its flag, aligned with them as the front reads. A front without text says "Image"
/// or "Sound" in gray, as Mail says "No Subject", rather than leave the cell
/// empty.
struct FrontCell: View {
    let card: Card
    /// Whether a long front goes on over more lines, as below a capture in
    /// its detail, rather than being cut short, as in the inbox's row.
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
                SetAsideCardIcon()
            }
            if let media = card.frontWithoutText {
                mediaText(media)
                    .foregroundStyle(.secondary)
            } else {
                Text(card.front)
                    .lineLimit(wraps ? nil : 1)
                    .fixedSize(horizontal: false, vertical: wraps)
            }
        }
        .alignedAsItReads(card.front)
    }

    /// The word that stands for a front without text, as `media` says.
    private func mediaText(_ media: SideMedia) -> Text {
        switch media {
        case .image:
            Text("Image", comment: "The Cards window, in place of a card's front that has an image and no text.")
        case .sound:
            Text("Sound", comment: "The Cards window, in place of a card's front that has only a sound.")
        }
    }
}

/// The flag beside a flagged card, in the inbox and the detail.
private struct FlagIcon: View {
    var body: some View {
        Image(systemName: "flag.fill")
            .foregroundStyle(.orange)
            .accessibilityLabel(Text("Flagged", comment: "The flag icon beside a flagged card, in the Cards window."))
            .help(Text("Flagged", comment: "The flag icon beside a flagged card, in the Cards window."))
    }
}

/// The mark beside a card set aside on its own in the detail, as beside the
/// card an expansion or a follow-up is tied to: an eye crossed out, since the
/// card stays out of the reviews until it's put back (#539). The inbox lists
/// no card set aside on its own.
private struct SetAsideCardIcon: View {
    var body: some View {
        Image(systemName: "eye.slash")
            .foregroundStyle(.secondary)
            .accessibilityLabel(
                Text("Set aside", comment: "The icon beside a card set aside on its own, in the Cards window."))
            .help(Text("Set aside", comment: "The icon beside a card set aside on its own, in the Cards window."))
    }
}

/// The mark beside a card set aside with its deck in the detail.
private struct SetAsideIcon: View {
    var body: some View {
        Image(systemName: "rectangle.portrait.on.rectangle.portrait.slash")
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}

/// The selected card, whole: Lucas's note on top when it's flagged, when he
/// set it aside when it's set aside on its own, and its set-aside decks when
/// it's set aside with its deck, whether it goes both ways, its front and
/// back, each side's image above its text and its sound below it, and its
/// source; then, in words, that it's new, or when it's back and how many
/// times he saw it (`CardWords`); and under Details, closed until he opens
/// it, where it stands as Anki's Card Info says it, and its review log, in a
/// chart and in full (#537). Details is a disclosure triangle, which Tab
/// reaches while macOS's Keyboard navigation is on and Space opens, and
/// VoiceOver reads and opens as one. Its front, back, source and images show
/// at the card size, and the rest stays its size.
struct CardDetail: View {
    let row: CardRow
    /// Where the card is, in words, as the window says it.
    let wording: CardRow.Wording
    /// The images the window shows, the card's among them.
    let images: ShownImages
    /// The engine's time, which the due time counts from.
    let now: Date
    /// The card's review log, oldest first, or why it couldn't be read, or
    /// nil until it's read.
    let reviewLog: Result<[ReviewLogRow], EngineError>?
    /// Whether Details is open, as the window keeps it from card to card.
    @Binding var isDetailsOpen: Bool
    /// The ▶ and the length of a side's sound, which the window fills.
    let soundControls: (CardSide) -> SoundControls
    @Environment(\.cardSize) private var cardSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FlagAndSetAside(standing: row.cardStanding)
                BothWaysMark(card: row.card)
                if let image = row.card.frontImage {
                    SideImage(image: images[image], maximumHeight: cardSize.scaled(320))
                }
                if !row.card.front.isEmpty {
                    TextAsItReads(row.card.front)
                        .cardFont(.title)
                }
                if row.card.frontSound != nil {
                    soundControls(.front)
                }
                if [row.card.frontImage, row.card.backImage].contains(where: { $0 != nil })
                    || [row.card.frontSound, row.card.backSound].contains(where: { $0 != nil })
                {
                    // Which side is which, once an image or a sound makes
                    // them more than two lines of text.
                    Divider()
                }
                if let image = row.card.backImage {
                    SideImage(image: images[image], maximumHeight: cardSize.scaled(320))
                }
                if !row.card.back.isEmpty {
                    TextAsItReads(row.card.back)
                        .cardFont(.body)
                }
                if row.card.backSound != nil {
                    soundControls(.back)
                }
                if let source = row.card.source {
                    TextAsItReads(source)
                        .cardFont(.callout)
                        .foregroundStyle(.secondary)
                }
                Divider()
                CardWords(wording: wording)
                DisclosureGroup(isExpanded: $isDetailsOpen) {
                    details
                        .padding(.top, 8)
                } label: {
                    Text(
                        "Details",
                        comment: """
                            In the Cards window's detail, the disclosure under a card's words that holds its numbers, \
                            as Anki's Card Info shows them, and its review log, closed until the user opens it.
                            """)
                }
            }
            .textSelection(.enabled)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// What Details holds: where the card stands, and its review log, or why
    /// it couldn't be read.
    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            standing
            switch reviewLog {
            case .success(let rows):
                Divider()
                ReviewLogView(rows: rows)
            case .failure(let error):
                Divider()
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            case nil:
                EmptyView()
            }
        }
    }

    /// Where the card stands, and why it shows up when it does, as Anki's
    /// Card Info says: its interval, when it's due, and its stability,
    /// difficulty and retrievability once it has them, front first, and
    /// back first too when it goes both ways; when Lucas last saw it, how
    /// many times he reviewed it, when he approved it, and, once its front
    /// or back changed since, when they last did.
    private var standing: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
            wayRows(
                row.frontFirst,
                labels: WayLabels(
                    interval: Text(
                        "Interval",
                        comment: "In the Cards window's detail: how long the card waits after its last review."),
                    due: Text("Due", comment: "In the Cards window's detail: when the card is due."),
                    stability: Text(
                        "Stability",
                        comment: """
                            In the Cards window's detail, as Anki's Card Info says it: FSRS's stability, how many days \
                            it takes the chance of remembering the card to fall to 90%.
                            """),
                    difficulty: Text(
                        "Difficulty",
                        comment: """
                            In the Cards window's detail, as Anki's Card Info says it: FSRS's difficulty, how hard the \
                            card is to remember, as a percentage.
                            """),
                    retrievability: Text(
                        "Retrievability",
                        comment: """
                            In the Cards window's detail, as Anki's Card Info says it: FSRS's retrievability, the \
                            chance of remembering the card now.
                            """)))
            if let backFirst = row.backFirst {
                wayRows(
                    backFirst,
                    labels: WayLabels(
                        interval: Text(
                            "Back-first interval",
                            comment:
                                "In the Cards window's detail: how long a card that goes both ways waits after its last review back first."
                        ),
                        due: Text(
                            "Back-first due",
                            comment: "In the Cards window's detail: when a card that goes both ways is due back first."
                        ),
                        stability: Text(
                            "Back-first stability",
                            comment: """
                                In the Cards window's detail, for a card that goes both ways: FSRS's stability back \
                                first, as Anki's Card Info says it, how many days it takes the chance of remembering \
                                the card back first to fall to 90%.
                                """),
                        difficulty: Text(
                            "Back-first difficulty",
                            comment: """
                                In the Cards window's detail, for a card that goes both ways: FSRS's difficulty back \
                                first, as Anki's Card Info says it, how hard the card is to remember back first, as a \
                                percentage.
                                """),
                        retrievability: Text(
                            "Back-first retrievability",
                            comment: """
                                In the Cards window's detail, for a card that goes both ways: FSRS's retrievability \
                                back first, as Anki's Card Info says it, the chance of remembering the card back \
                                first now.
                                """)))
            }
            if let lastSeen = row.lastSeen {
                GridRow {
                    gridLabel(
                        Text(
                            "Last seen",
                            comment:
                                "In the Cards window's detail: when Lucas last reviewed the card."
                        ))
                    Text(lastSeen.formatted(date: .abbreviated, time: .shortened))
                }
            }
            GridRow {
                gridLabel(
                    Text(
                        "Reviews",
                        comment: "In the Cards window's detail: how many times Lucas reviewed the card, either way."))
                reviews
            }
            GridRow {
                gridLabel(Text("Created", comment: "In the Cards window's detail: when Lucas approved the card."))
                Text(row.card.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
            if let editedAt = row.card.editedAt {
                GridRow {
                    gridLabel(
                        Text(
                            "Edited",
                            comment: """
                                In the Cards window's detail: when the card's front or back last changed, a side's \
                                image or sound included.
                                """))
                    Text(editedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
    }

    /// How many times Lucas reviewed the card, as `ReviewsText` says it, and,
    /// while it goes both ways, how many of those went each way in
    /// secondary text, which VoiceOver reads after the count with its noun.
    @ViewBuilder
    private var reviews: some View {
        if let backFirst = row.backFirst {
            reviewsByWay(Text(row.reviews, format: .number).foregroundStyle(.primary), backFirst: backFirst)
                .foregroundStyle(.secondary)
                .accessibilityLabel(reviewsByWay(Text(ReviewsText.spoken(row.reviews)), backFirst: backFirst))
        } else {
            ReviewsText(count: row.reviews)
        }
    }

    /// `total`, the card's reviews either way, then how many of them went
    /// each way, whose back-first way is `backFirst`.
    private func reviewsByWay(_ total: Text, backFirst: WayProgress) -> Text {
        Text(
            "\(total) · \(row.frontFirst.reviews) front first, \(backFirst.reviews) back first",
            comment: """
                In the Cards window's detail, for a card that goes both ways: how many times Lucas reviewed it, either \
                way, then how many of those went front first and back first, like “14 · 9 front first, 5 back first”. \
                The first value is the number, and for VoiceOver the number with its noun, like “14 reviews”.
                """)
    }

    /// What the rows of one of the card's ways are labeled.
    private struct WayLabels {
        let interval: Text
        let due: Text
        let stability: Text
        let difficulty: Text
        let retrievability: Text
    }

    /// Where one of the card's ways stands, in rows of the grid labeled as
    /// `labels` say: its interval, as `WayIntervalText` says it, when it's
    /// due, while it has a due time, and, once FSRS has a memory of it, its
    /// stability, in days, its difficulty, as a percentage, and its
    /// retrievability, the chance of remembering it now, as a percentage
    /// too, as Anki's Card Info shows them, and as VoiceOver reads them,
    /// with their units.
    @ViewBuilder
    private func wayRows(_ way: WayProgress, labels: WayLabels) -> some View {
        GridRow {
            gridLabel(labels.interval)
            WayIntervalText(way: way)
        }
        if let due = way.due {
            GridRow {
                gridLabel(labels.due)
                HStack(spacing: 6) {
                    Text(DueText.of(way, at: now))
                    Text(due.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            }
        }
        if let memory = way.memory {
            GridRow {
                gridLabel(labels.stability)
                Text(
                    Duration(days: memory.stabilityInDays).formatted(
                        .units(allowed: [.days], width: .wide, fractionalPart: .show(length: 1))))
            }
            GridRow {
                gridLabel(labels.difficulty)
                Text(memory.difficulty.formatted(.percent.precision(.fractionLength(0))))
            }
            GridRow {
                gridLabel(labels.retrievability)
                Text(memory.retrievability.formatted(.percent.precision(.fractionLength(0))))
            }
        }
    }
}

/// Where a card is, in words, as FichaData says it (`CardRow.Wording`), as
/// the desktop mock's card pane says it: that a new card waits its turn in
/// the queue, as the grid's legend says "New: waits its turn"; and of any
/// other card, when it's back, "Due now", as the grid's dot says, "Back today
/// at" a time, "Back on" a day, by its weekday, month and day, and its year
/// when it isn't this year's, as the Mac's locale writes them, or that it's
/// out of Lucas's reviews; and under it, how many times he saw it, "Seen 3
/// times".
private struct CardWords: View {
    let wording: CardRow.Wording

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch wording {
            case .new:
                Text(
                    "New: it waits its turn in the queue.",
                    comment: """
                        In the Cards window's detail, of a card the user hasn't met yet, which waits its turn in the \
                        queue of new cards, as the grid's “New: waits its turn” says.
                        """)
            case .seen(let times, let back):
                backText(back)
                Text(
                    "Seen \(times) times",
                    comment: """
                        In the Cards window's detail, under when the card is back: how many times the user reviewed \
                        it, either way, like “Seen 3 times”. None for a new card out of the user's reviews, \
                        and for a card an import from Anki brought in with its progress, which the user hasn't \
                        reviewed in Ficha since.
                        """
                )
                .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// When the card is back, as `back` says.
    private func backText(_ back: CardRow.Wording.Back) -> Text {
        switch back {
        case .now:
            Text(
                "Due now",
                comment: """
                    In the Cards window's detail: the card is due, front first or back first, as the orange dot on \
                    its tile says.
                    """)
        case .today(let time):
            Text(
                "Back today at \(time.formatted(date: .omitted, time: .shortened))",
                comment: """
                    In the Cards window's detail: the card is due again later today, at this time, like “Back today \
                    at 3:00 PM”. Today is Ficha's day, which runs until 4:00 the next morning, or the hour the user \
                    set, so at 11:00 PM a card due at 2:00 AM is back today.
                    """)
        case .on(let day, let inThisYear):
            Text(
                "Back on \(day.formatted(Self.dayFormat(inThisYear: inThisYear)))",
                comment: """
                    In the Cards window's detail: the card is due again on a later day, by its weekday, month and \
                    day, and its year when it isn't this year, like “Back on Tue, Dec 15” or “Back on Fri, \
                    Jan 21, 2028”. The day is Ficha's, which starts at 4:00, or the hour the user set, so a card due \
                    at 2:00 AM on a Friday is back on Thursday.
                    """)
        case .outOfReviews:
            Text(
                "Out of your reviews",
                comment: """
                    In the Cards window's detail, in place of when the card is back: it's out of the user's \
                    reviews, and the box above the card says why, so it isn't due until it's back in them.
                    """)
        }
    }

    /// How "Back on" writes a later day: by its weekday, month and day, and
    /// its year too when it isn't this year's.
    private static func dayFormat(inThisYear: Bool) -> Date.FormatStyle {
        let format: Date.FormatStyle = .dateTime.weekday(.abbreviated).month(.abbreviated).day()
        return inThisYear ? format : format.year()
    }
}

/// A word in a capsule of the window's tint, on top of a capture's detail:
/// what kind of capture it is.
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

/// Both ways, above a card's front while it goes both ways. A card shows
/// neither its type nor its tags, which the database keeps (#538).
private struct BothWaysMark: View {
    let card: Card

    var body: some View {
        if card.bothWays {
            Label {
                Text(
                    "Both ways",
                    comment: """
                        In the Cards window's detail, above a card's front: it's also reviewed back first, its back, \
                        then its front.
                        """)
            } icon: {
                // Arrows both ways, the same mirrored, so no backward and
                // forward.
                Image(systemName: "arrow.left.arrow.right")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

/// The capture selected in the inbox, whole: what kind it is, its text, its
/// note and source, when Lucas captured it, and, for an expansion or a
/// follow-up, the card it's tied to. Its text, note and source show at the card
/// size, and the rest stays its size.
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
                TextAsItReads(capture.text)
                    .cardFont(.title)
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                    if let note = capture.note {
                        GridRow {
                            gridLabel(
                                Text("Note", comment: "In the Cards window's detail: what Lucas noted with a capture."))
                            TextAsItReads(note)
                                .cardFont(.body)
                        }
                    }
                    if let source = capture.source {
                        GridRow {
                            gridLabel(
                                Text(
                                    "Source",
                                    comment: "In the Cards window's detail: where Lucas came across a capture's text."))
                            TextAsItReads(source)
                                .cardFont(.body)
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

/// The card an expansion or a follow-up is tied to, in its detail: whether
/// it goes both ways, its front, with the marks the inbox gives it, and its
/// back.
private struct TiedCard: View {
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BothWaysMark(card: card)
            FrontCell(card: card, wraps: true)
                .font(.headline)
            TextAsItReads(card.back)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: .rect(cornerRadius: 8))
    }
}

/// What the detail says on top of a card that's out of Lucas's reviews, as
/// where it stands says: his note when it's flagged, and when he set it
/// aside when it's set aside on its own, which the engine keeps as its
/// burial, after the note it keeps, or which decks set it aside, its own or
/// decks it sits inside, when it's set aside with its deck. While he edits a
/// flagged card, the note also says that saving fixes it.
struct FlagAndSetAside: View {
    let standing: CardStanding
    /// Whether Lucas is editing the card.
    var isEditing = false

    var body: some View {
        switch standing {
        case .inReviews:
            EmptyView()
        case .inInbox(let flag):
            note(flag)
        case .buried(let setAsideAt, let flag):
            if let flag {
                note(flag)
            }
            setAside(at: setAsideAt)
        case .setAside(let decks):
            setAside(by: decks)
        }
    }

    /// Which set-aside decks, the card's own or decks it sits inside, keep it
    /// out of Lucas's reviews, outermost first, each by its whole name.
    private func setAside(by decks: [String]) -> some View {
        Label {
            Text(
                "Set aside with \(decks.map(Deck.shownName).formatted(.list(type: .and)))",
                comment: """
                    In the Cards window's detail: the card is out of Lucas's reviews for now, since these decks are \
                    set aside, its own or decks it sits inside, outermost first, each by its whole name, like “Set \
                    aside with Historia and Historia › Roma”.
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
                    // The same whether the card is set aside or not: whether
                    // it goes back to Lucas's reviews is FichaData's to say,
                    // and when he set it aside shows below.
                    Text(
                        "Saving fixes it, and it keeps its progress.",
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

    /// When Lucas set the card aside on its own, which he puts back with Put
    /// Back, below.
    private func setAside(at setAsideAt: Date) -> some View {
        Label {
            Text(
                "Set aside on \(setAsideAt.formatted(date: .abbreviated, time: .shortened))",
                comment: """
                    In the Cards window's detail: when Lucas set the card aside on its own, like Oct 14, 2026 at \
                    9:00 AM.
                    """
            )
        } icon: {
            SetAsideCardIcon()
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

/// What one of a card's ways says in the Cards window's detail's Interval
/// rows, as Anki's Browse says it: how long it waits after its last
/// review, like "5d", "2h 30m" or "1.5mo", which VoiceOver reads in words;
/// "New" before its first review; or "Learning" while it's in its learning
/// steps, whatever the step's interval, as Anki's Browse says "(learning)".
struct WayIntervalText: View {
    let way: WayProgress

    var body: some View {
        switch way.intervalWording {
        case .new:
            Text(Self.new)
        case .learning:
            Text(Self.learning)
        case .interval(let interval):
            Text(intervalText(interval))
                .accessibilityLabel(spokenIntervalText(interval))
        }
    }

    /// A way before its first review.
    static var new: String {
        String(
            localized: "New",
            comment:
                "In the Cards window: a card that hasn't had its first review yet, or its back-first way, when it goes both ways."
        )
    }

    /// A way in its learning steps.
    static var learning: String {
        String(
            localized: "Learning",
            comment: """
                In the Cards window's detail's Interval rows: a card in its learning steps, the short intervals \
                before it graduates, whatever the step's interval, as Anki's Browse says “(learning)”; or a card \
                an import from Anki brought in while Anki was still learning it.
                """)
    }
}

/// How many times a card was reviewed, either way, as the Cards window's
/// detail's Reviews row says it: a number, which VoiceOver reads with its
/// noun, like "14 reviews".
struct ReviewsText: View {
    let count: Int

    var body: some View {
        Text(count, format: .number)
            .accessibilityLabel(Self.spoken(count))
    }

    /// `count` as VoiceOver reads it.
    static func spoken(_ count: Int) -> String {
        String(
            localized: "\(count) reviews",
            comment: """
                For VoiceOver, in the Cards window's detail's Reviews row: how many times Lucas reviewed the card, \
                either way.
                """)
    }
}

/// The texts of the Cards window's detail's Due and Back-first due rows,
/// which `of(_:at:)` picks from.
enum DueText {
    /// When one of a card's ways is due, counted from `now`: "now" once it's
    /// due, however long ago, and before, as the app's locale words it, like
    /// "in 2h", "tomorrow" or "in 5d" in US English. "set aside" while the
    /// card is set aside, on its own or by its deck, and nothing while the
    /// way is new, or the card flagged, since it won't show up then.
    static func of(_ way: WayProgress, at now: Date) -> String {
        switch way.dueWording {
        case .due(let date): way.isDue(at: now) ? Self.now : until(date, from: now)
        case .setAside: setAside
        case .nothing: ""
        }
    }

    /// A way that's due, however long ago.
    static var now: String {
        String(
            localized: "now",
            comment: """
                In the Cards window's detail's Due and Back-first due rows: the card is due, front first or back \
                first.
                """)
    }

    /// A way that won't show up, since its card is set aside, on its own or
    /// by its deck.
    static var setAside: String {
        String(
            localized: "set aside",
            comment: """
                In the Cards window's detail's Due and Back-first due rows: the card won't show up, since it's set \
                aside, on its own or with its deck, or a deck it sits inside. Lowercase, like “now”.
                """)
    }

    /// How long from `now` until `due`, as the app's locale words it.
    static func until(_ due: Date, from now: Date) -> String {
        // In days, hours and minutes, the units of a step's interval and of a
        // graduated one under a month: "in 8d", never "next week", and "in
        // 45d" where the Interval row says "1.5mo".
        var style = Date.AnchoredRelativeFormatStyle(anchor: due, presentation: .named, unitsStyle: .narrow)
        style.allowedFields = [.day, .hour, .minute]
        return style.format(now)
    }
}
