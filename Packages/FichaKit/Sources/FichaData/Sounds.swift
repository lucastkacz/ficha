import AVFoundation
import CryptoKit
import FichaCore
import Foundation
internal import GRDB
import Synchronization

/// The bit rate a sound keeps once it comes in, for each of its channels: AAC
/// at 64 kbps a channel, 128 kbps in stereo, good enough for music and light,
/// about 1 MB a minute, for the cards, the backups and later iCloud.
let soundBitRatePerChannel = 64_000

/// The sample rate a sound keeps once it comes in, CD's.
let soundSampleRate = 44_100

extension Engine {
    /// Brings in a sound for a side of a card: converts the sound in `data`,
    /// a file's, or a video's, as every sound that comes in, keeps it where
    /// Ficha keeps sounds, and returns the name a card's side refers to it
    /// by. The file's name, `fileName`, says its format by its extension, as
    /// in `coloratura.mp3`. The same sound coming in twice is kept once. Data
    /// with no sound Ficha can read is refused.
    public func addSound(_ data: Data, named fileName: String) async throws(EngineError) -> SoundName {
        let sound = try await CardSound(converting: data, named: fileName)
        try keepSound(sound)
        return sound.name
    }

    /// Keeps `sound` where Ficha keeps sounds, unless it's there already.
    func keepSound(_ sound: CardSound) throws(EngineError) {
        try sounds.keep(sound.data, as: sound.name)
    }

    /// The sound named `name`, as Ficha keeps it: AAC in an `m4a` file.
    public func sound(_ name: SoundName) throws(EngineError) -> Data {
        try sounds.data(of: name)
    }

    /// Every sound Ficha keeps, by name, whether a card uses it or not.
    func keptSounds() throws(EngineError) -> Set<SoundName> {
        try sounds.names()
    }
}

/// Every sound the cards in `db` refer to, on either side, as
/// `namesReferred(_:in:)` reads them.
func soundsReferred(in db: Database) throws -> Set<SoundName> {
    try namesReferred(SoundName.self, in: db)
}

/// A sound on its way to a side of a card, converted as every sound that
/// comes in, with the name it's kept by.
struct CardSound: Sendable, Equatable {
    let name: SoundName
    /// The sound as Ficha keeps it: AAC in an `m4a` file.
    let data: Data

    /// The sound `data`, which came in converted and named `name` already.
    init(name: SoundName, data: Data) {
        self.name = name
        self.data = data
    }

    /// The sound in `data`, the file named `fileName`, as `init(converting:)`
    /// converts a file's: AVFoundation tells a file's format by its
    /// extension.
    init(converting data: Data, named fileName: String) async throws(EngineError) {
        let file = URL.temporaryDirectory.appending(path: "Ficha-sound-\(UUID().uuidString)")
            .appendingPathExtension(URL(filePath: fileName).pathExtension)
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            try data.write(to: file)
        } catch {
            logger.error("Couldn't write a sound that came in to convert it: \(String(describing: error))")
            throw .soundConversion
        }
        try await self.init(converting: file)
    }

    /// The sound in `file`, in any format AVFoundation reads, such as an MP3,
    /// an M4A, a WAV or an AIFF, or a video's first sound track, written as
    /// AAC in an `m4a` file at `soundBitRatePerChannel`, mono or stereo as it
    /// came, with more channels mixed down to stereo, at `soundSampleRate`.
    /// It's named by the SHA-256 of what's written, once the times the file
    /// says it was made are cleared. What holds no sound AVFoundation can
    /// read is refused. A long sound takes a while, so it runs away from the
    /// actor it's called from.
    @concurrent
    init(converting file: URL) async throws(EngineError) {
        let written = URL.temporaryDirectory.appending(path: "Ficha-sound-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: written) }
        do {
            try await withTaskExecutorPreference(SoundConversion()) {
                try await convertSound(in: file, to: written)
            }
        } catch let error as EngineError {
            throw error
        } catch {
            logger.error("AVFoundation couldn't convert a sound: \(String(describing: error), privacy: .public)")
            throw .notASound
        }
        let data: Data
        do {
            data = try clearingTimesMade(in: Data(contentsOf: written))
        } catch let error as EngineError {
            throw error
        } catch {
            logger.error("Couldn't read a converted sound: \(String(describing: error), privacy: .public)")
            throw .soundConversion
        }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard let name = SoundName(rawValue: "\(hash).m4a") else {
            logger.error("A sound's SHA-256 didn't make a sound's name")
            throw .soundConversion
        }
        self.name = name
        self.data = data
    }
}

/// How long the sound in `data` lasts, as Ficha keeps it: AAC in an `m4a`
/// file. A sound that can't be read throws, as one that can't be read where
/// Ficha keeps sounds.
func soundLength(of data: Data) throws(EngineError) -> Duration {
    do {
        return .seconds(try AVAudioPlayer(data: data).duration)
    } catch {
        logger.error("Couldn't read a kept sound's length: \(String(describing: error), privacy: .public)")
        throw .soundsFolder
    }
}

/// Where a sound converts: a serial dispatch queue of its own, as a task
/// executor (SE-0417), away from the threads Swift's tasks share. The asset
/// reader holds the thread that asks it for the next samples until it has
/// them: run on the shared threads, as many sounds converting at once as the
/// Mac has cores held every one of them, and none ever got its samples; on
/// one concurrent queue, 64 at once held every thread Dispatch would bring
/// up for it, and none got them either; and on one serial queue, each held
/// the queue until it ended, so they converted one at a time. Each on a
/// queue of its own, sounds convert side by side, more than 64 at once too.
final class SoundConversion: TaskExecutor {
    private let queue = DispatchQueue(label: "Ficha.SoundConversion")

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        queue.async { job.runSynchronously(on: self.asUnownedTaskExecutor()) }
    }
}

/// Held while an asset reader starts, so that readers start one at a time.
/// Each sets up an audio queue on AudioToolbox's own serial queue as it
/// starts, so they waited for each other there anyway; but ten starting at
/// once hung there for good once, in a preview of Japanese Core 50K, each
/// waiting for that queue while nothing ran on it.
private let readerStarting = Mutex(())

/// Converts the first sound track in `file` to AAC in the `m4a` file
/// `output`, as `CardSound(converting:)` says, reading and writing it with
/// AVFoundation's asset reader and writer, on a `SoundConversion` queue. A
/// file with no sound track, or with one that ends before it starts, is
/// refused.
private func convertSound(in file: URL, to output: URL) async throws {
    let asset = AVURLAsset(url: file)
    guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
        throw EngineError.notASound
    }
    let sourceChannels = try await track.load(.formatDescriptions).compactMap { description in
        CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee.mChannelsPerFrame
    }.first
    // A track that doesn't say how many channels it has isn't one to guess.
    guard let sourceChannels, sourceChannels > 0 else {
        throw EngineError.notASound
    }
    let channels = min(Int(sourceChannels), 2)
    let reader = try AVAssetReader(asset: asset)
    let decoded = AVAssetReaderTrackOutput(
        track: track,
        outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: soundSampleRate, AVNumberOfChannelsKey: channels,
        ])
    guard reader.canAdd(decoded) else {
        throw EngineError.notASound
    }
    let writer = try AVAssetWriter(outputURL: output, fileType: .m4a)
    let encoded = AVAssetWriterInput(
        mediaType: .audio,
        outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: soundSampleRate, AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: soundBitRatePerChannel * channels,
        ])
    encoded.expectsMediaDataInRealTime = false
    guard writer.canAdd(encoded) else {
        throw EngineError.notASound
    }
    // Each adds the output or the input it's for.
    let samples = reader.outputProvider(for: decoded)
    let receiver = writer.inputReceiver(for: encoded)
    try readerStarting.withLock { _ in try reader.start() }
    try writer.start()
    guard let first = try await samples.next() else {
        writer.cancelWriting()
        throw EngineError.notASound
    }
    writer.startSession(atSourceTime: first.presentationTimeStamp)
    try await receiver.append(first)
    while let buffer = try await samples.next() {
        try await receiver.append(buffer)
    }
    receiver.finish()
    await writer.finishWriting()
    guard writer.status == .completed else {
        throw writer.error ?? EngineError.notASound
    }
}

/// `file`, an `m4a` file as AVFoundation writes it, with the times its movie,
/// its tracks and their media say they were made and changed set to zero, in
/// the `mvhd`, `tkhd` and `mdhd` boxes of the ISO base media file format
/// (ISO/IEC 14496-12, 8.2.2, 8.3.2 and 8.4.2): AVFoundation writes there
/// when it wrote the file, so the same sound converted twice would differ,
/// and be kept twice. A file laid out otherwise fails, which the engine logs.
private func clearingTimesMade(in file: Data) throws(EngineError) -> Data {
    var bytes = [UInt8](file)
    var cleared = 0
    guard clearTimesMade(in: &bytes, from: 0, to: bytes.count, counting: &cleared), cleared > 0 else {
        logger.error("A converted sound isn't laid out as an m4a file with a movie header")
        throw .soundConversion
    }
    return Data(bytes)
}

/// Clears the times made and changed of the movie, track and media headers
/// among the boxes from `start` to `end` of `bytes`, and in the boxes they
/// hold, adding each header cleared to `cleared`: whether the boxes fit
/// there.
private func clearTimesMade(in bytes: inout [UInt8], from start: Int, to end: Int, counting cleared: inout Int)
    -> Bool
{
    var offset = start
    while offset < end {
        guard offset + 8 <= end else { return false }
        var size = bigEndian(bytes[offset..<offset + 4])
        var header = 8
        if size == 1 {
            guard offset + 16 <= end else { return false }
            size = bigEndian(bytes[offset + 8..<offset + 16])
            header = 16
        } else if size == 0 {
            size = end - offset
        }
        guard size >= header, size <= end - offset else { return false }
        let body = offset + header
        let boxEnd = offset + size
        switch String(decoding: bytes[offset + 4..<offset + 8], as: UTF8.self) {
        case "moov", "trak", "mdia":
            guard clearTimesMade(in: &bytes, from: body, to: boxEnd, counting: &cleared) else { return false }
        case "mvhd", "tkhd", "mdhd":
            // A version, three bytes of flags, and then the two times, of 4
            // bytes each in version 0, or of 8 in version 1.
            guard body < boxEnd else { return false }
            let width = bytes[body] == 1 ? 8 : 4
            guard body + 4 + 2 * width <= boxEnd else { return false }
            for index in body + 4..<body + 4 + 2 * width {
                bytes[index] = 0
            }
            cleared += 1
        default:
            break
        }
        offset = boxEnd
    }
    return true
}

/// The unsigned number `bytes` hold, most significant byte first.
private func bigEndian(_ bytes: ArraySlice<UInt8>) -> Int {
    bytes.reduce(0) { $0 << 8 | Int($1) }
}
