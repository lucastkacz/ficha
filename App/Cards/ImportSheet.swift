import FichaCore
import FichaData
import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// The Cards window's Import… button, in its toolbar, and ⇧⌘I, which
    /// open the Import sheet, which `state` runs.
    func importButtonAndSheet(_ state: Binding<CardsWindowState>) -> some View {
        modifier(ImportButtonAndSheet(state: state))
    }
}

/// Import… and ⇧⌘I, and the sheet they open while the state imports.
private struct ImportButtonAndSheet: ViewModifier {
    @Binding var state: CardsWindowState

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    importButton
                }
            }
            .background {
                // ⇧⌘I, as in Anki, works through a hidden button, as ⌘N
                // does: the app has no main menu, whose File menu would
                // hold it.
                Button {
                    state.startImport()
                } label: {
                    Text("Import", comment: "A hidden button of the Cards window: ⇧⌘I, which opens the Import sheet.")
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .hidden()
            }
            .sheet(isPresented: isImporting) {
                if let importing = state.importing {
                    ImportSheet(
                        importing: importing, failure: failure, preview: { state.previewImport(of: $0) },
                        nameTag: { state.nameImportTag($0, as: $1) },
                        chooseForRepeatedCards: { state.chooseForRepeatedCards($0) },
                        importCards: { state.importCards() })
                }
            }
    }

    /// Import…, which opens the Import sheet.
    private var importButton: some View {
        Button {
            state.startImport()
        } label: {
            Label {
                Text("Import…", comment: "The Cards window's toolbar button that imports cards from a file.")
            } icon: {
                Image(systemName: "square.and.arrow.down")
            }
        }
        .help(Text("Import… (⇧⌘I)", comment: "The tooltip of the Cards window's toolbar button that imports cards."))
    }

    /// Whether the Import sheet is open, which closing it ends.
    private var isImporting: Binding<Bool> {
        Binding {
            state.importing != nil
        } set: {
            if !$0 {
                state.closeImport()
            }
        }
    }

    /// What couldn't be done in the Import sheet, as the alert over it says
    /// it, which closing it clears.
    private var failure: Binding<Failure?> {
        Binding {
            state.importing?.failure.map { failure in
                Failure(title: title(failure.action), error: failure.error)
            }
        } set: {
            if $0 == nil {
                state.dismissImportFailure()
            }
        }
    }

    /// The alert's title when `action` failed.
    private func title(_ action: CardsWindowState.ImportFailure.Action) -> LocalizedStringResource {
        switch action {
        case .preview:
            LocalizedStringResource(
                "Couldn't read the file", comment: "An alert's title in the Cards window's Import sheet.")
        case .importCards:
            LocalizedStringResource(
                "Couldn't import the cards", comment: "An alert's title in the Cards window's Import sheet.")
        }
    }
}

/// The sheet the Cards window's Import button opens. First it says in a line
/// what Ficha reads, and Choose File… opens a text file of cards. Then it
/// shows what importing the file would do: how many cards come in, how many
/// repeat the user's cards, with Update or Skip for them, which lines stay
/// out and why, and the tag every card gets, named after the file, which the
/// user renames, or clears to leave it out; Import imports them. Last, it
/// says what the import did. `CardsWindowState` holds the preview, the
/// choices and the outcome, and the sheet draws them.
struct ImportSheet: View {
    let importing: CardsWindowState.Importing
    /// What couldn't be done, as the alert over the sheet says it.
    let failure: Binding<Failure?>
    /// Reads the file chosen in the open panel and shows its preview.
    let preview: (URL) -> Void
    /// Gives the field of a proposed tag what the user typed in it.
    let nameTag: (_ proposed: String, _ name: String) -> Void
    /// Chooses Update or Skip for the repeated cards.
    let chooseForRepeatedCards: (ImportChoices.RepeatedCards) -> Void
    /// Imports the cards, as the user chose.
    let importCards: () -> Void
    @Environment(\.dismiss) private var dismiss
    /// Whether the open panel is open.
    @State private var isChoosingFile = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch importing.step {
            case .choosingFile:
                choosingFile
            case .preview(let preview):
                previewOf(preview)
            case .done(let outcome):
                done(outcome)
            }
        }
        .padding(20)
        .frame(width: 460)
        .fileImporter(
            isPresented: $isChoosingFile, allowedContentTypes: [.plainText, .commaSeparatedText, .tabSeparatedText]
        ) { result in
            if case .success(let file) = result {
                preview(file)
            }
        }
        .failureAlert(failure)
    }

    /// Before a file is chosen: what Ficha reads, and Choose File….
    private var choosingFile: some View {
        Group {
            heading(
                Text("Import Cards", comment: "The title of the Cards window's Import sheet, before a file is chosen."),
                Text(
                    """
                    Ficha reads a text file with one card per line: its front, back, tags, type and source, \
                    separated by tabs, commas or semicolons, as a spreadsheet, an AI or Anki's Notes in Plain Text \
                    save it.
                    """,
                    comment: "Under the title of the Cards window's Import sheet, before a file is chosen."))
            HStack {
                Spacer()
                cancelButton
                chooseFileButton(
                    Text("Choose File…", comment: "The Import sheet's button that opens a text file of cards."),
                    shortcut: .defaultAction)
            }
        }
    }

    /// The preview of the file chosen, with the choices for its import.
    private func previewOf(_ preview: ImportPreview) -> some View {
        Group {
            heading(
                Text(
                    "Import “\(preview.fileName)”",
                    comment: "The title of the Cards window's Import sheet, with the name of the file chosen."),
                Text(
                    "\(preview.newCount) new cards come in, at the pace of your new cards per day.",
                    comment: "In the Import sheet's preview, with how many new cards the file brings."))
            if !preview.leftOut.isEmpty {
                leftOutLines(preview.leftOut)
            }
            if preview.repeatedCount > 0 {
                repeatedCardsChoice(preview.repeatedCount)
            }
            ForEach(importing.tagFields, id: \.proposed) { field in
                LabeledContent {
                    TextField(
                        String(localized: "Tag", comment: "The Import sheet's field for the tag every card gets."),
                        text: Binding(get: { field.name }, set: { nameTag(field.proposed, $0) }),
                        prompt: Text(
                            "No tag",
                            comment: "The Import sheet's tag field, empty: the cards get no tag of the file's.")
                    )
                    .textFieldStyle(.roundedBorder)
                    // A focused text field keeps Return from reaching the
                    // default button. The state imports only while Import
                    // is on.
                    .onSubmit(importCards)
                } label: {
                    Text(
                        "Tag every card with",
                        comment: "In the Import sheet, before the field for the tag every card it imports gets.")
                }
            }
            HStack {
                chooseFileButton(
                    Text(
                        "Choose Another File…",
                        comment: "The Import sheet's button that opens another text file of cards instead."),
                    shortcut: KeyboardShortcut("o", modifiers: .command))
                Spacer()
                cancelButton
                Button {
                    importCards()
                } label: {
                    Text("Import", comment: "The Import sheet's button that imports the cards as previewed.")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!importing.canImport)
            }
        }
    }

    /// What the import did, and how to undo it.
    private func done(_ outcome: ImportOutcome) -> some View {
        Group {
            heading(
                Text("Import Done", comment: "The title of the Cards window's Import sheet, once the cards came in."),
                Text(
                    "\(outcome.added) new cards came in, \(outcome.updated) cards were updated and \(outcome.skipped) were skipped.",
                    comment:
                        "In the Import sheet once it's done, with how many cards came in, were updated and skipped."
                ))
            if outcome.copyBeforeImport != nil {
                Text(
                    "To undo it, restore the copy saved before it, in Settings › Backups.",
                    comment: "In the Import sheet once it's done, when Ficha saved a copy before the import."
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Done", comment: "The Import sheet's button that closes it once the cards came in.")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// The sheet's title, and what it says under it.
    private func heading(_ title: Text, _ message: Text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            title
                .font(.headline)
            message
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The lines the file can't read, how many and each with its number and
    /// why, in a list that scrolls when they're many.
    private func leftOutLines(_ lines: [LeftOutLine]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                "\(lines.count) lines can't be read, and stay out:",
                comment: "In the Import sheet's preview, above the lines of the file it can't read, with how many.")
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(lines, id: \.line) { line in
                        Text(reason(line))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 120)
            .fixedSize(horizontal: false, vertical: true)
            .background(.background.secondary, in: .rect(cornerRadius: 6))
        }
    }

    /// How many of the file's cards repeat the user's, and Update or Skip
    /// for them, under it.
    private func repeatedCardsChoice(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                "\(count) cards repeat cards you have, by their front:",
                comment: "In the Import sheet, above Update and Skip, with how many cards of the file repeat.")
            Picker(selection: repeatedCards) {
                Text(
                    "Update them with the file's back, tags, type and source, keeping their progress",
                    comment: "In the Import sheet, the choice that updates the cards the file repeats."
                )
                .tag(ImportChoices.RepeatedCards.update)
                Text("Skip them", comment: "In the Import sheet, the choice that leaves the cards the file repeats.")
                    .tag(ImportChoices.RepeatedCards.skip)
            } label: {
                Text(
                    "Repeated cards", comment: "In the Import sheet, the name of the Update and Skip choice, unseen.")
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Why `line` stays out, with its number.
    private func reason(_ line: LeftOutLine) -> String {
        let number = line.line
        return switch line.reason {
        case .oneColumn:
            String(
                localized: "Line \(number) has one column: a front with no back after it.",
                comment: "In the Import sheet, a line the file can't read.")
        case .blankFront:
            String(
                localized: "Line \(number) has no front.", comment: "In the Import sheet, a line the file can't read.")
        case .blankBack:
            String(
                localized: "Line \(number) has no back.", comment: "In the Import sheet, a line the file can't read.")
        case .unknownType(let type):
            String(
                localized: "Line \(number) has the type “\(type)”, which isn't word, concept, quote or question.",
                comment: "In the Import sheet, a line the file can't read, with the type it has.")
        case .unclosedQuote:
            String(
                localized: "Line \(number) opens a quote that nothing closes.",
                comment: "In the Import sheet, a line the file can't read.")
        case .strayQuote:
            String(
                localized: "Line \(number) has a quote inside a quoted field that isn't doubled.",
                comment: "In the Import sheet, a line the file can't read.")
        }
    }

    /// Cancel, which closes the sheet and imports nothing.
    private var cancelButton: some View {
        Button("Cancel") {
            dismiss()
        }
        .keyboardShortcut(.cancelAction)
    }

    /// A button with `shortcut` that opens the open panel for a text file of
    /// cards: Return before a file is chosen, and ⌘O once one is.
    private func chooseFileButton(_ label: Text, shortcut: KeyboardShortcut) -> some View {
        Button {
            isChoosingFile = true
        } label: {
            label
        }
        .keyboardShortcut(shortcut)
    }

    /// Update or Skip, as the state holds it.
    private var repeatedCards: Binding<ImportChoices.RepeatedCards> {
        Binding {
            importing.repeatedCards
        } set: {
            chooseForRepeatedCards($0)
        }
    }
}
