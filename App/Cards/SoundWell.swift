import FichaCore
import FichaData
import SwiftUI
import UniformTypeIdentifiers

/// Where a side of the card the user makes or edits takes its sound, under
/// the place for its image: a sound file, or a video, dragged from Finder onto
/// it, or pasted with ⌘V once it has the focus, which a click or Tab gives it.
/// While the file converts, it says so. With a sound, it shows its ▶ and its
/// length, with a button that removes it, and a new file replaces it. While
/// it has the focus, Space plays or stops the sound, and Delete removes it. The window decides whether the file
/// holds a sound, and says so when it doesn't.
struct SoundWell: View {
    /// The side's sound, or nil for none.
    let sound: SoundName?
    /// The sounds the window shows, the side's among them.
    let sounds: ShownSounds
    /// Whether a file dropped or pasted on the side is converting.
    let isComingIn: Bool
    /// Whether the side's sound plays.
    let isPlaying: Bool
    /// Plays the side's sound, or stops it while it plays.
    let playOrStop: () -> Void
    /// Puts the sound in a file dragged or pasted on the side.
    let put: (URL) -> Void
    /// Removes the side's sound.
    let remove: () -> Void
    /// Whether something is dragged over it.
    @State private var isTargeted = false
    /// Whether it has the focus, which it draws itself, as the image's place
    /// does.
    @FocusState private var isFocused: Bool

    var body: some View {
        // A stack, not a group, so the focus stays on one view when a sound
        // comes in or goes, as in the image's place.
        ZStack {
            if isComingIn {
                Label {
                    Text("Converting the sound…", comment: "In the place for the sound on a side of a card.")
                } icon: {
                    ProgressView()
                        .controlSize(.small)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(dashedBorder)
            } else if let sound {
                HStack(spacing: 8) {
                    SoundControls(sound: sounds[sound], isPlaying: isPlaying, playOrStop: playOrStop)
                    Spacer(minLength: 0)
                    Button(action: remove) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        Text("Remove Sound", comment: "The button that removes the sound on a side of a card.")
                    )
                    .help(
                        Text(
                            "Remove Sound (⌫)",
                            comment: "The tooltip of the button that removes the sound on a side of a card."))
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(.fill.quinary, in: .rect(cornerRadius: 6))
                .overlay {
                    if isTargeted || isFocused {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.tint, lineWidth: 3)
                    }
                }
            } else {
                Label {
                    Text("Drop or paste a sound", comment: "In the empty place for the sound on a side of a card.")
                } icon: {
                    Image(systemName: "waveform.badge.plus")
                }
                .font(.callout)
                .foregroundStyle(isTargeted || isFocused ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(dashedBorder)
                .contentShape(.rect)
            }
        }
        .focusable(interactions: .edit)
        .focused($isFocused)
        .focusEffectDisabled()
        .onPasteCommand(of: [.fileURL]) { providers in
            take(providers)
        }
        .onDeleteCommand {
            if sound != nil {
                remove()
            }
        }
        .onKeyPress(.space) {
            guard sound != nil, !isComingIn else { return .ignored }
            playOrStop()
            return .handled
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            take(providers)
            return true
        }
    }

    /// The dashed border of the empty place, and of one waiting for its sound,
    /// in the tint while something is dragged over it or it has the focus.
    private var dashedBorder: some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(style: StrokeStyle(lineWidth: isFocused ? 2 : 1, dash: [4, 3]))
            .foregroundStyle(isTargeted || isFocused ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
    }

    /// Puts the sound in the first local file among `providers` on the side,
    /// once it's loaded. A web address is never fetched: Ficha makes no
    /// network calls.
    private func take(_ providers: [NSItemProvider]) {
        Task {
            for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                if let file = await localFile(in: provider) {
                    put(file)
                    return
                }
            }
        }
    }
}

/// A sound's ▶, which plays it and becomes ■ while it plays, and its length,
/// such as "3:42", or why it couldn't be read, in the card form, the card
/// editor, a card's detail and the review panel.
struct SoundControls: View {
    /// The sound, with its length, or why it couldn't be read, or nil while
    /// the window doesn't show it.
    let sound: Result<ShownSound, EngineError>?
    /// Whether it plays.
    let isPlaying: Bool
    /// Whether R plays it or stops it, in the review panel, which its
    /// tooltip says.
    var takesR = false
    /// Plays it, or stops it while it plays.
    let playOrStop: () -> Void

    var body: some View {
        switch sound {
        case .success(let shown):
            HStack(spacing: 8) {
                Button(action: playOrStop) {
                    // As wide either way, so the length stays where it was.
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .frame(width: 14)
                }
                .accessibilityLabel(
                    isPlaying
                        ? Text("Stop Sound", comment: "The button that stops the sound of a card's side as it plays.")
                        : Text("Play Sound", comment: "The button that plays the sound on a side of a card.")
                )
                .help(help)
                Text(soundLengthText(shown.length))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        case .failure(let error):
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
    }

    /// The button's tooltip, with R when R does the same.
    private var help: Text {
        switch (isPlaying, takesR) {
        case (true, false):
            Text("Stop Sound", comment: "The tooltip of the button that stops the sound of a card's side as it plays.")
        case (true, true):
            Text(
                "Stop Sound (r)",
                comment:
                    "The tooltip of the review panel's button that stops the sound of a card's side as it plays, with its key."
            )
        case (false, false):
            Text("Play Sound", comment: "The tooltip of the button that plays the sound on a card's side.")
        case (false, true):
            Text(
                "Play Sound (r)",
                comment: "The tooltip of the review panel's button that plays the sound on a card's side, with its key."
            )
        }
    }
}

/// Converts the sound `work` brings in, which `state` started for a file
/// dropped or pasted on a side, away from the main actor, and hands what it
/// did back to `state`.
func convert(_ work: SoundWork?, for state: Binding<CardsWindowState>) {
    guard let work else { return }
    Task {
        state.wrappedValue.finishSoundWork(await work.run())
    }
}

/// How long a sound lasts as the window says it: minutes and seconds, as in
/// "3:42", and hours too from an hour on, as in "1:03:42".
func soundLengthText(_ length: Duration) -> String {
    length.formatted(.time(pattern: length < .seconds(3_600) ? .minuteSecond : .hourMinuteSecond))
}
