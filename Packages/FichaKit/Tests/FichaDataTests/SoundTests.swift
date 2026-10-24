import AVFoundation
import CryptoKit
import FichaCore
import Foundation
import GRDB
import Testing

// For the sounds the engine keeps, as ImageTests reads its images.
@testable import FichaData

/// Tests on sounds on cards: each side holds text, an image, a sound, or any
/// of them together, and Ficha keeps each sound once, converted as it comes
/// in, until no card uses it.
final class SoundTests {
    let time = ManualTimeSource(now: Date(timeIntervalSince1970: 1_760_000_000))
    /// A data folder of the test's own, for the tests on the Sounds folder,
    /// which the engine creates when it first keeps a sound.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaSoundTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    // AVFoundation writes when it made the file into it, to the second, so
    // the second time comes over a second later.
    @Test("the same sound added twice is kept once, as AAC in an m4a file beside the database, and reads back as kept")
    func theSameSoundAddedTwiceIsKeptOnce() async throws {
        let engine = try Engine(location: .folder(folder), time: time)
        let la = try tone(seconds: 2, hertz: 440, channels: 2)

        let first = try await engine.addSound(la, named: "la.wav")
        let kept = try engine.sound(first)
        try await Task.sleep(for: .seconds(1.1))
        let second = try await engine.addSound(la, named: "la.wav")
        let other = try await engine.addSound(tone(seconds: 2, hertz: 330, channels: 2), named: "mi.wav")

        #expect(first.rawValue.hasSuffix(".m4a"))
        #expect(second == first)
        #expect(other != first)
        #expect(try engine.keptSounds() == [first, other])
        #expect(try Engine(location: .folder(folder), time: time).sound(first) == kept)
        let format = try soundFormat(of: kept)
        #expect(format.id == kAudioFormatMPEG4AAC)
        #expect(format.channels == 2)
    }

    @Test("a sound is named by the SHA-256 of what Ficha keeps, and any other name is refused")
    func aSoundIsNamedByItsContent() async throws {
        let engine = try Engine(location: .inMemory, time: time)

        let la = try await engine.addSound(tone(seconds: 1, hertz: 440, channels: 1), named: "la.wav")

        let hash = SHA256.hash(data: try engine.sound(la)).map { String(format: "%02x", $0) }.joined()
        #expect(la.rawValue == "\(hash).m4a")
        let other = [
            hash.uppercased() + ".m4a", "\(hash).mp3", "\(hash).m4a.m4a", "\(hash.dropLast()).m4a",
            "../\(hash.dropFirst(3)).m4a", hash,
        ]
        #expect(other.compactMap(SoundName.init(rawValue:)).isEmpty)
    }

    @Test("a video comes in as its sound, mono as it was, and a video without sound or what isn't a sound doesn't")
    func aVideoComesInAsItsSound() async throws {
        let engine = try Engine(location: .inMemory, time: time)

        let excerpt = try await engine.addSound(video(seconds: 2, withSoundOf: 440), named: "aria.mov")

        let format = try soundFormat(of: engine.sound(excerpt))
        #expect(format.id == kAudioFormatMPEG4AAC)
        #expect(format.channels == 1)
        await #expect(throws: EngineError.notASound) {
            try await engine.addSound(video(seconds: 2, withSoundOf: nil), named: "mudo.mov")
        }
        await #expect(throws: EngineError.notASound) {
            try await engine.addSound(picture(width: 300, height: 200), named: "hornero.png")
        }
        await #expect(throws: EngineError.notASound) {
            try await engine.addSound(Data("un hornero".utf8), named: "hornero.mp3")
        }
        #expect(try engine.keptSounds() == [excerpt])
    }

    @Test("a card can have a sound on its front, its back, both, or a side with only a sound, beside its image")
    func aCardCanHaveSoundsOnItsSides() async throws {
        let engine = try Engine(location: .inMemory, time: time)
        let la = try await addTone(440, to: engine)
        let mi = try await addTone(330, to: engine)
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))

        let onFront = try engine.create(card(nil, front: "¿Qué nota es?", back: "La.", frontSound: la))
        let onBack = try engine.create(
            card(.word, front: "coloratura", back: "Ornamentos rápidos del canto.", backSound: mi))
        let onBoth = try engine.create(
            card(nil, front: "¿Cuál suena más agudo?", back: "El de la pregunta.", frontSound: la, backSound: mi))
        let onlyASound = try engine.create(card(nil, front: "  ", back: "La.", frontSound: la))
        let withAnImage = try engine.create(
            card(nil, front: "", back: "Un hornero.", frontImage: bird, frontSound: mi))

        let cards = [onFront, onBack, onBoth, onlyASound, withAnImage]
        #expect(cards.map(\.frontSound) == [la, nil, la, la, mi])
        #expect(cards.map(\.backSound) == [nil, mi, mi, nil, nil])
        #expect(onlyASound.front == "")
        #expect(withAnImage.frontImage == bird)
        #expect(try engine.cards() == cards)
        #expect(CardContent(type: nil, front: "La.", back: " ", tags: [], source: nil, frontSound: la) == nil)
        #expect(CardContent.isBlank(" ", image: nil, sound: la) == false)
        #expect(CardContent.isBlank(" ", image: nil, sound: nil))
    }

    @Test("a front with only a sound repeats no other card's front")
    func aFrontWithOnlyASoundRepeatsNone() async throws {
        let engine = try Engine(location: .inMemory, time: time)
        let la = try await addTone(440, to: engine)
        let mi = try await addTone(330, to: engine)
        try engine.create(card(nil, front: "", back: "La.", frontSound: la))

        #expect(try engine.frontsInUse().cardID(repeatedBy: "") == nil)
        #expect(try engine.create(card(nil, front: "", back: "Mi.", frontSound: mi)).frontSound == mi)
        #expect(try engine.create(card(nil, front: "", back: "La, otra vez.", frontSound: la)).frontSound == la)
    }

    @Test("deleting the only card that uses a sound deletes it, and one another card uses stays")
    func deletingACardDeletesTheSoundsNoOtherCardUses() async throws {
        let engine = try Engine(location: .folder(folder), time: time)
        let la = try await addTone(440, to: engine)
        let mi = try await addTone(330, to: engine)
        let both = try engine.create(
            card(nil, front: "¿Qué notas son?", back: "La y mi.", frontSound: la, backSound: mi))
        let one = try engine.create(card(nil, front: "¿Qué nota es?", back: "Mi.", frontSound: mi))

        try engine.delete([both.id])

        #expect(try engine.keptSounds() == [mi])
        #expect(throws: EngineError.soundsFolder) {
            try engine.sound(la)
        }
        try engine.delete([one.id])
        #expect(try engine.keptSounds().isEmpty)
    }

    @Test("replacing or removing a side's sound deletes the old one once no card uses it")
    func replacingASoundDeletesTheOldOne() async throws {
        let engine = try Engine(location: .inMemory, time: time)
        let la = try await addTone(440, to: engine)
        let mi = try await addTone(330, to: engine)
        let sol = try await addTone(392, to: engine)
        let notes = try engine.create(
            card(nil, front: "¿Qué notas son?", back: "La y mi.", frontSound: la, backSound: mi))
        try engine.create(card(nil, front: "¿Qué nota es?", back: "Mi.", frontSound: mi))

        let edited = try engine.edit(notes.id, with: card(nil, front: "¿Qué nota es?", back: "Sol.", frontSound: sol))

        #expect(edited.frontSound == sol)
        #expect(edited.backSound == nil)
        #expect(try engine.keptSounds() == [mi, sol])
    }

    // A refine session drafts text alone, until the CLI takes files (#247).
    @Test("fixing or changing a card's text through the CLI, or updating it from an import, keeps its sounds")
    func refiningAndImportingKeepACardsSounds() async throws {
        let engine = try Engine(location: .inMemory, time: time)
        let la = try await addTone(440, to: engine)
        let mi = try await addTone(330, to: engine)
        let flagged = try engine.create(card(.word, front: "coloratura", back: "Un ornamento.", backSound: la))
        let expanded = try engine.create(
            card(.word, front: "aria", back: "Una canción.", frontSound: mi, backSound: la))
        let imported = try engine.create(card(.word, front: "tenor", back: "Una voz.", frontSound: la, backSound: mi))
        try engine.flag(flagged.id, note: note("Decir que es de la ópera"))
        let expansion = try engine.expand(text: "aria", note: "De una ópera", source: nil)
        #expect(expansion.expandsCardID == expanded.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "ópera.txt")
        try Data("tenor\tLa voz masculina más aguda.\n".utf8).write(to: file)

        let fixed = try engine.fix(
            flagged.id, with: card(.word, front: "coloratura", back: "Los ornamentos rápidos del canto de ópera."))
        let approved = try engine.approveExpansion(
            expansion.id, into: card(.word, front: "aria", back: "Una canción de una ópera."))
        try engine.importCards(engine.previewImport(of: file), choosing: ImportChoices())

        #expect(fixed.backSound == la)
        #expect(approved.frontSound == mi && approved.backSound == la)
        let updated = try #require(try engine.cards().first { $0.id == imported.id })
        #expect(updated.back == "La voz masculina más aguda.")
        #expect(updated.frontSound == la && updated.backSound == mi)
        #expect(try engine.keptSounds() == [la, mi])
    }

    // As `ficha cards` prints a card, so a refine session knows it has one.
    @Test("a card's encoding has frontSound and backSound only when set, by name")
    func aCardsEncodingNamesItsSounds() async throws {
        let engine = try Engine(location: .inMemory, time: time)
        let la = try await addTone(440, to: engine)
        let withSound = try engine.create(card(nil, front: "¿Qué nota es?", back: "La.", backSound: la))
        let withNone = try engine.create(card(nil, front: "hornero", back: "Un pájaro."))

        let encoded = try [withSound, withNone].map { card in
            try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(card)) as? [String: Any])
        }

        #expect(encoded[0]["frontSound"] == nil)
        #expect(encoded[0]["backSound"] as? String == la.rawValue)
        #expect(encoded[1]["frontSound"] == nil)
        #expect(encoded[1]["backSound"] == nil)
    }

    @Test("a database from before sounds on cards migrates with its cards as they were, and refers to no sound")
    func aDatabaseFromBeforeSoundsRefersToNone() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "Ficha.sqlite")
        let bird = try Engine(location: .inMemory, time: time).addImage(picture(width: 800, height: 600, red: 0.8))
        try saveDatabaseBeforeSounds(at: file, at: time.now, image: bird)
        let old = try DatabaseQueue(path: file.path(percentEncoded: false))
        #expect(try await old.read(soundsReferred(in:)).isEmpty)
        try old.close()

        let engine = try Engine(location: .folder(folder), time: time)

        let cards = try engine.cards()
        #expect(cards.map(\.front) == ["hornero", "ubuntu"])
        #expect(cards.map(\.frontImage) == [bird, nil])
        #expect(cards.allSatisfy { $0.frontSound == nil && $0.backSound == nil })
        let la = try await addTone(440, to: engine)
        try engine.edit(2, with: card(.concept, front: "ubuntu", back: "Soy porque somos.", backSound: la))
        #expect(try engine.read(soundsReferred(in:)) == [la])
    }
}

/// Adds a mono tone of `hertz` lasting a second to `engine`'s sounds, and
/// returns its name: tones of other pitches are other sounds.
func addTone(_ hertz: Double, to engine: Engine) async throws -> SoundName {
    try await engine.addSound(tone(seconds: 1, hertz: hertz), named: "\(Int(hertz)).wav")
}

/// A tone of `hertz` lasting `seconds`, on `channels` channels, as a WAV
/// file's data: a test's own sound. Tones of other pitches or lengths are
/// other sounds.
func tone(seconds: Double, hertz: Double, channels: AVAudioChannelCount = 1) throws -> Data {
    let file = URL.temporaryDirectory.appending(path: "FichaTone-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: file) }
    let format = try #require(
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: channels, interleaved: false))
    let frames = AVAudioFrameCount(44_100 * seconds)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
    buffer.frameLength = frames
    let samples = try #require(buffer.floatChannelData)
    for channel in 0..<Int(channels) {
        for frame in 0..<Int(frames) {
            samples[channel][frame] = Float(sin(2 * Double.pi * hertz * Double(frame) / 44_100) * 0.5)
        }
    }
    do {
        let wav = try AVAudioFile(
            forWriting: file,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: channels,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try wav.write(from: buffer)
    }
    return try Data(contentsOf: file)
}

/// A video of 64 by 64 pixels lasting `seconds`, as a QuickTime movie's
/// data, with a mono tone of `hertz` as its sound track, or none when it's
/// nil: a test's own video.
func video(seconds: Double, withSoundOf hertz: Double?) async throws -> Data {
    let file = URL.temporaryDirectory.appending(path: "FichaVideo-\(UUID().uuidString).mov")
    let toneFile = URL.temporaryDirectory.appending(path: "FichaVideoTone-\(UUID().uuidString).wav")
    defer {
        try? FileManager.default.removeItem(at: file)
        try? FileManager.default.removeItem(at: toneFile)
    }
    let writer = try AVAssetWriter(outputURL: file, fileType: .mov)
    let picture = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
    let frames = writer.inputPixelBufferReceiver(for: picture, pixelBufferAttributes: nil)
    var sound:
        (
            samples: AVAssetReaderOutput.Provider<CMReadySampleBuffer<CMSampleBuffer.DynamicContent>>,
            receiver: AVAssetWriterInput.SampleBufferReceiver, reader: AVAssetReader
        )?
    if let hertz {
        try tone(seconds: seconds, hertz: hertz).write(to: toneFile)
        let asset = AVURLAsset(url: toneFile)
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let reader = try AVAssetReader(asset: asset)
        let samples = reader.outputProvider(
            for: AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM]))
        let receiver = writer.inputReceiver(
            for: AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
                ]))
        try reader.start()
        sound = (samples, receiver, reader)
    }
    try writer.start()
    writer.startSession(atSourceTime: .zero)
    for second in 0..<Int(seconds.rounded(.up)) {
        let buffer = try CVMutablePixelBuffer(
            CVPixelBufferCreationAttributes(
                pixelFormatType: CVPixelFormatType(rawValue: kCVPixelFormatType_32BGRA),
                size: CVImageSize(width: 64, height: 64)))
        try await frames.append(CVReadOnlyPixelBuffer(buffer), with: CMTime(value: CMTimeValue(second), timescale: 1))
    }
    frames.finish()
    if let sound {
        while let buffer = try await sound.samples.next() {
            try await sound.receiver.append(buffer)
        }
        sound.receiver.finish()
    }
    await writer.finishWriting()
    #expect(writer.status == .completed, "\(String(describing: writer.error))")
    return try Data(contentsOf: file)
}

/// The format of the sound in `data`, as AVFoundation reads its file: its
/// codec and its channels.
func soundFormat(of data: Data) throws -> (id: AudioFormatID, channels: AVAudioChannelCount) {
    let file = URL.temporaryDirectory.appending(path: "FichaSound-\(UUID().uuidString).m4a")
    defer { try? FileManager.default.removeItem(at: file) }
    try data.write(to: file)
    let sound = try AVAudioFile(forReading: file)
    return (sound.fileFormat.streamDescription.pointee.mFormatID, sound.fileFormat.channelCount)
}
