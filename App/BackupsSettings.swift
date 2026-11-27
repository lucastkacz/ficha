import AppKit
import FichaCore
import FichaData
import SwiftUI

/// Settings' Backups, in the Advanced tab (#492): how often Ficha backs up on
/// its own and how many backups it keeps, the last backup, where the copies
/// are, and every copy, which Lucas can restore or move to the Trash. The
/// list of copies scrolls inside the tab. What it lists, offers and asks, the
/// model's `BackupsState` decides.
enum BackupsSection {
    /// Backups' heading.
    static var header: some View {
        Text(
            "Backups",
            comment: """
                A heading of Settings' Advanced tab: over how often Ficha backs up on its own, how many backups it \
                keeps, the last backup and the folder the copies are in.
                """)
    }

    /// What Backups says under its settings.
    static var footer: some View {
        Text(
            """
            As each backup is saved, the oldest ones beyond that number go. Copies before an update, a restore or \
            an import stay until you delete them.
            """,
            comment: """
                Settings, under Backups, below its settings: "that number" is the one in Backups to keep, just \
                above.
                """)
    }
}

extension View {
    /// What Backups asks and says over the Advanced tab, and reads as the tab
    /// shows: whether to restore a copy, closing the review panel with
    /// `closeReviewPanel` before it does, or to move copies to the Trash, and
    /// what couldn't be done.
    func backupsActions(model: AppModel, closeReviewPanel: @escaping () -> Void) -> some View {
        // Each button acts on what its dialog presents, which SwiftUI hands
        // it: closing the dialog may drop the state's question before the
        // button acts.
        confirmationDialog(
            copyToRestore(model).map(restoreTitle) ?? Text(verbatim: ""),
            isPresented: Binding(
                get: { copyToRestore(model) != nil }, set: { if !$0 { model.backups.cancelQuestion() } }),
            titleVisibility: .visible,
            presenting: copyToRestore(model)
        ) { copy in
            Button {
                closeReviewPanel()
                model.backups.restore(copy)
            } label: {
                Text("Restore", comment: "The button that restores the copy Settings' Backups asks about.")
            }
        } message: { _ in
            Text(
                """
                Ficha first saves everything as it is now in a copy before a restore, which the list then shows: \
                restoring that copy undoes this one.
                """,
                comment: "Under the title of the question Settings' Backups asks before it restores a copy.")
        }
        .confirmationDialog(
            copiesToDelete(model).map(deletionTitle) ?? Text(verbatim: ""),
            isPresented: Binding(
                get: { copiesToDelete(model) != nil }, set: { if !$0 { model.backups.cancelQuestion() } }),
            titleVisibility: .visible,
            presenting: copiesToDelete(model)
        ) { copies in
            Button(role: .destructive) {
                model.backups.delete(copies)
            } label: {
                Text(
                    "Move to Trash",
                    comment: "The button that moves the copies Settings' Backups asks about to the Trash.")
            }
        } message: { _ in
            Text(
                "Until you empty the Trash, you can put back what you move there.",
                comment: "Under the title of the question Settings' Backups asks before it moves copies to the Trash.")
        }
        .failureAlert(backupsFailure(model))
        .onAppear {
            model.backups.read()
        }
    }
}

/// The copy Backups asks whether to restore, while it asks.
private func copyToRestore(_ model: AppModel) -> DatabaseCopy? {
    guard case .restore(let copy) = model.backups.question else { return nil }
    return copy
}

/// The copies Backups asks whether to move to the Trash, while it asks.
private func copiesToDelete(_ model: AppModel) -> [DatabaseCopy]? {
    guard case .delete(let copies) = model.backups.question else { return nil }
    return copies
}

/// The title of the question before restoring `copy`.
private func restoreTitle(_ copy: DatabaseCopy) -> Text {
    Text(
        "Restore the copy from \(copy.savedAt.formatted(date: .abbreviated, time: .shortened))?",
        comment: "The title of the question Settings' Backups asks before it restores a copy, with when it was saved.")
}

/// The title of the question before moving `copies` to the Trash.
private func deletionTitle(_ copies: [DatabaseCopy]) -> Text {
    Text(
        "Move \(copies.count) copies to the Trash?",
        comment: """
            The title of the question Settings' Backups asks before it moves copies to the Trash, with how many.
            """)
}

/// What Lucas did in Backups that couldn't be done, as an alert says it,
/// which closing it clears.
private func backupsFailure(_ model: AppModel) -> Binding<Failure?> {
    Binding {
        model.backups.failure.map { failure in
            switch failure.action {
            case .restore:
                Failure(
                    title: LocalizedStringResource(
                        "Couldn't restore the copy", comment: "An alert's title in Settings, under Backups."),
                    error: failure.error)
            case .delete(let count):
                Failure(
                    title: LocalizedStringResource(
                        "Couldn't move \(count) copies to the Trash",
                        comment: "An alert's title in Settings, under Backups, with how many copies."),
                    error: failure.error)
            }
        }
    } set: {
        if $0 == nil {
            model.backups.dismissFailure()
        }
    }
}

/// How often Ficha backs up on its own.
struct BackupFrequencyRow: View {
    @Bindable var model: AppModel

    var body: some View {
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
    }
}

/// How many backups Ficha keeps, which stays in its range: a pop-up, as Back
/// up is, so the two rows look alike.
struct BackupsKeptRow: View {
    @Bindable var model: AppModel

    var body: some View {
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
}

/// When the last backup was saved, or why the last attempt failed, with Back
/// Up Now.
struct LastBackupRow: View {
    let model: AppModel

    var body: some View {
        TwoLineRow {
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
}

/// Where the copies are, with Show in Finder: nothing for an engine in
/// memory, which saves none.
struct BackupsFolderRow: View {
    let model: AppModel

    var body: some View {
        if let folder = model.backups.folder {
            TwoLineRow {
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
    }

    /// The user's own home folder, `/Users/<name>`, which the folder's path
    /// starts with a tilde for. In the app's sandbox, Foundation's isn't, as
    /// `path(abbreviatingHome:)` says, so it's read from the user database,
    /// `getpwuid(getuid())`, which isn't in Apple's documentation: it's Apple
    /// staff's advice, from Quinn, of Apple's developer support (Apple's
    /// developer forums, threads 107593 and 666634). Out of the sandbox, and
    /// when the user database doesn't say, it's Foundation's, which
    /// `CFFIXED_USER_HOME` moves, as `make render`'s scratch home does, and
    /// the user database doesn't.
    private static var homeFolder: URL {
        guard signedEntitlement("com.apple.security.app-sandbox") as? Bool == true,
            let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir
        else {
            return .homeDirectory
        }
        return URL(fileURLWithFileSystemRepresentation: directory, isDirectory: true, relativeTo: nil)
    }
}

/// A row with `title` and `detail` under it, drawn as a form's label draws
/// its two lines, and `control` centered beside both: LabeledContent would
/// line the control up with the title alone.
private struct TwoLineRow<Title: View, Detail: View, Control: View>: View {
    @ViewBuilder let title: Title
    @ViewBuilder let detail: Detail
    @ViewBuilder let control: Control

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                title
                detail
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            control
        }
    }
}

/// Every copy, newest first, with when it was saved, its kind and its size,
/// or why they couldn't be read, in a table as wide as the tab, `width`,
/// which it fits.
struct CopiesTable: View {
    let model: AppModel
    let width: CGFloat

    var body: some View {
        switch model.backups.copies {
        case .failure(let error):
            Text(error.localizedDescription)
                .foregroundStyle(.secondary)
        case .success(let copies)?:
            // The grouped form puts the table 20 points in from each side.
            let columns = CopyTableColumns(now: model.now, tableWidth: width - 2 * 20)
            Table(copies, selection: selection) {
                TableColumn(Text(columns.saved.header)) {
                    Text($0.savedAt.formatted(CopyTableColumns.savedAt))
                }
                .width(fitting: columns.saved)
                TableColumn(Text(columns.kind.header)) {
                    // Wraps where the column is narrower than the kind's
                    // name, as beside Spanish's dates, rather than keep to
                    // one line, as a table's text does.
                    Text(kindName($0.kind))
                        .lineLimit(nil)
                }
                .width(fitting: columns.kind)
                TableColumn(Text(columns.size.header)) {
                    Text($0.size.formatted(.byteCount(style: .file)))
                }
                .width(fitting: columns.size)
            }
            .frame(height: 200)
        case nil:
            EmptyView()
        }
    }

    /// The copies Lucas selected in the table.
    private var selection: Binding<Set<DatabaseCopy.ID>> {
        Binding(get: { model.backups.selection }, set: { model.backups.select($0) })
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

/// What the table of copies says under it: how many copies there are and
/// what they weigh in all, and what the images and the sounds they share
/// weigh, when they share any; then Restore… and Delete….
struct CopiesFooter: View {
    let model: AppModel
    /// Whether the keyboard is in Advanced's Longest interval field, which
    /// keeps ⌘⌫ for itself.
    @FocusedValue(\.isEditingLongestInterval) private var isEditingLongestInterval

    var body: some View {
        HStack {
            if case .success(let copies)? = model.backups.copies {
                summary(copies)
            }
            Spacer()
            restoreButton
            deleteButton
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
        .help(Text("Restore… (⌘R)", comment: "The tooltip of Settings' Backups button that restores a copy."))
    }

    /// Delete…, which asks whether to move the selected copies to the Trash:
    /// ⌘⌫, as Delete… in the Cards window, but while the keyboard is in the
    /// Longest interval field, where it deletes what's before the insertion
    /// point, as the Cards window's ⌘⌫ leaves its search field alone.
    private var deleteButton: some View {
        Button {
            model.backups.askToDelete()
        } label: {
            Text("Delete…", comment: "Settings, under Backups: moves the selected copies to the Trash, asking first.")
        }
        .disabled(!model.backups.actions.contains(.delete))
        .keyboardShortcut(isEditingLongestInterval == true ? nil : KeyboardShortcut(.deleteKey, modifiers: .command))
        .help(Text("Delete… (⌘⌫)", comment: "The tooltip of Settings' Backups button that deletes copies."))
    }
}
