# El mercado de Ficha: investigación de #452

Investigado el 5 y 6 de noviembre de 2026 por 30 subagentes, sobre Anki, sus alternativas, quién paga y cómo se vende esto. Comparar con Ficha y sacar conclusiones lo hizo la sesión que los lanzó. Lo crudo está en [`market/`](market/README.md), un archivo por ángulo, con todos los links, y los bloqueos en [`market/blockers.md`](market/blockers.md).

## En corto

**¿Vale la pena hacerla y venderla?** Terminarla y venderla barata, sí. Vivir de esto, la evidencia no lo sostiene. Hay un hueco real y ya tenés casi todo el costo pagado, pero pocos la piden, nadie que siga con Anki pide una segunda app, y lo que decide todo nunca se midió: si alguien con sus propias tarjetas las deja llegar más de 3 semanas y recuerda más por eso. Tu beta con amigos (#359) puede ser la primera medición. [Parte 4](#4-vale-la-pena-hacerla-y-venderla).

**El hueco.** Ninguna app oficial de Anki muestra o responde una tarjeta afuera de la app, y en la Mac, con Anki cerrado, lo único gratis que apareció es la versión limitada de NotchWise, 1 mazo y 50 tarjetas (informes 01, 24, 30). Ninguna app grande de estudio lo promete; Vocabulary sí, con palabras puestas por ella. Lo cubren apps chicas: en la Mac, NotchWise y PopCards.

**"Complemento de Anki" (#450).** Como frase honesta, se sostiene. Como punto principal de venta, no: no encontré a nadie que siga con Anki y pida una segunda app más liviana, r/Anki saca las apps sueltas, y Apple cierra a "Anki" el nombre, el subtítulo y las keywords. [Parte 5](#5-el-punto-principal-de-venta).

**Lo que te propongo vender:** "las tarjetas vienen a vos, no te sentás a estudiar", con "nunca en una reunión" como prueba, y "no reemplaza a Anki" como frase de honestidad.

**El comprador quizá no esté en Anki** (inferencia, sin probar): adultos que quieren recordar pocas cosas, aunque quien aprende por gusto paga poco, y gente que paga $35–60 por año por apps de palabras y se enoja con los cobros. A esos les falta lo que Ficha no tiene: **tarjetas para empezar**. Es la mayor falta que encontré, y no está entre tus 5. [Parte 3](#3-lo-que-le-falta-a-ficha).

**Precio.** $1.99 queda en el piso: a ese precio o menos solo aparecen Word Drop y RecallPrompt. Las que muestran tarjetas en la Mac cobran $9.99 y $19.99 una vez. Te propongo debatir bajarla gratis con límite y un solo pago de unos $9.99. [Parte 6](#6-cómo-venderla).

**Una palabra a sacar:** "frictionless" es de la industria, no de la gente. La gente dice *pile*, *backlog*, *chore*, *too heavy*, *a few minutes*.

## Cómo leer esto

- **En una sentada:** "En corto" y las partes 3 a 6. Las partes 1 y 2 y el anexo son de consulta, y más densos.
- **Qué es cada cosa:** "dice la gente" son personas, "dice la app" es su propia web o tienda, e "inferencia" es una conclusión de un subagente o mía.
- **Las cuentas son aproximadas:** las leyó un modelo que resume, sobre muestras chicas y a menudo elegidas por búsqueda. Una cuenta alta dice "esto aparece", no "este porcentaje de usuarios".
- **Lo que quedó mal leído:** Reddit, por un archivo y con huecos. Student Doctor Network, solo por extractos. Google Play, nada. YouTube, sin comentarios ni la mayoría de las transcripciones.
- **Las citas son pocas:** varios subagentes se limitaron a una cita textual por informe, así que casi todo está parafraseado. Los originales están en los links.
- **Fuentes viejas:** lo de más de dos años lleva "[viejo, año]".

**Lo que la verificación (informe 30) corrigió, y pisa lo que digan las tablas de abajo:**

| Afirmación | Veredicto | Lo que queda en pie |
|---|---|---|
| Hay poca demanda de repasar en ratos sueltos | Se sostiene con límites | Pocos lo piden, y 1–3% es lo que saca cualquier falta en reseñas. La demanda **no se probó**, ni alta ni baja |
| Nadie que siga con Anki pide una segunda app liviana | Se sostiene con límites | Nadie la pide, pero sí hay gente con dos herramientas, sobre todo estudiantes de japonés que pagan contenido |
| "Anki pero simple" y las flashcards fracasan en Hacker News | **Débil** | Las flashcards sacan casi lo que cualquier Show HN: mediana 2 contra 3, y ~14% pasa de 10 en los dos. Un lanzamiento no dice nada de ventas |
| La pila es la queja número uno y el motivo número uno para irse | Se sostiene con límites | Es la queja número uno de los que siguen. Que sea el motivo para irse no está mostrado |
| AnkiMobile fue #4 paga en iPhone en EE.UU., 2025 | Se sostiene | Es por unidades, y entre apps pagas por adelantado. Cliente cautivo: quizá $0.5–2M brutos por año |
| Las nuevas suscripciones ganan ~$72 al mes | Se sostiene con límites | Lo publica quien vende suscripciones, y no incluye apps pagas |
| La gente paga contenido, no una app sola | Se sostiene con límites | La plata grande sigue a contenido, exámenes o IA. Las apps solas ganan poco, por un dispositivo, sync o sin tope |
| La privacidad no vende | **Débil** | Ente Photos vende por eso. En flashcards nadie la probó: es una incógnita, no un veredicto |
| No hay evidencia de uso más allá de 3 semanas | Se sostiene con límites | Hay uso largo con palabras (rachas de 300–665 días), sin medir memoria. Nada con tarjetas propias durante el trabajo |
| Solo NotchWise combina FSRS y tarjetas que aparecen solas en la Mac | Se sostiene con límites | También está PopCards, $9.99. En iPhone hay muchas |
| Apple cierra el nombre "Anki" | Se sostiene | Nombre, subtítulo y keywords, salvo aprobación. No soy abogado: es lectura, no consejo legal |
| AnkiHub tomó Anki en febrero de 2026 | Se sostiene | "Está tomando": el traspaso es gradual, y hace nueve meses que no se publica cómo se va a gobernar |

**Errores de datos que siguen en los crudos:**
- El "$406k MRR" del informe 27 es en realidad **$43**.
- Las valoraciones mezclan países sin avisar. Las de AlgoApp, Noji y AnkiMobile de la parte 2 son de EE.UU.; en el mundo son 93K, 52K y 9.1K. La misma app aparece con números distintos: Swiftflip tiene 8, 3 o ninguna, según el informe.
- Los ingresos de los trackers no coinciden, por 16 veces o más: no confíes en ninguno, tampoco en los $139M de Quizlet ni en los $75K por mes de AnkiMobile.
- Las reseñas plantadas no se filtraron: el informe 09 marca campañas (Medcof, Noji en México), y ninguna cuenta las descarta.

## 1. El panorama general

**En limpio.** A la gente le gusta que funcione, pagar una vez y que alguien le dé el contenido armado, que es por lo que más paga. Le molesta sobre todo la pila de tarjetas después de unos días sin repasar, que se vuelva una obligación, tener que hacer las tarjetas, que AnkiMobile cueste caro y tenga menos que lo gratis, lo difícil que es arrancar, y los cobros sorpresa de las suscripciones. Pide menos carga y una forma de volver después de un corte, una interfaz moderna con guía, y notificaciones que anden. Que la tarjeta llegue sola lo piden pocos, y eso todavía no dice si la querrían. Las tablas son el detalle, en formato corto.

Compilado de los informes 02 a 12 y 22 de #452.

**Cómo leerlo.** Sin marca, es *dice la gente*. *Dice la app*: la web o tienda de una app, o alguien que vende. *Inferencia*: conclusión del informe; el orden de las tablas también lo es. "(vende)": la fuente gana con eso. Números como en los informes (punto decimal, coma de miles), casi todos aproximados: los leyó un modelo que resume. No sumé fuentes distintas. Los links de reddit.com salen del archivo Arctic Shift, armados con IDs y sin abrir ("archivo"). Student Doctor Network (SDN): solo extractos de búsqueda, segunda mano. YouTube: transcripciones y resúmenes, ningún comentario. Google Play: ninguna reseña.

### 1. Lo que la gente valora

| Hallazgo | Quién | Evidencia | Fuerza | Informes, links |
|---|---|---|---|---|
| Funciona: exámenes, idiomas, carrera | Usuarios de Anki, medicina primero | ~20 comentarios en 2 hilos de HN; ~20 en r/Anki; gana 3 de 3 hilos de recomendación; 87.8% de alumnos de medicina de una escuela cree que ayudó | Fuerte: en todos lados, pero autopercibido (ver "Dónde se contradicen") | 02, 03, 12, 22. [HN 2025-05](https://news.ycombinator.com/item?id=44020591), [r/Anki 2026-09-30, archivo](https://www.reddit.com/r/Anki/comments/1wukk2a/) |
| Estructura y contenido listos: por eso pagan | Idiomas, Corea, medicina | Bunpro 15 personas; WaniKani 11 [viejo, 2023]; MalhaeVoca ~$35M (dice la app, Sensor Tower vende datos) | Fuerte: varios grupos; los foros eligen a quien pagó | 03, 04, 09, 11. [Bunpro 2026-04](https://community.bunpro.jp/t/is-bunpro-really-worth-it/184093) |
| Pagar una vez | AnkiMobile, ReWord, r/macapps | ~8 comentarios en r/Anki; 49 a favor de ~130 reseñas que nombran el precio; ReWord ~11 de 50; bajo $10, 0 quejas en 3 hilos | Fuerte: varios idiomas; a $30–60 ya hay quejas | 04, 06, 10, 12, 22. [r/Anki 2026-08-27, archivo](https://www.reddit.com/r/Anki/comments/1w0aipr/) |
| Gratis, abierto, offline, datos tuyos | HN, r/Anki | ~15 de ~170 comentarios en HN 2026; 0–3 en 2024; ~10 en r/Anki | Media: aparece cuando parece amenazado (inferencia) | 02, 12, 22. [HN 2026-02](https://news.ycombinator.com/item?id=46861313) |
| Control: add-ons, mazos, editar | Medicina, idiomas | ~15 comentarios en HN; quienes se quedan en un hilo de 13 personas | Media: usuarios avanzados | 02, 04, 12. [Bunpro 2025](https://community.bunpro.jp/t/ditching-anki-for-bunpro/129970) |
| Simple, lindo, sin avisos | Mochi, Brainscape, China | Mochi "mejor que Anki" ~5 de 49; look Onigiri puntaje 654; sin ads 3 de 50 en 2 apps chinas (quizá incentivadas) | Media: el puntaje puede premiar capturas | 06, 11, 12. [r/Anki 2025-10-12, archivo](https://www.reddit.com/r/Anki/comments/1o4pr8e/) |
| FSRS | Usuarios avanzados | ~10 menciones; issue con 69 reacciones | Media: una prueba con ~8,900 usuarios no vio mejora | 02, 07, 10. [#3616, sin fecha](https://github.com/ankitects/anki/issues/3616) |
| Ratos sueltos: cola, colectivo, baño | Idiomas, medicina, general | 7 de 18 en WaniKani [viejo, 2021]; Abdaal y Sung a favor, los 2 videos que lo tocan | Media: siempre una sesión que abre el usuario | 02, 03, 04, 07, 12. [HN 2024-12](https://news.ycombinator.com/item?id=42452527) |
| Hábito que devuelve lo viejo | Readwise | ~29 de 76 | Débil: casi una sola app | 06. [Feed, leído 2026-11-05](https://itunes.apple.com/us/rss/customerreviews/id=1476885528/sortby=mostrecent/json) |

### 2. Lo que le molesta y por qué se va

| Hallazgo | Quién | Evidencia | Fuerza | Informes, links |
|---|---|---|---|---|
| Pila tras días perdidos, carga diaria | Todos; peor en medicina | HN ~57 menciones, 27%; r/Anki ~33 de 54 posts; idiomas ~8 hilos; medicina ~12 menciones; 5 de 8 videos | Fuerte: todo grupo y método; los veteranos culpan al exceso de nuevas | 02–05, 07, 09, 12, 22. [r/Anki 2026-03-05, archivo](https://www.reddit.com/r/Anki/comments/1rld04r/) |
| Tedio, obligación | Todos | HN ~50, 23%; 5 de 9 hilos de otros subs | Fuerte: va junto con la pila | 02, 05, 12, 22. [r/languagelearning 2025-04, archivo](https://www.reddit.com/r/languagelearning/comments/1k4up52/) |
| Hacer tarjetas | Quien hace las suyas | HN ~38, 18%; 6 de 34 salidas; idiomas ~5 hilos; 4 de 9 hilos | Fuerte: otros dicen que escribirlas es lo que enseña | 02, 04, 05, 09, 11, 12, 22. [HN 2026-02](https://news.ycombinator.com/item?id=46861313) |
| AnkiMobile: paga y tiene menos que lo gratis | Compradores iOS | EE.UU. ~56 de 172 bajas; alemán ~18 de 50; francés ~14; chino 12; coreano 9 | Fuerte en tiendas; escriben los enojados | 06, 09, 10, 11. [Feed EE.UU., leído 2026-11-05](https://itunes.apple.com/us/rss/customerreviews/id=373493387/sortby=mostrecent/json) |
| Interfaz y arranque | Principiantes | HN ~34 más ~24 de instalación; AnkiMobile ~64 de 172; listas ~17 de 31 (rivales) | Fuerte: sobre todo al empezar | 02, 04, 06, 08, 10, 11. [Foro 2024](https://forums.ankiweb.net/t/revisiting-onboarding-decks-and-tutorials/43692) [viejo, 2024] |
| Paywall, cobro sorpresa, gratis recortado | Quizlet, Knowt, Vocabulary, Corea | Vocabulary 31 y 21 de 116 bajas; Knowt ~13 y ~12 de 43; 암기고래 ~21 de 50; Quizlet Trustpilot 1.4 de 664 | Fuerte: muchas apps y países | 06, 08, 09, 10, 11. [Feed Vocabulary, leído 2026-11-05](https://itunes.apple.com/us/rss/customerreviews/id=1084540807/sortby=mostrecent/json) |
| No pasa al uso real | Idiomas, medicina | 9 de 34 salidas, la primera; 5 de 8 videos; 3 de 9 hilos | Media: varios críticos venden otra cosa | 02, 03, 04, 07, 22. [Ensayo 2025-08 (promociona lo suyo)](https://miguelconner.substack.com/p/anki-is-already-dead) |
| Prefieren lectura o bancos de preguntas | Idiomas, medicina | 11 de ~20 dejaron sin arrepentirse; ~13 de 19; medicina ~15 de 20 | Media: esos hilos atraen a los que ya piensan así | 03, 04, 05, 22. [r/medicalschool 2026-03-27, archivo](https://www.reddit.com/r/medicalschool/comments/1s56n8u/) |
| Terminó la meta | Exámenes | r/Anki ~3 de ~16; Step 1 aprobado/reprobado ~4 [viejo, 2019–23] | Media: no es fracaso | 02, 03, 05, 12. [r/Anki 2026-04-07, archivo](https://www.reddit.com/r/Anki/comments/1sej46k/) |
| "No necesito memorizar" | No usuarios | 7 de 24 [viejo, 2020]; ~10 en 2026 | Media: casi solo HN | 05, 10. [HN 2026-01](https://news.ycombinator.com/item?id=46465493) |
| Fallas, sync, datos perdidos | AnkiMobile, Mac, Noji | Sync ~36; Mac ~7 de 24; Noji España ~17 de 50 | Media: picos puntuales | 06, 09, 12. [r/Anki, set.–nov. 2026, archivo](https://www.reddit.com/r/Anki/comments/1xanxx7/) |
| Avisos: no llegan o sobran | Android, iOS, Vocabulary | ~12 posts de que fallan; Vocabulary ~10 de 200 demasiados | Media | 02, 04, 06, 12. [r/Anki 2025-12-05, archivo](https://www.reddit.com/r/Anki/comments/1penp8r/) |

### 3. Lo que pide

| Hallazgo | Quién | Evidencia | Fuerza | Informes, links |
|---|---|---|---|---|
| Menos carga, volver tras un corte | Todos | Reacciones 69 y 41; idiomas ~8 hilos; tope diario 2 de 100 en China | Fuerte: parte ya existe y no se sabe (inferencia) | 02, 04, 11, 12. [Foro 2026-07](https://forums.ankiweb.net/t/proposal-backlog-recovery-planner-to-prevent-user-churn-burnout/70487) |
| Interfaz moderna, guía inicial | Principiantes | 205 respuestas; 113 [viejo, 2022]; 654 de puntaje | Fuerte: otros temen el rediseño | 02, 12. [r/Anki 2026-11-04, archivo](https://www.reddit.com/r/Anki/comments/1xngf6d/) |
| iOS igual al escritorio | Compradores iOS | EE.UU. ~24; alemán ~12 de 50; Egipto 5 de 9 | Fuerte en tiendas | 06, 09, 10, 11, 12. [r/Anki 2026-04-27, archivo](https://www.reddit.com/r/Anki/comments/1swrbx2/) |
| Tarjetas más rápido, con IA | Todos | 3–6 comentarios por hilo de HN; Italia 5; 暗記メーカー ~9 de 50 | Media: pedido y rechazo conviven | 02, 05, 09, 10, 11, 22. [HN 2025-09](https://news.ycombinator.com/item?id=45359524) |
| Recordatorios que anden | Android, iOS | ~12 posts; 11 en un hilo; ~4 de 381 reseñas | Media: el único médico dice que no hace falta | 02, 03, 04, 11, 12. [Foro 2025–26](https://forums.ankiweb.net/t/functional-notifications-are-essential-for-ankimobile/66148) |
| Widgets, sobre todo contadores y rachas | Android, iOS | ~30 personas en 5 hilos; puntajes 115, 91, 76; ~1% de reseñas | Media: pedido estable y chico; entre un tercio y la mitad de esos ~30 quiere la tarjeta misma (30) | 02, 04, 06, 10, 11, 12. [Foro 2023–26](https://forums.ankiweb.net/t/ankimobile-widget/32633) |
| Racha, heatmap, metas | r/Anki, Brasil | 17 reacciones; puntajes 148 y 51 | Media | 02, 09, 12. [r/Anki 2026-10-24, archivo](https://www.reddit.com/r/Anki/comments/1xfd3tn/) |
| Pago único o precio local | Vocabulary, Repetico, Brasil | 5 pedidos en 3 apps (2 viejos); ~3 en Repetico; 6 personas en Brasil | Media: pocos lo piden explícito | 06, 09, 10. [Foro 2025-06](https://forums.ankiweb.net/t/suggestion-please-consider-regional-pricing-for-brazilian-students/62383) |
| Que la tarjeta llegue sola | Minoría | Al desbloquear: 15 reacciones [viejo, 2024]; pedido en r/Anki puntaje 0; widget que repasa, 52; Vocabulary ~59 de 343 (no es repaso espaciado) | Pocos lo piden; la demanda no se probó, ni alta ni baja (30). Nadie cuenta meses de resultados | 02, 04, 06, 11, 12, 22. [r/Anki 2026-10-25, archivo](https://www.reddit.com/r/Anki/comments/1xffeoq/) |
| Importar de Anki, sin encierro | Quien prueba rivales | r/Anki 2 de 6 hilos; 2 lanzamientos | Débil: hilos chicos | 11, 12, 22. [r/macapps 2026-07-23, archivo](https://www.reddit.com/r/macapps/comments/1v47ius/) |

### 4. Por grupo

| Grupo | Cómo usa | Qué paga | Lo especial |
|---|---|---|---|
| Medicina | Mazo hecho (AnKing, ~35,096 tarjetas), 300–700 repasos por día (~5 fuentes); 120–180 en clínica [viejo, 2019–23] | Mazo mantenido: AnkiHub $6/mes, $450 de por vida (dice la app; 0 sí de 14, archivo). Bancos: UWorld $419 [viejo, 2022] | Sesiones largas, no ratos. Quien se va pasa a bancos. 0 pedidos de otra herramienta liviana (ausencia débil) |
| Idiomas | Mazo inicial, después propias; 10–30 minutos [viejo, 2020–24] | Estructura: Bunpro $5/mes (dice la app). Lo que es "solo flashcards" pierde contra Anki | Muchos cambian tarjetas por leer. Debate palabra o oración |
| Derecho | Facultad y examen; 5 relatos positivos (varios venden), sin cifras | Sin datos. Sets de editoriales en Alemania (dice la app) | Ninguno de los 5 sigue con tarjetas de derecho (inferencia). 19.2% más de aprobados: autoseleccionado, de quien vende [viejo, 2017] |
| Programación | Comandos, sintaxis; 17 a favor y 4 en contra en una búsqueda sesgada | Reticentes: $13/mes, ~5 interesados de ~29 | Se hacen la suya: 14 de 50 historias top de HN (inferencia) |
| Otros exámenes | Oposiciones, concursos con Anki; actuarios y CPA casi sin datos | Mazo por examen: R$159.90–279.90, €14.99 (dice la app) | Fuera de medicina, casi solo vendedores |
| Por placer | Países, cumpleaños, trivia, libros; ~40 relatos, sin encuesta; mediana 16 minutos [viejo en su mayoría, 2013–25] | Sin datos; herramientas gratis | Ultimate Geography: 978 tarjetas (dice la app). Tinycards cerró en 2020. 0 relatos de jubilados |

### 5. Por idioma o región

Los informes avisan: "distinto del inglés" es inferencia, no medición.

| Dónde | Qué dicen |
|---|---|
| España | La ley cambia y el mazo envejece (vende). La IA puede inventar un artículo (guía, 2026-08). "los únicos que pagamos". Caídas de Noji antes de exámenes, ~17 de 50 |
| México | Mazos ENARM a MXN 99 (dice la app). 500 pesos no valen, 1 reseña |
| Brasil | Piden precio regional. Vendedores con Pix y 12 cuotas (dice la app). Cursos de residencia con tarjetas propias (dice la app). 70–80% Android: estimación de foro |
| Argentina | Nada: 4 búsquedas sin comunidad. Nadie habla de dólares y tarjetas |
| Alemania | Ankizin: 20,000+ usuarios, gratis (dice la app). Privacidad: 0 de 250 reseñas; aparece en lo institucional (RGPD, 1 hilo) |
| Francia | *Méthode des J* en planilla. Mazos en papel (dice la app). Los mazos no siguen cada polycopié (vende). "Fiches" son resúmenes |
| Italia | Piden IA, 2 y 3 reseñas. 0 de medicina. |
| Rusia | ReWord por precio único, ~11 de 50. Pagar desde allá: 5 de 50 en Quizlet, 0 en Anki; las guías venden el servicio. Fallan medios, ~6 de 50 |
| Japón | Pegar desde Goodnotes rompe imágenes. Modo 赤シート. 国試 y otros exámenes nacionales |
| Corea | Docentes asignan ClassCard, ~9 de 50. El teclado parte sílabas, 3 de 50. Bronca por cobro repentino de ₩89,000 |
| China | El número pendiente presiona [viejo, 2020]. Sync con AnkiWeb falla. Cobros por un toque. Barato y compra única son norma (dice la app) |
| Árabe | Estudio religioso: canal de 15.5K (dice la app). Apps del Corán con repaso espaciado, mínimas. 31 reseñas |

### 6. Grupos mal atendidos hoy

Todo es inferencia: las cinco primeras, de 05; las dos últimas, de esta compilación.

| Grupo | Evidencia |
|---|---|
| Adultos curiosos, fuera de tecnología | Los mandan a Anki; sin examen, los obstáculos pesan más; Tinycards cerró; 0 relatos de mayores (05, débil) |
| Los que dejaron por la pila | Grupo más grande que describen los hilos (05); 3,000+ tras 3 meses ([r/Anki, archivo](https://www.reddit.com/r/Anki/comments/1rld04r/)); planificador pedido, sin respuesta (02) |
| Geografía con mapa y repaso | Los mazos no se tocan bien, las apps no espacian; 217 puntos en HN, ~9 piden saltear países sabidos (05, [2025-03](https://news.ycombinator.com/item?id=43392951)) |
| Derecho y exámenes no médicos | Sin cultura de mazos compartidos; llegan vendedores de IA (05, 09) |
| Profesionales después del examen | Sin señales de hábito ni herramienta (05, débil) |
| Widgets de palabras, con control | Frecuencia, silencio: ~10 de 200; 2 piden una palabra por día (06) |
| Estudio del Corán con repaso | Tathbeet, menos de 1,000 descargas (dice la app); web con 2 estrellas (11, débil) |

### 7. Dónde se contradicen

| Tema | Un lado | Otro lado | Qué tan sólido |
|---|---|---|---|
| Por qué se van | Pila: 27% de quejas (02), ~8 de ~16 (12) | No rendía: 9 contra 7 de 34 (02); lectura 4, pila 2 (05) | Muestras chicas; cada foro atrae su bando |
| Agotamiento | Estudio de la University of Central Florida (UCF): 82.1% abrumado, 34.5% pierde sueño (vía blog que vende) | Estudio de Wothe: sin vínculo, mejor sueño (n=165) | Débil: 02 cita UCF directo; 03 y 05 no pudieron abrirlo |
| ¿Sube notas? | 87.8% cree; Step 1 238 contra 233.5 | Halperin, Irlanda: sin ventaja; sin ensayo aleatorio | Medio; autorinforme |
| ¿Usan Anki en medicina? | 94%, ~80%, 68.3% | Jordania 25.2%; ~15 de 20 no, pero ~21 de 32 siguen (22) | Fuerte en EE.UU.; hilos sesgados |
| Precio de AnkiMobile | ~82 contra 49; Alemania 25 contra 6 | Más útiles: 12 contra 10; r/Anki ~37 sí, ~6 no | Compradores nuevos contra los de adentro |
| ¿Interfaz, problema? | ~64 de 172 bajas | r/Anki casi no lo escribe; 35 de 50 favorables; 1 persona lo llama mito (2026) | Fuerte al empezar; débil después |
| ¿Suscripción odiada? | Cobros sorpresa, "scam" | Vocabulary 4.77 de 221,986 (escritas: 2.98); pagadores en Bunpro | Los enojados escriben (inferencia) |
| ¿Widgets? | Vocabulary 17%; Android 230K–450K instalaciones | Anki ~1%; 0 videos hallados; dev de Anki duda | Débil: públicos distintos, sin retención |
| Ratos sueltos | Abdaal, Sung; 7 de 18 | 9 de 18 horario fijo; medicina en bloques; pushback en r/Anki | Medio |
| Palabra u oración | Guías y Migaku (vende): oración | 4 de 8 ponen la palabra; estudios en conflicto | Medio |

**Conteos que no cierran entre informes** (mismo feed). Precio y paridad en AnkiMobile España: ~7 y ~11 (06), ~13 y ~7 (09). Alemania, precio: ~14 (06), ~18 (10). Japón, Goodnotes: 6 (06), ~8 (11); precio: 16 (06), ~7 (11). Wunderbar: $3.99 (08), $5 (22). AnkiHub: $6 y $5 (03).

### 8. Por qué se pasan de una app a otra

Nadie tiene datos de cuánta gente se va ni adónde (30): son relatos sueltos. Dos cosas se repiten (inferencia): se van cuando les sacan algo o les cobran lo que era gratis, y llevarse las tarjetas pesa en la decisión.

| De, a | Por qué | Cuántos | Informes |
|---|---|---|---|
| Quizlet, a RemNote y otras | Funciones gratis que pasaron a pago | 7 de 7 diarios estudiantiles sobre el recorte [viejo, 2022]; adónde van, sin cifras | 13, 14 |
| Memrise, a LingQ o Anki | Sacó los cursos de la comunidad en 2024 | De 22 comentarios en HN, 10 dicen que empeoró, 6 nombran contenido perdido, 3 apuntan a Anki | 16 |
| Anki, a Bunpro o WaniKani | Estructura y contenido listos | Bunpro 15 personas; WaniKani 11 [viejo, 2023] | 04 |
| Bunpro, a Anki para vocabulario | FSRS | Varios, en un hilo de 2026 | 16 |
| Anki, a leer o escuchar | Idiomas: prefieren el uso real | 11 de ~20 | 04, 05, 22 |
| Anki, a bancos de preguntas | Medicina: rinden más para el examen | ~15 de 20 en hilos que atraen a los que ya piensan así | 03, 22 |
| RemNote, a otra | Interfaz torpe, bugs en el móvil, límites pasados a pago; no aparece una ola de vuelta a Anki | Sin cuenta | 14 |
| Mochi, a Anki | Límites del calendario | 1 persona, 2025 | 12 |
| Anki, a SuperMemo | Menos carga | 1 persona, que la llama lejos de perfecta [viejo, 2021] | 15 |
| Tinycards, a Memrise o Anki | Cerró en 2020 | 503 firmaron una petición; adónde fueron, sin cifras [viejo, 2020] | 15 |

**Lo que frena el cambio:** importar detrás de un pago, varios en un hilo [viejo, 2024] (22), y perder el trabajo hecho, como sienten los autores de cursos de Memrise [viejo, 2023] (16). Ficha importa de Anki con el progreso.
## 2. Anki y cada alternativa

Compilado de los informes crudos. Tiendas leídas el 2026-11-05, EE.UU. salvo aclaración. TP = Trustpilot, HN = Hacker News. "Bajas" = reseñas de 1 a 3★. "Sin pedirlas" = si muestra tarjetas sin que las pidas, y cómo cae. Conteos aproximados, de muestras chicas que tienden al enojo.

### Anki, con AnkiMobile, AnkiDroid y AnkiHub

- **Para quién:** medicina e idiomas sobre todo; quien banca una curva de aprendizaje a cambio de poder (dice la gente). Nadie publica un total. AnkiDroid dice 4.0M usuarios en Google Play (acumulado, inferencia) y 260k activos por día (fines de 2024).
- **Ofrece:** Desktop con ~3.8k add-ons, AnkiWeb (sync, mazos compartidos), AnkiMobile (oficial, offline, sin add-ons), AnkiDroid (voluntarios). Se elogia: potente, sin anuncios ni cuenta, oficial frente a las copias (~12). Si FSRS viene activado está en disputa: blogs dicen que sí, el manual que lo activás vos.
- **Quejas:** AnkiMobile, 172 bajas de 300: difícil o viejo ~64, precio ~56, sync o importar ~36, menos que el desktop ~24. Por "más útiles", 35 de 50 favorables; el "difícil" viene en buena parte de novatos (inferencia). AnkiDroid: sin reseñas contadas, Google Play no se pudo leer.
- **Precio:** todo gratis salvo AnkiMobile, $24.99 una vez, ~$25 desde al menos 2013 [viejo, 2013]. De ~130 menciones, ~82 negativas y ~49 positivas; por "más útiles", 12 positivas, 7 mixtas, 10 negativas. Negativas: pagaron y no les funcionó; Android es gratis. Positivas: pago único. Alemania: 25 contra 6.
- **Sin pedirlas:** no. Ninguna app oficial muestra ni responde una tarjeta afuera (inferencia). Desktop sin recordatorios; AnkiMobile, una alerta y un badge que fallan en ≥7 hilos (2020-2026); AnkiDroid, avisos y widgets de conteos, y un sistema nuevo tras una opción de desarrollador. 4 hilos piden widgets, más heatmap (5) y conteos (3) que tarjeta al azar (3). Elmes, su creador, duda de la exposición pasiva (2025). En reseñas: ~1%.
- **Estado:** vivo. Desktop 26.09.4 (2026-11-04, arreglos críticos de seguridad); AnkiMobile 26.10 (2026-11-03) tras 14 meses sin update, 4.0 de 2.4K; AnkiDroid 2.25.3.
- **AnkiHub:** Elmes le traspasa de a poco la operación desde 2026-02-02. Promete código central abierto y ningún cambio de precio planeado; el gobierno formal no aparece nueve meses después (inferencia). 141 respuestas: miedo a paywalls y conflicto de interés; HN, ~12 escépticos y ~6 optimistas. La marca sigue en Ankitects, y no se sabe quién la tendrá. Vende mazos sincronizados: Core a $5 o $6 por mes según la fuente, Premium $10, $450 de por vida (ver el anexo).
- **Fuentes:** [hilo del widget, 2023 a 2026-10-30](https://forums.ankiweb.net/t/ankimobile-widget/32633); [traspaso, 2026-02-02](https://forums.ankiweb.net/t/ankis-growing-up/68610.md); [reseñas, leído 2026-11-05](https://itunes.apple.com/us/rss/customerreviews/id=373493387/sortby=mostrecent/json).

### Quizlet

- **Para quién:** secundaria, facultad, docentes. 60M+ por mes [viejo, 2021].
- **Ofrece:** sets compartidos, Match, Learn, Test, juegos, notas con IA. Dice la gente: sets hechos, docentes que los asignan, más amable que Anki.
- **Quejas:** [TP, 1.4 de 664](https://www.trustpilot.com/review/quizlet.com). De 40 últimas: paywall ~18, cobros ~12, soporte ~8, bugs ~7. App Store: 36 bajas de 100, paywall 15. Pero 4.8 de 1.1M: el enojo no se ve en las estrellas.
- **Precio:** los informes no coinciden: Plus $7.99/mes o $35.99/año y Unlimited $9.99 o $44.99 (informe 13); Plus $9.99 o $44.99 (06 y 26). Desde 2022-08-01 solo Flashcards y Match gratis; 7 de 7 diarios escolares, bronca [viejo, 2022]. Límite gratis actual sin confirmar.
- **Sin pedirlas:** no. Push de recordatorio; sin rastros de widget, reloj ni barra de menú (inferencia). Nadie los comenta; algunos se quejan de mails.
- **Estado:** vivo, 10.59. Visitas estimadas -29%, [causa no demostrada, 2026-09-03](https://ppc.land/chegg-loses-61-of-web-visits-as-chatbots-gain-90-82-yoy/).

### Brainscape

- **Para quién:** exámenes (NCLEX, CFA, WSET), idiomas, colegios, empresas (dice la app).
- **Ofrece:** repaso por confianza de 1 a 5, mazos certificados, IA, gratis sin anuncios. Dice la gente: fácil, buenos mazos.
- **Quejas:** [TP, 4.7 de 602](https://www.trustpilot.com/review/brainscape.com). De 17 con 1-2★: paywall o precio ~10, soporte 6, contenido 4. App Store: 13 bajas de 100, paywall 5, rating forzado 3.
- **Precio:** gratis con texto; imágenes y sonido en Pro. Web $7.99/mes anual; iOS $19.99/mes, $95.99/año, $199.99 de por vida. La app niega cerrar funciones gratis; una reseña dice lo contrario.
- **Sin pedirlas:** no. Push de racha [viejo, 2023]; 1 queja por mensajes culpógenos.
- **Estado:** vivo, 4.20261002 (19 oct); 4.8 de 22K.

### RemNote

- **Para quién:** estudiantes, sobre todo medicina. Dice 1,000,000+; terceros, "cientos de miles".
- **Ofrece:** notas donde una línea se vuelve tarjeta, IA desde PDF y clases. Dice la gente: todo junto (~8 de 34 con 5★).
- **Quejas:** [50 últimas](https://itunes.apple.com/us/rss/customerreviews/id=1545429784/sortby=mostrecent/json), 10 con 1-2★: paywall 6, IA 5, bugs 5. Las 50 anteriores (2023-2025): bugs 13, móvil 13, paywall 0. Pasaron de bugs a precio (inferencia).
- **Precio:** notas y tarjetas gratis; [Pro $8, con IA $18, anual](https://www.remnote.com/pricing) (leído 2026-11-05); tienda $14.99 y $29.99/mes. De por vida: $395 según una reseña, sin precio en su página.
- **Sin pedirlas:** no. Sin widget, reloj ni barra de menú; 1 elogia recordatorios por mail.
- **Estado:** vivo, 1.29.7; 4.8 de 1.7K.

### Mochi

- **Para quién:** quien quiere Anki con otra cara; coreano y japonés (inferencia).
- **Ofrece:** Markdown, local-first, IA, API. ~12 de 22 comentarios de [HN, 2021-2026](https://hn.algolia.com/api/v1/search?query=mochi%20cards%20anki&tags=comment&hitsPerPage=30) la ven más linda que Anki.
- **Quejas:** 49 reseñas, 2020-2026: faltantes 10, bugs 8, UI 8, tarjetas perdidas 2.
- **Precio:** gratis offline; [Pro $5/mes](https://mochi.cards/pricing) (leído 2026-11-05) con sync; un informe lo lee mensual, otro facturado por año. Se paga por el sync (inferencia).
- **Sin pedirlas:** no. Recordatorio diario desde abril 2025; un pedido del foro lo llama básico.
- **Estado:** vivo, 26.10.1 (2026-10-23), un desarrollador; 4.6 de 175.

### SuperMemo

- **Para quién:** Windows: lectura incremental, sistema al máximo. SuperMemo.com, otro producto: idiomas.
- **Ofrece:** [SuperMemo 20, 2026-04-01](https://supermemo.guru/wiki/SuperMemo_20): SM-20, editor de PDF. App: tutor con IA; 24, 25 o 27 idiomas según dónde mires.
- **Quejas:** Windows: difícil o feo en 8 de 9 voces, muestra flaca y vieja. App: 4 reseñas polacas (anticuada; tope sorpresa de 1,000 tarjetas [viejo, 2023]).
- **Precio:** [$64 la 20, $28 la 19](https://supermemo.store/) (leído 2026-11-05), pago único. App $9.99/mes, $99.99/año, con descuentos frecuentes (inferencia).
- **Sin pedirlas:** no.
- **Estado:** vivo, 20.00.32 (2026-06-29). App 2.1.22, 28 oct, sin año; 4.6 de 2.9k en Polonia.

### Mnemosyne

Gratis, de escritorio, sin superficies; [última versión 2.11, 2023-11-12](https://github.com/mnemosyne-proj/mnemosyne/releases), commits hasta 2026-04-18, sitio suspendido el 2026-11-05.

### Memrise

- **Para quién:** gente con un motivo concreto, de principiante a intermedio (dice la app). 87M registrados según Wikipedia.
- **Ofrece:** videos de nativos, chat con IA. Dice la gente: funciona (~12 de 50), gente real (~6).
- **Quejas:** App Store: 41 bajas de 100, no carga ~14, cobros ~10, IA forzada ~6. [TP, 1.6 de 143](https://www.trustpilot.com/review/memrise.com). Sacó los cursos comunitarios en [marzo 2024](https://www.memrise.com/blog/changes-to-the-memrise-app); las reseñas que los nombran bajan de 5 por 50 (fines de 2024) a 0.
- **Precio:** $24.99/mes, $61.99/año, $329.99 de por vida; una reseña con afiliados da $39.99/mes.
- **Sin pedirlas:** no; sin widget hallado.
- **Estado:** vivo, v2026.10.21 (23 oct); 4.8 de 218K.

### WaniKani

- **Para quién:** quien quiere leer kanji. Es de Tofugu.
- **Ofrece:** 2,000 kanji, 6,000 palabras, horario fijo. Dice la gente, sesgo de pagadores: otro decide por vos (~11 de 20, [2022](https://community.wanikani.com/t/wanikani-vs-anki/57819) [viejo]), frena la sobrecarga.
- **Quejas:** pilas tras un corte (1,481 en 2025). [Foro rival, 2024](https://community.bunpro.jp/t/anki-vs-wanikani/83766): 9 de 20 prefieren Anki u otras, 2 WaniKani. HN: 12 elogian, 6 se quejan.
- **Precio:** $9, $89, $299 de por vida; ~$200 en oferta (diciembre 2025). De por vida le sirve a quien corta y vuelve (~13, enero 2026).
- **Sin pedirlas:** no, y sin app oficial de iOS. La gratis Tsurukame notifica; 4.7 de 636.
- **Estado:** vivo, foro activo; changelog no leído.

### Otras apps de idiomas

- **Duolingo:** [64.9M diarios, 13.1M pagan, Q3 2026](https://www.sec.gov/Archives/edgar/data/0001562088/000162828026069474/q3fy26duolingo9-30x26share.htm). Super $9.99 a $12.99/mes. Widget con la racha, no tarjetas; [su blog](https://blog.duolingo.com/widget-feature) dice que retiene, sin cifras del efecto [viejo, 2023]. 4.7 de 5.6M.
- **Lingvist y Clozemaster:** vocabulario y frases. Lingvist: promedio escrito 2.9, precio ~11 de 50; $79.99/año. Clozemaster: precio ~7, traducciones ~7; $79.99/año. Widgets sin menciones.
- **Bunpro y Renshuu:** japonés. Bunpro: 30 de 36 con 5★, $5/mes en su sitio, $6.49 en la tienda, widgets, piden FSRS. Renshuu: 49 de 50 con 5★, desde $3.99/mes, sin superficies.
- **Migaku y Drops:** Migaku, tarjetas desde Netflix; precio o sin prueba ~9 de 50; $14/mes. Drops, juegos de 5 minutos; bugs ~6; widget de racha.
- **En conjunto:** todas con versión reciente. De 336 reseñas de siete feeds, 0 hablan de widgets y 2 de notificaciones (inferencia).

### Knowt

- **Para quién:** secundaria y facultad en EE.UU., AP. Dice 8.9M en su sitio, 7M en la tienda.
- **Ofrece:** tarjetas y Learn gratis, importa de Quizlet, IA, grabación de clases.
- **Quejas:** [App Store](https://itunes.apple.com/us/rss/customerreviews/id=6463744184/sortby=mostrecent/json), 43 bajas de 100: paywall ~13, cobros sorpresa ~12, IA ~9. No coinciden: [Unstar, junio 2026](https://unstar.app/blog/quizlet-anki-brainscape-knowt-studysmarter-flashcard-study-apps-ranked-2026) ve pocas quejas de paywall; [Headway, septiembre 2026](https://makeheadway.com/blog/knowt-review/), una recurrente. Ambos venden algo.
- **Precio:** $7.99/mes anual, $24.99 mensual; tienda $9.99 por semana, $59.99 a $149.99/año.
- **Sin pedirlas:** no. Sus widgets crean y graban, no repasan.
- **Estado:** vivo, 4.3.0 (26 oct); 4.7 de 11K.

### Creadoras de tarjetas con IA

Gizmo, StudyFetch, Turbo AI, Jungle, Revisely, Mindgrasp; gratis y sin horario de repaso, ChatGPT, Gemini y NotebookLM.

- **Para quién:** estudiantes. Turbo arranca por apuntes; Gizmo es un juego con vidas.
- **Ofrece:** tarjetas desde PDF, video o clases. Errores medidos: [~1.0% en radiología, agosto 2026](https://news-en.amc.seoul.kr/news/eng/detail.do?cntId=3283); [2 de 100 en biología, junio 2025](https://denovo.substack.com/p/ai-generated-anki-cards-are-not-to).
- **Quejas:** TP: Turbo 2.1 de 21, Mindgrasp 2.2 de 136, Revisely 2.6 de 54, Gizmo 3.1 de 7, StudyFetch 4.1 de 307; los cobros encabezan o empatan en los cinco. Las tiendas dan 4.6 a 4.8: disienten.
- **Precio:** muchos precios por app (Gizmo 8, Turbo 9), planes semanales de $6.99 a $13.99. Turbo dice ~$500K/mes a marzo 2025 (autorreportado). Poca evidencia de que paguen solo por generar.
- **Sin pedirlas:** no. Gizmo, StudyFetch y Turbo no mencionan notificaciones, widgets ni reloj.
- **Estado:** vivas. Gizmo 3.2.143, StudyFetch 3.1.3, Turbo 1.5.12, Jungle 1.315; Revisely y Mindgrasp, con reseñas hasta oct 2026.

### Readwise

- **Para quién:** power users que subrayan mucho, según su cofundador [viejo, 2021].
- **Ofrece:** junta subrayados; Daily Review por mail y app; rachas. Dice la gente: reencontrar, sacar ideas; casi nadie dice retener. Matuschak duda de que dé memoria detallada ([nota, sin fecha](https://notes.andymatuschak.org/zAt1K9ARQYguinoHH8cfaqQ)).
- **Quejas:** App Store: 24 bajas de 100, importar o sync ~8, precio ~7. HN: de 76, 6 se fueron. Rachas como peso: 3 fuentes [viejo, 2023-2024]. Los que abandonan callados son el agujero (inferencia).
- **Precio:** [Full $9.99, Reader o Highlights $7.99, Lite $5.59, anual](https://readwise.io/pricing) (leído 2026-11-05); subió en febrero 2024; sin plan gratis. HN: ~5 en contra, ~7 a favor.
- **Sin pedirlas:** sí, subrayados, no tarjetas: mail y push diarios; widget con un subrayado al azar cada 5 minutos tras el repaso. No coinciden: un informe no halla casi comentarios; otro, ~7 de 100 reseñas favorables que piden más notificaciones.
- **Estado:** vivo, 3.5.2 (21 oct); 4.8 de 1.5K. La atención va a [Readwise Books, 2026-11-02](https://techcrunch.com/2026/11/02/readwise-takes-on-amazons-kindle-and-goodreads-with-its-new-app-for-book-lovers/) (inferencia).

### Apps nativas de Apple

**AlgoApp (antes AnkiApp).** Idiomas, medicina, exámenes; todas las plataformas, IA, FSRS, cuenta propia. Sin relación con Anki, [cuyo FAQ](https://docs.ankiweb.net/faqs/anki-knockoffs) (sin fecha) la señala. 21 bajas de 50: bugs 7, cobros 7. Tope gratis: 100 por día en un informe, 80 en otro. $29.99/año, $149.99 de por vida. Recordatorios opcionales. 15.8.1; 4.7 de 20K.

**Noji (antes Anki Pro).** Escuela, medicina, idiomas; 50,000+ mazos; sin app de Mac; tope gratis de 50 por día. [~55 reseñas](https://justuseapp.com/en/app/1573585542/anki-pro-flashcards-learning/reviews) (casi sin fecha): imitar a Anki ~14, bugs ~9, precio ~8. $17.99 a $89.99/año, de por vida entre $39.99 y $74.99 según la fuente. 4 elogian recordatorios con texto casi igual (¿inducido?, inferencia). Viva; 4.6 de 14K.

**Flashcards Deluxe.** Usuarios avanzados; 5 lados, Leitner; compleja [viejo, 2017]. Precio en disputa: [$4.99](https://apps.apple.com/us/app/flashcards-deluxe/id307840670) (leído 2026-11-05), $6.99 en Canadá, $3.99 en un agregador. Se elogia el pago único. Sin superficies. 4.86, 16 sep, sin año; 4.5 de 341.

**Flashcard Hero.** Estudiantes y docentes; Leitner, iCloud Drive. Quejas pocas y viejas; iCloud falla, 2 (snippets). [Mac $14.99](https://apps.apple.com/us/app/flashcard-hero/id650802274?mt=12) (leído 2026-11-05), iOS $4.99. Sin superficies. iOS 3.7.3 (agosto 2025); 4.8 de 884.

**Flashcards by NKO.** Clases, juegos, reloj con recordatorios; sin Mac. $9.99/año. 3.7.0 (octubre 2025); [4.9 de 2.1K](https://apps.apple.com/us/app/flashcards-by-nko/id478986342).

**Flashcards World.** FSRS-6, .apkg, IA; corre en Mac. $49.99/año. Sin superficies. 2.072; [4.6 de 925](https://apps.apple.com/app/id6447302554).

**Las chicas:** Studies, Fresh Cards, Wokabulary, Swiftflip, FlashCards, Truly Simple, Discito, Retrieve, Recall, FlashCard, Zorbi.

- **Ofrecen:** de 12 nuevas, todas iCloud o local, ~9 FSRS, ~9 importan de Anki; eso lo piden más los fabricantes que los usuarios (inferencia).
- **Quejas:** pocas. Studies, datos rotos [viejo, 2019]; Fresh Cards, repite tarjetas [viejo, 2021].
- **Precio:** pago único de $4.99 (Truly Simple) a $24.99 (Studies Mac); Swiftflip $39.99/año. Se elogia el pago único; la privacidad casi no aparece: [0 de 36 posts, 2020-2024](https://talk.macpowerusers.com/t/mac-ios-flashcards-app/17508) [viejo].
- **Sin pedirlas:** widgets en Wokabulary, Swiftflip, FlashCards, Retrieve; pantalla bloqueada en Swiftflip, FlashCards, Retrieve, Discito. Recepción casi nula.
- **Estado:** minúsculas: Fresh Cards 63 valoraciones, Wokabulary 27; Swiftflip 3, 8 o ninguna según informe y tienda. Zorbi, tienda en 404 (inferencia: quizá muerta).

### Vocabulary (Monkey Taps)

- **Para quién:** palabras raras en inglés; [una reseña de 2025](https://www.woshipm.com/evaluating/6272227.html) ve un público chico y avanzado.
- **Ofrece:** 10,000+ palabras propias, widgets, juegos, reloj. ~63 de 250 dicen que aprenden; nadie lo mide (inferencia).
- **Quejas:** [250 últimas](https://itunes.apple.com/us/rss/customerreviews/page=1/id=1084540807/sortby=mostrecent/json): 110 con 1-2★, precio o cobros ~82. Otro corte, 116 bajas de 200: paywall tras configurar 31, palabras malas 26. Pero 4.8 de 222K (otro informe llega a 336K). ~20 de 250 olvidan o no pueden repasar.
- **Precio:** hasta $14.99/mes, $35.99 a $59.99/año, $149.99 de por vida. Ingresos estimados de $50K a $800K/mes: los modelos no coinciden.
- **Sin pedirlas:** sí, es su promesa: una palabra por desbloqueo, no tarjetas tuyas. ~59 de 343 reseñas lo tratan; ~14 de 200 elogian, ~10 se quejan: demasiadas (hasta ~30 por día), sin control.
- **Estado:** vivo, 7.7.0 (~2026-11-04), desde 2016.

### WordBit y otras de pantalla bloqueada

- **Para quién:** WordBit, idiomas en Android, sin iOS hallado. Word of the Day y las motivacionales Motivation e I am usan la misma pantalla.
- **Ofrece:** WordBit: un aviso sobre la pantalla bloqueada al prenderla, banco A1-C2.
- **Quejas:** WordBit: interrupciones, anuncios ([reseña con afiliados, mayo 2024](https://www.alllanguageresources.com/wordbit/) [viejo]); notas en conflicto: 4.8, 4.41, 3.95. Word of the Day: 50 de 100 con 1-2★, paywall ~34, anuncios ~30.
- **Precio:** WordBit gratis con anuncios. Word of the Day $9.99/mes, $49.99 a $99.99/año.
- **Sin pedirlas:** sí, contenido propio. Único estudio directo, [30 personas, 3 semanas](https://ar5iv.labs.arxiv.org/html/2109.07944) [viejo, 2021]: respuestas +54% al desbloquear, +43% con notificación fija, -14% por día; favorita, la notificación (18 de 30). Nada a meses. WordBit alemán: 694K instalaciones, ~5.2K activos (estimación).
- **Estado:** vivas. WordBit alemán sep 2026; Word of the Day 9.13.15. De 16 apps nuevas de widget, barra, notch y reloj, 15 tienen menos de 100 valoraciones.

### Mac: tarjetas que aparecen solas

- **NotchWise:** usuarios de Anki con Mac. Tarjetas en el notch o flotando, .apkg, FSRS-4.5; se esconde al compartir pantalla (dice la app). Sin quejas ni valoraciones. Gratis con 50 tarjetas; [Pro $19.99](https://apps.apple.com/app/notchwise/id6760242442) (leído 2026-11-05), £14.99 al lanzar. iCloud: la tienda dice sí, el blog no. v1.9, 2026.
- **[PopCards](https://popcards.app/):** Mac. Las tarjetas aparecen cada 10, 30 o 60+ minutos, "sin interrumpir" trabajo ni reuniones (dice la app). Espaciado sin nombrar, CSV, sin importar de Anki. $9.99 una vez. © 2025. Sin reseñas leídas; lo encontró la verificación.
- **Wunderbar:** una palabra por minuto en la barra de menú, listas propias, 4 botones. Quejas: lugar en la barra (3), voces robóticas. Se elogia no tener sesión aparte (varios de 42, [HN, abril 2024](https://news.ycombinator.com/item?id=39999163) [viejo]). $4.99 una vez; su sitio dice $3.99. 2.1.1, 29 jul.
- **Otras de palabras:** [LingoBar](https://apps.apple.com/app/lingobar/id6761308258) (leído 2026-11-05) $4.99, adrede sin notificaciones; VocaBar $2.99; Word Drop $1.99. Sin valoraciones.
- **Dentro de otra app:** Ruzu Pop-ups (Anki abierto, 8 estrellas); Obsidian Popup Review (205 descargas).
- **Cómo cae:** casi sin evidencia; 1 comentario de HN sobre una palabra grosera al compartir pantalla.

### Las que cerraron

- **Tinycards (Duolingo, 2016 a 2020-09-01):** la empresa se enfocó en su app. [503 firmas, 2020](https://www.change.org/p/duolingo-duolingo-tinycards-should-not-be-taken-down) [viejo] pedían venderla o cobrar. Sin exportar en 2017; un snippet dice que luego se pudo.
- **StudyBlue (hasta fines de 2020):** Chegg la compró por $20.8M en 2018; sin motivo declarado. [Chegg Prep](https://justuseapp.com/en/app/1462189360/chegg-prep-study-flashcards/reviews) (hasta 2023): ~14 de 33 perdieron mazos, aunque la misma página da 4.6 sobre 3,102.
- **Semper / UnlockYourBrain:** tarjeta al desbloquear; sin updates desde 2017, [fuera de iOS](https://alternativeto.net/software/semper/about) [viejo, 2019]. Sin causa declarada.
- **Menores:** Kindle Flashcards (2024) [viejo], zuknow, Pocket (2025), Omnivore. Cerego se fue a instituciones.
- **Qué enseñan (inferencia):** las gratis dentro de una empresa más grande mueren cuando esta cambia de foco (4 de 4). Duelen los datos perdidos. Las pagas chicas duran más, con sesgo de supervivencia. La herramienta sola dio poco incluso a SuperMemo [viejo, 2001]. El muro es el hábito.
## 3. Lo que le falta a Ficha

Comparé con lo que Ficha hace hoy según `README.md` y `GLOSSARY.md`, sin abrir la app. El orden es inferencia mía: cuánto pesa cada falta para alguien que podría comprarla.

| # | Falta | Qué muestra la evidencia | Peso |
|---|---|---|---|
| 1 | **iPhone** | Lo que se vende de Anki en las tiendas es el iPhone (23). "Falta plataforma" sale en ~6 de 15 hilos de lanzamientos, casi siempre por Android (27). También ahí está lo más amontonado (30) | Muy alto; ya está en #160 |
| 2 | **Tarjetas para empezar** | Hacer tarjetas: ~18% de las quejas en HN (02). "Mazos listos" es por lo que paga la gente (04, 03, 11). Tu amigo de #252 dice lo mismo. Hoy, quien no viene de Anki llega a una app vacía. En contra: en 5 de 6 experimentos aprendió más quien armó sus propias tarjetas (Pan, en 17) [viejo, 2024] | Muy alto, **y no está en ningún plan** |
| 3 | **Probar antes de pagar** | Un hilo de 2025 se lo reclama a AnkiMobile (24), y ~9 de 50 reseñas de Migaku hablan de precio o falta de prueba (16). Las comunidades piden prueba o parte gratis (27, 22). NotchWise: gratis con 1 mazo y 50 tarjetas | Alto; ver la parte 6 |
| 4 | **Volver después de un corte** | La pila también aparece tras un corte: 3,000+ después de 3 meses (12). Hay un planificador pedido y sin respuesta (02). Ficha trae hasta cinco por aparición, pero su menú muestra el total pendiente. No sé cómo se siente volver: nadie lo probó | Alto, y puede ser una ventaja real |
| 5 | **Hacer tarjetas más rápido** | Se pide y se rechaza a la vez (02, 05, 11). Errores medidos: ~1–2% en dos casos con tarjetas, 22% en preguntas de ChatGPT, todo con pocas muestras (17). Ya tenés las instrucciones para una IA (#218) | Medio; #252 |
| 6 | **#443 Estado del sync** | Molestia común y chica, y un sync que falla sin avisar cuesta confianza. Detalle abajo | Medio |
| 7 | **#394 Formato** | Se nota cuando desaparece. Detalle abajo | Medio, si vendés a gente de Anki |
| 8 | **Contadores y racha** | Lo más pedido en widgets, aunque entre un tercio y la mitad de un grupo de ~30 quiere la tarjeta misma (02, 12, 20, 30). Las rachas pesan: 3 fuentes en Readwise (18) | Medio, con cuidado |
| 9 | **#392 Repaso libre** | Se pide, sobre todo cerca de un examen o al empezar. Detalle abajo | Medio o bajo |
| 10 | **#397 Varios sonidos** | Casi nadie habla de esto. Detalle abajo | Bajo, hasta contar tus mazos |
| 11 | **#395 Escribir la respuesta** | Lo quiere con ganas una minoría. Detalle abajo | Bajo |

**Afuera a propósito:** Android, Windows y web pesan mucho como límite, porque Anki es gratis ahí y Brasil es ~70–80% Android (09, estimación de foro). Los mazos enormes, los add-ons y el cloze propio son lo que retiene a medicina (03), que no es tu público.

**Lo que Ficha ya tiene y la gente pide:** recordatorios que funcionan, con ~12 posts diciendo que los de Anki fallan (12). Un pago único, si se mantiene el plan. FSRS, sin tener que tocar nada. Importar de Anki con el progreso. Elegir horas, cuántas tarjetas y cada cuánto, que le falta a Vocabulary (~10 de 200 se quejan). Frenarse en mal momento, que ninguna app grande promete.

### Tus cinco issues

No reabro tu decisión. Esto es lo que encontró el informe 29, atacado por el 30. **Limitación común:** no hay ninguna estadística de uso de ninguno de los cinco, solo gente que escribió en foros.

| Issue | A favor | En contra | Qué agrega o saca |
|---|---|---|---|
| **#443 Estado del sync** | Molestia común: 394 "me too" en Apple Fotos [viejo, 2018], varios hilos de Infuse. El sync que falla sin avisar cuesta confianza (Pleco, Mental Case). La gente pregunta al configurar | Lo que llena los hilos son fallas, no falta de información. Los 394 son de hace 8 años y de una fototeca, mucho más grande que unas tarjetas. Lo que una app sabe de iCloud es limitado (Ulysses, DEVONthink). No encontré a nadie preocupado por lo que ocupa una app de tarjetas, aunque a vos te importa | **Agrega** confianza, sin costar segundos. Lo que más se sostiene es el "¿ya está?". La barra importa solo en envíos grandes, y el espacio, solo al llegar a un límite |
| **#394 Formato** | Molesta cuando desaparece: ~10 de 18 resultados son de negrita y color perdidos *al entrar* a Anki. Mochi lidera con Markdown (dice la app) | Nadie se quejó de perder negrita *al salir* de Anki. Markdown en sí es un pedido chico, de gente que escribe tarjetas. El creador de Anki dijo que no representa todo su HTML, así que la conversión pierde cosas | **Agrega** que lo importado se vea bien, lo que importa si vendés a gente de Anki. **No saca** nada al responder: el costo cae en escribir y en la app |
| **#392 Repaso libre** | Se pide seguido: ~11 hilos de "finished for now". Los rivales revisados tienen algo así | De los 5 hilos leídos, 3 nombran un examen y 2 son de usuarios nuevos. Tu "hora libre" aparece una sola vez, antes de un examen. Los habituales desaconsejan estudiar a último momento, y uno avisa que estudiar sin registrar afecta la memoria sin que FSRS lo vea, lo que toca tu inclinación de que no cuente. Anki lo trae con reprogramación **activada** | **Agrega** elegir un mazo y repasar fuera del calendario; "más tarjetas" ya lo dan See more y Review ahead. **Saca** algo del mensaje: es sentarse a estudiar, y vas a vender lo contrario |
| **#397 Varios sonidos** | Palabra más oración es un patrón en mazos de japonés (Kaishi, ambos en el dorso) | Casi nadie habla de esto: ~5 hilos, y ~4 piden *menos* audio. Nadie se quejó de una app que traiga un solo sonido, quizá porque pocos lo probaron | **Agrega** fidelidad al importar idiomas. **Saca** algo de tiempo: palabra y oración alargan un dorso. Su peso depende de los mazos, y eso se puede contar |
| **#395 Escribir la respuesta** | Una minoría lo quiere con ganas, por ortografía y escritura, sobre todo en idiomas: evita engañarse. RemNote lo ofrece opcional por tarjeta | El mayor choque con los segundos. Efecto en memoria mínimo: d=0.07 (Sundqvist, 2017), aunque no prueba ortografía. Las cuentas de WaniKani se inclinan a no escribir, y el único "me voy si me obligan" es en contra. Ninguna app de notificaciones o widgets encontrada lo ofrece | **Agrega** algo para quien cuida la ortografía. **Saca** la promesa de segundos si es general; quienes lo piden lo piden opcional, tarjeta por tarjeta. En iOS se puede técnicamente (30) |

**Antes de los grillings:** la mejor evidencia para #394, #395 y #397 la tenés vos. Contar en tus paquetes de Anki cuántos lados tienen varios sonidos, y cuántas tarjetas usan negrita o `{{type:}}`, lleva unos 30 minutos y vale más que cualquier foro (29).

## 4. ¿Vale la pena hacerla y venderla?

**Mi respuesta: vale como apuesta chica, no como negocio del que vivir, y lo que decide nunca se midió.** Puede no ser lo que esperabas, y esto es lo que la sostiene.

**A favor:**
- **El hueco existe.** Lo confirmaron los informes 01 y 24 y la verificación. Anki no muestra tarjetas afuera de la app. Una tarjeta al desbloquear se pidió en AnkiDroid de 2017 a 2024, con 15 reacciones y 60 comentarios, y los mantenedores dijeron que se hiciera [como app aparte](https://github.com/ankidroid/Anki-Android/issues/4709) [viejo]. Una vuelta sin probar: los widgets de iPhone pueden verse en el escritorio de una Mac (30).
- **Hay gente que paga por una forma de repasar.** AnkiMobile: $25, #4 entre las pagas de iPhone en EE.UU. Es cliente cautivo, pero existe.
- **Se acepta que el contenido llegue solo.** Vocabulary tiene 222K valoraciones en EE.UU., Motivation 82.7M de instalaciones (cifra de tracker). Venden palabras y frases puestas por ellos, no memoria, y parte de la plata son anuncios.
- **Repasar poco es algo real.** Quienes dan una cifra cuentan unos 10–20 minutos por día, con mediana de 16, que ya es más que "unas pocas tarjetas". Hay casos de 1 a 5 minutos, y topes de 10 o 20 repasos como defensa contra la pila (05). Mayormente viejo.
- **Hay espacio en el mensaje.** Ninguna app grande de estudio lidera con tarjetas que llegan solas, con frenarse en mal momento, ni con privacidad (26). Vocabulary lidera con lo primero, con palabras suyas.
- **Tu costo es casi cero (inferencia).** Sin servidor, sin costo por usuario, y la app está casi hecha. Con poca venta ya no perdés plata.

**En contra:**
- **Casi nadie la pide.** Pocos piden repasar en ratos sueltos, y no encontré a nadie que siga con Anki y quiera una segunda app liviana (24). Eso no prueba que no la quieran: en reseñas, cualquier falta saca 1–3% (30). Quien usa dos apps suele hacerlo por contenido. Hay voces por tener todo en un solo lugar: ~5 en un hilo de Hashcards, tarjetas en texto plano, y la mayoría de 8 personas en un pedido a Obsidian, con ~3 conformes con herramientas aparte. "Ficha para lo chico" les pide partir sus tarjetas en dos.
- **Lo gratis es la vara.** "¿Por qué no Anki?" aparece en 8 de 11 lanzamientos que compiten (27).
- **Los parecidos no despegan.** 15 de 16 apps nuevas de widget o barra de menú tienen menos de 100 valoraciones. NotchWise, 7 meses y ninguna. No sé si es poca demanda o que nadie las encuentra, pero es lo que hay.
- **Hubo un antecedente que murió.** Semper, tarjeta al desbloquear, sin updates desde 2017. Sin causa declarada.
- **No hay un número de plata confiable, y lo que se ve es chico.** Ningún fundador de flashcards publica ingresos, y los trackers no coinciden. Lo verificable: una app de flashcards con $43 por mes, NameMemory, para recordar nombres, con 2 pagos de 215 descargas en 6 meses. Con la verificación, los casos indie de Mac a $5–30 van de cientos a pocos miles por mes, y esos son los que sobrevivieron y lo cuentan.
- **Tus canales naturales están cerrados.** AlgoApp y Noji parecen haber crecido con "Anki" en el nombre, por búsqueda (inferencia). Vos no podés, y r/Anki saca las apps sueltas (leído por el archivo y de segunda mano). Es la objeción que menos esperaba.
- **Interrumpir no está probado.** Ningún estudio prueba una tarjeta no pedida durante trabajo real contra una sesión enfocada, con memoria medida después (25). El más cercano: 30 personas, 3 semanas, más respuestas por día con una notificación (mediana de 5.5 contra 2), memoria sin medir, y ~14% menos respuestas cada día (Schneegass) [viejo, 2021]. El creador de Anki duda de la exposición pasiva. Que el repaso distraído fije o no la memoria, está en disputa.
- **Dejar la app no es cuestión de minutos.** Hay quien abandona Readwise con un minuto por día (18). Hacer pocas no alcanza si la persona no siente que lo necesita.

**Qué podés esperar, inferencia mía y sin datos firmes.** A $9.99, con la comisión de 15%, cada venta te deja ~$8.50, así que $1,000 por mes piden ~118 ventas, todos los meses. Wins, una app de Mac de las que salieron bien, vendió ~107 por mes durante 15 meses, a ~$6 cada una: unos $630 por mes [viejo, 2023]. A $1.99, los mismos $1,000 piden ~590 ventas por mes. Lo más probable, para mí, es entre casi nada y $1,000 por mes. Un buen resultado serían pocos miles. Más que eso no lo sostiene nada de lo que encontré.

**Qué cambiaría mi respuesta.** Una sola cosa, y la podés medir: entre tus amigos de #359, ¿cuántos la dejan prendida después de 3 semanas, siguen respondiendo y pagarían? Alcanza con preguntarles, sin analytics. Con 5 o 10 personas no es estadística, pero nadie tiene ni eso. Y tus amigos no son compradores: pueden largarla porque no sienten la necesidad, o seguir por cariño. Si se cansan a las dos semanas, igual la respuesta cambia, por más hueco que haya.

## 5. El punto principal de venta

| Opción | A favor | En contra | Mi lectura |
|---|---|---|---|
| **A. "Las tarjetas vienen a vos"**, sin sentarte a estudiar | Espacio vacío entre las apps grandes de estudio (26). Es la promesa de Vocabulary. A Wunderbar la elogian por no tener sesión aparte (varios de 42, [HN, 2024](https://news.ycombinator.com/item?id=39999163) [viejo]). Abdaal y Sung defienden los ratos sueltos (07) | Demanda sin probar. Los que prometen esto son chicos. VocaBar se publicita como *sin* pop-ups: el pop-up cae mal (25, inferencia) | **El principal** |
| **B. "Nunca en una reunión"**, se frena sola | Trabajo de laboratorio sólido sobre momentos de corte (25) [viejo]. Ninguna app grande de estudio lo promete. Responde el miedo a A | No alcanza sola, y no te distingue de las chicas: PopCards y NotchWise también lo prometen, y ninguna muestra una reseña que lo confirme | **La prueba de A**, no un lema aparte |
| **C. "Unas pocas, para toda la vida"**, sin pila | La pila es la queja número uno. Palabras reales: *a few minutes*, *instead of scrolling*. Unas pocas por día es real (05) | Sin probar que resuelva nada. WaniKani limita y se apila igual. La gente también se va sin pila | **Segunda línea**, si tus amigos la confirman |
| **D. "Complemento de Anki"** (#450) | Honesta. Responde "¿por qué no Anki?". AnkiMobile y NotchWise usan esa idea. Importa con progreso | Nadie que siga con Anki la pide. No le dice nada a quien no conoce Anki. No puede ir en nombre, subtítulo ni keywords. El público es el más duro y ya tiene lo gratis | **Una frase de honestidad**, no el titular |
| **E. "Tus propias palabras", en vez de Vocabulary** | Pagan $35–60 por año; ~82 de 250 reseñas recientes se quejan de cobros; ~20 de 250 olvidan o quieren repasar (21). Pago único gusta | Quieren palabras puestas, y "spaced repetition" aparece 0 veces en 300 reseñas. Sin mazo inicial no hay caso | **Público para probar**, necesita tarjetas para empezar |
| **F. Privacidad, sin cuenta, pago único** | Pago único: varias fuentes. r/macapps pregunta qué hacés con los datos. Ente muestra que vende si los datos parecen delicados | Quizá unas tarjetas no se sienten delicadas (inferencia mía). En flashcards nadie lo probó | **Línea de apoyo**, no titular |

**La idea de #450, contra la evidencia:**
- Tu honestidad se sostiene. Es tu mejor respuesta a la objeción más repetida.
- "Complemento" como titular no. Te ata a un público que no lo pidió, y te deja sin nombrar lo que hace distinta a Ficha.
- "100% frictionless" no: ver la parte 6.

**Para quién es (inferencia):**
- Gente que pasa el día en la Mac y quiere recordar pocas cosas por gusto o por su trabajo: palabras, definiciones, conceptos, citas.
- Quien dejó Anki por la pila, y quien nunca se sentaría a estudiar.
- Quien ya usa Anki, solo como caso secundario: para lo chico, si lo quiere.
- **No es para:** medicina (300–700 repasos por día), exámenes con fecha, mazos de miles, ni quien quiere leer oraciones largas.

**Tu lista de #450, con lo que encontró esto:**
- **Palabras nuevas:** sostenido, con debate. La oración gana en teoría y en la práctica muchos ponen la palabra al frente (4 de 8, 04).
- **Una definición o un concepto:** nada en contra, y tampoco a favor de "Anki es demasiado". No encontré a nadie que diga overkill para capitales, citas, una palabra o una definición. Lo que la gente cuenta es el costo por dato, escribirlo y repasarlo, no la app (24).
- **Mapas:** geografía es el tema de placer más citado (05), y ya está el mazo gratis Ultimate Geography. Lo que falta es tocar el mapa, y Ficha tampoco lo hace. **No encontré evidencia de que Ficha gane acá.**
- **Oraciones largas y volumen:** confirmado que no.

**Dónde Ficha le gana claro a Anki:**
1. **Con Anki cerrado, en la Mac:** la tarjeta llega sola, y Anki no lo hace.
2. **Quien no se va a sentar a estudiar:** responde en segundos, sin parar lo que hace.
3. **Una colección chica de datos sueltos:** el costo de repasar cada dato baja. El de escribirlo, no.
4. **Arrancar sin aprender nada:** ~64 de 172 reseñas bajas de AnkiMobile lo critican por difícil, confuso o viejo.
5. **En la notificación del iPhone,** cuando salga.

Dónde **no**: gratis, Android y Windows, add-ons, mazos compartidos, volumen. Decirlo te conviene.

## 6. Cómo venderla

### El mensaje, con las palabras de la gente

**Sacá:** "frictionless", "microlearning", "bite-sized", "AI-powered", "overkill" y "habit": son de la industria, no de la gente (28). "Friction" subió en el foro de Anki (2 a 16 posts por año), pero la mitad de lo leído son desarrolladores. Evitá también "leech", "FSRS" al frente y "retention", que espantan al que recién llega.

**Usá lo que dicen:** *pile*, *wall of cards*, *chore*, *can't keep up*, *too heavy*, *a few minutes*, *instead of scrolling*, *simple*, *pay once*. En español no hay datos firmes de cómo lo dicen acá: en Argentina no encontré comunidad (09).

### Página del App Store, borrador para debatir

- **Nombre:** Ficha, y en la línea siguiente lo que hace. Nada de "Anki".
- **Subtítulo:** "Flashcards that come to you" (27 caracteres).
- **Primera frase:** "You don't sit down to study. Every so often a small card shows up on your Mac: flip it, rate it, and go back to what you were doing."
- **Segunda:** "Never during a meeting, a video or a full-screen app."
- **Tercera:** "A few cards at a time, instead of a wall of cards. For words, definitions and things you want to keep."
- **Cuarta:** "Simple, no fuss. Pay once, with no account and no subscription. Your cards stay on your devices and your own iCloud."
- **Honestidad:** "It doesn't replace Anki, and it isn't built for thousands of cards. If you use Anki, you can bring a deck with its progress. Anki is a trademark of Ankitects; Ficha isn't affiliated."
- **Primeras capturas (inferencia):** la tarjeta sobre trabajo real, no sobre un fondo vacío; que se ve chica; el widget.
- **Keywords:** flashcards, vocabulary, memorize, words, menu bar, widget. "Spaced repetition" la buscan los que ya saben. Nunca "Anki". Sin una herramienta de keywords esto es a ojo (bloqueo).

**Sobre nombrar a Anki.** Regla 2.3.7 de Apple: nada de marcas ajenas en metadatos, ni otras apps en el subtítulo. Regla 4.1(c): ni nombre ni ícono sin aprobación. No hay regla sobre una línea factual en la descripción, pero el silencio no es permiso, y 5.2.1 alcanza para objetarla. Otras apps lo hacen, y eso prueba poco. El creador de Anki aprobó en 2025 un aviso de no afiliación, pero era una función gratis de otra plataforma, de alguien que dijo no competir. Ficha sería paga y compite. **No soy abogado.** Antes de publicar, conviene preguntarle a Anki por escrito, y averiguar quién tiene la marca desde el traspaso a AnkiHub.

### Precio

| App | Cobra | Dato |
|---|---|---|
| Plan actual (#252) | ~$1.99 una vez | En el piso, con Word Drop, $1.99, y RecallPrompt, $0.99 |
| Wunderbar, palabras en la barra | $4.99 una vez | Sin quejas de precio |
| Flashcards Deluxe | $4.99 una vez | Se elogia el pago único |
| PopCards, tarjetas que aparecen | $9.99 una vez | Sin datos |
| Flashcard Hero, Mac | $14.99 una vez | |
| NotchWise Pro | $19.99 una vez, gratis con 50 tarjetas | Sin datos |
| AnkiMobile | $24.99 una vez | Por lo que vale: ~82 en contra, 49 a favor. Un hilo reclama que no haya prueba |
| Mochi Pro | $5 por mes | Se paga por el sync |
| Vocabulary | $35–60 por año | Cobros: la queja mayor |

**Lo que sale de acá:**
- Bajo $10, sin quejas en 3 de 3 hilos de r/macapps; de $30 a $60, quejas en 3 de 4. Son pocos hilos, y que nadie se queje no es elogio.
- Te propongo debatir **gratis con límite y un pago único de unos $9.99, que valga para Mac y iPhone**. Da prueba, que le reclaman a AnkiMobile en un hilo (24), y no hay suscripción que enoje. No hay evidencia para fijar el número exacto.
- Precio regional: un hilo de Brasil lo pide para AnkiMobile, 6 personas con respuestas divididas (09). Apple deja fijar por país.
- Para el debate de #252: en 5 de 6 apps de IA con reseñas en Trustpilot, los cobros son la queja mayor o empatada (17), y una suscripción cambiaría lo que hoy te hace distinta.

### Canales, en este orden

1. **Búsqueda del App Store.** ~65% de las descargas de iOS, dice Apple. En Mac no hay cifra de Apple: MacPaw, que vende Setapp, dice que 52% llega directo, así que una página propia también cuenta. AlgoApp y Noji crecieron por búsqueda con el atajo del nombre, que vos no tenés. Pedir destacado a Apple, 2 semanas a 3 meses antes.
2. **r/macapps, 260K.** Me parece la vía más clara para algo con precio, y es inferencia: explicar qué problema resuelve, comparar, dar el precio, 1 vez cada 30 días. En una lista de dos días, 18 de 25 posts figuraban sin texto, quizá borrados, y no sé qué le pasó ahí a ninguna app de flashcards paga.
3. **Prensa por contacto, no en frío.** [Indie App Spotlight de 9to5Mac](https://9to5mac.com/guides/indie-app-spotlight), el hilo por producto de MacRumors, TidBITS (preguntando antes), Mac Power Users (participando antes).
4. **Show HN**, con parte gratis. Esperá ~3 puntos: es lo normal. Ayuda una idea angosta y clara, y responder.
5. **awesome-fsrs**, por issue o PR: gratis y admite apps pagas.
6. **Con permiso:** r/Anki pidiendo excepción antes, r/languagelearning, el hilo de los miércoles de r/LearnJapanese, el foro de Anki en Add-ons, diciendo precio e independencia.

Product Hunt da poco: en casos recientes, 7 pagos con un top 5, y 4 suscriptores con 179 votos. Medicina, no.

### Dos riesgos a pensar antes de lanzar

- **Ficha la hacen agentes.** "AI slop" y "vibe coded" son acusaciones que corren en r/macapps y r/Anki (28), y el repo público lo muestra. Si lo preguntan y no lo contaste, sale peor. No hay evidencia de qué conviene decir; lo pondría en el debate.
- **AnkiHub puede cerrar el hueco.** AnkiMobile sacó versión nueva el 3 de noviembre, después de 14 meses, y sus notas no mencionan widgets. El equipo publica más rápido, AnkiDroid tiene recordatorios nuevos detrás de una opción, y un widget podría salir sin aviso (01). Si agregan tarjetas fuera de la app, tu ventaja cambia.

El detalle de quién paga, los precios, las palabras, las comunidades y los lanzamientos está en el [anexo](#anexo-material-de-marketing).

## Bloqueos

Están todos en [`market/blockers.md`](market/blockers.md), con 14 cosas concretas que podrías hacer. Reddit sigue siendo el más grande: por el archivo pude leer r/Anki y algunos otros, no todos, y muchas búsquedas fallaron.

## Anexo: material de marketing

Junta los informes 06, 12, 22, 23, 26, 27 y 28, de noviembre de 2026, con las correcciones de la verificación. No hay nada nuevo.

**Cómo leerlo:**
- Reddit no se pudo leer directo. **[archivo]**: por Arctic Shift; puntajes y borrados pueden diferir, y los links, armados con IDs, no se abrieron. **[segunda mano]**: snippet o resumen ajeno.
- Los informes parafrasean casi todo. Acá van subtítulos como dato, términos sueltos y una sola frase entera. Las otras frases cortas están en "Words people use" de 12, 23 y 27.

### 1. Quién paga y por qué

No hay ninguna encuesta sobre quién paga flashcards: esto está armado de pedazos. Solidez: **A** auditado; **B** lo dice la empresa o el desarrollador; **C** estimación de tracker, errada a veces por 4x o más; **D** sin fuente.

- **Idiomas, los mayores pagadores probados.** Duolingo: ver tabla. Inferencia: ~8.6% de los mensuales paga, ~$82 al año cada uno.
- **Escolares y universitarios, mayor audiencia, pagan con bronca.** Quizlet dice 60M+ ([prensa, jul 2025](https://techintelpro.com/news/ai/enterprise-ai/quizlets-how-america-learns-report-highlights-ai-and-digital-learning-trends)), B; no publica cuántos pagan. Trustpilot 1.4/5 de 500+ reseñas, según [un sitio que vende tutorías](https://www.myengineeringbuddy.com/blog/quizlet-reviews-alternatives-pricing-offerings/).
- **Medicina, los más seguros, y pagan más de una vez.** 68.3% de 560 estudiantes de EE.UU. usaba Anki ([snippet](https://pmc.ncbi.nlm.nih.gov/articles/PMC8651966), [viejo, 2020]). Sin encuesta en dólares.
- **Profesionales:** bancos de preguntas ([Pocket Prep](https://www.pocketprep.com/frequently-asked-questions/), [AMBOSS](https://www.amboss.com/int/pricing)), sin cifras. Inferencia: la plata sigue a una fecha de examen.
- **Hobby:** poco. [HN](https://hn.algolia.com/api/v1/search?query=anki%20would%20pay%20for&tags=comment&hitsPerPage=40): ~4 de 8 pagarían, ~4 no porque Anki es gratis; casi todo viejo.
- **Padres:** sin evidencia.

| Quién | Número | Solidez |
|---|---|---|
| Duolingo | $309.0M el trimestre, ~87% suscripciones; 13.1M pagos de 153.1M mensuales ([SEC](https://www.sec.gov/Archives/edgar/data/0001562088/000162828026069474/q3fy26duolingo9-30x26share.htm)) | A |
| Chegg | $121M el trimestre, -30%; 3.2M subs, -31% ([Maginative, may 2025](https://www.maginative.com/article/chegg-slashes-22-of-workforce-amid-ai-disruption-in-edtech/)) | A |
| Quizlet | $139M, jun 2025 ([Latka](https://www.getlatka.com/companies/quizlet)), no creíble: $80M ocho meses antes, con visitas en baja (30); ~$4M/mes App Store ([AppSprint](https://appsprint.app/quizlet-monthly-downloads)) | C |
| Brainscape | $6.1M 2024, 40 personas ([Latka](https://getlatka.com/companies/brainscape)); iOS bajo $10K/mes ([AppGoblin](https://appgoblin.info/apps/442415567)) o $65K ([ScreensDesign](https://screensdesign.com/apps/brainscape-smart-flashcards/)) | C |
| Noji | $160K y $250K/mes en [la misma página](https://screensdesign.com/showcase/anki-pro-study-flashcards) | C |
| Memrise | $18.5M 2023 ([snippet](https://businessofapps.com/?p=70303), [viejo, 2023]) | C |
| RemNote | ~$2.1M ([Latka](https://getlatka.com/companies/remnote.com/competitors)); 1M+ usuarios ([About](https://www.remnote.com/about)) | C/B |
| Gizmo | 13M usuarios; "<$1M" o "$25M by 2026" ([TAMradar](https://www.tamradar.com/funding-rounds/gizmo-series-a-22m), [Dealroom](https://dealroom.co/companies/gizmo/), [Caplight](https://www.caplight.com/company/gizmo)) | B/D |
| AnkiDroid | 4.0M usuarios únicos en Google Play ([equipo, dic 2025](https://forums.ankiweb.net/t/ankidroid-2025-wrapped/68014.md)) | B |
| AnkiMobile | #4 paga en iPhone, EE.UU., 2025 ([9to5Mac](https://9to5mac.com/2025/12/10/here-are-iphones-most-downloaded-apps-and-games-of-2025/)); solo puesto | B |

Inferencia, floja, sobre AnkiMobile: [456K instalaciones, +3K/mes](https://www.appgoblin.info/apps/373493387) a $25 da ~$900K por año antes de Apple. La verificación le da un rango de $0.5M a $2M, sin publicar. Ese tracker le da 9K usuarios mensuales, demasiado poco: no confiar en ninguno. Anki dice que iOS paga el sync ([foro, feb 2026](https://forums.ankiweb.net/t/ankis-growing-up/68610/110)), B.

**Fábricas de informes, a descartar:** [PW Consulting](https://pmarketresearch.com/it/flashcard-app-market) $740M (2025, informe a $3,340); [Verified Market Research](https://www.verifiedmarketresearch.com/product/flashcard-learning-software-market/) $1.32B (2025); [Business Research Insights](https://www.businessresearchinsights.com/market-reports/flashcard-app-market-124828) $0.93B (2026), que se contradice (test prep 42.8% y 32%) y le da a Anki ~$167M; [Verified Market Reports](https://www.verifiedmarketreports.com/product/flashcard-app-market/) $2.01B (2026). Ninguno muestra método. También D: [Readwise "$14M ARR"](https://fueler.io/blog/readwise-usage-revenue-valuation-growth-statistics), [5.2M pagos de Quizlet](https://canvasbusinessmodel.com/products/quizlet-swot-analysis).

**Pago único o suscripción.**
- Pago único subió de 6.4% de los ingresos (2023) a 10.3% (2025), con consumibles adentro; los planes semanales tienen 55.6% ([Adapty](https://adapty.io/state-of-in-app-subscriptions-report/), vende paywalls). 23.2% de las apps vende suscripción más lifetime ([RevenueCat](https://www.revenuecat.com/state-of-subscription-apps-2026/), vende suscripciones). Sus datos excluyen apps pagas que nunca las usaron.
- [Educación](https://www.revenuecat.com/state-of-subscription-apps-2026-education): mediana $44.99/año, la más alta; $9.99/mes; 6.5% de descarga a prueba; $0.30 por instalación al día 14.
- La mayoría gana casi nada: ~$72/mes al año de lanzar; 17.3% llega a $1K/mes en dos años, 4.6% a $10K (RevenueCat).
- Mac: 52% de los ingresos viene de fuera del App Store entre quienes usan ambos; 20% usa solo la tienda ([MacPaw](https://brettterpstra.com/2024/12/10/the-macpaw-2024-developer-survey/), patrocinada, vende Setapp).

| App indie (autodeclarado) | Modelo | Números |
|---|---|---|
| [Lunar y otras 4](https://notes.alinpanaitiu.com/Costs-of-running-a-macOS-app-studio-business), Mac | 86% vendido fuera de la tienda | 2023: $108.4K ventas, ~$5,800/mes neto [viejo, 2023] |
| [VirtualHostX](https://tyler.io/2014/07/28/a-candid-look-at-the-financial-side-of-building-mac-apps-on-your-own/), Mac | Único, $7 a $49 | $2,288 (2008) a $58,093 (2013); ~$200K total [viejo, 2014] |
| [MacWhisper](https://startupsemail.substack.com/p/100000-revenue-with-a-simple-mac) | Único | ~$100K en ~8 meses, sin verificar [viejo, 2023] |
| [Launch Center Pro](https://www.revenuecat.com/blog/growth/david-barnard-launch-center-pro-launched-podcast-2026.md) | Único $3-5; la suscripción fracasó | ~$1M bruto total (blog de RevenueCat, que lo emplea) |
| [Ulysses](https://techround.co.uk/startups/ulysses-the-writing-app) | Único a $39.99/año | ~50,000 subs a 4 años; ~6 meses de enojo [viejo, 2021] |
| [Slopes](https://yespress.io/curtis-herbert) | Suscripción | $1M ARR tras nueve años (snippet) |

Ningún fundador de una app de flashcards publicó ingresos. [Mochi](https://www.appgoblin.info/apps/1507775056): 29K instalaciones iOS, C. Inferencia del informe 23, que la verificación no pudo sostener porque no hay número honesto: la mayoría, bajo $1K/mes; un buen resultado solo, $50K-150K/año; raro, ~$1M/año. A $25 único, con 15% de corte, $50K/año pide ~2,350 compradores nuevos por año, siempre.

Compradores, dice la gente: [MPU](https://talk.macpowerusers.com/t/why-do-developers-prefer-subscriptions/40177), 12 voces, aceptan suscripción si el valor sigue llegando. [Voice Dream Reader](https://mjtsai.com/blog/2024/04/08/voice-dream-reader-switches-to-subscriptions/) revirtió sus $79/año [viejo, 2024].

### 2. Tabla de precios

Precios: dice la app. Reseñas: dice la gente (06, salvo aviso).

| App | Cobra | Qué dicen del precio |
|---|---|---|
| AnkiMobile | $24.99 único | ~130 de 250 reseñas: ~82 en contra, 49 a favor; en "most helpful", 12 a favor, 7 mixtas, 10 en contra. Alemania 25 a 6 en contra (~€30). Japón, 16 divididas (~¥4,000). [R$149.90 en Brasil](https://forums.ankiweb.net/t/suggestion-please-consider-regional-pricing-for-brazilian-students/62383.md) |
| AnkiDroid, Anki escritorio | Gratis | Al menos 12 reseñas de AnkiMobile lo oponen |
| [AnkiHub](https://www.ankihub.net) | Core $6/mes (su [FAQ](https://www.ankihub.net/faq): $5); Premium $10; lifetime $450 | Lifetime: 0 sí, 11 no, 2 condicionales de 14 ([1qv6kec](https://www.reddit.com/r/medicalschoolanki/comments/1qv6kec/), [archivo]) |
| Quizlet | Plus $9.99 y $44.99; Teacher $35.99 | 34 de 50 hablan de precio; recorte del gratis [viejo, 2022-23] |
| Brainscape | Pro $19.99/mes, $59.99/6 meses, $95.99/año, $199.99 lifetime | 78 de 100 con cinco estrellas; muchos elogian el gratis |
| RemNote | Pro $14.99, $149.99/año; con AI $29.99, $299.99; MCAT hasta $399.99 | 1 queja por lifetime de $395 |
| Knowt | $9.99/semana, $14.99-$24.99/mes, $59.99-$149.99/año | 12 cobros sorpresa |
| Vocabulary | $9.99-$14.99 cortos, $35.99-$69.99 largos, $149.99 lifetime | 21 cobros sorpresa; ~8, paywall tras un setup largo; 2 piden pago único |
| Memrise | $24.99/mes, $61.99/año, $329.99 lifetime, oferta $131.99 | Recorte del gratis; ~6 contra pagar AI |
| Readwise | Lite $4.99-$6.99/mes; Full $8.99-$12.99/mes | Caro, y se quedan; 2 piden pago único [viejo] |
| Noji | Hasta $89.99/año; [lifetime $39.99-59.99](https://apptail.io/app/noji-flashcards-learning-Qzz/sri-lanka) | ~4 contra topes diarios |
| AlgoApp | $29.99/año, $149.99 lifetime | 2 contra topes; recorte del gratis |
| Wunderbar | $4.99 ($3.99 en su sitio) | Sin queja de precio ([archivo](https://www.reddit.com/r/macapps/comments/1v47ius/)) |

Sin datos de opinión: Mochi Pro $5/mes anual; SuperMemo $9.99, $99.99/año, cursos hasta $249.99; NotchWise Pro $19.99; PopCards $9.99; LingoBar $4.99; Space Pro $4.99, $44.99/año; Flashcards Deluxe $4.99; Flashcard Hero $14.99; [Migaku](https://community.wanikani.com/t/any-good-black-friday-cyber-monday-sales/72691) $500, $150 en oferta.

En r/macapps ([archivo], informe 22, pocos hilos, inferencia): de $30 a $60 únicos hubo quejas en 3 de 4 hilos; bajo $10, ninguna en 3 de 3. En HN: [Godspeed](https://news.ycombinator.com/item?id=39756325) $150 único, ~10-12 en contra y 5-6 a favor [viejo, 2024]; [Flash Notes](https://news.ycombinator.com/item?id=39962415), $35/año le pareció justo a alguien [viejo, 2024]. [Bunpro](https://community.bunpro.jp/t/lifetime-membership/28508?page=2) ~$120 lifetime [viejo, 2021]: casi todos contentos, 2-3 no llegan a pagarlo junto.

### 3. Cómo se presenta cada app

Dice la app. Subtítulo textual ([26](market/26-presentation.md)); primera frase parafraseada, porque 26 no la copió: el original está en sus links.

| App | Subtítulo | Primera frase |
|---|---|---|
| AnkiMobile | "Smart & powerful flashcards" | La app oficial de Anki |
| Quizlet | "Walk into every test ready" | Lo que estudies se vuelve herramientas personales |
| Brainscape | "Learn Faster & Remember Longer" | La app de flashcards con AI |
| RemNote | "Replace: Notion, Quizlet, Anki" | Todo en uno: notas y repetición espaciada |
| Mochi | "Simple, intelligent flashcards" | Notas y tarjetas en markdown |
| SuperMemo | "24 languages, 300 courses" | Idiomas con AI |
| Memrise | "Learn Spanish, French & More" | Para quien tiene un motivo concreto |
| Knowt | "AI Summarizers + Exam Prep" | Todo en uno, 7M estudiantes |
| Readwise | "Remember & Learn from Books" | Volver a tus subrayados |
| Vocabulary | "Word of the day widget & games" | Una palabra por desbloqueo |
| NotchWise | "Ambient notch flashcards" | El notch como lugar de repaso |
| Swiftflip | "Remember more. Study less." | Novedades; tarjetas ilimitadas, sin cuenta |
| LingoBar | "Learn Spanish, French & More" | Cuentas de palabras y audio |
| Space | "Study Smart - Anki Alternative" | Abre con el olvido |
| Noji | "Study Smart(formerly Anki Pro)" | Recordá cualquier cosa |
| AlgoApp | "Advanced spaced repetition" | La más potente y amigable |
| Flashcards Deluxe | "Clean, efficient, effective" | |
| Flashcard Hero | "Powerful flashcard app" | |

**Capturas** (dice la app, set de iPhone de EE.UU., parafraseado; las demás, en el [informe 26](market/26-presentation.md)):
- **AnkiMobile:** marco viejo de iPhone, sin eslóganes; tarjetas como en la compu y el calendario de Anki.
- **Quizlet:** aprender con tarjetas; apuntes a tarjetas y tests; ayuda con la tarea.
- **Brainscape:** "arma de estudio", 10M de usuarios; la IA hace tarjetas, con un archivo "ANKI" en el embudo.
- **Mochi:** estudiar menos y recordar más; notas en Markdown.
- **SuperMemo y Memrise:** 15 minutos por día.
- **Vocabulary:** 1 minuto por día, sobre una pantalla bloqueada real; 10,000+ palabras.
- **NotchWise:** repaso en 8 segundos; lista de funciones que arranca con "Anki Compatible" e incluye "Screen-Share Safe".
- **Noji:** tarjetas de YouTube en 5 segundos.

**Keywords:** el campo es privado, así que solo se infieren del nombre y el subtítulo: flashcards, test, AI. Verlas mejor pide una herramienta paga (bloqueo).

**Promesas que se repiten** (inferencia, sobre 23 apps): recordar más, ~9; AI hace las tarjetas, ~7 la ponen primero y ~13 la mencionan; poco tiempo, ~6; tamaño como prueba, ~6; calificaciones y exámenes, ~4; todo en uno, ~4.

**Casi vacío** (inferencia): tarjetas que llegan sin abrir la app (ninguna grande; solo apps de palabras, NotchWise y PopCards); frenarse en mal momento (NotchWise y PopCards); privacidad y sin cuenta (solo chicas); complemento y no reemplazo (NotchWise, AnkiLock, Flashcard Adder); pago único (AnkiMobile, Flashcards Deluxe, Flashcard Hero, chicas). Ojo: vacío puede ser falta de demanda, y las chicas tienen pocas calificaciones. AnkiMobile vende con la página más floja.

### 4. Nombrar a Anki

**No es asesoramiento legal (not legal advice).** Lo escribió quien no es abogado.

**Reglas de [Apple](https://developer.apple.com/app-store/review/guidelines/), parafraseadas:** 2.3.7, nombre único, sin llenar metadatos con marcas o apps populares, y el subtítulo no nombra otras apps. 4.1(c), ni nombre ni ícono ajenos sin aprobación. 5.2.1, nada protegido sin permiso. [Keywords](https://developer.apple.com/app-store/product-page/): sin marcas ni apps rivales. Inferencia: nombre, subtítulo y keywords están cerrados; ninguna regla habla de una frase factual de compatibilidad en la descripción, aunque 5.2.1 alcanza para objetarla. Sin casos en ningún sentido.

**La marca:** registrada por Ankitects Pty Ltd ([sitio](https://apps.ankiweb.net/)). EE.UU.: serie 79340880, registro 7838778, 24 de junio de 2025, por un snippet, sin verificar. [Las operaciones pasan a AnkiHub](https://forums.ankiweb.net/t/ankis-growing-up/68610.md); no se sabe quién tendrá la marca.

**Los mantenedores:** sin política escrita.
- [Sep 2025](https://forums.ankiweb.net/t/question-about-api-access-naming-anki-cards-in-external-app/66116): el desarrollador aprobó el aviso "marca de Ankitects, sin afiliación ni aval" de una plataforma paga, en una función gratis; dijo que los imitadores debieron renombrarse. Es lo único de un mantenedor sobre ese texto.
- Un miembro, no oficial ([jul 2026](https://forums.ankiweb.net/t/own-re-created-anki-app/70522), [abr 2026](https://forums.ankiweb.net/t/requesting-to-add-a-new-anki-add-on-to-ankiweb/69372)): quien repasa compite; lo voluntario se tolera, lo comercial arriesga.
- [FAQ](https://docs.ankiweb.net/faqs/anki-knockoffs.md): AlgoApp y Noji no son del ecosistema; pide avisar en reseñas.

**Qué hacen las otras:** 8 de 19 apps y 5 listados más la nombran. En el nombre: Renki, AnkiLock, Flashcard Adder, AnkiCard. Subtítulo: RemNote, Space, Noji, Flashcard Adder. Descripción: Brainscape, AlgoApp, Swiftflip, NotchWise, Azri. No la nombran: Quizlet, Memrise, Knowt, Readwise, SuperMemo, Vocabulary y otras. Con aviso de no afiliación: Renki, AlgoApp, Flashcard Adder. Esos subtítulos parecen romper 2.3.7 y siguen: estar publicado prueba poco. Sin juicios ni bajas conocidos.

**"Compatible con":** solo Renki y NotchWise. Doctrina: uso nominativo en EE.UU. ([abogado](https://www.patenttrademarkblog.com/?p=693), [viejo, 2023]); art. 14(1)(c) en la UE ([CMS](https://cms.law/en/gbr/legal-updates/pre-branded-spare-parts-cjeu-has-its-say-in-audi-trade-mark-case), no sobre apps). Modelo: [las reglas de marca de Apple](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html). Inferencia de 26: no en nombre, subtítulo ni keywords; una línea factual en la descripción tiene práctica y doctrina, sin permiso explícito.

### 5. Las palabras de la gente

Dice la gente: términos en su idioma. La única frase entera: "It's effective but it's miserable." ([HN, ene 2025](https://news.ycombinator.com/item?id=42733983)).

| Sentimiento | Sus palabras | Fuente |
|---|---|---|
| La carga | backlog, pile, wall of cards, debt, can't keep up, time-suck | [47 posts/año](https://forums.ankiweb.net/search.json?q=backlog%20after:2025-11-05); [propuesta](https://forums.ankiweb.net/t/proposal-backlog-recovery-planner-to-prevent-user-churn-burnout/70487); [1xc1ik0](https://www.reddit.com/r/Anki/comments/1xc1ik0/) [archivo] |
| Agotados | burnout, overwhelming, unbearable, throw in the towel | [18 posts/año](https://forums.ankiweb.net/search.json?q=overwhelming%20after:2025-11-05); [1u7urkq](https://www.reddit.com/r/Anki/comments/1u7urkq/) [archivo]; [hilo](https://forums.ankiweb.net/t/1671-reviews-burnout-please-help/7502) [viejo, 2021] |
| Aburridos | chore, tedious, sterile, artificial, boring | [1k4up52](https://www.reddit.com/r/languagelearning/comments/1k4up52/), [1xd3o1t](https://www.reddit.com/r/Spanish/comments/1xd3o1t/) [archivo]; [LingQ](https://forum.lingq.com/t/how-to-use-anki-without-getting-burnt-out-how-many-cards-a-day-and-stuff/34692) [viejo, 2022] |
| Demasiada app | too heavy, cumbersome, not intuitive, archaic, clunky, learning curve | [HN](https://news.ycombinator.com/item?id=44974565); reseñas (06) |
| Estorba | friction, needs a computer | [16 posts/año](https://forums.ankiweb.net/search.json?q=friction%20after:2025-11-05); reseñas (06) |
| Quieren un empujón | reminder, nudge, streak, motivation | [33 posts/año](https://forums.ankiweb.net/search.json?q=motivation%20after:2025-11-05); [pedido](https://forums.ankiweb.net/t/suggestion-add-notifications-to-anki/67355): 5 a favor, 4 críticos, 5 neutros |
| Quieren poco | simple, clean, no fuss, a few minutes, 5 minutes a day, instead of scrolling | Reseñas (06); [1vdft1u](https://www.reddit.com/r/Anki/comments/1vdft1u/) [archivo] |
| Dudan de las tarjetas | memorizing rectangles, rote, passive | [HN](https://news.ycombinator.com/item?id=44974565); [1s56n8u](https://www.reddit.com/r/medicalschool/comments/1s56n8u/) [archivo] |
| Desconfían de lo nuevo | AI slop, vibe coded, feels like an ad, clone, bloat, enshittification | [1quli3k](https://www.reddit.com/r/Anki/comments/1quli3k/), [1puozl7](https://www.reddit.com/r/Anki/comments/1puozl7/), [1lkxh9p](https://www.reddit.com/r/Anki/comments/1lkxh9p/), [1xhkxhd](https://www.reddit.com/r/macapps/comments/1xhkxhd/), [1xoh667](https://www.reddit.com/r/macapps/comments/1xoh667/) [archivo]; [Ricotta](https://news.ycombinator.com/item?id=42966942) |
| Bronca con cobros | scam, charged, bait and switch, subscription fatigue, money grab, lock-in | Reseñas (06); [1mqm3cm](https://www.reddit.com/r/macapps/comments/1mqm3cm/) [archivo]; [MPU](https://talk.macpowerusers.com/t/why-do-developers-prefer-subscriptions/40177) |
| Quieren ser dueños | one-time, no subscription, worth every penny, pay once and own | Reseñas (06); [1xhwqwp](https://www.reddit.com/r/macapps/comments/1xhwqwp/) [archivo] |

**De la industria, no de la gente** (inferencia): microlearning, bite-sized, frictionless, AI-powered, overkill; review debt como titular; habit, sobre todo. Investigadores: memory system, retrieval practice. Iniciados: leech, ease hell, retention, FSRS, que espantan al recién llegado.

**Matices:** "guilt" casi no aparece. Burnout es flojo en el foro de Anki (2 posts en un año), más fuerte en r/Anki y en blogs que venden. Friction subió de 2 a 16 posts en dos años, pero ~la mitad de 10 leídos son constructores. AI slop y vibe coded se extienden entre comunidades.

### 6. Dónde se junta la gente

Tamaños: [GummySearch](https://gummysearch.com/r/Anki/) y listas de Discord; miembros no son lectores. Las reglas de Reddit, SDN, Language Learners' Forum y MacRumors: [archivo] o [segunda mano]. "Cómo": lo que permite la regla.

| Lugar, tamaño | Regla | Cómo, con honestidad |
|---|---|---|
| r/Anki, 210k | Reglas 3 y 5 sacan apps sueltas; 9 removidas | Pidiendo excepción antes |
| [Foro de Anki](https://forums.ankiweb.net/about), 1,479 activos | Solo [prohíbe spam](https://forums.ankiweb.net/faq); AnkiHub administra | En Add-ons, con independencia y precio dichos; 0 a 2 responden |
| Discord de Anki, ~14.5k; Refold, 37k; MoeWay, ~30k | No legibles sin entrar | Sin datos |
| r/medicalschoolanki 200k; r/usmle 74k | No leídas | Sin datos |
| [SDN](https://forums.studentdoctor.net/help/tos) | Promoción paga solo en foros fijados | Como vendor verificado |
| r/languagelearning, 3.4M | [Permiso y etiqueta](https://www.reddit.com/r/languagelearning/wiki/rules_for_promotion) | Con permiso, sincero |
| r/LearnJapanese, 878k | [Hilo de los miércoles](https://www.reddit.com/r/LearnJapanese/wiki/subredditrules); posts sueltos con parte gratis | Ese hilo |
| [Language Learners' Forum](https://forum.language-learners.org/viewtopic.php?t=2968) | Hilo con permiso | Pidiéndolo |
| [Chinese-Forums](https://www.chinese-forums.com/forums/topic/64482-is-self-promotion-on-this-forum-becoming-a-problem-for-anyone-else/) | Útil y sobre chino | Solo si es específico |
| r/GetStudying 3.3M; r/productivity 4.3M | No leídas | Sin datos |
| [r/macapps](https://www.reddit.com/r/macapps/comments/1uknpm8/), 260k | Problema, comparación, precio; 1 cada 30 días; criterios de confianza; ~18 de 25 sin texto, quizá borrados | La vía más clara para algo con precio, y dura (inferencia) |
| [Mac Power Users](https://talk.macpowerusers.com/t/advertising-software-in-the-mpu-forum/44348) | Sin política; ~13 de 15 quieren límites | Participar primero |
| [MacRumors](https://forums.macrumors.com/threads/post-mac-applications.854050/) | Un hilo por producto | Ahí; los nuevos no se autolinkean |
| [TidBITS Talk](https://talk.tidbits.com/t/rules-on-self-promotion/30612) | Si vende, preguntar | Preguntándole al editor |
| [Show HN](https://news.ycombinator.com/showhn.html) | Fácil de probar sin registro | Con prueba o parte gratis (inferencia); responder |
| [Product Hunt](https://www.producthunt.com/launch) | No pedir votos | Cuenta personal |
| r/SideProject, 892k | Abierto; ~14 de 25 sin comentarios | Poca atención |
| [awesome-fsrs](https://github.com/open-spaced-repetition/awesome-fsrs) | Issue o PR; admite pagas | Un listado simple |
| [App Store](https://developer.apple.com/app-store/getting-featured/) | Nominar 2 semanas a 3 meses antes | Dice la app |

Newsletters y podcasts: no hay ninguno dedicado a repetición espaciada. [Indie App Spotlight de 9to5Mac](https://9to5mac.com/guides/indie-app-spotlight) recibe pitches por mail.

### 7. Lanzamientos

Puntos/comentarios de HN, que no son ventas. Mediana de los [368 Show HN de flashcards](https://hn.algolia.com/api/v1/search?query=flashcards&tags=story,show_hn&hitsPerPage=0): 2 puntos. La de todo Show HN, en dos muestras: 3 (30). No es un fracaso de la categoría.

| Tipo | Lanzamientos |
|---|---|
| Necesidad angosta | [AWS cards](https://news.ycombinator.com/item?id=27264500) 365/118 [viejo, 2021]; [LeetCode](https://news.ycombinator.com/item?id=40173237) 206/100 [viejo, 2024]; [Fata](https://news.ycombinator.com/item?id=48489163) 124/53 |
| Alimentan a Anki | [Anki AI Utils](https://news.ycombinator.com/item?id=42534931) 253/43; [Ankify](https://news.ycombinator.com/item?id=31294306) 180/62 [viejo, 2022] |
| App general, idea clara | [Ginkgo](https://news.ycombinator.com/item?id=42317393) 244/94; [21st Night](https://news.ycombinator.com/item?id=27662266) 123/128 [viejo, 2021]; [Mochi](https://news.ycombinator.com/item?id=20029466) 91/31 [viejo, 2019] |
| Planos | [Funky Flashcards](https://news.ycombinator.com/item?id=46205560) 6/2; [Discito](https://news.ycombinator.com/item?id=48910518) 1/0; [flashcasts](https://news.ycombinator.com/item?id=39777720) 3/1 [viejo, 2024] |
| Barra de menú | [MeetingBar](https://news.ycombinator.com/item?id=23991111) 131/54 [viejo, 2020]; [Nightwatch](https://news.ycombinator.com/item?id=49952148) 89/28; casi todas 1-5 |
| Product Hunt, votos | [FlashCard](https://www.hunted.space/product/flashcard) 12; [StackCards](https://www.hunted.space/product/stackcards) 14; sin fecha |

**Ventas, dice cada autor:** [Wins](https://news.ycombinator.com/item?id=38388608): 1,612 licencias, $9,485 en 15 meses. [DisplayBuddy](https://www.starterstory.com/stories/i-launched-a-mac-app-with-zero-advertising-800-customers-in-first-8-months) [viejo, 2021]: 800+ clientes en 8 meses, ~$5,000 (el sitio vende membresías). [Redacted](https://soff.es/blog/redacted-for-mac-launch) [viejo, 2015]: 538 votos; #8 paga con 59 unidades; [$302](https://www.macrumors.com/2015/05/07/redacted-mac-app-profits/). [ExtraBar](https://www.producthunt.com/p/extrabar/one-month-later-380-users-4-major-updates-and-extrabar-is-just-getting-started): 380 usuarios en un mes. [Noticky](https://www.indiehackers.com/product/noticky): 150+ ventas en 10 semanas (snippet). [Chunk](https://hackernoon.com/lite/i-turned-a-failed-product-hunt-launch-into-a-top-3-win-on-a-budget): 10 votos, ~300 al relanzar, con intercambio de comentarios.

**Por qué:** un primer post plano no es final (CleverDeck, Zorbi, 21st Night, Chunk). Chunk culpa a la página. Responder parece ayudar (inferencia, 3 hilos). El pico cae rápido: [Unread](https://mjtsai.com/blog/2014/07/28/a-candid-look-at-unreads-first-year/) hizo media venta anual en cinco días [viejo, 2014].

**Objeciones en 15 hilos de HN** (dice la gente; conteo, inferencia): ¿por qué no Anki?, 8 de 11 que compiten; precio, ~9 de 15; memorizar no es entender, ~8; página confusa, ~7; encierro, ~7; falta plataforma, ~6; ¿qué algoritmo?, ~5; offline, ~4; cuenta para probar, ~3. r/macapps ([archivo](https://www.reddit.com/r/macapps/comments/1xns7fo/)): en qué difiere, prueba, qué hace con los datos. Elogiar "sin cuenta": nadie en ~17 hilos de Reddit, pero sí en StackCards. En barra de menú: desorden, seguridad, avisos de Gatekeeper.

**Qué trae ventas a apps chicas pagas** (dicen autores, casi todo viejo):
- Boca a boca y versiones mayores a clientes ([VirtualHostX](https://tyler.io/2014/07/28/a-candid-look-at-the-financial-side-of-building-mac-apps-on-your-own/)).
- Búsqueda en la tienda: [~65% de descargas](https://www.macrumors.com/2025/12/18/app-store-search-results-more-ads-2026/), dice Apple, sin cifra para Mac; [TableFlip](https://christiantietze.de/posts/2019/06/tableflip-app-store-stats/) [viejo, 2019]. Anuncios [comen lo orgánico](https://pxlnv.com/linklog/another-ad-app-store-search/) en iOS.
- Prensa por contacto, no en frío (DisplayBuddy).
- Directo: Wins vendió 701 licencias en su sitio.
- Sin datos: MacStories, YouTube, Setapp, newsletters. r/macapps: feedback, pocas ventas ([segunda mano](https://clearfounder.com/presenting-launch)).
