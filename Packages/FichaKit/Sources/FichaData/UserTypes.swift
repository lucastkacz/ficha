import FichaCore
import Foundation
internal import GRDB

// Card types of the user's own (`GLOSSARY.md`'s Card type), beside the four
// Ficha comes with: each a row of the `userType` table, by its ID unique
// across devices, which a card's type column names it by, so renaming it
// changes no card (`Schema`'s "v28 card types of the user's own"). Deleting
// one leaves its cards with no type; a deletion from another device does the
// same (`SyncedDeletions.swift`), and a card whose column names a user type
// the device doesn't hold, which another device gave it before it heard of
// the deletion, has no type either.

extension Engine {
    /// The user's types, in alphabetical order as the Mac sorts text, each
    /// with its name and its emoji.
    public func userTypes() throws(EngineError) -> [UserType] {
        try read { db in try UserTypes(in: db).sorted }
    }

    /// Makes a user type named `name`, without the spaces around it, with
    /// `emoji`, or none when it's nil, and returns it. Refuses a blank name,
    /// a name of one of the four Ficha comes with, and one another user type
    /// has, ignoring case and accents (`UserType.isSameName(_:as:)`).
    @discardableResult
    public func makeUserType(named name: String, emoji: TagEmoji? = nil) throws(EngineError) -> UserType {
        try write { db in
            let type = UserType(
                id: UUID(), name: try checkedTypeName(name, among: UserTypes(in: db)), emoji: emoji?.text)
            try save(madeTypes: [type], in: db)
            return type
        }
    }

    /// Renames the user type with this ID `name`, without the spaces around
    /// it, and returns it: its cards keep it, by its ID. Refuses a name as
    /// `makeUserType(named:emoji:)` does, but its own, and a type that isn't
    /// there.
    @discardableResult
    public func renameUserType(_ id: UUID, to name: String) throws(EngineError) -> UserType {
        try write { db in
            let types = try UserTypes(in: db)
            let type = try types.existing(id)
            let renamed = UserType(
                id: id, name: try checkedTypeName(name, renaming: id, among: types), emoji: type.emoji)
            try db.execute(
                sql: "UPDATE userType SET name = ? WHERE uuid = ?", arguments: [renamed.name, id.uuidString])
            return renamed
        }
    }

    /// Gives the user type with this ID `emoji`, or takes its emoji away when
    /// it's nil, and returns it. Refuses a type that isn't there.
    @discardableResult
    public func setEmoji(_ emoji: TagEmoji?, ofUserType id: UUID) throws(EngineError) -> UserType {
        try write { db in
            let type = try UserTypes(in: db).existing(id)
            try db.execute(
                sql: "UPDATE userType SET emoji = ? WHERE uuid = ?", arguments: [emoji?.text, id.uuidString])
            return UserType(id: id, name: type.name, emoji: emoji?.text)
        }
    }

    /// Deletes the user type with this ID, if it's there: its cards have no
    /// type then, and keep everything else, and each records the change,
    /// which syncs as an edit to its type.
    public func deleteUserType(_ id: UUID) throws(EngineError) {
        try write { db in
            try db.execute(sql: "DELETE FROM userType WHERE uuid = ?", arguments: [id.uuidString])
            try forgetType(id, in: db)
        }
    }

    /// `name` as the name of a new user type, or of the one with the ID
    /// `renamed`, as `makeUserType(named:emoji:)` and
    /// `renameUserType(_:to:)` take it, without the spaces around it, or an
    /// error when they refuse it, for the Cards window's sheets to say before
    /// OK.
    func checkedUserTypeName(_ name: String, renaming renamed: UUID?) throws(EngineError) -> String {
        try read { db in try checkedTypeName(name, renaming: renamed, among: UserTypes(in: db)) }
    }

    /// How many cards have the user type with this ID, buried ones too, as
    /// the Cards window asks before it deletes the type.
    public func cardCount(ofUserType id: UUID) throws(EngineError) -> Int {
        try read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM card WHERE type = ?", arguments: [id.uuidString]) ?? 0
        }
    }
}

/// Takes the user type with this ID off every card that has it, which then
/// has no type, in the write `db`: as the type is deleted, on this device or
/// on another.
func forgetType(_ id: UUID, in db: Database) throws {
    try db.execute(sql: "UPDATE card SET type = NULL WHERE type = ?", arguments: [id.uuidString])
}

/// The user's types, as the `userType` table keeps them, read at once.
struct UserTypes: Sendable {
    /// Every user type, by its ID.
    private let byID: [UUID: UserType]

    /// The user's types as the `userType` table keeps them now.
    init(in db: Database) throws {
        let types = try Row.fetchAll(db, sql: "SELECT uuid, name, emoji FROM userType").map(UserType.init(row:))
        byID = Dictionary(uniqueKeysWithValues: types.map { ($0.id, $0) })
    }

    /// The user type with this ID, or nil when there's none: it was deleted,
    /// or hasn't come from another device yet.
    func type(_ id: UUID) -> UserType? {
        byID[id]
    }

    /// The user type with this ID, or an error when there's none.
    func existing(_ id: UUID) throws(EngineError) -> UserType {
        guard let type = byID[id] else {
            throw .userTypeNotFound
        }
        return type
    }

    /// Every user type, in alphabetical order as the Mac sorts text, and two
    /// with the same name, as two devices may make offline, by their IDs.
    var sorted: [UserType] {
        byID.values.sorted { type, other in
            switch type.name.localizedStandardCompare(other.name) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: type.id.uuidString < other.id.uuidString
            }
        }
    }
}

/// `name`, without the spaces around it, as the name of a user type among
/// `types`, the one with the ID `renamed` aside, if any: or an error when
/// it's blank, a name of one of the four Ficha comes with, or another user
/// type's, ignoring case and accents (`UserType.isSameName(_:as:)`).
func checkedTypeName(_ name: String, renaming renamed: UUID? = nil, among types: UserTypes) throws(EngineError)
    -> String
{
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
        throw .blankTypeName
    }
    guard !CardType.builtIn.flatMap(\.builtInNames).contains(where: { UserType.isSameName(name, as: $0) }) else {
        throw .builtInTypeName(name)
    }
    if let taken = types.sorted.first(where: { $0.id != renamed && UserType.isSameName(name, as: $0.name) }) {
        throw .typeNameTaken(taken.name)
    }
    return name
}

/// Saves `madeTypes`, user types just made, in the write `db`, as they are.
func save(madeTypes: [UserType], in db: Database) throws {
    for type in madeTypes {
        try db.execute(
            sql: "INSERT INTO userType (uuid, name, emoji) VALUES (?, ?, ?)",
            arguments: [type.id.uuidString, type.name, type.emoji])
    }
}

/// The card types the names a text file of cards or a refine session gives
/// stand for, as an import and the `ficha` CLI read them: one of the four
/// Ficha comes with, by its raw value or its name in the Mac's language,
/// ignoring case; or the user type with that name, ignoring case and
/// accents; or else a new user type with that name and no emoji, which
/// `made` holds, for the write that saves its cards to make too.
struct CardTypesByName {
    /// The user's types, in alphabetical order, and those made, after them.
    private var userTypes: [UserType]
    /// The user types made for names no type had, in the order they were
    /// made.
    private(set) var made: [UserType] = []

    /// The types the user has in `db` now.
    init(in db: Database) throws {
        userTypes = try UserTypes(in: db).sorted
    }

    /// The type `name` stands for, as the struct says, or nil for a blank
    /// name, which is no type. The same name twice stands for the same type,
    /// a new one too.
    mutating func type(named name: String) -> CardType? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return nil
        }
        if let builtIn = CardType.builtIn.first(where: {
            $0.builtInNames.contains { UserType.isSameName(name, as: $0) }
        }) {
            return builtIn
        }
        if let type = userTypes.first(where: { UserType.isSameName(name, as: $0.name) }) {
            return .user(type)
        }
        let type = UserType(id: UUID(), name: name, emoji: nil)
        userTypes.append(type)
        made.append(type)
        return .user(type)
    }

    /// Saves the user types made since it last saved, in the write `db`, as
    /// an import does before each card that has one.
    mutating func saveMade(in db: Database) throws {
        try save(madeTypes: made, in: db)
        made = []
    }
}

extension CardType {
    /// The names a type Ficha comes with goes by: its raw value, and its name
    /// in the Mac's language, as the app's `CardType.name` writes it, whose
    /// keys of the app's String Catalog these are; none for a user type.
    var builtInNames: [String] {
        let name: String? =
            switch self {
            case .word: String(localized: "Word", comment: "A card type.")
            case .concept: String(localized: "Concept", comment: "A card type.")
            case .quote: String(localized: "Quote", comment: "A card type.")
            case .question: String(localized: "Question", comment: "A card type.")
            case .user: nil
            }
        return [builtInName, name].compactMap(\.self)
    }

    /// How a card's type column keeps it: one of the four by its raw value,
    /// and a user type by its ID.
    var column: String {
        switch self {
        case .user(let type): type.id.uuidString
        case .word, .concept, .quote, .question: writtenName
        }
    }

    /// The type a card's type column, `column`, keeps, among `userTypes`, or
    /// nil for a user type the device doesn't hold, which is no type; or an
    /// error for what's neither a raw value nor an ID.
    init?(column: String, among userTypes: UserTypes) throws {
        if let type = CardType.builtIn.first(where: { $0.builtInName == column }) {
            self = type
            return
        }
        guard let id = UUID(uuidString: column) else {
            throw unreadable("A card has an unknown type")
        }
        guard let type = userTypes.type(id) else {
            return nil
        }
        self = .user(type)
    }

    /// Whether it's `other`, whatever their names and emoji now: one of the
    /// four is itself, and a user type the one with its ID, also once
    /// renamed.
    func isSameType(as other: CardType) -> Bool {
        switch (self, other) {
        case (.user(let type), .user(let otherType)): type.id == otherType.id
        default: self == other
        }
    }
}

/// Throws when `type`, a card's, is a user type the device doesn't hold,
/// since it was deleted meanwhile, as on another device, rather than save
/// the card with no type.
func checkExists(_ type: CardType?, in db: Database) throws {
    guard case .user(let userType)? = type else {
        return
    }
    guard
        try Bool.fetchOne(
            db, sql: "SELECT EXISTS (SELECT 1 FROM userType WHERE uuid = ?)", arguments: [userType.id.uuidString])
            == true
    else {
        throw EngineError.userTypeNotFound
    }
}

extension UserType {
    /// A user type read from a row of the `userType` table.
    init(row: Row) throws {
        let uuid: String = try row.decode(forColumn: "uuid")
        guard let id = UUID(uuidString: uuid) else {
            throw unreadable("A card type isn't named by a UUID")
        }
        self.init(id: id, name: try row.decode(forColumn: "name"), emoji: try row.decode(forColumn: "emoji"))
    }
}
