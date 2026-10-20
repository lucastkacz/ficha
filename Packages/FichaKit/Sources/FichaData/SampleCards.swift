import FichaCore
import Foundation

/// Ficha Dev's cards, so Lucas and agents can try a change without capturing
/// and refining first: the Mac's debug menu loads them, and so does the
/// iPhone app. They're written by hand, never taken from Lucas's cards, and
/// follow the rules the content guide starts from: Rioplatense Spanish, one
/// idea per card, a one-line front and a back of at most 40 words, and words
/// from other languages explained in Spanish. There are 50, words most of all.
public enum SampleCards {
    /// Loads the sample cards into the engine's database as new cards, each
    /// approved from a capture of its own, the way refining leaves them, so the
    /// inbox stays as it was. Every sample is checked before any is saved, so a
    /// mistake in this file saves none. Loading them again adds them again.
    public static func load(into engine: Engine) throws {
        let samples = try sampleCaptures.map { sample in (sample, try sample.cardContents()) }
        for (sample, cards) in samples {
            // Loaded again, a sample repeats the capture its cards were
            // approved from, so it's a duplicate. Expanding saves it anyway,
            // and approving it adds its cards again, as new ones.
            let capture = try engine.expand(text: sample.text, note: nil, source: sample.source)
            try engine.approve(capture.id, into: cards)
        }
    }

    /// Loads the sample cards as `load(into:)` does, but only into a database
    /// with no cards yet, as the iPhone app does each time it opens: the first
    /// time, and never again once they're there.
    public static func loadIfThereAreNoCards(into engine: Engine) throws {
        guard try engine.cards().isEmpty else {
            return
        }
        try load(into: engine)
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
public enum SampleCardsError: LocalizedError {
    /// A card of the sample capture with this text has a blank front or back.
    case blankSide(capture: String)

    public var errorDescription: String? {
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
    SampleCapture(
        text: "por qué el mar es salado",
        source: nil,
        cards: [
            SampleCard(
                .question,
                front: "¿Por qué el mar es salado?",
                back: """
                    Porque la lluvia disuelve sales de las rocas y los ríos las llevan al mar. El agua se evapora, \
                    pero la sal se queda, y en millones de años se fue acumulando.
                    """,
                tags: ["ciencia"]
            )
        ]
    ),
    SampleCapture(
        text: "ojalá viene del árabe?",
        source: "Un libro de etimología",
        cards: [
            SampleCard(
                .word,
                front: "ojalá",
                back: "Expresa el deseo de que algo pase. Por ejemplo: «Ojalá mañana no llueva, que tenemos el asado».",
                tags: ["lenguaje"]
            ),
            SampleCard(
                .question,
                front: "¿De dónde viene la palabra «ojalá»?",
                back: """
                    Del árabe hispánico «law šá lláh», «si Dios quiere», que el español tomó en los siglos de \
                    al-Ándalus. Cada vez que decís «ojalá», sin saberlo, nombrás a Alá.
                    """,
                tags: ["lenguaje", "historia"]
            ),
        ]
    ),
    SampleCapture(
        text: "efecto Dunning-Kruger",
        source: nil,
        cards: [
            SampleCard(
                .concept,
                front: "El efecto Dunning-Kruger",
                back: """
                    Cuanto menos sabés de un tema, más sobreestimás lo que sabés: te falta justo el saber que \
                    necesitarías para ver tus errores. Como el que vio dos videos y le discute al médico.
                    """,
                tags: ["psicología"]
            )
        ]
    ),
    SampleCapture(
        text: "pienso luego existo",
        source: "Discurso del método",
        cards: [
            SampleCard(
                .quote,
                front: "Pienso, luego existo.",
                back: """
                    René Descartes: podés dudar de todo, menos de que estás dudando, y para dudar tenés que existir. \
                    Es la primera certeza sobre la que construyó su filosofía. Se hizo famosa en latín: «cogito, ergo \
                    sum».
                    """,
                tags: ["filosofía"]
            )
        ]
    ),
    SampleCapture(
        text: "procrastinar",
        source: nil,
        cards: [
            SampleCard(
                .word,
                front: "procrastinar",
                back: """
                    Postergar lo que tendrías que hacer ahora, haciendo en su lugar algo más fácil. Por ejemplo: \
                    «Tenía que estudiar, pero procrastiné toda la tarde ordenando el placard».
                    """,
                tags: ["lenguaje"]
            )
        ]
    ),
    SampleCapture(
        text: "cuántos huesos tenemos",
        source: nil,
        cards: [
            SampleCard(
                .question,
                front: "¿Cuántos huesos tiene un adulto?",
                back: """
                    206. Al nacer tenés unos 300, pero muchos se van soldando entre sí mientras crecés, como los del \
                    cráneo.
                    """,
                tags: ["ciencia"]
            )
        ]
    ),
    SampleCapture(
        text: "sesgo de confirmación",
        source: "Pensar rápido, pensar despacio",
        cards: [
            SampleCard(
                .concept,
                front: "El sesgo de confirmación",
                back: """
                    La tendencia a notar y recordar lo que confirma lo que ya creés, y a pasar por alto lo que lo \
                    contradice. Si creés que los lunes todo sale mal, solo te acordás de los lunes malos.
                    """,
                tags: ["psicología"]
            )
        ]
    ),
    SampleCapture(
        text: "efímero",
        source: nil,
        cards: [
            SampleCard(
                .word,
                front: "efímero",
                back: """
                    Que dura muy poco. Viene del griego: «que dura un día». Por ejemplo: «La fama de ese video fue \
                    efímera: a la semana nadie se acordaba».
                    """,
                tags: ["lenguaje"]
            )
        ]
    ),
    SampleCapture(
        text: "yo soy yo y mi circunstancia",
        source: "Meditaciones del Quijote",
        cards: [
            SampleCard(
                .quote,
                front: "Yo soy yo y mi circunstancia…",
                back: """
                    José Ortega y Gasset: sos vos y también lo que te rodea, tu época, tu lugar y lo que te toca \
                    vivir; no se te puede entender por separado.
                    """,
                tags: ["filosofía"]
            )
        ]
    ),
    SampleCapture(
        text: "inefable",
        source: nil,
        cards: [
            SampleCard(
                .word,
                front: "inefable",
                back: """
                    Tan intenso o tan grande que no se puede explicar con palabras. Por ejemplo: «Ver el glaciar \
                    Perito Moreno de cerca fue algo inefable».
                    """,
                tags: ["lenguaje"]
            )
        ]
    ),
    SampleCapture(
        text: "ley de Parkinson",
        source: "Un artículo sobre productividad",
        cards: [
            SampleCard(
                .concept,
                front: "La ley de Parkinson",
                back: """
                    El trabajo se expande hasta ocupar todo el tiempo disponible: si tenés una semana para un informe, \
                    te lleva una semana; si tenés un día, lo terminás en un día.
                    """,
                tags: ["trabajo"]
            )
        ]
    ),
    SampleCapture(
        text: "planeta más caliente",
        source: "Un documental del espacio",
        cards: [
            SampleCard(
                .question,
                front: "¿Cuál es el planeta más caliente?",
                back: """
                    Venus, aunque Mercurio está más cerca del Sol. Su atmósfera espesa de dióxido de carbono atrapa el \
                    calor como un invernadero, y en la superficie hay unos 460 °C.
                    """,
                tags: ["ciencia"]
            )
        ]
    ),
    SampleCapture(
        text: "resiliencia",
        source: nil,
        cards: [
            SampleCard(
                .word,
                front: "resiliencia",
                back: """
                    La capacidad de recuperarte después de un golpe duro y seguir adelante. Por ejemplo: «Cerró su \
                    negocio, y al año abrió otro: qué resiliencia».
                    """,
                tags: ["lenguaje", "psicología"]
            )
        ]
    ),
    SampleCapture(
        text: "regla del 80/20",
        source: nil,
        cards: [
            SampleCard(
                .concept,
                front: "El principio de Pareto",
                back: """
                    En muchos casos, el 80 % de los resultados sale del 20 % de las causas. Vilfredo Pareto lo notó en \
                    Italia: el 20 % de la gente tenía el 80 % de la tierra.
                    """,
                tags: ["economía"]
            )
        ]
    ),
    SampleCapture(
        text: "hygge",
        source: "Un viaje a Copenhague",
        cards: [
            SampleCard(
                .word,
                front: "hygge",
                back: """
                    Palabra danesa: la sensación de calidez y bienestar de un momento simple y acogedor, en buena \
                    compañía. Por ejemplo: «Llovía afuera, y adentro había velas, mate y amigos: puro hygge».
                    """,
                tags: ["lenguaje"]
            )
        ]
    ),
    SampleCapture(
        text: "lo que no te mata te hace más fuerte",
        source: "Crepúsculo de los ídolos",
        cards: [
            SampleCard(
                .quote,
                front: "Lo que no te mata te hace más fuerte.",
                back: """
                    Friedrich Nietzsche: las dificultades que superás te dejan mejor preparado. Él lo escribió en \
                    primera persona: «lo que no me mata me hace más fuerte».
                    """,
                tags: ["filosofía"]
            )
        ]
    ),
    SampleCapture(
        text: "años bisiestos",
        source: nil,
        cards: [
            SampleCard(
                .question,
                front: "¿Por qué hay años bisiestos?",
                back: """
                    Porque la Tierra tarda unos 365 días y 6 horas en dar la vuelta al Sol. Esas 6 horas, en cuatro \
                    años, suman un día: el 29 de febrero.
                    """,
                tags: ["ciencia"]
            )
        ]
    ),
    SampleCapture(
        text: "saudade",
        source: nil,
        cards: [
            SampleCard(
                .word,
                front: "saudade",
                back: """
                    Palabra portuguesa: la nostalgia, entre dulce y triste, por algo o alguien que ya no está y quizá \
                    no vuelva. Por ejemplo: «Esa canción me da saudade de aquel verano en Brasil».
                    """,
                tags: ["lenguaje"]
            )
        ]
    ),
    SampleCapture(
        text: "efecto placebo",
        source: nil,
        cards: [
            SampleCard(
                .concept,
                front: "El efecto placebo",
                back: """
                    Sentirte mejor solo porque creés que te están curando, aunque lo que tomaste no tenga nada activo, \
                    como una pastilla de azúcar. Por eso un remedio nuevo tiene que ganarle a un placebo.
                    """,
                tags: ["ciencia"]
            )
        ]
    ),
    SampleCapture(
        text: "Zeitgeist",
        source: nil,
        cards: [
            SampleCard(
                .word,
                front: "Zeitgeist",
                back: """
                    Palabra alemana: el espíritu de una época, lo que la gente piensa y siente en un momento dado. \
                    Viene de «Zeit», tiempo, y «Geist», espíritu. Por ejemplo: «Esa película captó el Zeitgeist de los \
                    noventa».
                    """,
                tags: ["lenguaje"]
            )
        ]
    ),
    SampleCapture(
        text: "sangre, sudor y lágrimas",
        source: "Un documental sobre la Segunda Guerra",
        cards: [
            SampleCard(
                .quote,
                front: "Sangre, sudor y lágrimas.",
                back: """
                    Winston Churchill, en 1940, en su primer discurso como primer ministro, en plena guerra: no \
                    prometía una victoria fácil, sino sacrificio. En realidad dijo «sangre, esfuerzo, lágrimas y \
                    sudor»; en inglés, «blood, toil, tears and sweat».
                    """,
                tags: ["historia"]
            )
        ]
    ),
    SampleCapture(
        text: "efecto Streisand",
        source: nil,
        cards: [
            SampleCard(
                .concept,
                front: "El efecto Streisand",
                back: """
                    Intentar esconder algo y conseguir que se difunda más. En 2003, Barbra Streisand demandó para que \
                    quitaran de internet una foto de su casa; casi nadie la había visto, y con el escándalo la vieron \
                    cientos de miles.
                    """,
                tags: ["internet"]
            )
        ]
    ),
    SampleCapture(
        text: "sobremesa",
        source: nil,
        cards: [
            SampleCard(
                .word,
                front: "sobremesa",
                back: """
                    El rato que te quedás en la mesa charlando después de comer. Por ejemplo: «El almuerzo terminó a \
                    las dos, pero la sobremesa siguió hasta las seis».
                    """,
                tags: ["lenguaje"]
            )
        ]
    ),
    SampleCapture(
        text: "caída del Muro de Berlín",
        source: nil,
        cards: [
            SampleCard(
                .question,
                front: "¿En qué año cayó el Muro de Berlín?",
                back: """
                    En 1989, el 9 de noviembre. Un vocero de Alemania del Este anunció por error que se podía cruzar \
                    ya mismo, y esa noche miles de berlineses lo pasaron y empezaron a derribarlo.
                    """,
                tags: ["historia"]
            )
        ]
    ),
    SampleCapture(
        text: "tragedia de los comunes",
        source: "Un curso de economía",
        cards: [
            SampleCard(
                .concept,
                front: "La tragedia de los comunes",
                back: """
                    Cuando un recurso es de todos, a cada uno le conviene usar un poco más, y entre todos lo agotan. \
                    Como un campo compartido donde cada pastor suma una vaca más, hasta que no queda pasto.
                    """,
                tags: ["economía"]
            )
        ]
    ),
    SampleCapture(
        text: "nefelibata",
        source: nil,
        cards: [
            SampleCard(
                .word,
                front: "nefelibata",
                back: """
                    Una persona soñadora, que no tiene los pies en la tierra. Del griego: «el que anda por las nubes». \
                    Por ejemplo: «Es un nefelibata: se pasa el día imaginando viajes que nunca va a hacer».
                    """,
                tags: ["lenguaje"]
            )
        ]
    ),
    SampleCapture(
        text: "el hombre es un lobo para el hombre",
        source: nil,
        cards: [
            SampleCard(
                .quote,
                front: "El hombre es un lobo para el hombre.",
                back: """
                    Thomas Hobbes la hizo famosa: sin leyes ni un Estado que nos frene, nos atacaríamos unos a otros. \
                    Pero es más vieja: viene de una comedia del romano Plauto. En latín, «homo homini lupus».
                    """,
                tags: ["filosofía"]
            )
        ]
    ),
    SampleCapture(
        text: "epifanía",
        source: nil,
        cards: [
            SampleCard(
                .word,
                front: "epifanía",
                back: """
                    El momento en que de golpe entendés algo que tenías adelante. Por ejemplo: «Tuve una epifanía en \
                    la ducha y entendí por qué no me salía el ejercicio».
                    """,
                tags: ["lenguaje"]
            )
        ]
    ),
    SampleCapture(
        text: "quién inventó la imprenta",
        source: nil,
        cards: [
            SampleCard(
                .question,
                front: "¿Quién inventó la imprenta en Europa?",
                back: """
                    Johannes Gutenberg, en Maguncia, hacia 1450. Con letras de metal que se reordenaban para cada \
                    página, los libros dejaron de copiarse a mano.
                    """,
                tags: ["historia"]
            )
        ]
    ),
    SampleCapture(
        text: "efecto mariposa",
        source: nil,
        cards: [
            SampleCard(
                .concept,
                front: "El efecto mariposa",
                back: """
                    En sistemas como el clima, un cambio mínimo puede tener consecuencias enormes más adelante. El \
                    meteorólogo Edward Lorenz lo planteó con una pregunta: ¿el aleteo de una mariposa en Brasil puede \
                    provocar un tornado en Texas?
                    """,
                tags: ["ciencia"]
            )
        ]
    ),
    SampleCapture(
        text: "idiosincrasia",
        source: nil,
        cards: [
            SampleCard(
                .word,
                front: "idiosincrasia",
                back: """
                    La manera de ser propia de una persona o de un pueblo, lo que lo distingue de los demás. Por \
                    ejemplo: «Compartir el mate con desconocidos es parte de nuestra idiosincrasia».
                    """,
                tags: ["lenguaje"]
            )
        ]
    ),
    SampleCapture(
        text: "por qué vemos siempre la misma cara de la luna",
        source: "Una charla de divulgación",
        cards: [
            SampleCard(
                .question,
                front: "¿Por qué vemos siempre la misma cara de la Luna?",
                back: """
                    Porque gira sobre sí misma en el mismo tiempo que tarda en dar la vuelta a la Tierra, unos 27 \
                    días: la gravedad terrestre la fue frenando hasta sincronizarla.
                    """,
                tags: ["ciencia"]
            )
        ]
    ),
    SampleCapture(
        text: "chamuyo",
        source: nil,
        cards: [
            SampleCard(
                .word,
                front: "chamuyo",
                back: """
                    En el habla rioplatense, una charla hábil para convencer o seducir, a veces con mentiras. Por \
                    ejemplo: «No le creas lo del auto nuevo: es puro chamuyo».
                    """,
                tags: ["lenguaje", "argentina"]
            )
        ]
    ),
    // The most tags: the three a card can have.
    SampleCapture(
        text: "sesgo de supervivencia, los aviones de la guerra",
        source: "Un video de estadística",
        cards: [
            SampleCard(
                .concept,
                front: "El sesgo de supervivencia",
                back: """
                    Sacar conclusiones mirando solo los casos que sobrevivieron. En la Segunda Guerra Mundial querían \
                    blindar los aviones donde volvían agujereados; Abraham Wald propuso blindar justo donde no: los \
                    que recibían balas ahí no volvían.
                    """,
                tags: ["psicología", "historia", "estadística"]
            )
        ]
    ),
    SampleCapture(
        text: "ikigai",
        source: nil,
        cards: [
            SampleCard(
                .word,
                front: "ikigai",
                back: """
                    Palabra japonesa: tu razón de ser, lo que hace que valga la pena levantarte cada mañana. Por \
                    ejemplo: «Desde que se jubiló, la huerta es su ikigai».
                    """,
                tags: ["lenguaje"]
            )
        ]
    ),
    SampleCapture(
        text: "síndrome del impostor",
        source: nil,
        cards: [
            SampleCard(
                .concept,
                front: "El síndrome del impostor",
                back: """
                    Sentir que no merecés tus logros y que en cualquier momento van a descubrir que no sos tan capaz, \
                    aunque las pruebas digan lo contrario. Es común en gente que se destaca en lo suyo.
                    """,
                tags: ["psicología"]
            )
        ]
    ),
    SampleCapture(
        text: "nostalgia",
        source: nil,
        cards: [
            SampleCard(
                .word,
                front: "nostalgia",
                back: """
                    La tristeza de extrañar un lugar, una persona o un tiempo pasado. Del griego «nóstos», regreso, y \
                    «álgos», dolor: el dolor de no poder volver. Por ejemplo: «Ver fotos del secundario me da \
                    nostalgia».
                    """,
                tags: ["lenguaje"]
            )
        ]
    ),
]
