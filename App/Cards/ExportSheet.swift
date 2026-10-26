import AppKit
import FichaData
import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// The Cards window's Export… button, in its toolbar, and ⇧⌘E, which
    /// open the Export sheet, which `state` runs. `failure` is the alert over
    /// the sheet.
    func exportButtonAndSheet(_ state: Binding<CardsWindowState>, failure: Binding<Failure?>) -> some View {
        modifier(ExportButtonAndSheet(state: state, failure: failure))
    }
}

/// Export… and ⇧⌘E, and the sheet they open while the state exports.
private struct ExportButtonAndSheet: ViewModifier {
    @Binding var state: CardsWindowState
    let failure: Binding<Failure?>

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        state.startExport()
                    } label: {
                        Label {
                            Text("Export…", comment: "The Cards window's toolbar button that exports cards to a file.")
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .help(
                        Text(
                            "Export… (⇧⌘E)",
                            comment: "The tooltip of the Cards window's toolbar button that exports cards."))
                }
            }
            .background {
                // ⇧⌘E, beside Import's ⇧⌘I, works through a hidden button,
                // as ⌘N does: the app has no main menu, whose File menu would
                // hold it. ⌘E is Bury's.
                Button {
                    state.startExport()
                } label: {
                    Text("Export", comment: "A hidden button of the Cards window: ⇧⌘E, which opens the Export sheet.")
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .hidden()
            }
            .sheet(isPresented: Binding(get: { state.exporting != nil }, set: { if !$0 { state.closeExport() } })) {
                if let exporting = state.exporting {
                    ExportSheet(
                        exporting: exporting, tags: state.tags, failure: failure,
                        choose: { state.chooseCardsToExport($0) }, export: { state.export(to: $0) })
                }
            }
    }
}

/// The sheet the Cards window's Export button opens: a line on what an
/// export holds, a menu of what to export, the selected cards, all cards
/// and each tag, each with how many cards it takes, and Export…, which opens
/// a save panel and writes the file where the user saves it.
/// `CardsWindowState` decides what the menu offers, what it starts on and
/// what each item takes, and the sheet draws it.
struct ExportSheet: View {
    let exporting: CardsWindowState.Exporting
    /// The sidebar's tags, for the menu to name each tag as the sidebar does.
    let tags: [CardTag]
    /// What couldn't be done, as the alert over the sheet says it.
    let failure: Binding<Failure?>
    /// Chooses what to export.
    let choose: (CardsToExport) -> Void
    /// Writes what's chosen to the file the save panel gives.
    let export: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Export Cards", comment: "The title of the Cards window's Export sheet.")
                    .font(.headline)
                Group {
                    if exporting.writesZip {
                        Text(
                            """
                            Ficha saves the cards to a zip, with a text file and their images and sounds, that \
                            another Ficha imports. It holds what the cards say, never your progress.
                            """,
                            comment:
                                "Under the title of the Cards window's Export sheet, when a card has an image or a sound."
                        )
                    } else {
                        Text(
                            """
                            Ficha saves the cards to a text file that another Ficha imports, and Anki too. It holds \
                            what the cards say, never your progress.
                            """,
                            comment: "Under the title of the Cards window's Export sheet."
                        )
                    }
                }
                .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Picker(selection: chosen) {
                ForEach(exporting.cardChoices, id: \.cards) { choice in
                    Text(title(of: choice)).tag(choice.cards)
                }
                if !exporting.tagChoices.isEmpty {
                    Divider()
                }
                ForEach(exporting.tagChoices, id: \.cards) { choice in
                    Text(title(of: choice)).tag(choice.cards)
                }
            } label: {
                Text("Export", comment: "In the Export sheet, before the menu of the cards to export.")
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    chooseFile()
                } label: {
                    Text("Export…", comment: "The Export sheet's button that opens a save panel for the file.")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!exporting.canExport)
            }
        }
        .padding(20)
        .frame(width: 420)
        .failureAlert(failure)
    }

    /// What the menu has chosen, as the state holds it.
    private var chosen: Binding<CardsToExport> {
        Binding {
            exporting.chosen
        } set: {
            choose($0)
        }
    }

    /// The menu's item for `choice`, with how many cards it takes.
    private func title(of choice: CardsWindowState.ExportChoice) -> String {
        let count = choice.cardCount
        return switch choice.cards {
        case .cards:
            String(
                localized: "Selected cards (\(count))",
                comment: "An item of the Export sheet's menu: the cards selected in the table, with how many.")
        case .all:
            String(
                localized: "All cards (\(count))",
                comment: "An item of the Export sheet's menu: every card, buried ones too, with how many.")
        case .tag(let name):
            String(
                localized: "\(tags.first { $0.name == name }?.title ?? name) (\(count))",
                comment: "An item of the Export sheet's menu: the cards with a tag, with the tag and how many.")
        }
    }

    /// The name the save panel proposes for the file, as the state chose it.
    private var fileName: String {
        switch exporting.fileName {
        case .selectedCards:
            String(
                localized: "Selected cards",
                comment: "The name the Export sheet's save panel proposes for the file of the selected cards.")
        case .allCards:
            String(
                localized: "All cards",
                comment: "The name the Export sheet's save panel proposes for the file of all cards.")
        case .tag(let name):
            name
        }
    }

    /// Opens a save panel over the sheet, as a plain text file, or a zip when
    /// a card has an image or a sound, and exports there once the user
    /// saves. AppKit's own panel, since SwiftUI's file exporter writes a
    /// document itself, and the engine writes this file.
    private func chooseFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [exporting.writesZip ? .zip : .plainText]
        panel.nameFieldStringValue = fileName
        panel.canCreateDirectories = true
        let save = { (response: NSApplication.ModalResponse) in
            if response == .OK, let file = panel.url {
                export(file)
            }
        }
        // The sheet is the key window while it's open.
        if let sheet = NSApp.keyWindow {
            panel.beginSheetModal(for: sheet, completionHandler: save)
        } else {
            panel.begin(completionHandler: save)
        }
    }
}
