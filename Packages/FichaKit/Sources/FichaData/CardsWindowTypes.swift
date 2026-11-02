import FichaCore
import Foundation

// The Cards window's card types of the user's own (#365), beside the four
// Ficha comes with: the sidebar's Types section lists them after the four, in
// alphabetical order, also while no card has one; the type picker, in the
// card form and the editor, offers them, and New Type…, which makes one in
// the New Type sheet; and a user type's context menu in the sidebar renames
// it, gives it an emoji and deletes it, asking first with how many cards have
// it. The sheets are the window's rename and emoji sheets, which a tag's menu
// opens too.

extension CardsWindowState {
    /// What OK in the New Type sheet makes of what its fields hold.
    public enum NewTypeEntry: Sendable, Equatable {
        /// A name, without the spaces around it, and an emoji, or none, which
        /// OK makes the type with.
        case type(name: String, emoji: Emoji?)
        /// A blank name, as the sheet opens, which keeps OK off, and which
        /// the sheet doesn't call a mistake.
        case blankName
        /// What OK refuses, and why, for the sheet to say: a name of one of
        /// the four Ficha comes with or another user type's, or something
        /// that isn't one emoji.
        case refused(EngineError)
    }

    /// The types the type picker offers, in the card form and the editor,
    /// after None and before New Type…: the four Ficha comes with, then the
    /// user's, in alphabetical order, as the sidebar lists them.
    public var pickerTypes: [CardType] {
        typeGroups.compactMap { group in
            guard case .type(let type) = group else { return nil }
            return type
        }
    }

    /// The user type whose context menu the sidebar's group `group` has,
    /// with Rename…, Emoji… and Delete…, while the sidebar lists it, as last
    /// read; nil for one of the four Ficha comes with, No Type and any other
    /// group, which have no menu.
    public func typeMenu(for group: CardGroup) -> UserType? {
        guard case .type(.user(let type)) = group else { return nil }
        return listedUserType(type.id)
    }

    /// The user type with the ID `id` as the sidebar lists it, as last read,
    /// or nil when it doesn't.
    private func listedUserType(_ id: UUID) -> UserType? {
        pickerTypes.lazy.compactMap(\.userType).first { $0.id == id }
    }

    /// Sets the type of the card the user edits, as Save will give it to it,
    /// or no type when it's nil, while they edit one.
    public mutating func setTypeInEditor(_ type: CardType?) {
        guard case .card = editing else { return }
        editedType = type
    }

    /// Asks for a new type's name and emoji, in the New Type sheet, after New
    /// Type… in the type picker of the fields `fields`, while they're there:
    /// the card form's, while it's open, or the editor's, while Lucas edits a
    /// card.
    public mutating func askForNewType(in fields: CardFields) {
        guard areOpen(fields) else { return }
        question = .newType(fields)
    }

    /// What OK in the New Type sheet makes of what its fields hold, `name`
    /// in its name field and `emoji` in its emoji field: the type's name,
    /// without the spaces around it, and its emoji, or none for an empty
    /// field; a blank name, as the sheet opens, which keeps OK off; or a
    /// refusal of a name of one of the four Ficha comes with, another user
    /// type's, or of anything but one emoji, as the engine refuses them. Nil
    /// while the window asks for no new type.
    public func newTypeEntry(name: String, emoji: String) -> NewTypeEntry? {
        guard case .newType = question else { return nil }
        if case .refused(let error) = emojiEntry(emoji) {
            return .refused(error)
        }
        switch typeNameEntry(name) {
        case .name(let name): return .type(name: name, emoji: emojiEntry(emoji).emoji)
        case .refused(.blankTypeName): return .blankName
        case .refused(let error): return .refused(error)
        }
    }

    /// Chooses OK in the New Type sheet, whose name field holds `name` and
    /// emoji field `emoji`: makes the type, with that emoji, or none when the
    /// field is empty, which the type picker it was asked from takes, and
    /// reads the cards again; or records why it couldn't and goes on asking.
    /// While OK doesn't take what the fields hold, as `newTypeEntry` says, it
    /// does nothing, and the sheet says why.
    public mutating func chooseNewType(name: String, emoji: String) {
        guard case .newType(let fields) = question,
            case .type(let name, let emoji)? = newTypeEntry(name: name, emoji: emoji)
        else { return }
        var made: UserType?
        let done = perform(.makeType) { engine throws(EngineError) in
            made = try engine.makeUserType(named: name, emoji: emoji)
        }
        guard done, let made else { return }
        question = nil
        switch fields {
        case .form: cardForm?.draft.type = .user(made)
        case .editor: setTypeInEditor(.user(made))
        }
        read(with: scheduler)
    }

    /// Asks which name the user type with the ID `id` gets, in the rename
    /// sheet, after Rename… in its context menu, while the sidebar lists it.
    public mutating func askToRenameType(_ id: UUID) {
        guard let type = listedUserType(id) else { return }
        question = .renameType(type)
    }

    /// Asks which emoji the user type with the ID `id` gets, in the emoji
    /// sheet, after Emoji… in its context menu, while the sidebar lists it.
    public mutating func askForTypeEmoji(_ id: UUID) {
        guard let type = listedUserType(id) else { return }
        question = .typeEmoji(type)
    }

    /// Asks whether to delete the user type with the ID `id`, saying how many
    /// cards have it, after Delete… in its context menu, while the sidebar
    /// lists it; or records why it couldn't count them.
    public mutating func askToDeleteType(_ id: UUID) {
        guard let type = listedUserType(id) else { return }
        var count = 0
        let counted = perform(.deleteType(name: type.name)) { engine throws(EngineError) in
            count = try engine.cardCount(of: .user(type))
        }
        if counted {
            question = .deleteType(type, cardCount: count)
        }
    }

    /// Deletes `type`, a user type the window asked about and Lucas
    /// confirmed: its cards have no type then, and keep everything else; and
    /// reads the cards again, the sidebar going back to All cards when it
    /// chose the type; or records why it couldn't. The dialog that asked
    /// hands `type` back, as Delete's hands its cards.
    public mutating func deleteType(_ type: UserType) {
        question = nil
        let done = perform(.deleteType(name: type.name)) { engine throws(EngineError) in
            try engine.deleteUserType(type.id)
        }
        if done {
            read(with: scheduler)
        }
    }

    /// Renames `type`, the user type the window asks about, `name`, a name
    /// OK takes, and reads the cards again, the sidebar following it; or
    /// records why it couldn't. Whether it did.
    mutating func renameType(_ type: UserType, to name: String) -> Bool {
        let done = perform(.renameType(name: type.name)) { engine throws(EngineError) in
            try engine.renameUserType(type.id, to: name)
        }
        if done {
            read(with: scheduler)
        }
        return done
    }

    /// Gives `type`, the user type the window asks about, `emoji`, or takes
    /// its emoji away when it's nil, and reads the cards again; or records
    /// why it couldn't. Whether it did.
    mutating func setEmoji(_ emoji: Emoji?, of type: UserType) -> Bool {
        let done = perform(.setTypeEmoji(name: type.name)) { engine throws(EngineError) in
            try engine.setEmoji(emoji, ofUserType: type.id)
        }
        if done {
            read(with: scheduler)
        }
        return done
    }

    /// `name`, a type's name the rename sheet or the New Type sheet holds, as
    /// OK takes it, for the user type with the ID `renamed` or a new one:
    /// without the spaces around it, or a refusal of a blank name, a name of
    /// one of the four, or another user type's, as the engine refuses them,
    /// among the user's types as the window last read them, as a tag's name
    /// is checked; the engine checks it again as it saves it.
    func typeNameEntry(_ name: String, renaming renamed: UUID? = nil) -> RenameEntry {
        do throws(EngineError) {
            return .name(try checkedTypeName(name, renaming: renamed, among: pickerTypes.compactMap(\.userType)))
        } catch {
            return .refused(error)
        }
    }

    /// Points what the window holds of a user type, the group the sidebar
    /// chose, the type of the card form and of the one Show Card set aside,
    /// and the editor's, at the type as it was last read, renamed or given
    /// another emoji since, while the sidebar lists it. A type gone from the
    /// sidebar, deleted, stays in the forms and the editor, where Save says
    /// so, and the sidebar goes back to All cards (`read(on:)`).
    mutating func followUserTypes() {
        if case .cards(.type(.user(let type))) = sidebarItem, let listed = listedUserType(type.id) {
            sidebarItem = .cards(.type(.user(listed)))
        }
        if let type = cardForm?.draft.type.map(followed) {
            cardForm?.draft.type = type
        }
        if let type = setAsideCardForm?.draft.type.map(followed) {
            setAsideCardForm?.draft.type = type
        }
        editedType = editedType.map(followed)
    }

    /// `type` as it was last read, when it's a user type the sidebar lists,
    /// renamed or given another emoji since; as it is otherwise.
    private func followed(_ type: CardType) -> CardType {
        guard case .user(let userType) = type, let listed = listedUserType(userType.id) else { return type }
        return .user(listed)
    }

    /// Whether the sidebar offers the type group of `type`, as last read: one
    /// of the four always, and a user type while it lists it.
    func offersType(_ type: CardType) -> Bool {
        guard let userType = type.userType else { return true }
        return listedUserType(userType.id) != nil
    }
}

extension CardsWindowState.EmojiEntry {
    /// The emoji OK gives, or nil for none: for a removal, and a refusal,
    /// which gives nothing.
    var emoji: Emoji? {
        guard case .emoji(let emoji) = self else { return nil }
        return emoji
    }

    /// Whether OK refuses it.
    var isRefused: Bool {
        guard case .refused = self else { return false }
        return true
    }
}
