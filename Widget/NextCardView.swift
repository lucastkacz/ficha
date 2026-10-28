import AppKit
import FichaCore
import FichaData
import SwiftUI
import WidgetKit

/// What the widget shows from a time on, as WidgetKit keeps it in a timeline:
/// by the system's time, which WidgetKit's timeline runs on, also in Ficha
/// Dev, whose engine runs ahead of it.
struct NextCardEntry: TimelineEntry {
    /// What the widget shows: what the engine decided, or why it couldn't.
    enum Shows: Sendable, Equatable {
        /// What the engine decided, by the system's time, with the image on
        /// the card's side, made small, when it has one and it could be read.
        case content(WidgetContent, image: Data?)
        /// There's no database to read yet, or it waits for the app to
        /// migrate it: the app hasn't opened it since it was installed or
        /// updated.
        case notReady
        /// The cards couldn't be read, for this reason, which the log details.
        case unreadable(String)
    }

    let date: Date
    let shows: Shows

    /// What the widget gallery and WidgetKit show while the widget loads: a
    /// card of its own, never one of Lucas's.
    static func placeholder(at date: Date) -> NextCardEntry {
        NextCardEntry(
            date: date,
            shows: .content(
                .card(
                    WidgetCard(
                        way: CardWay(cardID: 0, way: .frontFirst), isNew: false, side: .front, text: "serendipia",
                        image: nil, showsSpeaker: false)),
                image: nil))
    }
}

/// The widget's view: the card a review now would start with, by the side
/// the review panel shows first, with its image, or a speaker when the side
/// holds only a sound, and its badges, "New" and "Back first"; or when the
/// next card comes; or that there's none, or why the cards couldn't be read.
/// The engine decides what it shows, and the link a click on it opens, and
/// the view draws it at the widget's size, `family`. Its margins and its
/// background are WidgetKit's.
struct NextCardView: View {
    let entry: NextCardEntry
    let family: WidgetFamily

    private let variant = AppVariant.current

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(link.url(scheme: variant.urlScheme))
    }

    /// The link a click opens: a review now, which starts with the card the
    /// widget shows, if it shows one.
    private var link: WidgetLink {
        switch entry.shows {
        case .content(let content, _): content.link
        case .notReady, .unreadable: WidgetLink(startingWith: nil)
        }
    }

    /// The app's icon, and its name unless the small size needs the room for
    /// the card's badges, and the badges, when it has some.
    private var header: some View {
        HStack(spacing: 4) {
            Group {
                if family == .systemSmall, hasBadges {
                    Image(systemName: variant.menuBarSymbol)
                        .accessibilityLabel(Text(verbatim: variant.name))
                } else {
                    Label {
                        Text(verbatim: variant.name)
                    } icon: {
                        Image(systemName: variant.menuBarSymbol)
                    }
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            Spacer(minLength: 4)
            if case .content(.card(let card), _) = entry.shows {
                if card.isNew {
                    Badge(
                        title: Text("New", comment: "A badge on the card the widget shows, when it's new."),
                        isProminent: true)
                }
                if card.way.way == .backFirst {
                    Badge(
                        title: Text(
                            "Back first",
                            comment: "A badge on the card the widget shows, when it shows its back first."),
                        isProminent: false)
                }
            }
        }
    }

    /// Whether the card the widget shows has a badge.
    private var hasBadges: Bool {
        guard case .content(.card(let card), _) = entry.shows else { return false }
        return card.isNew || card.way.way == .backFirst
    }

    @ViewBuilder
    private var content: some View {
        switch entry.shows {
        case .content(.card(let card), let image):
            CardSideView(card: card, image: image, family: family)
        case .content(.nextCard(let time), _):
            message(
                Text("No card waiting", comment: "In the widget, when no card waits to be reviewed."),
                detail: nextCardLine(time), symbol: "checkmark.circle")
        case .content(.noneComing, _):
            message(
                Text(
                    "No cards to review",
                    comment:
                        "In the widget, when no card waits and none comes on its own: they're buried, flagged or set aside."
                ),
                detail: nil, symbol: "checkmark.circle")
        case .content(.noCards, _):
            message(
                Text("No cards yet", comment: "In the widget, when the user has no cards at all."), detail: nil,
                symbol: "rectangle.stack")
        case .notReady:
            message(
                Text(
                    "Open \(variant.name) to see your next card.",
                    comment: "In the widget, before the app made or updated its database."),
                detail: nil, symbol: "rectangle.stack")
        case .unreadable(let reason):
            message(
                Text(
                    "\(variant.name) can't read your cards.",
                    comment: "In the widget, when it couldn't read the cards. The reason follows, small."),
                detail: Text(reason), symbol: "exclamationmark.triangle")
        }
    }

    /// A message in place of a card, in the middle: a symbol above a line, and
    /// a detail under it, smaller, when there's one.
    private func message(_ line: Text, detail: Text?, symbol: String) -> some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            line
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                detail
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    /// When the next card comes: its time, today, and its day too on
    /// another, which stays right whenever the widget shows it, since the
    /// card comes before its day ends.
    private func nextCardLine(_ time: Date) -> Text {
        let calendar = Calendar.autoupdatingCurrent
        let hour = time.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(time, inSameDayAs: entry.date) {
            return Text("Next card at \(hour)", comment: "In the widget: when the next card comes, today.")
        }
        let inAWeek = calendar.date(byAdding: .day, value: 6, to: calendar.startOfDay(for: entry.date))
        let day =
            if let inAWeek, time < inAWeek {
                time.formatted(.dateTime.weekday(.wide))
            } else {
                time.formatted(.dateTime.month(.abbreviated).day())
            }
        return Text(
            "Next card on \(day) at \(hour)",
            comment: "In the widget: when the next card comes, another day. The day is a weekday or a date.")
    }
}

/// The side of the card the widget shows, in the middle, as the review panel
/// shows a card: its image, fitted to the widget, beside its text in the
/// medium size and above it otherwise, its text, or a speaker when it holds
/// only a sound. An image that couldn't be read shows as a symbol.
private struct CardSideView: View {
    let card: WidgetCard
    /// The image, made small, or nil when the side has none or it couldn't be
    /// read.
    let image: Data?
    let family: WidgetFamily

    var body: some View {
        Group {
            if card.image != nil, family == .systemMedium {
                HStack(spacing: 12) {
                    picture
                    text
                }
            } else {
                VStack(spacing: 8) {
                    if card.image != nil {
                        picture
                    }
                    // The image gives up the room the text needs.
                    text
                        .layoutPriority(1)
                    if card.showsSpeaker {
                        speaker
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var picture: some View {
        if let image, let picture = NSImage(data: image) {
            Image(nsImage: picture)
                .resizable()
                .scaledToFit()
                .clipShape(.rect(cornerRadius: 6))
                .frame(maxWidth: .infinity, maxHeight: family == .systemLarge ? 220 : .infinity)
                .accessibilityLabel(Text("Image", comment: "The accessibility label of an image on a card's side."))
        } else {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(
                    Text(
                        "Image that couldn't be shown",
                        comment: "In the widget, in place of an image on a card's side that couldn't be read."))
        }
    }

    @ViewBuilder
    private var text: some View {
        if !card.text.isEmpty {
            Text(card.text)
                .font(font.weight(.semibold))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .lineLimit(card.image == nil ? nil : lines)
                .frame(maxWidth: .infinity)
        }
    }

    private var speaker: some View {
        Image(systemName: "speaker.wave.2.fill")
            .font(.system(size: family == .systemSmall ? 34 : 44))
            .foregroundStyle(.tint)
            .accessibilityLabel(
                Text("Sound", comment: "In the widget, the speaker on a card's side that holds only a sound."))
    }

    /// The text's size: larger as the widget is, and a step smaller beside or
    /// under an image.
    private var font: Font {
        let besideAnImage = card.image != nil
        return switch family {
        case .systemSmall: besideAnImage ? .headline : .title2
        case .systemLarge, .systemExtraLarge: besideAnImage ? .title : .largeTitle
        default: besideAnImage ? .title2 : .title
        }
    }

    /// How many lines the text takes beside or under an image.
    private var lines: Int {
        switch family {
        case .systemSmall: 2
        default: 3
        }
    }
}

/// A badge on the card the widget shows, as the review panel draws them:
/// "New" in the tint, and "Back first" in gray.
private struct Badge: View {
    let title: Text
    let isProminent: Bool

    var body: some View {
        title
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isProminent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                isProminent ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.secondary.opacity(0.15)),
                in: .capsule)
    }
}
