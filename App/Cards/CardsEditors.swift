import FichaCore
import FichaData
import SwiftUI

/// The fields the user edits a card in, in place of its detail: its type, or
/// None, front and back, each with its text, its image and its sound, dragged
/// or pasted under it, an image also with ⌘V in its text while the clipboard
/// holds no text, tags, source and Both ways, under the flag's note when
/// it's flagged. Return saves, Option-Return starts a new line, and Escape
/// cancels, as in the capture window, unless the search field has the focus.
/// Save is off while a sound converts. Saving with a side that has neither
/// text, an image nor a sound says, under it, what's missing. When the card
/// can't be saved, the window's alert says why, and the fields stay as the
/// user left them.
struct CardEditor: View {
    /// The card as it was when Lucas started editing it.
    let card: Card
    /// The images on its sides as Save would give them to it, which the
    /// window holds.
    let images: SideImages
    /// The images the window shows, those on its sides among them.
    let shownImages: ShownImages
    /// The sounds on its sides as Save would give them to it, which the
    /// window holds.
    let sounds: SideSounds
    /// Whether it goes both ways as Save would set it, which the window
    /// holds.
    let bothWays: Bool
    /// Whether Save is on: not while a sound converts.
    let canSave: Bool
    /// Whether Lucas is in the window's search field, which then keeps Return
    /// and Escape: Escape there clears the search, and leaves his edit alone.
    let isSearching: Bool
    /// Puts what was dragged or pasted on a side, as its image.
    let putImage: (DroppedImage, CardSide) -> Void
    /// Removes a side's image.
    let removeImage: (CardSide) -> Void
    /// The place for a side's sound, which the window fills.
    let soundWell: (CardSide) -> SoundWell
    /// Turns Both ways on or off, as Save will set it.
    let setBothWays: (Bool) -> Void
    /// Saves the card with `content`, which ends the edit once it's saved.
    let save: (CardContent) -> Void
    /// Ends the edit without saving it.
    let cancel: () -> Void
    /// The card's type, or nil for None.
    @State private var type: CardType?
    @State private var front: String
    @State private var back: String
    /// The card's tags as the Tags field holds them, separated by commas.
    @State private var tagsText: String
    @State private var source: String
    /// Whether Lucas tried to save with the front or the back blank, so that
    /// the blank one says it's missing.
    @State private var showsMissingSides = false
    /// The side whose text has the focus.
    @FocusState private var focusedText: CardSide?

    init(
        card: Card,
        images: SideImages,
        shownImages: ShownImages,
        sounds: SideSounds,
        bothWays: Bool,
        canSave: Bool,
        isSearching: Bool,
        putImage: @escaping (DroppedImage, CardSide) -> Void,
        removeImage: @escaping (CardSide) -> Void,
        soundWell: @escaping (CardSide) -> SoundWell,
        setBothWays: @escaping (Bool) -> Void,
        save: @escaping (CardContent) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.card = card
        self.images = images
        self.shownImages = shownImages
        self.sounds = sounds
        self.bothWays = bothWays
        self.canSave = canSave
        self.isSearching = isSearching
        self.putImage = putImage
        self.removeImage = removeImage
        self.soundWell = soundWell
        self.setBothWays = setBothWays
        self.save = save
        self.cancel = cancel
        _type = State(initialValue: card.type)
        _front = State(initialValue: card.front)
        _back = State(initialValue: card.back)
        _tagsText = State(initialValue: CardContent.tagsField(of: card.tags))
        _source = State(initialValue: card.source ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FlagAndBurial(standing: card.standing, isEditing: true)
                fields
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            EditorActions(isSearching: isSearching, canSave: canSave, cancel: cancel, save: submit)
        }
        .onAppear {
            focusedText = .front
        }
    }

    private var fields: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                let label = Text(
                    "Type", comment: "In the Cards window, the label of a card's type, while Lucas edits it.")
                gridLabel(label)
                CardTypePicker(type: $type, label: label)
            }
            GridRow {
                gridLabel(
                    Text("Front", comment: "In the Cards window, the label of a card's front, while Lucas edits it."))
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Front", text: $front, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($focusedText, equals: .front)
                        .pastesImages(while: focusedText == .front) { image in
                            putImage(image, .front)
                        }
                    if showsMissingSides && CardContent.isBlank(front, image: images.front, sound: sounds.front) {
                        missing(
                            Text(
                                "A card needs a front.",
                                comment: "In the Cards window, under a card's front, when Lucas saves it blank."))
                    }
                    imageWell(on: .front)
                    soundWell(.front)
                }
            }
            GridRow {
                gridLabel(
                    Text("Back", comment: "In the Cards window, the label of a card's back, while Lucas edits it."))
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Back", text: $back, axis: .vertical)
                        .lineLimit(4...12)
                        .focused($focusedText, equals: .back)
                        .pastesImages(while: focusedText == .back) { image in
                            putImage(image, .back)
                        }
                    if showsMissingSides && CardContent.isBlank(back, image: images.back, sound: sounds.back) {
                        missing(
                            Text(
                                "A card needs a back.",
                                comment: "In the Cards window, under a card's back, when Lucas saves it blank."))
                    }
                    imageWell(on: .back)
                    soundWell(.back)
                }
            }
            GridRow {
                gridLabel(
                    Text("Tags", comment: "In the Cards window, the label of a card's tags, while Lucas edits it."))
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Tags", text: $tagsText)
                    Text(
                        "Separate tags with commas.",
                        comment: "In the Cards window, under a card's tags, while Lucas edits it."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            GridRow {
                gridLabel(
                    Text("Source", comment: "In the Cards window, the label of a card's source, while Lucas edits it."))
                TextField(
                    "Source", text: $source,
                    prompt: Text(
                        "A book, a podcast…",
                        comment: "In the Cards window, in a card's empty source, while Lucas edits it."),
                    axis: .vertical
                )
                .lineLimit(1...3)
            }
            GridRow {
                gridLabel(BothWaysToggle.label)
                BothWaysToggle(
                    bothWays: Binding {
                        bothWays
                    } set: {
                        setBothWays($0)
                    })
            }
        }
        .textFieldStyle(.roundedBorder)
        // A focused text field keeps Return from reaching the default button.
        .onSubmit(submit)
    }

    /// The tags in the Tags field.
    private var tags: [String] {
        CardContent.tags(inField: tagsText)
    }

    /// The place for the image on `side`.
    private func imageWell(on side: CardSide) -> some View {
        ImageWell(image: images[side], images: shownImages) { dropped in
            putImage(dropped, side)
        } remove: {
            removeImage(side)
        }
    }

    /// Saves the card with what the fields hold and the images and sounds on
    /// its sides, while Save is on, unless a side has neither text, an image
    /// nor a sound.
    private func submit() {
        guard canSave else { return }
        guard
            let content = CardContent(
                type: type, front: front, back: back, tags: tags, source: source, frontImage: images.front,
                backImage: images.back, frontSound: sounds.front, backSound: sounds.back)
        else {
            showsMissingSides = true
            return
        }
        save(content)
    }
}

/// The fields Lucas edits a capture in, in place of its detail: its text,
/// note and source, as the capture window has them. Return saves,
/// Option-Return starts a new line, and Escape cancels, as in the capture
/// window, unless he's in the window's search field. Saving with the text
/// blank says, under it, that it's missing. When the capture can't be saved,
/// the window's alert says why, and the fields stay as Lucas left them.
struct CaptureEditor: View {
    /// The capture as it was when Lucas started editing it.
    let capture: Capture
    /// Whether Lucas is in the window's search field, which then keeps Return
    /// and Escape, as `CardEditor` says.
    let isSearching: Bool
    /// Saves the capture with what the fields hold, its text, note and
    /// source, which ends the edit once it's saved.
    let save: (String, String, String) -> Void
    /// Ends the edit without saving it.
    let cancel: () -> Void
    @State private var text: String
    @State private var note: String
    @State private var source: String
    /// Whether Lucas tried to save with the text blank, so that it says it's
    /// missing.
    @State private var showsMissingText = false
    @FocusState private var isTextFocused: Bool

    init(
        capture: Capture,
        isSearching: Bool,
        save: @escaping (String, String, String) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.capture = capture
        self.isSearching = isSearching
        self.save = save
        self.cancel = cancel
        _text = State(initialValue: capture.text)
        _note = State(initialValue: capture.note ?? "")
        _source = State(initialValue: capture.source ?? "")
    }

    var body: some View {
        ScrollView {
            fields
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            EditorActions(isSearching: isSearching, cancel: cancel, save: submit)
        }
        .onAppear {
            isTextFocused = true
        }
    }

    private var fields: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                gridLabel(
                    Text("Text", comment: "In the Cards window, the label of a capture's text, while Lucas edits it."))
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Text", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($isTextFocused)
                    if showsMissingText && !fieldsMakeACapture {
                        missing(
                            Text(
                                "A capture needs a text.",
                                comment: "In the Cards window, under a capture's text, when Lucas saves it blank."))
                    }
                }
            }
            GridRow {
                gridLabel(
                    Text("Note", comment: "In the Cards window, the label of a capture's note, while Lucas edits it."))
                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(1...4)
            }
            GridRow {
                gridLabel(
                    Text(
                        "Source", comment: "In the Cards window, the label of a capture's source, while Lucas edits it."
                    ))
                TextField(
                    "Source", text: $source,
                    prompt: Text(
                        "A book, a podcast…",
                        comment: "In the Cards window, in a capture's empty source, while Lucas edits it."),
                    axis: .vertical
                )
                .lineLimit(1...3)
            }
        }
        .textFieldStyle(.roundedBorder)
        // A focused text field keeps Return from reaching the default button.
        .onSubmit(submit)
    }

    /// Whether the fields hold a capture, by the rule the engine saves it
    /// with: until there's text, they don't.
    private var fieldsMakeACapture: Bool {
        CaptureContent(text: text, note: note, source: source) != nil
    }

    /// Saves the capture with what the fields hold, unless the text is blank.
    private func submit() {
        guard fieldsMakeACapture else {
            showsMissingText = true
            return
        }
        save(text, note, source)
    }
}

/// What's missing, under a field Lucas left blank in one of the editors.
private func missing(_ text: Text) -> some View {
    text
        .font(.caption)
        .foregroundStyle(.red)
}

/// Cancel and Save, at the foot of an editor: Escape cancels and Return saves,
/// unless Lucas is in the window's search field, which then keeps them, so
/// that Escape there clears the search and leaves his edit alone.
private struct EditorActions: View {
    /// Whether Lucas is in the window's search field.
    let isSearching: Bool
    /// Whether Save is on.
    var canSave = true
    let cancel: () -> Void
    let save: () -> Void

    var body: some View {
        ActionBar {
            Spacer()
            Button("Cancel", action: cancel)
                .keyboardShortcut(isSearching ? nil : .cancelAction)
            Button("Save", action: save)
                .keyboardShortcut(isSearching ? nil : .defaultAction)
                .disabled(!canSave)
        }
    }
}

/// The bar at the foot of the detail, always in sight, with what Lucas can
/// do there.
struct ActionBar<Buttons: View>: View {
    @ViewBuilder let buttons: Buttons

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                buttons
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }
}
