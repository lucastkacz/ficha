import ArgumentParser
import FichaCore
import FichaData
import Foundation

// The pace and the queue of decks new cards come from (ADR 0034): the CLI
// sets the pace and a deck's place in the queue, and prints each queued
// deck's finish date.

/// `ficha pace`: prints the pace, or sets it.
struct PaceCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "pace",
        abstract: "Print how fast new cards come, or set it, and print it.",
        discussion: """
            The pace is the new cards a day, for all your decks together: chill is 1, steady 2 and faster 4. \
            A number another way set prints with no pace. It syncs to your other devices, as Settings' does.
            """
    )

    @Argument(help: "The pace to set: chill, steady or faster. Leave it out to print the pace.")
    var pace: Pace?

    func run(on engine: Engine) throws -> any Encodable {
        let old = try engine.progressSettings()
        if let pace {
            var new = old
            new.newCardsPerDay = pace.newCardsPerDay
            try engine.saveProgressSettings(new, changedFrom: old)
        }
        let newCardsPerDay = try engine.progressSettings().newCardsPerDay
        return PrintedPace(pace: Pace(newCardsPerDay: newCardsPerDay), newCardsPerDay: newCardsPerDay)
    }
}

extension Pace: ExpressibleByArgument {}

/// The pace as the CLI prints it.
private struct PrintedPace: Encodable {
    /// The pace, or nil when the new cards a day are another number.
    let pace: Pace?
    /// The new cards a day.
    let newCardsPerDay: Int
}

/// `ficha queue`: prints the queue.
struct QueueCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "queue",
        abstract: "Print the decks new cards come from, in their order, each with when you'll have met its cards.",
        discussion: """
            New cards come from the first deck alone, at the pace, until you've met them all; then from the next. \
            Each deck is a deck at the top of the tree, with the decks inside it, that still has new cards: \
            newCards counts them, each way a card goes as one. Its finish is a range of days: soonest if you have \
            appearances every day, latest if on five days in seven. It counts Ficha's own active hours, 9 to 22, \
            since the CLI can't read the app's. A priority deck's cards come first, so a deck at the top that is \
            one comes first, and one that holds one where its other new cards come; a set-aside deck is out of \
            the queue.
            """
    )

    func run(on engine: Engine) throws -> any Encodable {
        try PrintedQueue(of: engine).decks
    }
}

/// `ficha deck queue`: moves a deck in the queue.
struct QueueDeckCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "queue",
        abstract: "Move a deck in the queue new cards come from, and print the queue.",
        discussion: """
            A deck inside another moves the deck at the top of the tree it sits in, which every deck inside it \
            comes with. The decks it passes take each other's places. A priority deck's new cards still come \
            first, wherever it goes. Each deck keeps its place while it's set aside, and syncs it to your other \
            devices.
            """
    )

    @Argument(help: "The deck's whole name, as `ficha decks` prints it, or \"\" for Default.")
    var deck: String

    @ArgumentParser.Flag(help: "Put it first in the queue, after any priority deck.")
    var first = false

    @ArgumentParser.Flag(help: "Put it last in the queue.")
    var last = false

    @Option(help: "Put it at this place in the queue, from 1, the first, as `ficha queue` lists it.")
    var place: Int?

    func validate() throws {
        guard [first, last, place != nil].filter(\.self).count == 1 else {
            throw ValidationError("Give one of --first, --last or --place.")
        }
        if let place, place < 1 {
            throw ValidationError("A place counts from 1, the first.")
        }
    }

    func run(on engine: Engine) throws -> any Encodable {
        let deck = try PrintedDecks(of: engine).existing(deck)
        let position: QueuePosition =
            if first {
                .first
            } else if let place {
                .at(place - 1)
            } else {
                .last
            }
        try engine.moveInQueue(deck: deck, to: position)
        return try PrintedQueue(of: engine).decks
    }
}

/// The queue as the CLI prints it.
private struct PrintedQueue {
    /// Each deck in the queue, first to last.
    let decks: [PrintedQueuedDeck]

    /// The queue `engine` holds now, by the settings that sync, and Ficha's
    /// own for the rest, such as active hours, which only the app reads.
    init(of engine: Engine) throws {
        var settings = ReviewSettings.defaults
        settings.progress = try engine.progressSettings()
        decks = try engine.queue(settings).map {
            PrintedQueuedDeck(deck: $0.deck, newCards: $0.newCards, finish: $0.finish)
        }
    }
}

/// A deck in the queue as the CLI prints it.
private struct PrintedQueuedDeck: Encodable {
    /// The deck's whole name, or "" for Default.
    let deck: String
    /// Its new cards still to meet, each way a card goes as one.
    let newCards: Int
    /// When they'll all be met, or nil when the pace brings none.
    let finish: FinishDate?
}
