# The app follows the Mac's language, starting with English

Lucas's Mac is set to English, and he wants Ficha in his Mac's language, though he speaks Spanish and his cards are in Spanish. So the app's interface follows the Mac's language: every text is written in English first, as the base language, and other languages come later as translations, starting with Rioplatense Spanish with "vos". The cards' content is Lucas's and doesn't depend on the app's language. The `ficha` CLI stays in English whatever the Mac's language, since Claude reads it while refining and Lucas is its only other reader.

## Considered options

- Spanish only, as the app started: Ficha wouldn't match the rest of Lucas's Mac.
- English and Spanish from the start, keeping the first Spanish texts as the translation: every change would write both languages, while Lucas's Mac shows English anyway.

## Consequences

- Texts go through Apple's String Catalogs, so a translation only adds strings. macOS picks the language from the Mac's preferred languages, and once there's a translation, System Settings can set it per app: Ficha has no language setting of its own.
- ADR 0008's last consequence no longer holds: the CLI's own help and messages are in English too.
