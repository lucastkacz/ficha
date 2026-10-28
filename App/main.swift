import FichaICloud
import Foundation

// Ficha's entry point: the app, or, run with `--delete-scratch-zones`, the
// deletion of the zones an agent's scratch run of Ficha Dev synced in, which
// shows no window and takes neither the pointer nor the keyboard
// (docs/development.md, "Agents' runs of Ficha Dev's `ficha`").
if CommandLine.arguments.dropFirst().first == ScratchZonesDeletion.argument {
    ScratchZonesDeletion.run()
} else {
    FichaApp.main()
}

/// Deletes from iCloud the zones of the scratch run `FICHA_DEV_SCRATCH` names,
/// without starting the app, prints their names and exits: from Ficha Dev's
/// own process, which holds iCloud's entitlements, where the CLI's doesn't.
/// It refuses in the real Ficha, without a scratch run's name, and in a build
/// not signed for iCloud, which CloudKit would stop. Its messages are an
/// agent's, in English and verbatim, as Ficha Dev's debug tools' are (ADR
/// 0009).
enum ScratchZonesDeletion {
    /// The argument that asks for it.
    static let argument = "--delete-scratch-zones"

    static func run() -> Never {
        guard AppVariant.current == .dev, let name = AppVariant.current.scratchName else {
            stop(
                """
                Only Ficha Dev deletes a scratch run's zones, those FICHA_DEV_SCRATCH names: run \
                FICHA_DEV_SCRATCH=<name> "<Ficha Dev.app>/Contents/MacOS/Ficha Dev" \(argument).
                """)
        }
        // A name that can't name a scratch folder names no zones either.
        do {
            _ = try AppVariant.current.dataFolder
        } catch {
            stop(error.localizedDescription)
        }
        guard signedEntitlement("com.apple.developer.icloud-services") != nil else {
            stop(
                """
                This Ficha Dev isn't signed for iCloud, so it can't reach the scratch run's zones: build it with \
                make build, with your team's ID in iPhone/Local.xcconfig, as docs/development.md says.
                """)
        }
        Task {
            do {
                let deleted = try await ScratchZones.delete(ofScratch: name)
                print(
                    deleted.isEmpty
                        ? "iCloud holds no zone of the scratch run \(name)."
                        : "Deleted from iCloud: \(deleted.joined(separator: ", ")).")
                exit(0)
            } catch {
                stop(error.localizedDescription)
            }
        }
        dispatchMain()
    }

    /// Says why it can't, and exits.
    private static func stop(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(1)
    }
}
