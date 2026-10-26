import FichaCore
import FichaData
import SwiftUI

extension View {
    /// The Cards window's way to create cards: New Card in its toolbar, and
    /// ⌘N, which open the card form on a new card, and the form itself, a
    /// sheet over the window while `state` has it open, from New Card or from
    /// Convert to Card on a capture or a follow-up. `failure` is the alert
    /// over the sheet.
    func creatingCards(_ state: Binding<CardsWindowState>, failure: Binding<Failure?>) -> some View {
        modifier(CreatingCards(state: state, failure: failure))
    }
}

/// New Card, ⌘N and the card form's sheet, as `creatingCards` says.
private struct CreatingCards: ViewModifier {
    @Binding var state: CardsWindowState
    let failure: Binding<Failure?>

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        state.openNewCardForm()
                    } label: {
                        Label {
                            Text("New Card", comment: "The Cards window's toolbar button that opens the card form.")
                        } icon: {
                            Image(systemName: "plus")
                        }
                    }
                    .help(
                        Text(
                            "New Card (⌘N)",
                            comment: "The tooltip of the Cards window's toolbar button that opens the card form."))
                }
            }
            .background {
                // ⌘N, as ⌘F, works through a hidden button: the app has no
                // main menu, whose File menu would hold it.
                Button {
                    state.openNewCardForm()
                } label: {
                    Text("New Card", comment: "A hidden button of the Cards window: ⌘N, which opens the card form.")
                }
                .keyboardShortcut("n")
                .hidden()
            }
            .sheet(isPresented: Binding(get: { state.cardForm != nil }, set: { if !$0 { state.closeCardForm() } })) {
                CardFormSheet(state: $state, failure: failure)
            }
    }
}

/// Convert to Card, at the foot of a capture's or a follow-up's detail beside
/// Edit and Discard…, which opens the card form from it: ⇧⌘N, as New Card's
/// ⌘N with Shift.
struct ConvertToCardButton: View {
    let convert: () -> Void

    var body: some View {
        Button(
            String(
                localized: "Convert to Card",
                comment: "A button of the Cards window that opens the card form from the capture in the detail.")
        ) {
            convert()
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])
        .help(
            Text(
                "Convert to Card (⇧⌘N)",
                comment: "The tooltip of the Cards window's button that opens the card form from the capture."))
    }
}

/// The card form, a sheet over the Cards window: an optional type, a front
/// and a back, each with its text, an image and a sound, dragged or pasted
/// under it, tags, a source and Both ways, and, when it was opened from a capture, the capture
/// beside them, whole, with the card it follows up below it when it's a
/// follow-up. Add saves the card and keeps the form open, with the
/// front and the back cleared for the next one, as Anki's Add
/// window does; Return adds too, Option-Return starts a new line, and Escape
/// closes, as Close does. While the front repeats another card's, the form
/// says so under it, with Show Card (⌘R), which sets the form aside, as it
/// is, until it's opened the same way again, and selects that card in the
/// window. `CardsWindowState` decides what the form holds
/// after each change, whether Add is on, what it warns about, and what
/// closing does to the capture; the sheet draws it, and keeps which field has
/// the focus. When a card can't be added, an alert says why, and the fields
/// stay as the user left them.
private struct CardFormSheet: View {
    @Binding var state: CardsWindowState
    /// What couldn't be saved, as the alert over the sheet says it.
    let failure: Binding<Failure?>
    @FocusState private var isFrontFocused: Bool

    var body: some View {
        if let form = state.cardForm {
            HStack(alignment: .top, spacing: 0) {
                if let capture = form.capture {
                    captureColumn(capture, followUp: form.followUp, approvedOnClose: form.approvesCaptureOnClose)
                        .frame(width: 260)
                    Divider()
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("New Card", comment: "The title of the Cards window's card form.")
                        .font(.headline)
                    fields(form)
                    footer(form)
                }
                .padding(20)
                .frame(width: 460)
            }
            .fixedSize(horizontal: false, vertical: true)
            .onAppear {
                isFrontFocused = true
            }
            // Back to the front for the next card.
            .onChange(of: form.addedCards.count) {
                isFrontFocused = true
            }
            .failureAlert(failure)
        }
    }

    /// The capture the form was opened from, whole, as the inbox's detail
    /// shows it, with its card below it when it's a follow-up, and what
    /// closing the form does to it.
    private func captureColumn(_ capture: Capture, followUp: FollowUp?, approvedOnClose: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let followUp {
                CaptureDetail(
                    capture: capture, kind: InboxRow.Item.followUp(followUp).kindName, tie: .followsUp(followUp.card))
            } else {
                CaptureDetail(capture: capture, kind: InboxRow.Item.capture(capture).kindName, tie: nil)
            }
            Group {
                if approvedOnClose {
                    Text(
                        "Once you close the form, the capture leaves the inbox.",
                        comment: "In the Cards window's card form opened from a capture, once a card was added from it."
                    )
                } else {
                    Text(
                        "The capture stays in the inbox until you add a card from it.",
                        comment: "In the Cards window's card form opened from a capture, before any card was added.")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.fill.quinary)
    }

    private func fields(_ form: CardsWindowState.CardForm) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                let label = Text("Type", comment: "In the Cards window's card form, the label of the card's type.")
                gridLabel(label)
                CardTypePicker(type: draft(\.type), label: label)
            }
            GridRow {
                gridLabel(Text("Front", comment: "In the Cards window's card form, the label of the card's front."))
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Front", text: draft(\.front.text), axis: .vertical)
                        .lineLimit(1...4)
                        .focused($isFrontFocused)
                    if let warning = form.frontWarning {
                        FrontWarningView(warning: warning) {
                            state.showRepeatedCard()
                        }
                    }
                    imageWell(on: .front, of: form)
                    soundWell(on: .front, of: form)
                }
            }
            GridRow {
                gridLabel(Text("Back", comment: "In the Cards window's card form, the label of the card's back."))
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Back", text: draft(\.back.text), axis: .vertical)
                        .lineLimit(4...10)
                    imageWell(on: .back, of: form)
                    soundWell(on: .back, of: form)
                }
            }
            GridRow {
                gridLabel(Text("Tags", comment: "In the Cards window's card form, the label of the card's tags."))
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Tags", text: draft(\.tags))
                    Text("Separate tags with commas.", comment: "In the Cards window's card form, under the tags.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            GridRow {
                gridLabel(Text("Source", comment: "In the Cards window's card form, the label of the card's source."))
                TextField(
                    "Source", text: draft(\.source),
                    prompt: Text(
                        "A book, a podcast…", comment: "In the Cards window's card form, in the empty source."),
                    axis: .vertical
                )
                .lineLimit(1...3)
            }
            GridRow {
                gridLabel(BothWaysToggle.label)
                BothWaysToggle(bothWays: draft(\.bothWays))
            }
        }
        .textFieldStyle(.roundedBorder)
        // A focused text field keeps Return from reaching the default button.
        .onSubmit {
            state.addCard()
        }
    }

    /// The last card added, Close and Add.
    private func footer(_ form: CardsWindowState.CardForm) -> some View {
        HStack(alignment: .firstTextBaseline) {
            if let added = form.addedCards.last {
                Label {
                    Text(
                        "Added “\(added.front)”",
                        comment: "In the Cards window's card form, after Add, with the front of the card it added.")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                state.closeCardForm()
            } label: {
                Text("Close", comment: "The button that closes the Cards window's card form.")
            }
            .keyboardShortcut(.cancelAction)
            Button {
                state.addCard()
            } label: {
                Text("Add", comment: "The button of the Cards window's card form that saves the card.")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!form.canAdd)
        }
    }

    /// The place for the image on `side` of the card the form makes.
    private func imageWell(on side: CardSide, of form: CardsWindowState.CardForm) -> some View {
        ImageWell(
            image: side == .front ? form.draft.front.image : form.draft.back.image, images: state.images
        ) { dropped in
            state.putImageInForm(dropped, on: side)
        } remove: {
            state.removeImageFromForm(on: side)
        }
    }

    /// The place for the sound on `side` of the card the form makes.
    private func soundWell(on side: CardSide, of form: CardsWindowState.CardForm) -> some View {
        SoundWell(
            sound: side == .front ? form.draft.front.sound : form.draft.back.sound, sounds: state.sounds,
            isComingIn: form.isSoundComingIn(on: side), isPlaying: state.isPlaying(at: .form(side))
        ) {
            state.playOrStopSound(at: .form(side))
        } put: { file in
            convert(state.putSoundInForm(file, on: side), for: $state)
        } remove: {
            state.removeSoundFromForm(on: side)
        }
    }

    /// A field of the form's draft, which the state changes as the user types.
    private func draft<Value>(_ field: WritableKeyPath<CardsWindowState.CardForm.Draft, Value>) -> Binding<Value> {
        Binding {
            // The form is open while the sheet shows it.
            (state.cardForm?.draft ?? CardsWindowState.CardForm.Draft())[keyPath: field]
        } set: { value in
            guard var draft = state.cardForm?.draft else { return }
            draft[keyPath: field] = value
            state.changeDraft(draft)
        }
    }
}

/// What the card form says under the front: the card whose front it repeats,
/// with Show Card, or that it couldn't check.
private struct FrontWarningView: View {
    let warning: CardsWindowState.CardForm.FrontWarning
    /// Shows the card it repeats in the window.
    let show: () -> Void

    var body: some View {
        switch warning {
        case .repeats(let card):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(
                    "Another card has this front: “\(card.front)”.",
                    comment:
                        "In the Cards window's card form, under a front that repeats another card's, with its front."
                )
                .lineLimit(2)
                Button(action: show) {
                    Text(
                        "Show Card",
                        comment: "In the Cards window's card form: closes it and selects the card the front repeats.")
                }
                .buttonStyle(.link)
                .keyboardShortcut("r")
                .help(
                    Text(
                        "Show Card (⌘R)",
                        comment: "The tooltip of the card form's button that shows the card the front repeats."))
            }
            .font(.callout)
        case .uncheckable(let error):
            Label {
                Text(
                    "Couldn't check whether another card has this front. \(error.localizedDescription)",
                    comment: "In the Cards window's card form, under the front, with why it couldn't be checked.")
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}
