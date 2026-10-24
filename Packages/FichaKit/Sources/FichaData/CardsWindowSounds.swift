import FichaCore
import Foundation

/// The sound on each side of a card, or none.
public struct SideSounds: Sendable, Equatable {
    public internal(set) var front: SoundName?
    public internal(set) var back: SoundName?

    init(front: SoundName? = nil, back: SoundName? = nil) {
        self.front = front
        self.back = back
    }

    /// The sound on `side`, or nil for none.
    public subscript(side: CardSide) -> SoundName? {
        get {
            switch side {
            case .front: front
            case .back: back
            }
        }
        set {
            switch side {
            case .front: front = newValue
            case .back: back = newValue
            }
        }
    }

    /// Every sound on the sides, each once.
    var all: Set<SoundName> {
        Set([front, back].compactMap(\.self))
    }
}

/// A sound the window shows: as Ficha keeps it, AAC in an `m4a` file, and how
/// long it lasts.
public struct ShownSound: Sendable, Equatable {
    public let data: Data
    public let length: Duration
}

/// The sounds a window shows, by name, each read from where Ficha keeps them,
/// with its length, or why it couldn't be, or held as it came in, dropped or
/// pasted, until a card that has it is saved.
public struct ShownSounds: Sendable, Equatable {
    private var sounds: [SoundName: Result<ShownSound, EngineError>] = [:]
    /// The sounds that came in and aren't kept yet.
    private var held: [SoundName: ShownSound] = [:]

    /// The sound named `name`, with its length, or why it couldn't be read,
    /// or nil when the window doesn't show it.
    public subscript(name: SoundName) -> Result<ShownSound, EngineError>? {
        held[name].map(Result.success) ?? sounds[name]
    }

    /// Holds `sound`, which came in, until a card that has it is saved.
    mutating func hold(_ sound: ShownSound, as name: SoundName) {
        held[name] = sound
    }

    /// The sounds among `names` it holds, which aren't kept yet, ready to
    /// keep.
    func held(among names: Set<SoundName>) -> [CardSound] {
        names.sorted { $0.rawValue < $1.rawValue }.compactMap { name in
            held[name].map { CardSound(name: name, data: $0.data) }
        }
    }

    /// Shows the sounds named `names`: reads with `engine` those it hasn't
    /// read yet, or couldn't, with their length, and lets go of the others,
    /// held ones too.
    mutating func show(_ names: Set<SoundName>, readingWith engine: Engine) {
        held = held.filter { names.contains($0.key) }
        sounds = sounds.filter { names.contains($0.key) }
        for name in names where held[name] == nil {
            if case .success = sounds[name] { continue }
            sounds[name] = Result { () throws(EngineError) in
                let data = try engine.sound(name)
                return ShownSound(data: data, length: try soundLength(of: data))
            }
        }
    }
}

/// Where a sound shows in the Cards window, for its ▶ to play it.
public enum SoundPlace: Sendable, Hashable {
    /// A side of the card the form makes.
    case form(CardSide)
    /// A side of the card the user edits.
    case editor(CardSide)
    /// A side of the card with this id, which the detail shows.
    case detail(cardID: Int64, CardSide)
}

/// The sound that plays in a window, and where its ▶ is, which shows ■.
public struct PlayingSound: Sendable, Equatable {
    public let place: SoundPlace
    public let name: SoundName

    public init(place: SoundPlace, name: SoundName) {
        self.place = place
        self.name = name
    }
}

/// A sound file dropped or pasted on a side of a card in the Cards window,
/// converted as every sound that comes in, with its length: converting a
/// long one takes a while, so the app runs it away from the main actor, and
/// hands what it did to the window's `finishSoundWork(_:)`.
public struct SoundWork: Sendable {
    /// What the work did: the sound, with its length, or why it couldn't
    /// come in.
    public struct Done: Sendable {
        fileprivate let id: UUID
        fileprivate let result: Result<(sound: CardSound, length: Duration), EngineError>
    }

    fileprivate let id: UUID
    fileprivate let file: URL

    /// Converts the sound, away from the actor it's called from, and says
    /// what it did.
    @concurrent
    public func run() async -> Done {
        do throws(EngineError) {
            let sound = try await CardSound(converting: file)
            return Done(id: id, result: .success((sound, try soundLength(of: sound.data))))
        } catch {
            return Done(id: id, result: .failure(error))
        }
    }
}

extension CardsWindowState.CardForm {
    /// Whether a sound dropped or pasted on `side` is still converting,
    /// which then shows on the side, and keeps Add off.
    public func isSoundComingIn(on side: CardSide) -> Bool {
        soundsComingIn[side] != nil
    }
}

extension CardsWindowState {
    /// Puts the sound in `file`, dropped or pasted on `side` of the card the
    /// form makes, in place of the one it had, once the work it returns is
    /// done: the app runs it, and the side shows the sound coming in until
    /// then. The window holds the sound until Add saves the card. A file
    /// that can't be read stays out, as one with no sound once the work is
    /// done, and the window records why.
    public mutating func putSoundInForm(_ file: URL, on side: CardSide) -> SoundWork? {
        guard cardForm != nil, let work = soundWork(for: file) else { return nil }
        cardForm?.soundsComingIn[side] = work.id
        return work
    }

    /// Removes the sound on `side` of the card the form makes.
    public mutating func removeSoundFromForm(on side: CardSide) {
        guard var draft = cardForm?.draft else { return }
        draft[side].sound = nil
        changeDraft(draft)
        showFiles()
    }

    /// Puts the sound in `file`, dropped or pasted on `side` of the card the
    /// user edits, in place of the one it had, as `putSoundInForm(_:on:)`
    /// does, until Save saves the card.
    public mutating func putSoundInEditor(_ file: URL, on side: CardSide) -> SoundWork? {
        guard case .card = editing, let work = soundWork(for: file) else { return nil }
        editedSoundsComingIn[side] = work.id
        return work
    }

    /// Removes the sound on `side` of the card the user edits, which Save
    /// then takes away from the card.
    public mutating func removeSoundFromEditor(on side: CardSide) {
        guard case .card = editing else { return }
        editedSounds[side] = nil
        showFiles()
    }

    /// Whether a sound dropped or pasted on `side` of the card the user edits
    /// is still converting, which then shows on the side, and keeps Save off.
    public func isSoundComingInEditor(on side: CardSide) -> Bool {
        editedSoundsComingIn[side] != nil
    }

    /// Whether Save saves the card the user edits: while they edit one and
    /// no sound is converting for it.
    public var canSaveCard: Bool {
        guard case .card = editing else { return false }
        return editedSoundsComingIn.isEmpty
    }

    /// Takes what a sound's work did, once the app ran it: puts the sound on
    /// the side it was dropped on, while that side still waits for it, or
    /// records why it couldn't come in. A sound that comes in once another
    /// replaced it, or once its form or its edit closed, is let go.
    public mutating func finishSoundWork(_ done: SoundWork.Done) {
        if let side = cardForm?.soundsComingIn.first(where: { $0.value == done.id })?.key {
            cardForm?.soundsComingIn[side] = nil
            guard let name = holdSound(done), var draft = cardForm?.draft else { return }
            draft[side].sound = name
            changeDraft(draft)
        } else if let side = setAsideCardForm?.soundsComingIn.first(where: { $0.value == done.id })?.key {
            setAsideCardForm?.soundsComingIn[side] = nil
            guard let name = holdSound(done) else { return }
            setAsideCardForm?.draft[side].sound = name
        } else if let side = editedSoundsComingIn.first(where: { $0.value == done.id })?.key {
            editedSoundsComingIn[side] = nil
            guard let name = holdSound(done) else { return }
            editedSounds[side] = name
        } else {
            return
        }
        showFiles()
    }

    /// Plays the sound at `place`, stopping the one that plays, or stops it
    /// when it's the one at `place`, as its ■ does.
    public mutating func playOrStopSound(at place: SoundPlace) {
        if playingSound?.place == place {
            playingSound = nil
        } else if let name = sound(at: place), case .success = sounds[name] {
            playingSound = PlayingSound(place: place, name: name)
        }
    }

    /// Whether the sound at `place` plays, so its ▶ shows ■.
    public func isPlaying(at place: SoundPlace) -> Bool {
        playingSound?.place == place
    }

    /// Says `sound` ended on its own, or couldn't play, as the app's player
    /// tells: it no longer plays, unless another started since.
    public mutating func soundEnded(_ sound: PlayingSound) {
        if playingSound == sound {
            playingSound = nil
        }
    }

    /// The sound at `place`, while the window shows it there, or nil.
    func sound(at place: SoundPlace) -> SoundName? {
        switch place {
        case .form(let side):
            return cardForm?.draft[side].sound
        case .editor(let side):
            guard case .card = editing else { return nil }
            return editedSounds[side]
        case .detail(let cardID, let side):
            // The editor takes the detail's place.
            guard editing == nil, case .card(let row, _) = detail, row.id == cardID else { return nil }
            return row.card.sound(on: side)
        }
    }

    /// The work that converts the sound in `file`, or nil when the file
    /// can't be read, which the window records.
    private mutating func soundWork(for file: URL) -> SoundWork? {
        guard FileManager.default.isReadableFile(atPath: file.path(percentEncoded: false)) else {
            logger.error("Couldn't read a file dropped for a sound")
            record(.unreadableDroppedFile(file.lastPathComponent), for: .putSound)
            return nil
        }
        return SoundWork(id: UUID(), file: file)
    }

    /// The sound `done` brought, held until a card that has it is saved, or
    /// nil when it couldn't come in, which the window records.
    private mutating func holdSound(_ done: SoundWork.Done) -> SoundName? {
        switch done.result {
        case .success(let (sound, length)):
            sounds.hold(ShownSound(data: sound.data, length: length), as: sound.name)
            return sound.name
        case .failure(let error):
            record(error, for: .putSound)
            return nil
        }
    }

    /// Shows the sounds of the card the detail shows, of the card the user
    /// edits and of the card the form makes, and lets go of the others. A
    /// sound that plays where the window no longer shows it stops.
    mutating func showSounds() {
        var names = Set<SoundName>()
        if case .card(let row, _) = detail {
            names.formUnion(row.card.sounds)
        }
        if case .card = editing {
            names.formUnion(editedSounds.all)
        }
        for form in [cardForm, setAsideCardForm].compactMap(\.self) {
            names.formUnion([form.draft.front.sound, form.draft.back.sound].compactMap(\.self))
        }
        sounds.show(names, readingWith: engine)
        if let playingSound, sound(at: playingSound.place) != playingSound.name {
            self.playingSound = nil
        }
    }
}
