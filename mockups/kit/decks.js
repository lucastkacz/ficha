/*
 * Ficha mock kit: sample decks, small and made up, never Lucas's. Facts here
 * are for a mock, but they should still be right.
 *
 * Four stand for Ficha's decks, which come inside the app, in English
 * (ADR 0035, #458): `ficha: true`, and the Welcome page offers them. Which
 * decks ship, and each card, is Lucas's to approve; these are examples.
 * One stands for a deck of the user's own, from an Anki file, in Spanish,
 * as Lucas's cards are: cards are the user's, in any language (ADR 0036).
 */
(function (root) {
  'use strict';

  const decks = [
    {
      id: 'clouds',
      name: 'Types of clouds',
      emoji: '☁️',
      ficha: true,
      blurb: 'The ten kinds of cloud and four more you can spot, and how to tell them apart from the ground.',
      cards: [
        { front: 'Cirrus', back: 'High, thin and white, in wisps like strands of hair. Made of ice crystals.', tags: ['high'] },
        { front: 'Cirrocumulus', back: 'High, in tiny white puffs set in rows: a mackerel sky.', tags: ['high'] },
        { front: 'Cirrostratus', back: 'A thin, high veil over the whole sky. It draws a halo around the Sun or the Moon.', tags: ['high'] },
        { front: 'Altocumulus', back: 'Mid-level patches of white or grey puffs, larger than cirrocumulus.', tags: ['middle'] },
        { front: 'Altostratus', back: 'A grey or bluish mid-level sheet. The Sun shows as through frosted glass.', tags: ['middle'] },
        { front: 'Nimbostratus', back: 'A thick, dark grey layer that brings steady rain or snow for hours.', tags: ['middle'] },
        { front: 'Stratocumulus', back: 'Low, lumpy grey masses with gaps of sky between them. The most common cloud.', tags: ['low'] },
        { front: 'Stratus', back: 'A low, even grey layer, like fog that doesn\'t touch the ground. It can drizzle.', tags: ['low'] },
        { front: 'Cumulus', back: 'A fair-weather cloud: a flat base and a white, cotton-like top.', tags: ['low'] },
        { front: 'Cumulonimbus', back: 'A towering storm cloud with an anvil top. Brings downpours, lightning and sometimes hail.', tags: ['low'] },
        { front: 'Fog', back: 'A stratus cloud that touches the ground.', tags: ['more'] },
        { front: 'Lenticular cloud', back: 'A smooth, lens-shaped cloud that sits still over or beside a mountain.', tags: ['more'] },
        { front: 'Mammatus', back: 'Pouches hanging under the anvil of a cumulonimbus.', tags: ['more'] },
        { front: 'Contrail', back: 'A line of cloud behind a plane, from the water vapour in its exhaust.', tags: ['more'] },
      ],
    },
    {
      id: 'mountains',
      name: 'The 14 eight-thousanders',
      emoji: '🏔️',
      ficha: true,
      blurb: 'Every mountain above 8,000 metres: its height and where it stands.',
      cards: [
        { front: 'Everest', back: '8,849 m. Himalaya, between Nepal and China. The highest of all.' },
        { front: 'K2', back: '8,611 m. Karakoram, between Pakistan and China. The second highest.' },
        { front: 'Kangchenjunga', back: '8,586 m. Himalaya, between Nepal and India. The third highest.' },
        { front: 'Lhotse', back: '8,516 m. Himalaya, between Nepal and China, joined to Everest.' },
        { front: 'Makalu', back: '8,485 m. Himalaya, between Nepal and China. A pyramid with four ridges.' },
        { front: 'Cho Oyu', back: '8,188 m. Himalaya, between Nepal and China.' },
        { front: 'Dhaulagiri', back: '8,167 m. Himalaya, in Nepal. Its name means white mountain.' },
        { front: 'Manaslu', back: '8,163 m. Himalaya, in Nepal.' },
        { front: 'Nanga Parbat', back: '8,126 m. Himalaya, in Pakistan. Called the killer mountain.' },
        { front: 'Annapurna', back: '8,091 m. Himalaya, in Nepal. The first eight-thousander climbed, in 1950.' },
        { front: 'Gasherbrum I', back: '8,080 m. Karakoram, between Pakistan and China.' },
        { front: 'Broad Peak', back: '8,051 m. Karakoram, between Pakistan and China.' },
        { front: 'Gasherbrum II', back: '8,035 m. Karakoram, between Pakistan and China.' },
        { front: 'Shishapangma', back: '8,027 m. Himalaya, in Tibet, China. The lowest of the fourteen.' },
      ],
    },
    {
      id: 'paintings',
      name: 'Famous paintings',
      emoji: '🖼️',
      ficha: true,
      blurb: 'The paintings everyone has seen: who painted them, when, and where they hang.',
      cards: [
        { front: 'Mona Lisa', back: 'Leonardo da Vinci, about 1503–1519. The Louvre, Paris.' },
        { front: 'The Starry Night', back: 'Vincent van Gogh, 1889, from his window at Saint-Rémy. MoMA, New York.' },
        { front: 'Las Meninas', back: 'Diego Velázquez, 1656. The Prado, Madrid.' },
        { front: 'The Scream', back: 'Edvard Munch, 1893. The National Museum, Oslo.' },
        { front: 'Girl with a Pearl Earring', back: 'Johannes Vermeer, about 1665. The Mauritshuis, The Hague.' },
        { front: 'Guernica', back: 'Pablo Picasso, 1937. The Reina Sofía, Madrid.' },
        { front: 'The Birth of Venus', back: 'Sandro Botticelli, about 1485. The Uffizi, Florence.' },
        { front: 'The Persistence of Memory', back: 'Salvador Dalí, 1931: the melting clocks. MoMA, New York.' },
        { front: 'The Garden of Earthly Delights', back: 'Hieronymus Bosch, about 1490–1510. The Prado, Madrid.' },
        { front: 'The Night Watch', back: 'Rembrandt, 1642. The Rijksmuseum, Amsterdam.' },
        { front: 'Impression, Sunrise', back: 'Claude Monet, 1872. It gave Impressionism its name. Musée Marmottan Monet, Paris.' },
        { front: 'The Kiss', back: 'Gustav Klimt, 1907–1908. The Belvedere, Vienna.' },
        { front: 'The Great Wave off Kanagawa', back: 'Katsushika Hokusai, about 1831. A woodblock print: its copies hang in many museums.' },
        { front: 'American Gothic', back: 'Grant Wood, 1930. The Art Institute of Chicago.' },
      ],
    },
    {
      id: 'words',
      name: 'Beautiful words',
      emoji: '💬',
      ficha: true,
      blurb: 'Words worth having: what they mean, in one line.',
      cards: [
        { front: 'serendipity', back: 'Finding something good by chance, while looking for something else.' },
        { front: 'petrichor', back: 'The smell of rain falling on dry earth.' },
        { front: 'ineffable', back: 'Too great or too beautiful to be put into words.' },
        { front: 'ephemeral', back: 'Lasting a very short time.' },
        { front: 'mellifluous', back: 'Sweet and smooth to hear.' },
        { front: 'halcyon', back: 'Calm, happy and peaceful, said of a time now past: halcyon days.' },
        { front: 'epiphany', back: 'A sudden moment when you understand something.' },
        { front: 'languid', back: 'Slow and relaxed, without energy.' },
        { front: 'susurrus', back: 'A soft whispering or rustling sound.' },
        { front: 'sonorous', back: 'Deep and full in sound.' },
        { front: 'quintessential', back: 'The most perfect example of its kind.' },
        { front: 'effervescent', back: 'Bubbly; lively and full of enthusiasm.' },
        { front: 'luminous', back: 'Giving off light; bright, glowing.' },
        { front: 'sempiternal', back: 'Lasting forever; without end.' },
      ],
    },
    {
      id: 'palabras',
      name: 'Palabras lindas',
      emoji: '🗂️',
      ficha: false,
      file: 'Palabras lindas.apkg',
      blurb: 'A deck of the user\'s own, from an Anki file.',
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
  ];

  root.FichaDecks = decks;
})(typeof window !== 'undefined' ? window : globalThis);
