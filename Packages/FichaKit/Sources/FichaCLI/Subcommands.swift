import ArgumentParser
import FichaData

/// `ficha set-aside`: sets a card aside, or puts it back, as `ficha deck
/// set-aside` does a deck (ADR 0041). The engine buries the card, as the
/// database keeps a card set aside on its own, and unburies it.
struct SetCardAsideCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-aside",
        abstract: "Set a card aside, or with --off put it back, and print the card.",
        discussion: """
            A card set aside is out of your reviews until you put it back, flagged or not; it keeps its progress, \
            its review log and its flag, with its note, and its deck still lists it. Put back, it goes back to \
            your reviews, or waits in its deck to be fixed when it's flagged, or it stays set aside with its deck \
            while that deck, or a deck it sits inside, is. `ficha deck set-aside` sets a whole deck aside.
            """
    )

    @Argument(help: "The card's id, as `ficha cards` shows it.")
    var cardID: Int64

    @ArgumentParser.Flag(help: "Put it back instead.")
    var off = false

    func run(on engine: Engine) throws -> any Encodable {
        if off {
            return try engine.unbury(cardID)
        }
        return try engine.bury(cardID)
    }
}

/// `ficha cards`: lists the cards.
struct CardsCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "cards",
        abstract: "List your cards, in the order they came in, and whether each goes both ways.",
        discussion: """
            Every card says in "bothWays" whether it goes both ways, coming back first too, its back on top, once \
            you've met it; `ficha add` and `ficha fix` set it. Every card names in "deck" the deck it lives in, by its \
            whole name, as "Idiomas::Inglés", or "" for Default, where a card lives when it has no other deck; \
            `ficha add`, `ficha fix` and `ficha change-deck` set it. A flagged card has your note on what to fix in \
            "flag", one set aside on its own says when you set it aside in "buriedAt", as `ficha set-aside` and the \
            Cards window set it aside, and one set aside with its deck lists in "setAsideBy" the set-aside decks it's \
            set aside by, the outermost first: its own deck, or decks it sits inside, as the Cards window and \
            `ficha deck set-aside` set them aside. A card's "type" is word, concept, quote or question, or a type of \
            your own, by its name. A card leaves out "type" or "source" when it has no type or no source. A card with \
            an image or a sound on its front or back names it in "frontImage", "backImage", "frontSound" or \
            "backSound", left out when that side has none; a side with only an image or a sound has an empty text. \
            `ficha attach` puts one on a side and `ficha detach` takes one off, and `ficha add` and `ficha fix` take \
            them too. A card whose front or back changed since it came in says when it last did in "editedAt": an \
            edit, a fix, a side's image or sound put on or taken off, or an import; a change to its tags, type or \
            source alone doesn't count.
            """
    )

    func run(on engine: Engine) throws -> any Encodable {
        try engine.cards()
    }
}
