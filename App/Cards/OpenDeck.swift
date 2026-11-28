import FichaData
import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// Open Deck…'s open panel over the Cards window while `state` asks for
    /// a deck's `.ficha`, ⌘O, which asks for one, and the file Finder opened
    /// Ficha with, which `model` holds until the window takes it: each read
    /// away from the main actor, after which `state` asks How fast? for its
    /// deck, or says why it couldn't (`CardsWindowOpenDeck.swift`, ADR 0044).
    func openingDecks(_ state: Binding<CardsWindowState>, model: AppModel) -> some View {
        modifier(OpeningDecks(state: state, model: model))
    }
}

/// Open Deck…'s open panel, ⌘O, and the file Finder opened Ficha with.
private struct OpeningDecks: ViewModifier {
    @Binding var state: CardsWindowState
    let model: AppModel

    func body(content: Content) -> some View {
        content
            .background {
                // ⌘O, as in any Mac app, works through a hidden button, as
                // ⌘N does: the app has no main menu, whose File menu would
                // hold it.
                Button {
                    state.askToOpenDeck()
                } label: {
                    OpenDeckItem.title
                }
                .keyboardShortcut("o")
                .hidden()
            }
            .fileImporter(isPresented: isChoosingDeckFile, allowedContentTypes: [.fichaDeck]) { result in
                if case .success(let file) = result {
                    run(state.openDeck(file))
                }
            }
            // A deck's file Finder opened Ficha with, as it opens the window,
            // or while it's open.
            .onChange(of: model.deckFileToOpen, initial: true) {
                if let file = model.deckFileToOpen {
                    model.deckFileToOpen = nil
                    run(state.openDeck(file))
                }
            }
    }

    /// Whether the open panel shows, while the state asks for a deck's
    /// `.ficha`. The panel closed with no file cancels the question, and
    /// leaves alone any other the window asks by then.
    private var isChoosingDeckFile: Binding<Bool> {
        Binding(
            get: { state.isChoosingDeckFile },
            set: { isShown in
                if !isShown, state.isChoosingDeckFile {
                    state.cancelQuestion()
                }
            })
    }

    /// Runs `work`, which the state started, away from the main actor, and
    /// hands what it read back to the state.
    private func run(_ work: OpenDeckWork?) {
        guard let work else { return }
        Task {
            state.finishOpenDeck(await readAwayFromTheMainActor(work))
        }
    }
}

/// What `work` read, read away from the main actor: a big deck's pictures
/// take a while, while the window goes on answering.
@concurrent
private func readAwayFromTheMainActor(_ work: OpenDeckWork) async -> OpenDeckWork.Done {
    await work.run()
}

extension UTType {
    /// A deck's `.ficha`, a zip of Ficha's own, as the app's Info.plist
    /// exports it, which both apps open (ADR 0044).
    nonisolated static let fichaDeck = UTType(exportedAs: "com.lucastkacz.ficha.deck", conformingTo: .zip)
}
