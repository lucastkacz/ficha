import AppKit
import SwiftUI
import os

private let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "import")

/// Copy Instructions for an AI, in the Import sheet before a file is chosen:
/// it copies the instructions for an AI, which tell an AI how to write a file
/// of cards Ficha imports, for the user to paste into an AI chat. The app
/// bundles them from the repo's `docs/instructions-for-an-ai.md`, so the two
/// are the same page. ⇧⌘C, as Copy's ⌘C with Shift, since the sheet has no
/// text to copy then. When the app holds no copy of them, as `make render`'s
/// tool doesn't, an alert says so.
struct CopyInstructionsButton: View {
    /// Why the instructions couldn't be copied, while the alert says so.
    @State private var failure: Failure?

    var body: some View {
        Button {
            copy()
        } label: {
            Text(
                "Copy Instructions for an AI",
                comment: "The Import sheet's button that copies instructions to paste into an AI chat.")
        }
        .keyboardShortcut("c", modifiers: [.command, .shift])
        .help(
            Text(
                "Copies instructions to paste into an AI chat, so that it writes a file of cards Ficha imports (⇧⌘C)",
                comment: "The tooltip of the Import sheet's button that copies the instructions for an AI.")
        )
        .failureAlert($failure)
    }

    /// Puts the instructions on the clipboard, or says why it couldn't.
    private func copy() {
        do throws(MissingInstructions) {
            let instructions = try instructionsForAnAI()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(instructions, forType: .string)
        } catch {
            failure = Failure(
                title: LocalizedStringResource(
                    "Couldn't copy the instructions",
                    comment: "An alert's title in the Import sheet, after Copy Instructions for an AI."),
                message: String(
                    localized: """
                        This copy of Ficha is missing its instructions for an AI. Install Ficha again, or read them \
                        in Ficha's repository on GitHub, in docs/instructions-for-an-ai.md.
                        """,
                    comment: "An alert's message in the Import sheet, when the app has no instructions for an AI."))
        }
    }
}

/// The app has no copy of the instructions for an AI, or can't read it.
private struct MissingInstructions: Error {}

/// The instructions for an AI, as the app bundles them: `project.yml` puts
/// `docs/instructions-for-an-ai.md` in the app's resources.
private func instructionsForAnAI() throws(MissingInstructions) -> String {
    guard let file = Bundle.main.url(forResource: "instructions-for-an-ai", withExtension: "md") else {
        logger.error("The app has no instructions-for-an-ai.md in its resources")
        throw MissingInstructions()
    }
    do {
        return try String(contentsOf: file, encoding: .utf8)
    } catch {
        logger.error("Couldn't read the instructions for an AI: \(String(describing: error))")
        throw MissingInstructions()
    }
}
