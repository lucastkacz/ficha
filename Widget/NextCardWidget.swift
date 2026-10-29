import FichaCore
import FichaData
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import WidgetKit

/// The widget with the next card to review (#171), on the desktop or in
/// Notification Center, in each app, Ficha Dev's for its cards and the real
/// Ficha's for Lucas's: the card a review now would start with, or when the
/// next one comes. A click on it opens a review now that starts with that
/// card, through a link the app handles.
@main
struct NextCardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextCard", provider: NextCardProvider()) { entry in
            NextCardEntryView(entry: entry)
        }
        .configurationDisplayName(Text("Next Card", comment: "The widget's name in the widget gallery."))
        .description(
            Text(
                "The next card to review, or when it comes. Click it to review it.",
                comment: "The widget's description in the widget gallery.")
        )
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// The widget's view at the size WidgetKit gives it, on WidgetKit's
/// background.
private struct NextCardEntryView: View {
    let entry: NextCardEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        NextCardView(entry: entry, family: family)
            .containerBackground(.background, for: .widget)
    }
}

/// Gives WidgetKit what the widget shows, read from the cards in the app's
/// data folder whenever WidgetKit asks: when the widget comes on screen, at
/// the time its last timeline said, and when the app asks it to reload,
/// which the app does whenever what it shows changes. It reads the database
/// alone, beside the app and the CLI, which write it.
struct NextCardProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextCardEntry {
        .placeholder(at: SystemTimeSource().now)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (NextCardEntry) -> Void) {
        let timeline = readTimeline(for: context.family)
        completion(timeline.entries.first ?? .placeholder(at: SystemTimeSource().now))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<NextCardEntry>) -> Void) {
        completion(readTimeline(for: context.family))
    }
}

/// How long the widget waits to read the cards again when it couldn't, if
/// the app doesn't ask it to reload first.
private let retryAfter: TimeInterval = 15 * 60

/// The widget's timeline, as the cards in the app's data folder say now.
private func readTimeline(for family: WidgetFamily) -> Timeline<NextCardEntry> {
    let variant = AppVariant.current
    let now = SystemTimeSource().now
    widgetLogger.info(
        "Building a timeline for \(variant.name, privacy: .public)'s \(family.description, privacy: .public) widget")
    // Picks with this Mac's settings, as review now does, once the app
    // handed them over, and opens the cards only then: the real Ficha hands
    // nothing over until its widget shares its group (#310), and its data
    // folder, in that group, is out of the widget's reach meanwhile.
    guard let settings = WidgetHandover.handedOver() else {
        widgetLogger.info("The app hasn't handed over this Mac's settings yet")
        return single(.notReady, at: now)
    }
    let folder: URL
    let debugTime: DebugTimeSource?
    let engine: Engine
    do {
        folder = try variant.dataFolder
        // Ficha Dev's engine runs on the time its debug menu moved forward,
        // as its app and its CLI do.
        debugTime = variant.hasDebugMenu ? try DebugTimeSource(savedIn: folder) : nil
        guard let opened = try Engine(readingOnlyIn: folder, time: debugTime ?? SystemTimeSource()) else {
            widgetLogger.info("No database to read in \(folder.path(percentEncoded: false), privacy: .public) yet")
            return single(.notReady, at: now)
        }
        engine = opened
    } catch {
        widgetLogger.error("Couldn't open the cards to read them: \(String(describing: error), privacy: .public)")
        return single(.unreadable(error.localizedDescription), at: now)
    }
    widgetLogger.info("Opened the database in \(folder.path(percentEncoded: false), privacy: .public) to read it")

    let timeline: WidgetTimeline
    do {
        timeline = try engine.widgetTimeline(settings, engineAheadBy: debugTime?.shift ?? .zero)
    } catch {
        widgetLogger.error("Couldn't read what the widget shows: \(String(describing: error), privacy: .public)")
        return single(.unreadable(error.localizedDescription), at: now)
    }
    var images = SmallImages(engine: engine)
    let entries = timeline.spacedEntries.map { entry in
        NextCardEntry(date: entry.date, shows: .content(entry.content, image: images.image(for: entry.content)))
    }
    log(entries, refreshAt: timeline.refreshAt)
    return Timeline(entries: entries, policy: timeline.refreshAt.map { .after($0) } ?? .never)
}

/// A timeline that shows `shows`, which isn't the cards, from `now` on: until
/// the app asks WidgetKit to reload it, as it does when it opens its
/// database, or for a while.
private func single(_ shows: NextCardEntry.Shows, at now: Date) -> Timeline<NextCardEntry> {
    let entry = NextCardEntry(date: now, shows: shows)
    log([entry], refreshAt: now + retryAfter)
    return Timeline(entries: [entry], policy: .after(now + retryAfter))
}

/// Logs what the widget shows now, and next, by the system's time, with the
/// cards by their ids, never by their content.
private func log(_ entries: [NextCardEntry], refreshAt: Date?) {
    guard let first = entries.first else { return }
    let later = entries.dropFirst().prefix(3).map { "\(described($0.shows)) at \($0.date)" }
    let next = later.isEmpty ? "" : " (\(later.joined(separator: "; ")))"
    let refresh = refreshAt.map { "at \($0)" } ?? "when the app reloads it"
    widgetLogger.info(
        """
        The widget shows \(described(first.shows), privacy: .public) from \(first.date, privacy: .public), \
        then \(entries.count - 1, privacy: .public) more entries\(next, privacy: .public), and reads the cards \
        again \(refresh, privacy: .public)
        """)
}

/// What an entry shows, for the log: never a card's content.
private func described(_ shows: NextCardEntry.Shows) -> String {
    switch shows {
    case .content(.card(let card), let image):
        let image = card.image == nil ? "" : image == nil ? " with an unreadable image" : " with its image"
        return
            "card \(card.way.cardID) \(card.way.way.rawValue)\(card.isNew ? ", new," : "") on its \(card.side)\(image)"
            + (card.showsSpeaker ? " with a speaker" : "")
    case .content(.nextCard(let time), _): return "no card waiting, the next at \(time)"
    case .content(.noneComing, _): return "no card coming"
    case .content(.noCards, _): return "no cards"
    case .notReady: return "that the app hasn't opened its database or handed over its settings yet"
    case .unreadable: return "that it couldn't read the cards"
    }
}

/// The images the widget shows, made small, read once each: WidgetKit keeps
/// every entry's view, and a widget's extension has little memory.
private struct SmallImages {
    let engine: Engine
    /// Each image read so far, made small, or nil when it couldn't be.
    private var cache: [ImageName: Data?] = [:]

    init(engine: Engine) {
        self.engine = engine
    }

    /// The image on the card's side `content` shows, made small, or nil when
    /// it has none or it couldn't be read.
    mutating func image(for content: WidgetContent) -> Data? {
        guard case .card(let card) = content, let name = card.image else { return nil }
        if let image = cache[name] {
            return image
        }
        let image: Data?
        do {
            image = shrunk(try engine.image(name))
        } catch {
            widgetLogger.error(
                "Couldn't read an image on card \(card.way.cardID): \(String(describing: error), privacy: .public)")
            image = nil
        }
        cache[name] = image
        return image
    }
}

/// The longest side, in pixels, of an image the widget shows: its large size
/// is about 360 points wide, 720 pixels on a Retina display, and the image
/// takes part of it.
private let longestSide = 600

/// `data`, an image as Ficha keeps it, shrunk to `longestSide` pixels on its
/// long side, as a PNG, or nil when it isn't an image ImageIO reads.
private func shrunk(_ data: Data) -> Data? {
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: longestSide,
    ]
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
        let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else {
        return nil
    }
    let png = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else {
        return nil
    }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination) ? png as Data : nil
}
