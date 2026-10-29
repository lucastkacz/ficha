import FichaCore
import FichaData
import SwiftUI

/// The card's front, after a flag when it's flagged and a mark when it's
/// buried, as where it stands says, since a buried card keeps its flag. A
/// front without text says "Image" or "Sound" in gray, as Mail says "No
/// Subject", rather than leave the cell empty.
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
            if let media = card.frontWithoutText {
                mediaText(media)
                    .foregroundStyle(.secondary)
            } else {
                Text(card.front)
                    .lineLimit(wraps ? nil : 1)
                    .fixedSize(horizontal: false, vertical: wraps)
            }
        }
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

/// What the card holds besides its text, in the table's Media column: a
/// photo when a side has an image and a speaker when one has a sound, each
/// saying which sides in its tooltip, and nothing for a card of text alone.
struct MediaCell: View {
    let card: Card

    var body: some View {
        HStack(spacing: 4) {
            if let sides = card.sidesWithImages {
                mark("photo", saying: imagesText(sides))
            }
            if let sides = card.sidesWithSounds {
                mark("speaker.wave.2", saying: soundsText(sides))
            }
        }
        .foregroundStyle(.secondary)
    }

    /// The icon named `systemName`, which says `text` in its tooltip and to
    /// VoiceOver.
    private func mark(_ systemName: String, saying text: Text) -> some View {
        Image(systemName: systemName)
            .accessibilityLabel(text)
            .help(text)
    }

    /// Which sides have an image, as the photo's tooltip says it.
    private func imagesText(_ sides: WhichSides) -> Text {
        switch sides {
        case .front:
            Text(
                "The front has an image",
                comment: "The tooltip of the photo in the Cards window's Media column, when the card's front has one.")
        case .back:
            Text(
                "The back has an image",
                comment: "The tooltip of the photo in the Cards window's Media column, when the card's back has one.")
        case .both:
            Text(
                "Both sides have an image",
                comment: "The tooltip of the photo in the Cards window's Media column, when both sides have one.")
        }
    }

    /// Which sides have a sound, as the speaker's tooltip says it.
    private func soundsText(_ sides: WhichSides) -> Text {
        switch sides {
        case .front:
            Text(
                "The front has a sound",
                comment: "The tooltip of the speaker in the Cards window's Media column, when the card's front has one."
            )
        case .back:
            Text(
                "The back has a sound",
                comment: "The tooltip of the speaker in the Cards window's Media column, when the card's back has one.")
        case .both:
            Text(
                "Both sides have a sound",
                comment: "The tooltip of the speaker in the Cards window's Media column, when both sides have one.")
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
/// its type and tags and whether it goes both ways, its front and back, each
/// side's image above its text and its sound below it, and its source, where
/// it stands, and its review log, in a chart and in full.
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
    /// The ▶ and the length of a side's sound, which the window fills.
    let soundControls: (CardSide) -> SoundControls

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
                    SideImage(image: images[image], maximumHeight: 320)
                }
                if !row.card.back.isEmpty {
                    Text(row.card.back)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if row.card.backSound != nil {
                    soundControls(.back)
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

    /// Where the card stands: its step and wait, and when it's due, front
    /// first, and back first too when it goes both ways, as the table's
    /// columns name them; when Lucas last saw it and when he approved it.
    private var standing: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
            wayRows(
                row.frontFirst,
                step: Text(
                    "Step", comment: "In the Cards window's detail: the card's step on the ladder, and its wait."),
                due: Text("Due", comment: "In the Cards window's detail: when the card is due."))
            if let backFirst = row.backFirst {
                wayRows(
                    backFirst,
                    step: Text(
                        "Back-first step",
                        comment:
                            "In the Cards window's detail: the step on the ladder of a card that goes both ways, back first, and its wait."
                    ),
                    due: Text(
                        "Back-first due",
                        comment: "In the Cards window's detail: when a card that goes both ways is due back first."))
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

    /// Where one of the card's ways stands, in two rows of the grid labeled
    /// `stepLabel` and `dueLabel`: its step and wait, and when it's due,
    /// while it has a due time.
    @ViewBuilder
    private func wayRows(_ way: WayProgress, step stepLabel: Text, due dueLabel: Text) -> some View {
        GridRow {
            gridLabel(stepLabel)
            Text(stepText(way))
        }
        if let due = way.due {
            GridRow {
                gridLabel(dueLabel)
                HStack(spacing: 6) {
                    Text(dueText(way, at: now))
                    Text(due.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
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

/// A card's type, when it has one, its tags after it when it has any, and
/// Both ways last when it goes both ways.
private struct TypeAndTags: View {
    let card: Card

    var body: some View {
        HStack(spacing: 8) {
            if let type = card.type {
                Chip(text: type.title)
            }
            if !card.tags.isEmpty {
                Label(card.tags.map(TagPath.shown).formatted(.list(type: .and, width: .narrow)), systemImage: "tag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if card.bothWays {
                Label {
                    Text(
                        "Both ways",
                        comment: """
                            In the Cards window's detail, after a card's type and tags: it's also reviewed back \
                            first, its back, then its front.
                            """)
                } icon: {
                    Image(systemName: "arrow.left.arrow.right")
                }
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

/// The card an expansion or a follow-up is tied to, in its detail: its type,
/// tags and whether it goes both ways, its front, with the marks the table
/// gives it, and its back.
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

    /// Which set-aside tags, the card's own or tags they sit inside, keep it
    /// out of Lucas's reviews, each by its whole name.
    private func setAside(by tags: [String]) -> some View {
        Label {
            Text(
                "Set aside with \(tags.map(TagPath.shown).formatted(.list(type: .and)))",
                comment: """
                    In the Cards window's detail: the card is out of Lucas's reviews for now, since these tags are set \
                    aside, its own or tags they sit inside, each by its whole name, like “Set aside with filosofía and \
                    economía › Argentina”.
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

/// The step of one of a card's ways counted from 1, as Settings counts them,
/// with its wait, like "4 · 5d", or "New" before its first view.
func stepText(_ way: WayProgress) -> String {
    guard let step = way.step, let wait = way.wait else {
        return String(
            localized: "New",
            comment:
                "In the Cards window: a card that hasn't had its first view yet, or its back-first way, when it goes both ways."
        )
    }
    let waitText = wait.formatted(.units(allowed: [.days, .hours, .minutes], width: .narrow))
    return String(
        localized: "\(step + 1) · \(waitText)",
        comment:
            "In the Cards window: the card's step on the ladder, front first or back first, counted from 1, and how long it waits, like 4 · 5d."
    )
}

/// When one of a card's ways is due, counted from `now`: "now" once it's
/// due, however long ago, and before, as the Mac's locale words it, like
/// "in 2h", "tomorrow" or "in 5d" in US English. "set aside" while the card
/// is set aside, and nothing while the way is new, or the card flagged or
/// buried, since it won't show up then.
func dueText(_ way: WayProgress, at now: Date) -> String {
    let due: Date
    switch way.dueColumn {
    case .due(let date):
        due = date
    case .setAside:
        return String(
            localized: "set aside",
            comment: """
                In the Cards window's Due and Back-first due columns: the card won't show up, since one of its tags, \
                or a tag one of them sits inside, is set aside. Lowercase, like “now”.
                """)
    case .nothing:
        return ""
    }
    guard !way.isDue(at: now) else {
        return String(
            localized: "now",
            comment: "In the Cards window's Due and Back-first due columns: the card is due, front first or back first."
        )
    }
    // In the ladder's units, days, hours and minutes, as Settings shows its
    // waits: "in 8d", never "next week".
    var style = Date.AnchoredRelativeFormatStyle(anchor: due, presentation: .named, unitsStyle: .narrow)
    style.allowedFields = [.day, .hour, .minute]
    return style.format(now)
}
