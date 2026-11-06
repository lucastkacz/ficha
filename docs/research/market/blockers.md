# Bloqueos de la investigación de mercado (#452)

Lo que la investigación no pudo leer, por qué, qué se probó y cómo podría ayudar Lucas. Se va completando tanda por tanda.

## Reddit

Probado el 2026-11-05, antes de lanzar los subagentes.

| Vía | Resultado |
|---|---|
| WebSearch limitado a `reddit.com` | Error 400: el dominio no es accesible para el agente de Claude |
| WebFetch a `www.reddit.com` y `old.reddit.com`, también su `.json` | Rechazado |
| Arctic Shift, un archivo público de Reddit, con posts y comentarios | Funciona con r/Anki y r/Spanish. r/LearnJapanese funciona con un rango de fechas |
| Arctic Shift con otros subreddits | Error 422 en r/medicalschool, r/step1, r/GetStudying y r/French. r/languagelearning dio 429 (límite de pedidos) |
| PullPush, otro archivo | Error 526 del lado del servidor |
| WebSearch sin filtro | Encuentra Reddit sobre todo de segunda mano, en blogs que lo citan, varios de ellos publicidad de apps de IA |

**Cómo podría ayudar Lucas:** una sesión exclusiva de Reddit con el navegador de la app, que no le saca la pantalla, todavía sin probar. Si Reddit pide login o CAPTCHA, eso lo resuelve él.

## YouTube

El skill `youtube-transcriber` maneja el navegador, así que no se usa. YouTube se lee por búsqueda web.
