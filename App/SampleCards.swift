import FichaCore
import FichaData
import Foundation

/// The cards Ficha Dev's debug menu loads, so Lucas and agents can try a change
/// without capturing and refining first. They're written by hand, never taken
/// from Lucas's cards, and follow the rules the content guide starts from:
/// Rioplatense Spanish, one idea per card, a one-line front and a back of at
/// most 40 words, and words from other languages explained in Spanish. There
/// are three of each type.
enum SampleCards {
    /// Loads the sample cards into the engine's database as new cards, each
    /// approved from a capture of its own, the way refining leaves them, so the
    /// inbox stays as it was. Every sample is checked before any is saved, so a
    /// mistake in this file saves none. Loading them again adds them again.
    static func load(into engine: Engine) throws {
        let samples = try sampleCaptures.map { sample in (sample, try sample.cardContents()) }
        for (sample, cards) in samples {
            let capture = try engine.capture(text: sample.text, note: nil, source: sample.source)
            try engine.approve(capture.id, into: cards)
        }
    }
}

/// A capture, as Lucas might have jotted it down, and the cards it was approved
/// into, which take its source.
private struct SampleCapture {
    let text: String
    let source: String?
    let cards: [SampleCard]

    /// Its cards as the engine takes them, with its source.
    func cardContents() throws(SampleCardsError) -> [CardContent] {
        try cards.map { card throws(SampleCardsError) in
            guard let content = card.content(source: source) else {
                throw .blankSide(capture: text)
            }
            return content
        }
    }
}

/// A card a sample capture was approved into.
private struct SampleCard {
    let type: CardType
    let front: String
    let back: String
    let tags: [String]

    init(_ type: CardType, front: String, back: String, tags: [String]) {
        self.type = type
        self.front = front
        self.back = back
        self.tags = tags
    }

    /// The card as the engine takes it, with its capture's source, or nil when
    /// its front or back is blank.
    func content(source: String?) -> CardContent? {
        CardContent(type: type, front: front, back: back, tags: tags, source: source)
    }
}

/// A sample card written wrong in this file, so it can't be loaded.
enum SampleCardsError: LocalizedError {
    /// A card of the sample capture with this text has a blank front or back.
    case blankSide(capture: String)

    var errorDescription: String? {
        switch self {
        case .blankSide(let capture):
            "A sample card of “\(capture)” has a blank front or back: complete it in SampleCards.swift."
        }
    }
}

/// The sample captures, in the order they're approved, which is the order
/// their cards come in as new cards: the types take turns.
private let sampleCaptures = [
    SampleCapture(
        text: "serendipia",
        source: "Un podcast de etimología",
        cards: [
            SampleCard(
                .word,
                front: "serendipia",
                back: "Un hallazgo valioso que se da por casualidad, cuando estabas buscando otra cosa.",
                tags: ["lenguaje"]
            ),
            SampleCard(
                .question,
                front: "¿De dónde viene la palabra «serendipia»?",
                back: """
                    De «Los tres príncipes de Serendip», un cuento persa: Horace Walpole inventó la palabra inglesa \
                    en 1754, y el español la tomó de ahí.
                    """,
                tags: ["lenguaje", "historia"]
            ),
        ]
    ),
    SampleCapture(
        text: "ubuntu",
        source: nil,
        cards: [
            SampleCard(
                .concept,
                front: "ubuntu",
                back: """
                    Una idea de los pueblos bantúes del sur de África: una persona es persona a través de las demás. \
                    Se suele resumir como «soy porque somos».
                    """,
                tags: ["filosofía"]
            )
        ]
    ),
    SampleCapture(
        text: "Caminante, no hay camino",
        source: "Campos de Castilla",
        cards: [
            SampleCard(
                .quote,
                front: "Caminante, no hay camino, se hace camino al andar.",
                back: """
                    Antonio Machado, en «Campos de Castilla»: el camino no está trazado de antemano; lo vas haciendo \
                    vos, con cada paso.
                    """,
                tags: ["literatura"]
            )
        ]
    ),
    SampleCapture(
        text: "¿Por qué el cielo es azul?",
        source: "Una charla de divulgación",
        cards: [
            SampleCard(
                .question,
                front: "¿Por qué el cielo es azul?",
                back: """
                    Porque el aire dispersa mucho más la luz azul, de longitud de onda corta, que la roja, y esa luz \
                    dispersada te llega desde todo el cielo. Se llama dispersión de Rayleigh.
                    """,
                tags: ["ciencia"]
            )
        ]
    ),
    SampleCapture(
        text: "Schadenfreude",
        source: nil,
        cards: [
            SampleCard(
                .word,
                front: "Schadenfreude",
                back: """
                    Palabra alemana: la alegría por la desgracia ajena. Viene de «Schaden», daño, y «Freude», \
                    alegría.
                    """,
                tags: ["lenguaje"]
            )
        ]
    ),
    // The longest back: the 40 words a back can have.
    SampleCapture(
        text: "navaja de Ockham",
        source: nil,
        cards: [
            SampleCard(
                .concept,
                front: "La navaja de Ockham",
                back: """
                    Entre dos explicaciones que dan cuenta de lo mismo, conviene preferir la que necesita menos \
                    supuestos. Se atribuye a Guillermo de Ockham, un fraile franciscano inglés del siglo XIV, aunque \
                    la idea es más antigua: ya la había planteado Aristóteles.
                    """,
                tags: ["filosofía"]
            )
        ]
    ),
    SampleCapture(
        text: "Lo esencial es invisible a los ojos",
        source: "El principito",
        cards: [
            SampleCard(
                .quote,
                front: "Lo esencial es invisible a los ojos.",
                back: """
                    Se lo dice el zorro al principito, en el libro de Antoine de Saint-Exupéry: lo que más importa no \
                    se ve con los ojos, sino con el corazón.
                    """,
                tags: ["literatura"]
            )
        ]
    ),
    SampleCapture(
        text: "cuándo llegamos a la Luna",
        source: nil,
        cards: [
            SampleCard(
                .question,
                front: "¿En qué año llegó el ser humano a la Luna?",
                back: """
                    En 1969, con el Apolo 11. El 20 de julio, Neil Armstrong fue el primero en pisarla, y Buzz Aldrin \
                    lo siguió poco después.
                    """,
                tags: ["historia"]
            )
        ]
    ),
    // A card without tags.
    SampleCapture(
        text: "petricor",
        source: nil,
        cards: [
            SampleCard(
                .word,
                front: "petricor",
                back: "El olor que deja la lluvia al caer sobre la tierra seca.",
                tags: []
            )
        ]
    ),
    SampleCapture(
        text: "costo hundido",
        source: "Pensar rápido, pensar despacio",
        cards: [
            SampleCard(
                .concept,
                front: "La falacia del costo hundido",
                back: """
                    Seguir con algo solo por lo que ya invertiste, aunque no te convenga. Lo gastado no vuelve: para \
                    decidir, mirá lo que viene.
                    """,
                tags: ["psicología"]
            )
        ]
    ),
    SampleCapture(
        text: "Solo sé que no sé nada",
        source: nil,
        cards: [
            SampleCard(
                .quote,
                front: "Solo sé que no sé nada.",
                back: """
                    Se le atribuye a Sócrates, a partir de la «Apología» de Platón: reconocer lo que no sabés es el \
                    primer paso para aprender.
                    """,
                tags: ["filosofía"]
            )
        ]
    ),
]
