import FichaCore
import FichaData
import Foundation
import Testing

/// Tests on the Cards window's card types of the user's own (#365): the
/// sidebar's Types section, New Type… in the type picker of the card form and
/// the editor, and Rename…, Emoji… and Delete… in a user type's context menu,
/// on the default scheduler.
struct CardsWindowTypesTests {
    let engine: Engine
    let scheduler = ReviewSettings.defaults.scheduler

    init() throws {
        let calendar = try buenosAiresCalendar()
        engine = try Engine(
            location: .inMemory, time: ManualTimeSource(now: try morning(of: 14, in: calendar)), calendar: calendar)
    }

    // Efeméride has no card, and stays listed so that Lucas can give it one.
    @Test(
        "the Types section lists the four, then the user's types in alphabetical order, one with no card too, then No Type while a card has none"
    )
    func theTypesSectionsOrder() throws {
        let law = try engine.makeUserType(named: "Ley")
        let date = try engine.makeUserType(named: "Efeméride", emoji: Emoji("📅"))
        let formula = try engine.makeUserType(named: "fórmula")
        try engine.create(card(.user(law), front: "gravedad", back: "Todo cae."))
        try engine.create(card(.user(formula), front: "agua", back: "H₂O"))
        try engine.create(card(nil, front: "petricor", back: "El olor de la lluvia."))

        let window = openWindow()

        let types: [CardType] = [.word, .concept, .quote, .question, .user(date), .user(formula), .user(law)]
        #expect(window.typeGroups == types.map(CardGroup.type) + [.noType])
        #expect(window.pickerTypes == types)
        #expect(window.typeMenu(for: .type(.word)) == nil)
        #expect(window.typeMenu(for: .noType) == nil)
        #expect(window.typeMenu(for: .type(.user(date))) == date)
    }

    @Test(
        "choosing a user type lists its cards, and it stays chosen once it's renamed; once it's deleted, the sidebar goes back to All cards"
    )
    func choosingAUserType() throws {
        let formula = try engine.makeUserType(named: "Fórmula")
        let water = try engine.create(card(.user(formula), front: "agua", back: "H₂O"))
        try engine.create(card(.word, front: "petricor", back: "El olor de la lluvia."))
        var window = openWindow()

        window.choose(.cards(.type(.user(formula))))
        #expect(window.listedCardIDs == [water.id])
        let renamed = try engine.renameUserType(formula.id, to: "Fórmula química")
        window.read(with: scheduler)
        #expect(window.sidebarItem == .cards(.type(.user(renamed))))
        #expect(window.listedCardIDs == [water.id])

        try engine.deleteUserType(formula.id)
        window.read(with: scheduler)
        #expect(window.sidebarItem == .cards(.all))
    }

    @Test(
        "New Type… in the card form asks for a name and an emoji, refuses a blank, built-in or taken name and more than one emoji, and OK makes the type, which the form takes"
    )
    func newTypeInTheCardForm() throws {
        try engine.makeUserType(named: "Fórmula")
        var window = openWindow()
        window.openNewCardForm()

        window.askForNewType(in: .form)
        #expect(window.question == .newType(.form))
        #expect(window.newTypeEntry(name: "  ", emoji: "") == .blankName)
        #expect(window.newTypeEntry(name: "Quote", emoji: "") == .refused(.builtInTypeName("Quote")))
        #expect(window.newTypeEntry(name: "FORMULA", emoji: "") == .refused(.typeNameTaken("Fórmula")))
        #expect(window.newTypeEntry(name: "Ley", emoji: "⚖️📜") == .refused(.notOneEmoji))
        #expect(window.newTypeEntry(name: " Ley ", emoji: " ") == .type(name: "Ley", emoji: nil))
        window.chooseNewType(name: "Ley", emoji: "⚖️📜")
        #expect(window.question == .newType(.form))
        window.chooseNewType(name: " Ley ", emoji: "⚖️")

        let law = try #require(try engine.userTypes().first { $0.name == "Ley" })
        #expect(law.emoji == "⚖️")
        #expect(window.question == nil)
        #expect(window.failure == nil)
        #expect(window.cardForm?.draft.type == .user(law))
        #expect(window.pickerTypes.contains(.user(law)))
        guard var draft = window.cardForm?.draft else { return }
        draft.front.text = "gravedad"
        draft.back.text = "Todo cae."
        window.changeDraft(draft)
        window.addCard()
        #expect(try engine.cards().map(\.type) == [.user(law)])
    }

    @Test("a user type renamed while Show Card sets the card form aside is renamed in the form that comes back")
    func aTypeRenamedWhileTheFormIsSetAside() throws {
        let formula = try engine.makeUserType(named: "Fórmula")
        try engine.create(card(nil, front: "agua", back: "H₂O"))
        var window = openWindow()
        window.openNewCardForm()
        guard var draft = window.cardForm?.draft else { return }
        draft.type = .user(formula)
        draft.front.text = "agua"
        window.changeDraft(draft)

        window.showRepeatedCard()
        window.askToRenameType(formula.id)
        window.chooseNewName("Fórmula química")
        window.openNewCardForm()

        let renamed = UserType(id: formula.id, name: "Fórmula química", emoji: nil)
        #expect(window.failure == nil)
        #expect(window.cardForm?.draft.front.text == "agua")
        #expect(window.cardForm?.draft.type == .user(renamed))
    }

    @Test("New Type… in the editor makes the type, which the editor takes, and Save gives the card")
    func newTypeInTheEditor() throws {
        let water = try engine.create(card(.word, front: "agua", back: "H₂O"))
        var window = openWindow()
        window.select([water.id])
        window.startEditing()
        #expect(window.editedType == .word)

        window.askForNewType(in: .editor)
        window.chooseNewType(name: "Fórmula", emoji: "")

        let formula = try #require(try engine.userTypes().first)
        #expect(formula == UserType(id: formula.id, name: "Fórmula", emoji: nil))
        #expect(window.editedType == .user(formula))
        window.saveCard(try card(window.editedType, front: "agua", back: "H₂O"))
        #expect(window.editing == nil)
        #expect(window.editedType == nil)
        #expect(try engine.cards().map(\.type) == [.user(formula)])
    }

    @Test(
        "Rename… and Emoji… in a user type's menu ask with its name and its emoji, refuse what the engine refuses, and OK changes them"
    )
    func renameAndEmojiOnAUserType() throws {
        let formula = try engine.makeUserType(named: "Fórmula", emoji: Emoji("🧪"))
        try engine.makeUserType(named: "Ley")
        var window = openWindow()

        window.askToRenameType(formula.id)
        #expect(window.question == .renameType(formula))
        #expect(window.renameEntry("concept") == .refused(.builtInTypeName("concept")))
        #expect(window.renameEntry("ley") == .refused(.typeNameTaken("Ley")))
        #expect(window.renameEntry("FÓRMULA") == .name("FÓRMULA"))
        window.chooseNewName("Fórmula química")
        #expect(window.question == nil)

        window.askForTypeEmoji(formula.id)
        #expect(window.question == .typeEmoji(UserType(id: formula.id, name: "Fórmula química", emoji: "🧪")))
        window.chooseEmoji(" ")
        #expect(window.question == nil)

        let changed = UserType(id: formula.id, name: "Fórmula química", emoji: nil)
        #expect(try engine.userTypes().first == changed)
        #expect(window.typeMenu(for: .type(.user(changed))) == changed)
        #expect(window.failure == nil)
    }

    @Test(
        "Delete… on a user type asks with how many cards have it, buried ones too, and deleting it leaves them with no type"
    )
    func deleteAUserType() throws {
        let formula = try engine.makeUserType(named: "Fórmula")
        let water = try engine.create(card(.user(formula), front: "agua", back: "H₂O"))
        let salt = try engine.create(card(.user(formula), front: "sal", back: "NaCl"))
        try engine.bury(salt.id)
        var window = openWindow()
        window.choose(.cards(.type(.user(formula))))

        window.askToDeleteType(formula.id)
        #expect(window.question == .deleteType(formula, cardCount: 2))
        window.deleteType(formula)

        #expect(window.question == nil)
        #expect(window.failure == nil)
        #expect(window.sidebarItem == .cards(.all))
        #expect(window.pickerTypes == CardType.builtIn)
        #expect(window.typeGroups.last == .noType)
        #expect(try engine.cards().map(\.type) == [nil, nil])
        #expect(try engine.cards().map(\.id) == [water.id, salt.id])
    }

    /// The window as it opens, on All cards, with the cards read.
    private func openWindow() -> CardsWindowState {
        var window = engine.openCardsWindow(with: scheduler)
        window.read(with: scheduler)
        return window
    }
}

extension CardsWindowState {
    /// The ids of the cards the table lists, or nil when it lists the inbox
    /// or couldn't read them.
    fileprivate var listedCardIDs: [Int64]? {
        guard case .success(.cards(let rows)) = listing else {
            return nil
        }
        return rows.map(\.id)
    }
}
