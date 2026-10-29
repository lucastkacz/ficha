import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on card types of the user's own (#365), beside the four Ficha comes
/// with: each with a name and an optional emoji, made, renamed and deleted,
/// given to cards, and named in files and by a refine session, from an engine
/// in memory on a Mac in Buenos Aires, with files in a folder of the test's
/// own.
final class UserTypesTests {
    let calendar: Calendar
    let time: ManualTimeSource
    let engine: Engine
    /// A folder of the test's own, for the files it imports and exports.
    let folder = URL.temporaryDirectory.appending(
        path: "FichaUserTypesTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    init() throws {
        calendar = try buenosAiresCalendar()
        time = ManualTimeSource(now: try morning(of: 21, in: calendar))
        engine = try Engine(location: .inMemory, time: time, calendar: calendar)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("a type is made with its name and emoji, renamed, given another emoji, and listed in alphabetical order")
    func aTypeIsMadeRenamedAndGivenAnEmoji() throws {
        let formula = try engine.makeUserType(named: " Fórmula ", emoji: TagEmoji("🧪"))
        let law = try engine.makeUserType(named: "ley")
        let date = try engine.makeUserType(named: "Efeméride", emoji: TagEmoji("📅"))

        try engine.renameUserType(law.id, to: "Artículo")
        try engine.setEmoji(TagEmoji("⚗️"), ofUserType: formula.id)
        try engine.setEmoji(nil, ofUserType: date.id)

        #expect(
            try engine.userTypes() == [
                UserType(id: law.id, name: "Artículo", emoji: nil),
                UserType(id: date.id, name: "Efeméride", emoji: nil),
                UserType(id: formula.id, name: "Fórmula", emoji: "⚗️"),
            ])
    }

    @Test(
        "a blank name, a name of one of the four in English or as a file writes it, and another type's name ignoring case and accents are refused"
    )
    func takenAndBuiltInNamesAreRefused() throws {
        let formula = try engine.makeUserType(named: "Fórmula")

        #expect(throws: EngineError.blankTypeName) { try self.engine.makeUserType(named: "  ") }
        #expect(throws: EngineError.builtInTypeName("Word")) { try self.engine.makeUserType(named: "Word") }
        #expect(throws: EngineError.builtInTypeName("quote")) { try self.engine.makeUserType(named: "quote") }
        #expect(throws: EngineError.typeNameTaken("Fórmula")) { try self.engine.makeUserType(named: "formula") }
        #expect(throws: EngineError.builtInTypeName("Concept")) {
            try self.engine.renameUserType(formula.id, to: "Concept")
        }
        try engine.renameUserType(formula.id, to: "FÓRMULA")
        #expect(try engine.userTypes().map(\.name) == ["FÓRMULA"])
    }

    @Test("a card given a user type keeps it through a rename, and `ficha cards` writes it by its name")
    func aCardKeepsItsTypeThroughARename() throws {
        let formula = try engine.makeUserType(named: "Fórmula", emoji: TagEmoji("🧪"))
        let water = try engine.create(card(.user(formula), front: "agua", back: "H₂O"))
        try engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))

        let renamed = try engine.renameUserType(formula.id, to: "Fórmula química")

        #expect(water.type == .user(formula))
        #expect(try engine.cards().map(\.type) == [.user(renamed), .word])
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.cards()))
        let cards = try #require(encoded as? [[String: Any]])
        #expect(cards.map { $0["type"] as? String } == ["Fórmula química", "word"])
    }

    @Test("deleting a user type leaves its cards with no type and everything else as it was, a buried one too")
    func deletingATypeLeavesItsCardsWithNoType() throws {
        let formula = try engine.makeUserType(named: "Fórmula")
        let law = try engine.makeUserType(named: "Ley")
        let water = try engine.create(card(.user(formula), front: "agua", back: "H₂O", tags: ["química"]))
        let salt = try engine.create(card(.user(formula), front: "sal", back: "NaCl", source: "Un libro"))
        let gravity = try engine.create(card(.user(law), front: "gravedad", back: "Todo cae."))
        try engine.bury(salt.id)

        #expect(try engine.cardCount(ofUserType: formula.id) == 2)
        try engine.deleteUserType(formula.id)

        #expect(try engine.userTypes() == [law])
        #expect(try engine.cardCount(ofUserType: formula.id) == 0)
        let cards = try engine.cards()
        #expect(cards.map(\.type) == [nil, nil, .user(law)])
        #expect(cards.map(\.tags) == [["química"], [], []])
        #expect(cards.map(\.source) == [nil, "Un libro", nil])
        #expect(cards.map(\.id) == [water.id, salt.id, gravity.id])
        #expect(cards[1].buriedAt != nil)
    }

    // As the Cards window's form saves a card while another device's
    // deletion comes in.
    @Test("a card can't be saved with a user type deleted meanwhile, new or edited")
    func aCardCantBeSavedWithADeletedType() throws {
        let formula = try engine.makeUserType(named: "Fórmula")
        let water = try engine.create(card(nil, front: "agua", back: "H₂O"))
        try engine.deleteUserType(formula.id)

        #expect(throws: EngineError.userTypeNotFound) {
            try self.engine.create(card(.user(formula), front: "sal", back: "NaCl"))
        }
        #expect(throws: EngineError.userTypeNotFound) {
            try self.engine.edit(water.id, with: card(.user(formula), front: "agua", back: "H₂O"))
        }
        #expect(try engine.cards().map(\.type) == [nil])
    }

    @Test("an exported card with a user type imports back into another Ficha with a type of that name and no emoji")
    func anExportedUserTypeImportsBack() async throws {
        let formula = try engine.makeUserType(named: "Fórmula", emoji: TagEmoji("🧪"))
        try engine.create(card(.user(formula), front: "agua", back: "H₂O"))
        try engine.create(card(.quote, front: "\"Eureka.\"", back: "Arquímedes."))
        let file = folder.appending(path: "Tarjetas.txt")
        try engine.export(.all, to: file)

        let other = try Engine(location: .inMemory, time: time, calendar: calendar)
        try await other.importCards(other.previewImport(of: file), choosing: ImportChoices())

        let made = try #require(try other.userTypes().first)
        #expect(try other.userTypes() == [UserType(id: made.id, name: "Fórmula", emoji: nil)])
        #expect(try other.cards().map(\.type) == [.user(made), .quote])
    }

    @Test(
        "an import finds a type by its raw value or a user type's name ignoring case and accents, and makes one type for each name it doesn't know"
    )
    func anImportFindsAndMakesTypes() async throws {
        let formula = try engine.makeUserType(named: "Fórmula", emoji: TagEmoji("🧪"))
        let file = folder.appending(path: "Química.txt")
        try Data(
            """
            agua\tH₂O\t\tFORMULA
            sal\tNaCl\t\tfórmula
            Lavoisier\tNada se pierde.\t\tQUOTE
            oxígeno\tO\t\telemento
            hierro\tFe\t\tElemento
            neón\tNe\t\t
            """.utf8
        ).write(to: file)

        let preview = try await engine.previewImport(of: file)
        try engine.importCards(preview, choosing: ImportChoices())

        #expect(preview.leftOut == [])
        let element = try #require(try engine.userTypes().first { $0.name == "elemento" })
        #expect(try engine.userTypes() == [UserType(id: element.id, name: "elemento", emoji: nil), formula])
        #expect(
            try engine.cards().map(\.type) == [
                .user(formula), .user(formula), .quote, .user(element), .user(element), nil,
            ])
    }

    @Test("a card an import updates takes the type the file names, a new one too, and keeps its own when it names none")
    func anUpdatedCardTakesTheFilesType() async throws {
        try engine.create(card(.word, front: "agua", back: "Un líquido."))
        try engine.create(card(.word, front: "sal", back: "Un mineral."))
        let withType = folder.appending(path: "Con tipo.txt")
        try Data("agua\tH₂O\t\tFórmula\n".utf8).write(to: withType)
        let withoutType = folder.appending(path: "Sin tipo.txt")
        try Data("sal\tNaCl\n".utf8).write(to: withoutType)

        for file in [withType, withoutType] {
            try await engine.importCards(
                engine.previewImport(of: file), choosing: ImportChoices(repeatedCards: .update))
        }

        let formula = try #require(try engine.userTypes().first)
        #expect(formula.name == "Fórmula")
        #expect(try engine.cards().map(\.type) == [.user(formula), .word])
        #expect(try engine.cards().map(\.back) == ["H₂O", "NaCl"])
    }

    @Test(
        "a refine session's drafts name a type as the CLI reads them: one of the four, a user type ignoring case and accents, or a new one, made once"
    )
    func draftsNameTypes() async throws {
        let formula = try engine.makeUserType(named: "Fórmula", emoji: TagEmoji("🧪"))
        let capture = try engine.newCapture("química")

        let approved = try await engine.approve(
            capture.id,
            into: [
                namedDraft("formula", front: "agua", back: "H₂O"),
                namedDraft("Elemento", front: "oxígeno", back: "O"),
                namedDraft("elemento", front: "hierro", back: "Fe"),
                namedDraft("word", front: "alquimia", back: "La química de antes."),
                namedDraft(nil, front: "Lavoisier", back: "Nada se pierde."),
            ])

        let element = try #require(try engine.userTypes().first { $0.name == "Elemento" })
        #expect(try engine.userTypes() == [UserType(id: element.id, name: "Elemento", emoji: nil), formula])
        #expect(approved.map(\.type) == [.user(formula), .user(element), .user(element), .word, nil])

        try engine.flag(approved[4].id, note: note("Es una cita"))
        let fixed = try await engine.fix(
            approved[4].id, with: namedDraft("Cita célebre", front: "Lavoisier", back: "Nada se pierde."))
        let quote = try #require(try engine.userTypes().first { $0.name == "Cita célebre" })
        #expect(fixed.type == .user(quote))
        #expect(try engine.userTypes().count == 3)
    }

    // The capture left the inbox, as when the app discards it while the
    // refine session drafts its cards: the approval fails in the write that
    // would save the type with them.
    @Test("a refine session's draft whose approval fails makes no type")
    func aFailedDraftMakesNoType() async throws {
        let capture = try engine.newCapture("química")
        try engine.discard(capture.id)

        await #expect(throws: EngineError.captureNotInInbox(capture.id)) {
            try await self.engine.approve(capture.id, into: [namedDraft("Elemento", front: "oxígeno", back: "O")])
        }

        #expect(try engine.userTypes().isEmpty)
        #expect(try engine.cards().isEmpty)
    }

    @Test("an approved expansion's draft can name a type the user doesn't have, which it makes")
    func anExpansionMakesAType() async throws {
        let water = try engine.create(card(nil, front: "agua", back: "H₂O"))
        let expansion = try engine.expand(text: "agua", note: "Es una fórmula", source: nil)

        let approved = try await engine.approveExpansion(
            expansion.id, into: namedDraft("Fórmula", front: "agua", back: "H₂O, dos de hidrógeno y uno de oxígeno."))

        let formula = try #require(try engine.userTypes().first)
        #expect(try engine.userTypes() == [UserType(id: formula.id, name: "Fórmula", emoji: nil)])
        #expect(approved.id == water.id)
        #expect(approved.type == .user(formula))
    }
}

/// A draft from a refine session whose type is `typeName`, as the `ficha` CLI
/// reads it, or none when it's nil.
private func namedDraft(_ typeName: String?, front: String, back: String) -> CardDraft {
    CardDraft(
        type: typeName, front: front, back: back, tags: [], source: nil, frontImage: .keep, backImage: .keep,
        frontSound: .keep, backSound: .keep, bothWays: nil)
}
