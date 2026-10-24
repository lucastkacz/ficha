import AVFoundation
import os

// Nonisolated, for the player's delegate, which may be called on any thread.
private nonisolated let logger = Logger(subsystem: "com.lucastkacz.ficha", category: "sounds")

/// Plays a card's sound, one at a time, as a window's state says: it only
/// plays and stops what it's handed, and tells when a sound ended on its own,
/// or couldn't play. The Cards window has one.
@MainActor
final class SoundPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    /// What to do once the sound that plays ends on its own.
    private var ended: (() -> Void)?

    /// Plays the sound in `data`, as Ficha keeps it, from the start, stopping
    /// the one that plays, and does `ended` once it ends on its own, or at
    /// once when it can't play, which the app logs.
    func play(_ data: Data, ended: @escaping () -> Void) {
        stop()
        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(data: data)
        } catch {
            logger.error("Couldn't open a sound to play it: \(String(describing: error), privacy: .public)")
            ended()
            return
        }
        player.delegate = self
        guard player.play() else {
            logger.error("A sound didn't start playing")
            ended()
            return
        }
        self.player = player
        self.ended = ended
    }

    /// Stops the sound that plays, if any, which then never says it ended.
    func stop() {
        player?.stop()
        player = nil
        ended = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finished = ObjectIdentifier(player)
        Task { @MainActor in
            self.finish(finished)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        logger.error("A sound stopped on an error: \(String(describing: error), privacy: .public)")
        let finished = ObjectIdentifier(player)
        Task { @MainActor in
            self.finish(finished)
        }
    }

    /// Says the sound that plays ended, when it's the one `finished`
    /// identifies, rather than one stopped since.
    private func finish(_ finished: ObjectIdentifier) {
        guard let player, ObjectIdentifier(player) == finished else { return }
        let ended = ended
        stop()
        ended?()
    }
}
