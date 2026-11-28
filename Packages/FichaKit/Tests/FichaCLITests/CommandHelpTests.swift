import ArgumentParser
import FichaCLI
import Foundation
import Testing

/// Tests on what the `ficha` CLI's commands say of themselves: each one's
/// name and help, as `ficha help` prints them, every level down.
struct CommandHelpTests {
    // The words: "bury", "buries", "buried", "burying", "unbury" and its
    // forms, and "burial", in any case, as a whole word, as the String
    // Catalogs' test on Bury reads them, since a card is set aside now, as a
    // deck is, and put back (#539). Each command's help holds its name, in
    // its usage, its abstract and discussion, and its arguments' and
    // options' help, the hidden ones too. A whole word alone: a name such as
    // "buriedAt", the key `ficha cards` prints a card's field under, which
    // the decision keeps with no migration, is the code round's to rename or
    // keep.
    @Test("no `ficha` command's name or help says Bury, which Set aside and Put back say now", .bug(id: 539))
    func noCommandSaysBury() throws {
        let bury = try NSRegularExpression(
            pattern: #"\b(un)?bur(y|ies|ied|ying)\b|\bburials?\b"#, options: .caseInsensitive)
        let commands: [any ParsableCommand.Type] = [FichaCommand.self] + subcommands(of: FichaCommand.self)
        let saying = commands.flatMap { command -> [String] in
            let name = command.configuration.commandName ?? String(describing: command)
            return FichaCommand.helpMessage(for: command, includeHidden: true, columns: 10_000)
                .components(separatedBy: "\n")
                .filter { bury.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
                .map { "\(name): \($0.trimmingCharacters(in: .whitespaces))" }
        }
        #expect(
            saying.isEmpty,
            """
            `ficha` still says Bury, which Set aside and Put back say now, as `ficha deck set-aside` does for a deck \
            (#539). Say it as Set aside or Put back, and run the test again. The \(saying.count) lines, each after \
            its command's name:
            \(saying.joined(separator: "\n"))
            """)
    }
}

/// The commands under `command`, every level down, each before its own, in
/// the order their parents list them.
private func subcommands(of command: any ParsableCommand.Type) -> [any ParsableCommand.Type] {
    command.configuration.subcommands.flatMap { subcommand -> [any ParsableCommand.Type] in
        [subcommand] + subcommands(of: subcommand)
    }
}
