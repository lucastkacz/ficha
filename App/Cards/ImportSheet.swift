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
            .sheetWithinWindow(isPresented: isImporting) { maximumHeight in
                if let importing = state.importing {
                    ImportSheet(
                        importing: importing, maximumHeight: maximumHeight, failure: failure,
                        preview: { run(state.previewImport(of: $0)) },
                        nameTag: { state.nameImportTag($0, as: $1) }, removeTag: { state.removeImportTag($0) },
                        chooseForRepeatedCards: { state.chooseForRepeatedCards($0) },
                        chooseToBringProgress: { state.chooseToBringProgress($0) },
                        importCards: { run(state.importCards()) })
                }
            }
    }

    /// Runs `work`, which the state started, away from the main actor, and
    /// hands what it did back to the state.
    private func run(_ work: ImportWork?) {
        guard let work else { return }
        Task {
            state.finishImportWork(await doneAwayFromTheMainActor(work))
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

/// What `work` did, done away from the main actor: reading a big file, or
/// importing its cards, takes seconds, while the window goes on answering.
@concurrent
private func doneAwayFromTheMainActor(_ work: ImportWork) async -> ImportWork.Done {
    await work.run()
}

/// The sheet the Cards window's Import button opens. First it says in a line
/// what Ficha reads, Copy Instructions for an AI copies how to write such a
/// file, and Choose File… opens a text file of cards, a zip with one and its
/// cards' images and sounds, or an Anki package. Then it shows what
/// importing the file would do: how many cards come in, how many repeat the
/// user's cards, with Update or Skip for them, which lines stay out and why,
/// or for an Anki package, how many of its cards and why, how many of its
/// notes with a reversed card come in as one card that goes both ways (ADR
/// 0016), how many come in with the first of several images or sounds on a
/// side, and how many without a sound Ficha can't read, and the tags the
/// cards get: for a text file, one named after the file, for every card;
/// for an Anki package, one for each of its decks, with all its levels, and
/// each of its tags. The user renames each, or clears it to leave it out. An
/// Anki package's cards come in where Anki had them while Bring progress is
/// ticked (ADR 0013), and how many of them land on a step goes in the line
/// under the title. Import imports them. While it reads the file or
/// imports, it says so beside a spinner. A preview taller than the window
/// scrolls between the title and the buttons. Last, it says what the import did. `CardsWindowState` holds
/// the preview, the choices and the outcome, and the sheet draws them.
struct ImportSheet: View {
    let importing: CardsWindowState.Importing
    /// The tallest the sheet gets, as `sheetWithinWindow` hands it.
    let maximumHeight: CGFloat
    /// What couldn't be done, as the alert over the sheet says it.
    let failure: Binding<Failure?>
    /// Reads the file chosen in the open panel and shows its preview.
    let preview: (URL) -> Void
    /// Gives the field of a proposed tag what the user typed in it.
    let nameTag: (_ proposed: String, _ name: String) -> Void
    /// Leaves a proposed tag out, clearing its field.
    let removeTag: (_ proposed: String) -> Void
    /// Chooses Update or Skip for the repeated cards.
    let chooseForRepeatedCards: (ImportChoices.RepeatedCards) -> Void
    /// Ticks or unticks Bring progress.
    let chooseToBringProgress: (Bool) -> Void
    /// Imports the cards, as the user chose.
    let importCards: () -> Void
    @Environment(\.dismiss) private var dismiss
    /// Whether the open panel is open.
    @State private var isChoosingFile = false
    /// The space between the sheet's parts, and around them.
    private let spacing: CGFloat = 16
    private let padding: CGFloat = 20
    /// The height of a row of buttons, which a preview keeps in view under
    /// what scrolls.
    private let buttonsHeight: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            switch importing.step {
            case .choosingFile:
                choosingFile
            case .preview(let preview):
                previewOf(preview)
            case .done(let outcome):
                done(outcome)
            }
        }
        .padding(padding)
        .frame(width: 460)
        // An import that started goes on until it's done.
        .interactiveDismissDisabled(importing.busy == .importing)
        .fileImporter(
            isPresented: $isChoosingFile,
            allowedContentTypes: [.plainText, .commaSeparatedText, .tabSeparatedText, .zip]
                // Anki's packages, by their extension: Anki declares their
                // type on a Mac that has it, and macOS makes one up on
                // another.
                + [UTType(filenameExtension: "apkg")].compactMap(\.self)
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
                    save it. Cards with images or sounds come in a zip, with the text file and those files. Anki's \
                    decks come in from the .apkg files Anki exports.
                    """,
                    comment: "Under the title of the Cards window's Import sheet, before a file is chosen."))
            HStack {
                if importing.busy == nil {
                    CopyInstructionsButton()
                } else {
                    busyNote
                }
                Spacer()
                cancelButton
                chooseFileButton(
                    Text("Choose File…", comment: "The Import sheet's button that opens a text file of cards."),
                    shortcut: .defaultAction
                )
                .disabled(importing.busy != nil)
            }
        }
    }

    /// What the sheet is busy with, beside a spinner, while it is.
    @ViewBuilder
    private var busyNote: some View {
        if let busy = importing.busy {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                switch busy {
                case .reading(let fileName):
                    Text(
                        "Reading “\(fileName)”…",
                        comment: "In the Import sheet, beside a spinner, while it reads the file chosen, with its name."
                    )
                case .importing:
                    Text("Importing…", comment: "In the Import sheet, beside a spinner, while it imports the cards.")
                }
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
    }

    /// The preview of the file chosen, with the choices for its import,
    /// which scroll above its buttons when they're taller than the sheet can
    /// be.
    private func previewOf(_ preview: ImportPreview) -> some View {
        Group {
            ScrollView {
                VStack(alignment: .leading, spacing: spacing) {
                    heading(
                        Text(
                            "Import “\(preview.fileName)”",
                            comment: "The title of the Cards window's Import sheet, with the name of the file chosen."),
                        cardsComingIn)
                    previewDetails(preview)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: maximumHeight - 2 * padding - spacing - buttonsHeight)
            .fixedSize(horizontal: false, vertical: true)
            .scrollBounceBehavior(.basedOnSize)
            .scrollBarOnlyWhenItOverflows()
            .disabled(importing.busy != nil)
            HStack {
                if importing.busy == nil {
                    chooseFileButton(
                        Text(
                            "Choose Another File…",
                            comment: "The Import sheet's button that opens another text file of cards instead."),
                        shortcut: KeyboardShortcut("o", modifiers: .command))
                } else {
                    busyNote
                }
                Spacer()
                cancelButton
                    .disabled(importing.busy == .importing)
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

    /// What the preview of the file chosen says under its title, and the
    /// choices for its import.
    private func previewDetails(_ preview: ImportPreview) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            if importing.notesComingInBothWays > 0 {
                Text(
                    "\(importing.notesComingInBothWays) notes with a reversed card come in as one card each, with Both ways on.",
                    comment:
                        "In the Import sheet's preview of an Anki package, with how many of its notes that make a card and that card turned over come in as one Ficha card, which is also reviewed back first: its back, then its front."
                )
                .fixedSize(horizontal: false, vertical: true)
            }
            if preview.cardsWithImagesDropped > 0 {
                Text(
                    "\(preview.cardsWithImagesDropped) cards have more than one image on a side, and come in with the first.",
                    comment:
                        "In the Import sheet's preview of an Anki package, with how many of its cards have more than one image on a side, of which a Ficha card holds one."
                )
                .fixedSize(horizontal: false, vertical: true)
            }
            if preview.cardsWithSoundsDropped > 0 {
                Text(
                    "\(preview.cardsWithSoundsDropped) cards have more than one sound on a side, and come in with the first.",
                    comment:
                        "In the Import sheet's preview of an Anki package, with how many of its cards have more than one sound on a side, of which a Ficha card holds one."
                )
                .fixedSize(horizontal: false, vertical: true)
            }
            if preview.cardsWithUnreadableSoundsLeftOut > 0 {
                Text(
                    "\(preview.cardsWithUnreadableSoundsLeftOut) cards have a sound Ficha can't read, such as a damaged file, and come in without it.",
                    comment:
                        "In the Import sheet's preview of an Anki package, with how many of its cards come in without a sound Ficha can't read, since their side holds something else."
                )
                .fixedSize(horizontal: false, vertical: true)
            }
            if let weight = importing.weightGoingUpToICloud {
                Text(
                    "Their images and sounds weigh \(weight.formatted(.byteCount(style: .file))), and go up to your iCloud.",
                    comment: """
                        In the Import sheet's preview while sync is on: what the images and sounds the import brings, \
                        which go up to the user's iCloud, weigh, said from 100 MB.
                        """
                )
                .fixedSize(horizontal: false, vertical: true)
            }
            if !preview.leftOut.isEmpty {
                leftOut(of: preview)
            }
            if preview.repeatedCount > 0 {
                repeatedCardsChoice(preview.repeatedCount, kind: preview.kind)
            }
            if importing.offersProgress {
                bringProgressChoice
            }
            switch preview.kind {
            case .cardsFile:
                ForEach(importing.tagFields, id: \.proposed) { field in
                    LabeledContent {
                        tagTextField(
                            field,
                            prompt: Text(
                                "No tag",
                                comment: "The Import sheet's tag field, empty: the cards get no tag of the file's."))
                    } label: {
                        Text(
                            "Tag every card with",
                            comment: "In the Import sheet, before the field for the tag every card it imports gets.")
                    }
                }
            case .ankiPackage:
                if !importing.tagFields.isEmpty {
                    ankiTags
                }
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

    /// How many cards the import brings in, as the state counts them: new
    /// ones, and while Bring progress is ticked, those that land on a step.
    private var cardsComingIn: Text {
        switch importing.cardsComingIn {
        case .new(let count)?:
            Text(
                "\(count) new cards come in, at the pace of your new cards per day.",
                comment: "In the Import sheet's preview, with how many new cards the file brings.")
        case .newAndPlaced(let new, let placed)?:
            Text(
                "\(new) new cards come in, at the pace of your new cards per day, and \(placed) on a step, as Anki had them.",
                comment:
                    "In the Import sheet's preview of an Anki package, with how many cards come in new and how many on a step of the user's ladder."
            )
        case nil:
            Text(verbatim: "")
        }
    }

    /// Bring progress, ticked until the user unticks it, and what it does,
    /// under it.
    private var bringProgressChoice: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: bringsProgress) {
                Text(
                    "Bring progress",
                    comment:
                        "In the Import sheet's preview of an Anki package, the checkbox that keeps Anki's progress.")
            }
            .toggleStyle(.checkbox)
            Text(
                """
                Cards Anki was learning or reviewing land on the step nearest their interval, due when Anki said, \
                and suspended cards come in buried. Unticked, every card comes in new.
                """,
                comment: "In the Import sheet's preview of an Anki package, under Bring progress: what it does."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.leading, 20)
            .fixedSize(horizontal: false, vertical: true)
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

    /// What stays out, in a list that scrolls when it's long: the lines a
    /// file can't read, how many and each with its number and why; or an
    /// Anki package's cards that make none, how many, and how many for each
    /// reason, since a card's place in the package says nothing.
    private func leftOut(of preview: ImportPreview) -> some View {
        let (title, rows): (Text, [String]) =
            switch preview.kind {
            case .cardsFile:
                (
                    Text(
                        "\(preview.leftOut.count) lines can't be read, and stay out:",
                        comment:
                            "In the Import sheet's preview, above the lines of the file it can't read, with how many."),
                    preview.leftOut.compactMap(reason)
                )
            case .ankiPackage:
                (
                    Text(
                        "\(preview.leftOut.count) cards stay out:",
                        comment:
                            "In the Import sheet's preview of an Anki package, above why its cards that stay out do, with how many."
                    ),
                    preview.leftOutCounts.compactMap(reason)
                )
            }
        return VStack(alignment: .leading, spacing: 6) {
            title
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        Text(row)
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

    /// The tags an Anki package's cards get, each in a field the user
    /// renames, with a button that leaves it out, in a list that scrolls
    /// when they're many.
    private var ankiTags: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                "The cards get these tags, from Anki's decks and tags:",
                comment: "In the Import sheet's preview of an Anki package, above the tags its cards get.")
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(importing.tagFields, id: \.proposed) { field in
                        HStack(spacing: 6) {
                            tagTextField(
                                field,
                                prompt: Text(
                                    "Left out",
                                    comment:
                                        "The Import sheet's field for a tag of an Anki package, empty: the cards don't get it."
                                ))
                            Button {
                                removeTag(field.proposed)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .disabled(field.isLeftOut)
                            .help(
                                Text(
                                    "Leave Out “\(TagPath.shown(field.proposed))”",
                                    comment: """
                                        The tooltip of the Import sheet's button that leaves out a tag, with the tag's \
                                        whole name, like “Medicina › Anatomía”.
                                        """)
                            )
                            .accessibilityLabel(
                                Text(
                                    "Leave Out “\(TagPath.shown(field.proposed))”",
                                    comment: """
                                        The Import sheet's button that leaves out a tag, which shows a minus, with the \
                                        tag's whole name, like “Medicina › Anatomía”.
                                        """))
                        }
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
            }
            .frame(maxHeight: 156)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The field that names the proposed tag `field`, with `prompt` while
    /// it's empty.
    private func tagTextField(_ field: CardsWindowState.TagField, prompt: Text) -> some View {
        TextField(
            String(localized: "Tag", comment: "The Import sheet's field for a tag the imported cards get."),
            text: Binding(get: { field.name }, set: { nameTag(field.proposed, $0) }),
            prompt: prompt
        )
        .textFieldStyle(.roundedBorder)
        // A focused text field keeps Return from reaching the default
        // button. The state imports only while Import is on.
        .onSubmit(importCards)
    }

    /// How many of the file's cards repeat the user's, and Update or Skip
    /// for them, under it.
    private func repeatedCardsChoice(_ count: Int, kind: ImportPreview.Kind) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                "\(count) cards repeat cards you have, by their front:",
                comment: "In the Import sheet, above Update and Skip, with how many cards of the file repeat.")
            Picker(selection: repeatedCards) {
                switch kind {
                case .cardsFile:
                    Text(
                        "Update them with the file's back, tags, type and source, keeping their progress",
                        comment: "In the Import sheet, the choice that updates the cards the file repeats."
                    )
                    .tag(ImportChoices.RepeatedCards.update)
                case .ankiPackage:
                    Text(
                        "Update them with Anki's back and tags, keeping their progress",
                        comment: "In the Import sheet, the choice that updates the cards an Anki package repeats."
                    )
                    .tag(ImportChoices.RepeatedCards.update)
                }
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

    /// Why `line`, of a text file, stays out, with its number; nil for an
    /// Anki card's reason, which the sheet counts instead.
    private func reason(_ line: LeftOutLine) -> String? {
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
        case .missingImage(let image):
            String(
                localized: "Line \(number) has a side with only the image “\(image)”, which isn't in the zip.",
                comment: "In the Import sheet, a line of a zip's text file that makes no card, with an image's name.")
        case .notAnImage(let image):
            String(
                localized:
                    "Line \(number) has a side with only the image “\(image)”, which Ficha can't read as an image.",
                comment: "In the Import sheet, a line of a zip's text file that makes no card, with an image's name.")
        case .missingSound(let sound):
            String(
                localized: "Line \(number) has a side with only the sound “\(sound)”, which isn't in the zip.",
                comment: "In the Import sheet, a line of a zip's text file that makes no card, with a sound's name.")
        case .notASound(let sound):
            String(
                localized:
                    "Line \(number) has a side with only the sound “\(sound)”, which Ficha can't read as a sound.",
                comment: "In the Import sheet, a line of a zip's text file that makes no card, with a sound's name.")
        case .emptyAnkiSide, .missingAnkiImage, .unreadableAnkiImage, .missingAnkiSound, .unreadableAnkiSound,
            .ankiImageOcclusion, .brokenAnkiTemplate:
            nil
        }
    }

    /// How many of an Anki package's cards stay out for a reason, and why;
    /// nil for a text file's reason, which the sheet lists line by line.
    private func reason(_ counted: ImportPreview.LeftOutCount) -> String? {
        let count = counted.count
        return switch counted.reason {
        case .emptyAnkiSide:
            String(
                localized:
                    "\(count) cards have a side with neither text, an image nor a sound once images on the web are left out.",
                comment: "In the Import sheet, the cards of an Anki package that make none, with how many.")
        case .missingAnkiImage:
            String(
                localized:
                    "\(count) cards have a side with only an image the package lacks, as when Anki exports a deck without its media.",
                comment: "In the Import sheet, the cards of an Anki package that make none, with how many.")
        case .unreadableAnkiImage:
            String(
                localized: "\(count) cards have a side with only an image Ficha can't read, such as a damaged file.",
                comment: "In the Import sheet, the cards of an Anki package that make none, with how many.")
        case .missingAnkiSound:
            String(
                localized:
                    "\(count) cards have a side with only a sound the package lacks, as when Anki exports a deck without its media.",
                comment: "In the Import sheet, the cards of an Anki package that make none, with how many.")
        case .unreadableAnkiSound:
            String(
                localized: "\(count) cards have a side with only a sound Ficha can't read, such as a damaged file.",
                comment: "In the Import sheet, the cards of an Anki package that make none, with how many.")
        case .ankiImageOcclusion:
            String(
                localized: "\(count) cards are Image Occlusion cards, which hide parts of an image.",
                comment: "In the Import sheet, the cards of an Anki package that make none, with how many.")
        case .brokenAnkiTemplate:
            String(
                localized: "\(count) cards have a template with a mistake, so Anki shows an error for them too.",
                comment: "In the Import sheet, the cards of an Anki package that make none, with how many.")
        case .oneColumn, .blankFront, .blankBack, .unknownType, .unclosedQuote, .strayQuote, .missingImage,
            .notAnImage, .missingSound, .notASound:
            nil
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
    /// cards, or a zip with one: Return before a file is chosen, and ⌘O once
    /// one is.
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

    /// Whether Bring progress is ticked, as the state holds it.
    private var bringsProgress: Binding<Bool> {
        Binding {
            importing.bringsProgress
        } set: {
            chooseToBringProgress($0)
        }
    }
}
