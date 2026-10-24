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

    /// Plays the sound on `side` of the card Lucas is on, stopping the one
    /// that plays, or stops it when it's the one that plays, as its ■ does.
    /// Nothing plays once the panel closed.
    public mutating func playOrStopSound(on side: CardSide) {
        guard outcome == nil else { return }
        if playingSound?.side == side {
            playingSound = nil
        } else if let current, let name = current.card.sound(on: side), case .success = sounds[name] {
            playingSound = PlayingSound(cardID: current.card.id, side: side, name: name)
        }
        touch()
    }

    /// Plays or stops the sound `sideForR` says: R.
    public mutating func playOrStopSound() {
        guard let side = sideForR else { return }
        playOrStopSound(on: side)
    }

    /// The side whose sound R plays or stops, while Lucas is on a card as it
    /// shows, or nil when it has none: the side whose sound plays, which R
    /// stops, or else the back's once the back shows, on a flipped card or
    /// in a first view, or the front's when the back has none or doesn't
    /// show.
    public var sideForR: CardSide? {
        let card: Card
        let showsBack: Bool
        switch content {
        case .firstView(let shown), .back(let shown, _):
            (card, showsBack) = (shown, true)
        case .front(let shown, _):
            (card, showsBack) = (shown, false)
        case .nothingToReview, .flagging, .asking, .done:
            return nil
        }
        if let playingSound {
            return playingSound.side
        }
        if showsBack, card.backSound != nil {
            return .back
        }
        return card.frontSound != nil ? .front : nil
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

    /// Reads the sounds on the sides of the card Lucas is on, with their
    /// lengths, and lets go of the others.
    mutating func showSounds() {
        sounds.show(current?.card.sounds ?? [], readingWith: engine)
    }
}
