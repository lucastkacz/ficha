/*
 * Ficha mock kit: sample decks, small and bite-sized, and made up, never
 * Lucas's. The cards are in Spanish, as his are; a mock's UI is in English,
 * Ficha's base language. Facts here are for a mock, but they should still
 * be right.
 */
(function (root) {
  'use strict';

  const decks = [
    {
      id: 'palabras',
      name: 'Palabras lindas',
      emoji: '💬',
      language: 'Spanish',
      blurb: 'Words worth having: what they mean, in one line.',
      cards: [
        { front: 'serendipia', back: 'Un hallazgo valioso que se da por casualidad, cuando buscabas otra cosa.' },
        { front: 'petricor', back: 'El olor que deja la lluvia al caer sobre la tierra seca.' },
        { front: 'inefable', back: 'Tan intenso o tan hermoso que no se puede explicar con palabras.' },
        { front: 'efímero', back: 'Que dura muy poco.' },
        { front: 'melifluo', back: 'Dulce, suave y delicado, sobre todo al hablar.' },
        { front: 'sempiterno', back: 'Que durará siempre; que no tiene fin.' },
        { front: 'soslayar', back: 'Esquivar una dificultad o una pregunta: pasarla de costado.' },
        { front: 'ataraxia', back: 'Calma del ánimo, sin inquietud ni temor.', source: 'Epicuro y los estoicos' },
        { front: 'epifanía', back: 'Una revelación repentina: cuando de golpe entendés algo.' },
        { front: 'lánguido', back: 'Débil, sin fuerza ni ánimo.' },
        { front: 'dilucidar', back: 'Aclarar y explicar un asunto.' },
        { front: 'acendrado', back: 'Puro, sin mancha ni defecto: un amor acendrado.' },
      ],
    },
    {
      id: 'nubes',
      name: 'Tipos de nubes',
      emoji: '☁️',
      language: 'Spanish',
      blurb: 'The ten kinds of cloud, and how to tell them apart from the ground.',
      cards: [
        { front: 'Cirro', back: 'Nube alta, blanca y fina, en filamentos como mechones de pelo. Hecha de cristales de hielo.', tags: ['altas'] },
        { front: 'Cirrocúmulo', back: 'Nube alta en copitos blancos ordenados en filas: el cielo aborregado.', tags: ['altas'] },
        { front: 'Cirrostrato', back: 'Velo alto, fino y transparente que cubre el cielo. Forma un halo alrededor del Sol o de la Luna.', tags: ['altas'] },
        { front: 'Altocúmulo', back: 'Nube media en bancos de copos blancos o grises, más grandes que los del cirrocúmulo.', tags: ['medias'] },
        { front: 'Altostrato', back: 'Capa media, gris o azulada, que cubre el cielo. El Sol se ve como detrás de un vidrio esmerilado.', tags: ['medias'] },
        { front: 'Nimbostrato', back: 'Capa gris oscura y espesa que trae lluvia o nieve continua durante horas.', tags: ['medias'] },
        { front: 'Estratocúmulo', back: 'Nube baja en masas grises redondeadas, con huecos de cielo entre ellas. La más común.', tags: ['bajas'] },
        { front: 'Estrato', back: 'Capa baja, gris y pareja, como una niebla que no toca el suelo. Puede dar llovizna.', tags: ['bajas'] },
        { front: 'Cúmulo', back: 'Nube de buen tiempo, de base plana y cima blanca como un copo de algodón.', tags: ['bajas'] },
        { front: 'Cumulonimbo', back: 'Nube de tormenta enorme, de base oscura y cima en forma de yunque. Trae chaparrones, rayos y a veces granizo.', tags: ['bajas'] },
      ],
    },
    {
      id: 'ochomiles',
      name: 'Los catorce ochomiles',
      emoji: '🏔️',
      language: 'Spanish',
      blurb: 'Every mountain above 8,000 metres: its height and where it stands.',
      cards: [
        { front: 'Everest', back: '8.849 m. Himalaya, entre Nepal y China. La montaña más alta del mundo.' },
        { front: 'K2', back: '8.611 m. Karakórum, entre Pakistán y China. La segunda más alta.' },
        { front: 'Kangchenjunga', back: '8.586 m. Himalaya, entre Nepal y la India. La tercera más alta.' },
        { front: 'Lhotse', back: '8.516 m. Himalaya, entre Nepal y China, pegada al Everest.' },
        { front: 'Makalu', back: '8.485 m. Himalaya, entre Nepal y China. Una pirámide de cuatro aristas.' },
        { front: 'Cho Oyu', back: '8.188 m. Himalaya, entre Nepal y China.' },
        { front: 'Dhaulagiri', back: '8.167 m. Himalaya, en Nepal. Su nombre quiere decir montaña blanca.' },
        { front: 'Manaslu', back: '8.163 m. Himalaya, en Nepal.' },
        { front: 'Nanga Parbat', back: '8.126 m. Himalaya, en Pakistán. La llaman la montaña asesina.' },
        { front: 'Annapurna', back: '8.091 m. Himalaya, en Nepal. El primer ochomil escalado, en 1950.' },
        { front: 'Gasherbrum I', back: '8.080 m. Karakórum, entre Pakistán y China.' },
        { front: 'Broad Peak', back: '8.051 m. Karakórum, entre Pakistán y China.' },
        { front: 'Gasherbrum II', back: '8.035 m. Karakórum, entre Pakistán y China.' },
        { front: 'Shishapangma', back: '8.027 m. Himalaya, en el Tíbet, China. El más bajo de los catorce.' },
      ],
    },
    {
      id: 'cuadros',
      name: 'Cuadros famosos',
      emoji: '🖼️',
      language: 'Spanish',
      blurb: 'The paintings everyone has seen: who painted them, when, and where they hang.',
      cards: [
        { front: 'La Gioconda', back: 'Leonardo da Vinci, hacia 1503–1519. Museo del Louvre, París.' },
        { front: 'La noche estrellada', back: 'Vincent van Gogh, 1889, desde su ventana en Saint-Rémy. MoMA, Nueva York.' },
        { front: 'Las meninas', back: 'Diego Velázquez, 1656. Museo del Prado, Madrid.' },
        { front: 'El grito', back: 'Edvard Munch, 1893. Museo Nacional de Oslo.' },
        { front: 'La joven de la perla', back: 'Johannes Vermeer, hacia 1665. Mauritshuis, La Haya.' },
        { front: 'Guernica', back: 'Pablo Picasso, 1937. Museo Reina Sofía, Madrid.' },
        { front: 'El nacimiento de Venus', back: 'Sandro Botticelli, hacia 1485. Galería Uffizi, Florencia.' },
        { front: 'La persistencia de la memoria', back: 'Salvador Dalí, 1931: los relojes blandos. MoMA, Nueva York.' },
        { front: 'El jardín de las delicias', back: 'El Bosco, hacia 1490–1510. Museo del Prado, Madrid.' },
        { front: 'La ronda de noche', back: 'Rembrandt, 1642. Rijksmuseum, Ámsterdam.' },
        { front: 'Impresión, sol naciente', back: 'Claude Monet, 1872. Le dio su nombre al impresionismo. Museo Marmottan Monet, París.' },
        { front: 'El beso', back: 'Gustav Klimt, 1907–1908. Belvedere, Viena.' },
      ],
    },
  ];

  root.FichaDecks = decks;
})(typeof window !== 'undefined' ? window : globalThis);
