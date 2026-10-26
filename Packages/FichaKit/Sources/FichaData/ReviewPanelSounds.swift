import FichaCore
import Foundation

extension ReviewPanelState {
    /// The sound that plays in the review panel: the one on a side of the
    /// card Lucas is on, whose ▶ shows ■.
    public struct PlayingSound: Sendable, Equatable {
        /// The id of the card it's on.
        let cardID: Int64
        /// The side it's on.
        public let side: CardSide
        public let name: SoundName
    }

    /// Whether a sound plays when Lucas asks: while he's on a card as it
    /// shows, and the panel is open. Not while he writes a note or a question
    /// about it: Esc would throw away what he writes, and R goes into it, so
    /// nothing would stop the sound from the keyboard.
    public var canPlaySounds: Bool {
        outcome == nil && isOnACard
    }

    /// Plays the sound on `side` of the card Lucas is on, stopping the one
    /// that plays, or stops it when it's the one that plays, as its ■ does.
    public mutating func playOrStopSound(on side: CardSide) {
        guard canPlaySounds else { return }
        if playingSound?.side == side {
            playingSound = nil
        } else if let current, let name = readSound(on: side) {
            playingSound = PlayingSound(cardID: current.card.id, side: side, name: name)
        }
        touch()
    }

    /// Plays or stops the sound `sideForR` says: R.
    public mutating func playOrStopSound() {
        guard let side = sideForR else { return }
        playOrStopSound(on: side)
    }

    /// The side whose sound R plays or stops, while a sound plays when Lucas
    /// asks, or nil when the card has none: the side whose sound plays,
    /// which R stops, or else the lower side's once it shows, on a flipped
    /// card or in a first view that shows it whole, or the upper side's when
    /// the lower one has none or doesn't show. Front first, the lower side is
    /// the back, and back first, the front. A sound that couldn't be read
    /// counts as none.
    public var sideForR: CardSide? {
        guard canPlaySounds, let way = current?.way else { return nil }
        if let playingSound {
            return playingSound.side
        }
        let showsLowerSide =
            switch content {
            case .firstView, .bothSides: true
            case .nothingToReview, .upperSide, .flagging, .asking, .done: false
            }
        if showsLowerSide, readSound(on: way.lowerSide) != nil {
            return way.lowerSide
        }
        return readSound(on: way.upperSide) != nil ? way.upperSide : nil
    }

    /// Whether the sound on `side` of the card Lucas is on plays, so its ▶
    /// shows ■.
    public func isPlaying(on side: CardSide) -> Bool {
        playingSound?.side == side
    }

    /// Says `sound` ended on its own, or couldn't play, as the app's player
    /// tells: it no longer plays, unless another started since.
    public mutating func soundEnded(_ sound: PlayingSound) {
        if playingSound == sound {
            playingSound = nil
        }
    }

    /// The sound on `side` of the card Lucas is on, once it was read, or nil.
    private func readSound(on side: CardSide) -> SoundName? {
        guard let name = current?.card.sound(on: side), case .success = sounds[name] else { return nil }
        return name
    }

    /// Reads the sounds on the sides of the card Lucas is on, with their
    /// lengths, and lets go of the others. A sound that plays on another
    /// card stops: that card left.
    mutating func showSounds() {
        sounds.show(current?.card.sounds ?? [], readingWith: engine)
        if let playingSound, playingSound.cardID != current?.card.id {
            self.playingSound = nil
        }
    }
}
