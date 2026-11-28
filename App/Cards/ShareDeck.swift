import AppKit
import FichaData
import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// Opens macOS's Share menu from this view, the Actions menu above the
    /// grid, while `state` offers a deck's `.ficha` after Share Deck…
    /// (`CardsWindowShareDeck.swift`, ADR 0044): AirDrop, Messages, Mail and
    /// the Mac's other services, through AppKit's `NSSharingServicePicker`,
    /// and the app's own Save to File… at the menu's end, which saves the
    /// file where the user picks in a save panel.
    func sharingDecks(_ state: Binding<CardsWindowState>) -> some View {
        background(ShareMenuAnchor(state: state))
    }
}

/// The view the Share menu opens from, as AppKit's picker needs one, which
/// opens it once for each file the state offers.
private struct ShareMenuAnchor: NSViewRepresentable {
    @Binding var state: CardsWindowState

    func makeCoordinator() -> ShareMenu {
        ShareMenu()
    }

    func makeNSView(context: Context) -> AnchorView {
        AnchorView()
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        let shareMenu = context.coordinator
        shareMenu.state = $state
        guard let file = state.deckFileToShare, file != shareMenu.shownFile else { return }
        shareMenu.shownFile = file
        view.onceInAWindow { view in
            shareMenu.show(file, from: view)
        }
        // After SwiftUI's update, once the view is in its window.
        Task {
            view.doWhatWaits()
        }
    }
}

/// An empty view the Share menu opens from, which waits to be in a window.
private final class AnchorView: NSView {
    private var waiting: ((NSView) -> Void)?

    /// Does `work` with the view as soon as it's in a window.
    func onceInAWindow(_ work: @escaping (NSView) -> Void) {
        waiting = work
    }

    /// Does what waits, if the view is in a window.
    func doWhatWaits() {
        guard window != nil, let work = waiting else { return }
        waiting = nil
        work(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        doWhatWaits()
    }
}

/// The Share menu of a deck's `.ficha`, and its Save to File…, which tell the
/// state how it closed: on a service of macOS's, which may still read the
/// file; with nothing chosen; or through Save to File…'s save panel.
private final class ShareMenu: NSObject {
    var state: Binding<CardsWindowState>?
    /// The file the menu last opened on, so it opens once for each.
    var shownFile: URL?
    /// The picker while it shows, which AppKit doesn't keep.
    private var picker: NSSharingServicePicker?
    /// Save to File…, the menu's last item, by its identity.
    private var saveToFile: ObjectIdentifier?

    /// Opens the Share menu on `file`, under `view`.
    func show(_ file: URL, from view: NSView) {
        let picker = NSSharingServicePicker(items: [file])
        picker.delegate = self
        self.picker = picker
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    /// Notes which service Save to File… is, as the menu lists it.
    fileprivate func noteSaveToFile(_ service: ObjectIdentifier) {
        saveToFile = service
    }

    /// Tells the state how the menu closed, on `service`, or with nothing
    /// chosen when it's nil.
    fileprivate func closed(choosing service: ObjectIdentifier?) {
        picker = nil
        guard let service else {
            state?.wrappedValue.doneSharingDeck()
            return
        }
        // Save to File… closes the menu too, and its save panel says when
        // it's done.
        if service != saveToFile {
            state?.wrappedValue.closeShareMenu()
        }
    }

    /// Save to File…: a save panel over the window, named as the file is,
    /// which saves it where the user picks, or lets it go once cancelled.
    fileprivate func saveFile() {
        guard let state, let file = state.wrappedValue.deckFileToShare else { return }
        state.wrappedValue.closeShareMenu()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.fichaDeck]
        panel.nameFieldStringValue = file.lastPathComponent
        panel.canCreateDirectories = true
        let save = { (response: NSApplication.ModalResponse) in
            if response == .OK, let chosen = panel.url {
                state.wrappedValue.saveSharedDeck(to: chosen)
            } else {
                state.wrappedValue.doneSharingDeck()
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: save)
        } else {
            panel.begin(completionHandler: save)
        }
    }
}

// AppKit calls the picker's delegate on the main thread, where it shows the
// menu; its methods hop to the main actor for the state, however the SDK
// isolates the protocol.
extension ShareMenu: NSSharingServicePickerDelegate {
    /// The services macOS proposes for the file, and Save to File… last.
    nonisolated func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker, sharingServicesForItems items: [Any],
        proposedSharingServices proposedServices: [NSSharingService]
    ) -> [NSSharingService] {
        let title = String(
            localized: "Save to File…",
            comment: """
                The last item of the Share menu Share Deck… opens in the Cards window: it saves the deck's .ficha \
                file where the user picks.
                """)
        let image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil) ?? NSImage()
        let service = NSSharingService(title: title, image: image, alternateImage: nil) { [weak self] in
            MainActor.assumeIsolated {
                self?.saveFile()
            }
        }
        let identity = ObjectIdentifier(service)
        MainActor.assumeIsolated {
            noteSaveToFile(identity)
        }
        return proposedServices + [service]
    }

    nonisolated func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?
    ) {
        let chosen = service.map { ObjectIdentifier($0) }
        MainActor.assumeIsolated {
            closed(choosing: chosen)
        }
    }
}
