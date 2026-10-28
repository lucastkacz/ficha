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
        abstract: "Capture and refine your cards from the terminal.",
        discussion: "Every command prints its result as JSON.",
        subcommands: [
            CaptureCommand.self, InboxCommand.self, ApproveCommand.self, ApproveExpansionCommand.self,
            DiscardCommand.self, FixCommand.self, AttachCommand.self, DetachCommand.self, BuryCommand.self,
            UnburyCommand.self, CardsCommand.self, RestoreCommand.self,
        ]
    )

    public init() {}

    /// Runs the command in the process's arguments on the database in the
    /// folder `dataFolder` names, or says why it names none, prints its result
    /// as JSON, and exits. A command that fails says why on standard error and
    /// exits with an error code. It runs on the system's time or, for Ficha
    /// Dev's CLI, on the time Ficha Dev's debug menu moved forward, as Ficha
    /// Dev does. The files it puts on cards come from `downloads` alone, the
    /// Downloads folder, when the CLI's sandbox lets it read no other. A
    /// restore, which would change the cards under the app that the CLI
    /// belongs to, `appName`, is refused while `appIsRunning` says it runs,
    /// before the database opens.
    public static func main(
        dataFolder: () throws -> URL, refineFilesOnlyIn downloads: URL?, runsOnDebugTime: Bool, appName: String,
        appIsRunning: @MainActor () -> Bool
    ) async -> Never {
        do {
            var command = try parseAsRoot()
            guard let engineCommand = command as? any EngineCommand else {
                // `ficha` on its own, which prints the help.
                try command.run()
                Self.exit()
            }
            if let restore = engineCommand as? RestoreCommand, restore.copy != nil, await appIsRunning() {
                throw AppIsRunningError(appName: appName)
            }
            let folder = try dataFolder()
            let time: any TimeSource =
                if runsOnDebugTime {
                    try DebugTimeSource(savedIn: folder)
                } else {
                    SystemTimeSource()
                }
            let engine = try Engine(location: .folder(folder), time: time, refineFilesOnlyIn: downloads)
            print(try json(await engineCommand.run(on: engine)))
            Self.exit()
        } catch {
            Self.exit(withError: error)
        }
    }
}

/// A `ficha` subcommand, which reads or writes Lucas's cards through the engine.
protocol EngineCommand: ParsableCommand {
    /// Does the command's work on the cards, and returns what it prints: a
    /// file it puts on a card can take a while to come in.
    func run(on engine: Engine) async throws -> any Encodable
}

/// `value` as the CLI prints it: indented JSON, with its keys in order and its
/// dates in ISO 8601, in UTC.
private func json(_ value: any Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}
