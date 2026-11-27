import ArgumentParser
import FichaCore
import FichaData
import Foundation
import Testing

// For the commands, which the CLI parses from its arguments and runs on the
// engine, and the JSON it prints their results as.
@testable import FichaCLI

/// Tests on the `ficha` CLI's pace and queue (ADR 0034): each command parsed
/// from its arguments, as a refine session types them, run on an engine in
/// memory at noon on the first day of 1970 in UTC, inside Ficha's active
/// hours, and the JSON it prints.
struct QueueCommandsTests {
    let time = ManualTimeSource(now: Date(timeIntervalSince1970: 12 * 60 * 60))
    let engine: Engine

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
    }

    @Test(
        "`ficha pace` prints the pace with its new cards a day, sets it when named, and prints none for a number no pace has",
        .bug(id: 490))
    func paceSetsAndPrintsThePace() async throws {
        let started = try await ficha("pace")
        let set = try await ficha("pace", "faster")
        let faster = try engine.progressSettings()
        var five = faster
        five.newCardsPerDay = 5
        try engine.saveProgressSettings(five, changedFrom: faster)

        #expect(
            started == """
                {
                  "newCardsPerDay" : 2,
                  "pace" : "steady"
                }
                """)
        #expect(
            set == """
                {
                  "newCardsPerDay" : 4,
                  "pace" : "faster"
                }
                """)
        #expect(faster.newCardsPerDay == 4)
        #expect(
            try await ficha("pace") == """
                {
                  "newCardsPerDay" : 5
                }
                """)
    }

    // Arte's 3 cards come in a minute before Historia's 4; at Steady, with
    // today's 2 new cards still to come, Arte's are met by the 2nd if every
    // day has appearances, or the 3rd, and Historia's then by the 4th, or the
    // 6th.
    @Test(
        "`ficha queue` prints each deck in the queue with its new cards and finish date, and `ficha deck queue` moves a deck and prints the queue",
        .bug(id: 490))
    func queuePrintsAndMovesDecks() async throws {
        for front in ["La Gioconda", "Las Meninas", "El Grito"] {
            try approveCard(front, deck: "Arte")
        }
        time.advance(by: 60)
        for front in ["Coliseo", "Partenón", "Machu Picchu", "Chichén Itzá"] {
            try approveCard(front, deck: "Historia")
        }

        let queue = try await ficha("queue")
        let historiaFirst = try await ficha("deck", "queue", "Historia", "--first")

        #expect(
            queue == """
                [
                  {
                    "deck" : "Arte",
                    "finish" : {
                      "latest" : "1970-01-03T00:00:00Z",
                      "soonest" : "1970-01-02T00:00:00Z"
                    },
                    "newCards" : 3
                  },
                  {
                    "deck" : "Historia",
                    "finish" : {
                      "latest" : "1970-01-06T00:00:00Z",
                      "soonest" : "1970-01-04T00:00:00Z"
                    },
                    "newCards" : 4
                  }
                ]
                """)
        #expect(
            historiaFirst == """
                [
                  {
                    "deck" : "Historia",
                    "finish" : {
                      "latest" : "1970-01-03T00:00:00Z",
                      "soonest" : "1970-01-02T00:00:00Z"
                    },
                    "newCards" : 4
                  },
                  {
                    "deck" : "Arte",
                    "finish" : {
                      "latest" : "1970-01-06T00:00:00Z",
                      "soonest" : "1970-01-04T00:00:00Z"
                    },
                    "newCards" : 3
                  }
                ]
                """)
        #expect(try await decks(in: ficha("deck", "queue", "Historia", "--place", "2")) == ["Arte", "Historia"])
        #expect(try await decks(in: ficha("deck", "queue", "Arte", "--last")) == ["Historia", "Arte"])
    }

    @Test(
        "`ficha deck queue` refuses a deck no one has, and wants one of --first, --last or --place, from 1",
        .bug(id: 490))
    func queueDeckRefusesAnUnknownDeckAndAMissingPlace() async throws {
        try approveCard("La Gioconda", deck: "Arte")

        await #expect(throws: UnknownDeckError.self) { try await ficha("deck", "queue", "Música", "--first") }
        for arguments in [["Arte"], ["Arte", "--first", "--last"], ["Arte", "--place", "0"]] {
            #expect(throws: (any Error).self) { try FichaCommand.parseAsRoot(["deck", "queue"] + arguments) }
        }
    }

    /// Runs `ficha` with `arguments` on the engine, as the CLI parses and
    /// runs them, and returns the JSON it prints.
    private func ficha(_ arguments: String...) async throws -> String {
        let command = try FichaCommand.parseAsRoot(arguments)
        let engineCommand = try #require(command as? any EngineCommand)
        return try json(await engineCommand.run(on: engine))
    }

    /// The decks the queue `printed` lists, by name, first to last.
    private func decks(in printed: String) throws -> [String] {
        try JSONDecoder().decode([QueuedDeckAsPrinted].self, from: Data(printed.utf8)).map(\.deck)
    }

    /// Approves a capture into one word card with this front, in `deck`.
    @discardableResult
    private func approveCard(_ front: String, deck: String) throws -> Card {
        guard case .saved(let capture) = try engine.capture(text: front, note: nil, source: nil) else {
            throw EngineError.emptyCapture
        }
        let content = try #require(
            CardContent(type: .word, front: front, back: "Lo que quiere decir «\(front)».", tags: [], source: nil))
        return try #require(try engine.approve(capture.id, into: [content], deck: deck).first)
    }
}

/// A deck in the queue as the CLI prints it, read back by its name alone.
private struct QueuedDeckAsPrinted: Decodable {
    /// The deck's whole name.
    let deck: String
}
