import ArgumentParser
import FichaData

/// `ficha attach`: puts an image or a sound on a side of any card, as a
/// refine session does where Lucas asked for it.
struct AttachCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "attach",
        abstract: "Put an image or a sound on a side of a card, and print the card.",
        discussion: """
            Give the path of a file on your Mac, or the name of an image or a sound Ficha holds, as `ficha cards` \
            prints it, with --front or --back. Ficha tells an image from a sound by the file, shrinks an image, and \
            converts a sound, a video's too, as it comes in, and puts it in place of the side's own. It works on \
            any card, flagged, buried or set aside, which stays where it is. For example:

              ficha attach 7 --back ~/Downloads/coloratura.mp3
            """
    )

    @Argument(help: "The card's id, as `ficha cards` or `ficha inbox` shows it.")
    var cardID: Int64

    @Option(
        help: ArgumentHelp(
            "The image or sound to put on the card's front: a file's path, or a name `ficha cards` prints.",
            valueName: "file"))
    var front: String?

    @Option(
        help: ArgumentHelp(
            "The image or sound to put on the card's back: a file's path, or a name `ficha cards` prints.",
            valueName: "file"))
    var back: String?

    /// The file to put on the card, and the side it goes on, or nil unless
    /// the command gives one file for one side.
    private var file: (file: FileForSide, side: CardSide)? {
        switch (front, back) {
        case (let text?, nil): FileForSide(text).map { ($0, .front) }
        case (nil, let text?): FileForSide(text).map { ($0, .back) }
        case (nil, nil), (.some, .some): nil
        }
    }

    func validate() throws {
        guard file != nil else {
            throw ValidationError(Self.oneFile)
        }
    }

    func run(on engine: Engine) async throws -> any Encodable {
        guard let file else {
            throw ValidationError(Self.oneFile)
        }
        return try await engine.attach(file.file, to: file.side, of: cardID)
    }

    /// What went wrong, and what to do, when the command doesn't give one
    /// file for one side.
    private static let oneFile = """
        `ficha attach` puts one file on one side, and got none or two. Give one, with --front or --back: its path \
        on your Mac, or its name as `ficha cards` prints it.
        """
}

/// `ficha detach`: takes an image or a sound off a side of any card, as a
/// refine session does where Lucas asked for it.
struct DetachCommand: EngineCommand {
    static let configuration = CommandConfiguration(
        commandName: "detach",
        abstract: "Take an image or a sound off a side of a card, and print the card.",
        discussion: """
            Say which side with --front or --back, and what to take off it: image or sound. The side keeps the rest \
            of what it holds, and one that would be left with neither text, an image nor a sound is refused. It \
            works on any card, flagged, buried or set aside, which stays where it is. For example:

              ficha detach 7 --back sound
            """
    )

    @Argument(help: "The card's id, as `ficha cards` or `ficha inbox` shows it.")
    var cardID: Int64

    @Option(help: ArgumentHelp("What to take off the card's front.", valueName: "kind"))
    var front: FileKind?

    @Option(help: ArgumentHelp("What to take off the card's back.", valueName: "kind"))
    var back: FileKind?

    /// What to take off the card, and from which side, or nil unless the
    /// command says it for one side.
    private var file: (kind: FileKind, side: CardSide)? {
        switch (front, back) {
        case (let kind?, nil): (kind, .front)
        case (nil, let kind?): (kind, .back)
        case (nil, nil), (.some, .some): nil
        }
    }

    func validate() throws {
        guard file != nil else {
            throw ValidationError(Self.oneSide)
        }
    }

    func run(on engine: Engine) throws -> any Encodable {
        guard let file else {
            throw ValidationError(Self.oneSide)
        }
        return try engine.detach(file.kind, from: file.side, of: cardID)
    }

    /// What went wrong, and what to do, when the command doesn't say what to
    /// take off one side.
    private static let oneSide = """
        `ficha detach` takes a file off one side, and got none or two. Say which side with --front or --back, and \
        what to take off it: image or sound.
        """
}

extension FileKind: ExpressibleByArgument {}
