import AppKit
import FichaCore
import FichaData
import SwiftUI

/// The Backups tab of Settings: where the copies of Lucas's cards are, how
/// often Ficha backs up on its own and how many backups it keeps, the last
/// backup, and every copy, which he can restore or move to the Trash. Like
/// the other tabs, it's as tall as its settings: the list of copies scrolls
/// inside it. What it lists, offers and asks, the model's `BackupsState`
/// decides.
struct BackupsTab: View {
    @Bindable var model: AppModel
    /// Closes the review panel, if it's open, before a restore.
    let closeReviewPanel: () -> Void

    var body: some View {
        Form {
            Section {
                if let folder = model.backups.folder {
                    folderRow(folder)
                }
                Picker(selection: $model.backupSettings.frequency) {
                    Text("Every hour", comment: "Settings, under Backups: Ficha backs up once an hour.")
                        .tag(BackupSettings.Frequency.hourly)
                    Text("Every day", comment: "Settings, under Backups: Ficha backs up once a day.")
                        .tag(BackupSettings.Frequency.daily)
                    Text("Every week", comment: "Settings, under Backups: Ficha backs up once a week.")
                        .tag(BackupSettings.Frequency.weekly)
                } label: {
                    Text("Back up", comment: "Settings, under Backups: how often Ficha backs up on its own.")
                }
                // A pop-up, as Back up is, so the two rows look alike.
                Picker(selection: keptCount) {
                    ForEach(BackupSettings.keptRange, id: \.self) { count in
                        Text(count, format: .number)
                            .tag(count)
                    }
                } label: {
                    Text(
                        "Backups to keep",
                        comment: "Settings, under Backups: how many backups Ficha keeps, the newest ones.")
                }
                lastBackupRow
            } footer: {
                Text(
                    """
                    As each backup is saved, the oldest ones beyond that number go. Copies before an update, a \
                    restore or an import stay until you delete them.
                    """,
                    comment: """
                        Settings, under Backups, below its settings: "that number" is the one in Backups to keep, \
                        just above.
                        """)
            }
            Section {
                copiesTable
            } footer: {
                HStack {
                    if case .success(let copies)? = model.backups.copies {
                        summary(copies)
                    }
                    Spacer()
                    restoreButton
                    deleteButton
                }
            }
        }
        .formStyle(.grouped)
        // Each button acts on what its dialog presents, which SwiftUI hands
        // it: closing the dialog may drop the state's question before the
        // button acts.
        .confirmationDialog(
            copyToRestore.map { restoreTitle(for: $0) } ?? Text(verbatim: ""),
            isPresented: Binding(get: { copyToRestore != nil }, set: { if !$0 { model.backups.cancelQuestion() } }),
            titleVisibility: .visible,
            presenting: copyToRestore
        ) { copy in
            Button {
                closeReviewPanel()
                model.backups.restore(copy)
            } label: {
                Text("Restore", comment: "The button that restores the copy Settings' Backups tab asks about.")
            }
        } message: { _ in
            Text(
                """
                Ficha first saves everything as it is now in a copy before a restore, which the list then shows: \
                restoring that copy undoes this one.
                """,
                comment: "Under the title of the Backups tab's question before it restores a copy.")
        }
        .confirmationDialog(
            copiesToDelete.map { deletionTitle(for: $0) } ?? Text(verbatim: ""),
            isPresented: Binding(get: { copiesToDelete != nil }, set: { if !$0 { model.backups.cancelQuestion() } }),
            titleVisibility: .visible,
            presenting: copiesToDelete
        ) { copies in
            Button(role: .destructive) {
                model.backups.delete(copies)
            } label: {
                Text(
                    "Move to Trash",
                    comment: "The button that moves the copies Settings' Backups tab asks about to the Trash.")
            }
        } message: { _ in
            Text(
                "Until you empty the Trash, you can put back what you move there.",
                comment: "Under the title of the Backups tab's question before it moves copies to the Trash.")
        }
        .failureAlert(failure)
        .onAppear {
            model.backups.read()
        }
    }

    /// Where the copies are, with Show in Finder.
    private func folderRow(_ folder: URL) -> some View {
        twoLineRow {
            Text("Folder", comment: "Settings, under Backups: the folder the copies are in.")
        } detail: {
            Text(verbatim: folder.path(abbreviatingHome: Self.homeFolder))
                .textSelection(.enabled)
        } control: {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            } label: {
                Text("Show in Finder", comment: "Settings, under Backups: shows the Backups folder in Finder.")
            }
        }
    }

    /// The user's own home folder, `/Users/<name>`, which the folder's path
    /// starts with a tilde for, rather than Foundation's, for the reason
    /// `path(abbreviatingHome:)` gives. Reading it from the user database,
    /// `getpwuid(getuid())`, isn't in Apple's documentation: it's Apple
    /// staff's advice, from Quinn, of Apple's developer support (Apple's
    /// developer forums, threads 107593 and 666634). Foundation's, as before,
    /// when the user database doesn't say.
    private static var homeFolder: URL {
        guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else {
            return .homeDirectory
        }
        return URL(fileURLWithFileSystemRepresentation: directory, isDirectory: true, relativeTo: nil)
    }

    /// When the last backup was saved, or why the last attempt failed, with
    /// Back Up Now.
    private var lastBackupRow: some View {
        twoLineRow {
            Text("Last backup", comment: "Settings, under Backups: when the last backup was saved.")
        } detail: {
            switch model.backups.lastBackup {
            case .none:
                Text("None yet", comment: "Settings, under Backups: no backup was saved yet.")
            case .saved(let date):
                Text(date.formatted(date: .abbreviated, time: .shortened))
            case .failed(let error):
                Text(
                    "Failed: \(error.localizedDescription)",
                    comment: "Settings, under Backups: the last backup failed, and why."
                )
                .foregroundStyle(.red)
            }
        } control: {
            Button {
                model.backups.backUpNow(model.backupSettings)
            } label: {
                Text("Back Up Now", comment: "Settings, under Backups: saves a backup now.")
            }
        }
    }

    /// A row with `title` and `detail` under it, drawn as a form's label
    /// draws its two lines, and `control` centered beside both: LabeledContent
    /// would line the control up with the title alone.
    private func twoLineRow(
        @ViewBuilder title: () -> some View, @ViewBuilder detail: () -> some View,
        @ViewBuilder control: () -> some View
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                title()
                detail()
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            control()
        }
    }

    /// Every copy, newest first, with when it was saved, its kind and its
    /// size, or why they couldn't be read.
    @ViewBuilder
    private var copiesTable: some View {
        switch model.backups.copies {
        case .failure(let error):
            Text(error.localizedDescription)
                .foregroundStyle(.secondary)
        case .success(let copies)?:
            Table(copies, selection: selection) {
                TableColumn(Text("Saved", comment: "Settings, under Backups: the column of when a copy was saved.")) {
                    Text($0.savedAt.formatted(date: .abbreviated, time: .shortened))
                }
                TableColumn(Text("Kind", comment: "Settings, under Backups: the column of each copy's kind.")) {
                    Text(kindName($0.kind))
                }
                TableColumn(Text("Size", comment: "Settings, under Backups: the column of what each copy weighs.")) {
                    Text($0.size.formatted(.byteCount(style: .file)))
                }
                .width(80)
            }
            .frame(height: 200)
        case nil:
            EmptyView()
        }
    }

    /// How many `copies` there are and what they weigh in all, and under
    /// it what the images and the sounds they share weigh, when they share
    /// any.
    private func summary(_ copies: [DatabaseCopy]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(
                "\(copies.count) copies, \(model.backups.totalSize.formatted(.byteCount(style: .file))) in all",
                comment: "Settings, under Backups: how many copies there are, and what they weigh in all.")
            if let imagesSize = model.backups.sharedImagesSize {
                Text(
                    "Images they share: \(imagesSize.formatted(.byteCount(style: .file)))",
                    comment: """
                        Settings, under Backups, below how many copies there are: what the images on their cards \
                        weigh, each kept once for all the copies.
                        """)
            }
            if let soundsSize = model.backups.sharedSoundsSize {
                Text(
                    "Sounds they share: \(soundsSize.formatted(.byteCount(style: .file)))",
                    comment: """
                        Settings, under Backups, below how many copies there are: what the sounds on their cards \
                        weigh, each kept once for all the copies.
                        """)
            }
        }
    }

    /// Restore…, which asks whether to restore the selected copy: ⌘R.
    private var restoreButton: some View {
        Button {
            model.backups.askToRestore()
        } label: {
            Text("Restore…", comment: "Settings, under Backups: restores the selected copy, asking first.")
        }
        .disabled(!model.backups.actions.contains(.restore))
        .keyboardShortcut("r")
        .help(Text("Restore… (⌘R)", comment: "The tooltip of the Backups tab's button that restores a copy."))
    }

    /// Delete…, which asks whether to move the selected copies to the Trash:
    /// ⌘⌫, as Delete… in the Cards window.
    private var deleteButton: some View {
        Button {
            model.backups.askToDelete()
        } label: {
            Text("Delete…", comment: "Settings, under Backups: moves the selected copies to the Trash, asking first.")
        }
        .disabled(!model.backups.actions.contains(.delete))
        .keyboardShortcut(.deleteKey, modifiers: .command)
        .help(Text("Delete… (⌘⌫)", comment: "The tooltip of the Backups tab's button that deletes copies."))
    }

    /// How many backups Ficha keeps, which stays in its range.
    private var keptCount: Binding<Int> {
        Binding(
            get: { model.backupSettings.keptCount },
            set: { count in
                if let changed = BackupSettings(frequency: model.backupSettings.frequency, kept: count) {
                    model.backupSettings = changed
                }
            })
    }

    /// The copies Lucas selected in the table.
    private var selection: Binding<Set<DatabaseCopy.ID>> {
        Binding(get: { model.backups.selection }, set: { model.backups.select($0) })
    }

    /// The copy the tab asks whether to restore, while it asks.
    private var copyToRestore: DatabaseCopy? {
        guard case .restore(let copy) = model.backups.question else { return nil }
        return copy
    }

    /// The copies the tab asks whether to move to the Trash, while it asks.
    private var copiesToDelete: [DatabaseCopy]? {
        guard case .delete(let copies) = model.backups.question else { return nil }
        return copies
    }

    /// What Lucas did that couldn't be done, as an alert says it, which
    /// closing it clears.
    private var failure: Binding<Failure?> {
        Binding {
            model.backups.failure.map { failure in
                switch failure.action {
                case .restore:
                    Failure(
                        title: LocalizedStringResource(
                            "Couldn't restore the copy", comment: "An alert's title in Settings' Backups tab."),
                        error: failure.error)
                case .delete(let count):
                    Failure(
                        title: LocalizedStringResource(
                            "Couldn't move \(count) copies to the Trash",
                            comment: "An alert's title in Settings' Backups tab, with how many copies."),
                        error: failure.error)
                }
            }
        } set: {
            if $0 == nil {
                model.backups.dismissFailure()
            }
        }
    }

    /// The title of the question before restoring `copy`.
    private func restoreTitle(for copy: DatabaseCopy) -> Text {
        Text(
            "Restore the copy from \(copy.savedAt.formatted(date: .abbreviated, time: .shortened))?",
            comment: "The title of the Backups tab's question before it restores a copy, with when it was saved.")
    }

    /// The title of the question before moving `copies` to the Trash.
    private func deletionTitle(for copies: [DatabaseCopy]) -> Text {
        Text(
            "Move \(copies.count) copies to the Trash?",
            comment: "The title of the Backups tab's question before it moves copies to the Trash, with how many.")
    }

    /// What `kind` of copy is called in the table.
    private func kindName(_ kind: DatabaseCopy.Kind) -> String {
        switch kind {
        case .backup:
            String(localized: "Backup", comment: "Settings, under Backups: a copy's kind, a backup.")
        case .beforeUpdate:
            String(
                localized: "Before an update",
                comment: "Settings, under Backups: a copy's kind, saved before a new version changed the database.")
        case .beforeRestore:
            String(
                localized: "Before a restore",
                comment: "Settings, under Backups: a copy's kind, saved before a restore.")
        case .beforeImport:
            String(
                localized: "Before an import",
                comment: "Settings, under Backups: a copy's kind, saved before cards were imported from a file.")
        case .beforeICloudsCopy:
            String(
                localized: "Before taking iCloud's copy",
                comment: """
                    Settings, under Backups: a copy's kind, saved before this Mac replaced its cards with those \
                    another device restored and synced through iCloud.
                    """)
        }
    }
}
