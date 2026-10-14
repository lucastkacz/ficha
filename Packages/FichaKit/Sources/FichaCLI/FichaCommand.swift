import ArgumentParser
import FichaCore
import FichaData
import Foundation

/// The `ficha` command: how Claude reads and writes Lucas's cards in a refine
/// session he starts (ADR 0001), and how Lucas captures from a terminal. Like
/// the app, it goes through the engine, and it prints JSON for Claude.
public struct FichaCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "ficha",
        abstract: "Captura y refina tus fichas desde la terminal.",
        discussion: "Cada comando imprime su resultado en JSON.",
        subcommands: [
            CaptureCommand.self, InboxCommand.self, ApproveCommand.self, DiscardCommand.self, CardsCommand.self,
        ]
    )

    public init() {}

    /// Runs the command in the process's arguments on the database in
    /// `dataFolder`, prints its result as JSON, and exits. A command that
    /// fails says why on standard error and exits with an error code. It runs
    /// on the system's time or, for Ficha Dev's CLI, on the time Ficha Dev's
    /// debug menu moved forward, as Ficha Dev does.
    public static func main(dataFolder: URL, runsOnDebugTime: Bool) -> Never {
        do {
            var command = try parseAsRoot()
            guard let engineCommand = command as? any EngineCommand else {
                // `ficha` on its own, which prints the help.
                try command.run()
                Self.exit()
            }
            let time: any TimeSource =
                if runsOnDebugTime {
                    try DebugTimeSource(savedIn: dataFolder)
                } else {
                    SystemTimeSource()
                }
            let engine = try Engine(location: .folder(dataFolder), time: time)
            print(try json(engineCommand.run(on: engine)))
            Self.exit()
        } catch {
            Self.exit(withError: error)
        }
    }
}

/// A `ficha` subcommand, which reads or writes Lucas's cards through the engine.
protocol EngineCommand: ParsableCommand {
    /// Does the command's work on the cards, and returns what it prints.
    func run(on engine: Engine) throws -> any Encodable
}

/// `value` as the CLI prints it: indented JSON, with its keys in order and its
/// dates in ISO 8601, in UTC.
private func json(_ value: any Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}
