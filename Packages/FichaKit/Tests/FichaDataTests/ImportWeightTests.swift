import FichaCore
import Foundation
import Testing

// For the preview of what a reader read, and the files as they come in.
@testable import FichaData

/// Tests on what the Import sheet says the images and sounds it brings weigh
/// while sync is on (#317's decision of 2026-10-28), from an engine in memory
/// on a Mac in Buenos Aires, signed into iCloud. A file's reader is left
/// out: each test hands the engine's preview the cards and files a reader
/// would, files made only of zeros, which take no memory until read.
final class ImportWeightTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 21, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
        try Sync(engine: engine, zones: .ficha).noteAccount(signedIn: true)
    }

    /// The preview of a file of cards whose reader read `cards`, which bring
    /// `fields` beyond their front and back, and with them `images` and
    /// `sounds`.
    func preview(
        of cards: [CardContent], giving fields: Set<CardField> = [], images: [CardImage] = [],
        sounds: [CardSound] = []
    ) throws -> ImportPreview {
        let read = cards.enumerated().map { line, content in
            ImportedCard(content: content, fields: fields, line: line + 1)
        }
        return try engine.preview(
            ImportReading(cards: read, leftOut: []), of: "Mundo.txt", kind: .cardsFile,
            images: Dictionary(uniqueKeysWithValues: images.map { ($0.name, $0) }),
            sounds: Dictionary(uniqueKeysWithValues: sounds.map { ($0.name, $0) }))
    }

    // The map is on two cards, and counts once.
    @Test(
        "an import whose images and sounds weigh 100 MB or more says what goes up to iCloud, and one under it doesn't")
    func theLineFrom100MB() throws {
        let map = try incomingImage(weighing: 60_000_000, named: "a")
        let anthem = try incomingSound(weighing: 39_999_999, named: "b")
        let longerAnthem = try incomingSound(weighing: 40_000_000, named: "c")
        let cards = [
            try card(nil, front: "¿Qué país es?", back: "La Argentina.", frontImage: map.name),
            try card(nil, front: "¿Qué himno es?", back: "El de la Argentina.", backSound: anthem.name),
            try card(nil, front: "¿De dónde es este mapa?", back: "De la Argentina.", frontImage: map.name),
        ]

        let under = try preview(of: cards, images: [map], sounds: [anthem])
        let over = try preview(
            of: [
                cards[0],
                try card(nil, front: "¿Qué himno es?", back: "El de la Argentina.", backSound: longerAnthem.name),
                cards[2],
            ], images: [map], sounds: [longerAnthem])

        #expect(under.weightGoingUpToICloud(choosing: .update) == nil)
        #expect(over.weightGoingUpToICloud(choosing: .update) == 100_000_000)
    }

    // Ficha holds the bird already: the file's copy of it, however heavy,
    // goes nowhere. Ubuntu repeats a card of the user's, which an update
    // gives the nest's image on its back.
    @Test("the files Ficha holds don't count, nor those of repeated cards the import skips")
    func heldFilesAndSkippedCardsDontCount() throws {
        let bird = try engine.addImage(picture(width: 800, height: 600, red: 0.8))
        try engine.create(card(nil, front: "¿Qué pájaro es?", back: "Un hornero.", frontImage: bird))
        try engine.create(card(.concept, front: "ubuntu", back: "Soy porque somos."))
        let heavyBird = CardImage(name: bird, data: Data(count: 70_000_000))
        let nest = try incomingImage(weighing: 40_000_000, named: "a")
        let map = try incomingImage(weighing: 60_000_000, named: "b")

        let preview = try preview(
            of: [
                try card(nil, front: "¿Qué ave es?", back: "El hornero.", frontImage: bird),
                try card(.concept, front: "ubuntu", back: "Soy porque somos.", backImage: nest.name),
                try card(nil, front: "¿Qué país es?", back: "La Argentina.", frontImage: map.name),
            ], giving: [.backImage], images: [heavyBird, nest, map])

        #expect(preview.weightGoingUpToICloud(choosing: .update) == 100_000_000)
        #expect(preview.weightGoingUpToICloud(choosing: .skip) == nil)
    }

    // Only geografía syncs (#355): the map, on a card tagged geografía, goes
    // up; the anthem, on a card the file proposes "Himnos" for, only once
    // the user names that tag geografía.
    @Test(
        "the line counts only the files of the cards that sync once they come in, with the tags as the user names them")
    func theLineCountsOnlyTheCardsThatSync() throws {
        try engine.syncOnlyChosenTags(true)
        try engine.chooseToSync("geografía", true)
        let map = try incomingImage(weighing: 100_000_000, named: "a")
        let anthem = try incomingSound(weighing: 100_000_000, named: "b")
        let read = [
            ImportedCard(
                content: try card(
                    nil, front: "¿Qué país es?", back: "La Argentina.", tags: ["geografía"], frontImage: map.name),
                fields: [], line: 1),
            ImportedCard(
                content: try card(nil, front: "¿Qué himno es?", back: "El de la Argentina.", backSound: anthem.name),
                fields: [], line: 2, proposedTags: ["Himnos"]),
        ]

        let preview = try engine.preview(
            ImportReading(cards: read, leftOut: []), of: "Himnos.txt", kind: .cardsFile, images: [map.name: map],
            sounds: [anthem.name: anthem])

        #expect(preview.weightGoingUpToICloud(choosing: .update) == 100_000_000)
        #expect(preview.weightGoingUpToICloud(choosing: .update, naming: ["Himnos": "geografía"]) == 200_000_000)
    }

    // Only geografía syncs: the Mac holds the map on a card of historia
    // alone, so iCloud lacks it, and the file's card of geografía takes it
    // up. The file's copy of it weighs a byte.
    @Test("a file Ficha holds counts when no card that syncs uses it, at the size Ficha keeps it")
    func aHeldFileNoCardThatSyncsUsesCounts() throws {
        try engine.syncOnlyChosenTags(true)
        try engine.chooseToSync("geografía", true)
        let map = try heavyImage(weighing: 100_000_000, named: "a", in: engine)
        try engine.create(card(nil, front: "¿Qué país es?", back: "La Argentina.", tags: ["historia"], frontImage: map))
        let read = [
            ImportedCard(
                content: try card(
                    nil, front: "¿De qué país es este mapa?", back: "De la Argentina.", tags: ["geografía"],
                    frontImage: map),
                fields: [], line: 1)
        ]

        let preview = try engine.preview(
            ImportReading(cards: read, leftOut: []), of: "Mapas.txt", kind: .cardsFile,
            images: [map: CardImage(name: map, data: Data(count: 1))], sounds: [:])

        #expect(preview.weightGoingUpToICloud(choosing: .update) == 100_000_000)
    }

    @Test("with sync off, or no iCloud account, the import says nothing of iCloud")
    func noLineWithoutSync() throws {
        let map = try incomingImage(weighing: 120_000_000, named: "a")
        let cards = [try card(nil, front: "¿Qué país es?", back: "La Argentina.", frontImage: map.name)]
        #expect(try preview(of: cards, images: [map]).weightGoingUpToICloud(choosing: .update) == 120_000_000)

        try engine.turnSyncOff()
        let whileOff = try preview(of: cards, images: [map])
        try engine.turnSyncOn()
        try Sync(engine: engine, zones: .ficha).noteAccount(signedIn: false)
        let signedOut = try preview(of: cards, images: [map])
        let neverAsked = try Engine(location: .inMemory, time: time, calendar: calendar)

        #expect(whileOff.weightGoingUpToICloud(choosing: .update) == nil)
        #expect(signedOut.weightGoingUpToICloud(choosing: .update) == nil)
        #expect(
            try neverAsked.preview(
                ImportReading(cards: [ImportedCard(content: cards[0], fields: [], line: 1)], leftOut: []),
                of: "Mundo.txt", kind: .cardsFile, images: [map.name: map]
            ).weightGoingUpToICloud(choosing: .update) == nil)
    }
}

/// An image of `bytes` bytes as it comes in with a file, as an image Ficha
/// shrank would be, though it holds only zeros, named as `imageName(of:)`
/// names it.
func incomingImage(weighing bytes: Int, named digit: Character) throws -> CardImage {
    CardImage(name: try imageName(of: digit), data: Data(count: bytes))
}

/// A JPEG's name, as Ficha names an image by its content: `digit`, a
/// hexadecimal digit, 64 times, which tells it from the test's other images.
func imageName(of digit: Character) throws -> ImageName {
    try #require(ImageName(rawValue: String(repeating: digit, count: 64) + ".jpg"))
}

/// A sound of `bytes` bytes as it comes in with a file, as `incomingImage`
/// makes an image.
func incomingSound(weighing bytes: Int, named digit: Character) throws -> CardSound {
    CardSound(
        name: try #require(SoundName(rawValue: String(repeating: digit, count: 64) + ".m4a")),
        data: Data(count: bytes))
}
