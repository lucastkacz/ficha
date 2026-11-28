import FichaCore
import FichaData
import SwiftUI

/// The fields the user edits a card in, in place of its detail: its deck, which
/// Save moves it to, front and back, each with its text, its image and its
/// sound, dragged or pasted under it, an image also with ⌘V in its text while
/// the clipboard holds no text, source and Both ways, under the flag's note
/// when it's flagged. No type and no tags: Save keeps the card's own, which the
/// database holds (#538). Return saves, Option-Return starts a new line, and
/// Escape cancels, unless the search field has the focus. Save is off while a
/// sound converts. Saving with a side that has neither text, an image nor a
/// sound says, under it, what's missing. When the card can't be saved, the
/// window's alert says why, and the fields stay as the user left them.
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
    /// Its deck as Save would move it to, which the window holds.
    let deck: String
    /// The decks its Deck field offers, as the window offers them.
    let decks: [Deck]
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
    /// Picks its deck, as Save will move it to.
    let setDeck: (String) -> Void
    /// New Deck… in its Deck field.
    let newDeck: () -> Void
    /// Saves the card with `content`, which ends the edit once it's saved.
    let save: (CardContent) -> Void
    /// Ends the edit without saving it.
    let cancel: () -> Void
    @State private var front: String
    @State private var back: String
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
        deck: String,
        decks: [Deck],
        canSave: Bool,
        isSearching: Bool,
        putImage: @escaping (DroppedImage, CardSide) -> Void,
        removeImage: @escaping (CardSide) -> Void,
        soundWell: @escaping (CardSide) -> SoundWell,
        setBothWays: @escaping (Bool) -> Void,
        setDeck: @escaping (String) -> Void,
        newDeck: @escaping () -> Void,
        save: @escaping (CardContent) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.card = card
        self.images = images
        self.shownImages = shownImages
        self.sounds = sounds
        self.bothWays = bothWays
        self.deck = deck
        self.decks = decks
        self.canSave = canSave
        self.isSearching = isSearching
        self.putImage = putImage
        self.removeImage = removeImage
        self.soundWell = soundWell
        self.setBothWays = setBothWays
        self.setDeck = setDeck
        self.newDeck = newDeck
        self.save = save
        self.cancel = cancel
        _front = State(initialValue: card.front)
        _back = State(initialValue: card.back)
        _source = State(initialValue: card.source ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FlagAndSetAside(standing: card.standing, isEditing: true)
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
                    "Deck", comment: "In the Cards window, the label of a card's deck, while Lucas edits it.")
                gridLabel(label)
                DeckPicker(deck: deck, decks: decks, label: label, choose: setDeck, newDeck: newDeck)
            }
            GridRow {
                gridLabel(
                    Text("Front", comment: "In the Cards window, the label of a card's front, while Lucas edits it."))
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Front", text: $front, axis: .vertical)
                        .lineLimit(1...4)
                        .alignedAsItReads(front)
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
                        .alignedAsItReads(back)
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
                    Text("Source", comment: "In the Cards window, the label of a card's source, while Lucas edits it."))
                TextField(
                    "Source", text: $source,
                    prompt: Text(
                        "A book, a podcast…",
                        comment: "In the Cards window, in a card's empty source, while Lucas edits it."),
                    axis: .vertical
                )
                .lineLimit(1...3)
                .alignedAsItReads(source)
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
    /// nor a sound. The content has no type and no tags, and the card keeps
    /// its own (`CardsWindowState.saveCard(_:)`).
    private func submit() {
        guard canSave else { return }
        guard
            let content = CardContent(
                type: nil, front: front, back: back, tags: [], source: source, frontImage: images.front,
                backImage: images.back, frontSound: sounds.front, backSound: sounds.back)
        else {
            showsMissingSides = true
            return
        }
        save(content)
    }
}

/// What's missing, under a field Lucas left blank in the editor.
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
