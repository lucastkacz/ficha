# Ficha's words in each language

Every text the app shows is translated into Ficha's languages, which `scripts/languages.txt` lists, each from the change that first translates the catalogs into it (ADR 0027), and a term reads the same on every screen. This list holds the word each language uses for each term the UI shows: a new text uses the words here, and a new term gets a row in the change that brings it.

A term's source says where its words come from:

- **Anki**: Anki's own translation, from its Fluent files in [`ankitects/anki-core-i18n`](https://github.com/ankitects/anki-core-i18n), `core/<locale>/*.ftl`, under the message ID the row names. Where Anki has two words for one term, the row picks one.
- **Apple**: the word macOS uses in that language, in its own menus, System Settings and Finder. For Spanish, a Mac in Spanish (Latin America), `es_419` in macOS's own files, whose words are the ones Rioplatense Spanish uses ("Configuración", "Agregar", "respaldo"), not a Mac in Spain's Spanish ("Ajustes", "Añadir", "copia de seguridad"): Lucas's call, on 2 November 2026.
- **Ficha**: our own word, chosen in the first translation into that language.

A language gets its column here in the change that translates the catalogs into it. Spanish is Rioplatense, with "vos" in what the app asks of the user ("Elegí", "Revisá", "Tenés"), and Anki's words stay as Anki's Spanish has them, but where a row says otherwise. Quotes are « ».

## Anki's terms

| English | Source | Spanish (es) | German (de) |
|---|---|---|---|
| Again | Anki `studying-again` | Otra vez | Nochmal |
| Hard | Anki `studying-hard` | Difícil | Schwer |
| Good | Anki `studying-good` | Bien | Gut |
| Easy | Anki `studying-easy` | Fácil | Einfach |
| deck | Anki `decks-deck` | mazo | Stapel |
| card | Anki `browsing-card` | tarjeta | Karte |
| tags | Anki `editing-tags` | etiquetas | Schlagwörter, a tag: Schlagwort |
| new (a card) | Anki `actions-new` | nueva; New in the sidebar: Nuevas | neu; New in the sidebar: Neu |
| learning | Anki `scheduling-learning` | Aprendiendo | Lernen |
| interval | Anki `browsing-interval` | intervalo | Intervall |
| learning steps | Anki `deck-config-learning-steps` | pasos en la etapa de aprendizaje | Lernstufen; a step: Stufe |
| relearning steps | Anki `deck-config-relearning-steps` | pasos de reaprendizaje | Lernstufen für das Wiedererlernen; in a sentence beside the learning steps: Lern- und Wiedererlernstufen |
| desired retention | Anki `deck-config-desired-retention` | retención deseada | Gewünschte Erinnerungsquote |
| longest interval | Anki `scheduling-maximum-interval` | intervalo máximo | Höchstintervall |
| forgotten (lapses) | Anki `scheduling-lapses` | olvidada, as Anki's "Olvidos" | vergessen, as in „Nach 8-maligem Vergessen“: ours, since Ficha's English always says forget and shows no Lapses label, where Anki's „Fehlversuche“ (failed attempts) would fit |
| due | Anki `browsing-sidebar-due-today` | pendiente; Due in the sidebar: Pendientes | fällig; Due in the sidebar: Fällig |
| front | Anki `notetypes-front-field` | anverso | Vorderseite |
| back | Anki `notetypes-back-field` | reverso | Rückseite |
| bury, buried | Anki `studying-bury`, `browsing-buried` | enterrar, enterrada | begraben, begraben; unbury: ausgraben. Ours, not Anki's: Anki's German says „Bis morgen aufschieben“ and „Aufgeschoben“ (put off until tomorrow), which would tell the user a buried card comes back, while Ficha's bury is for good; „begraben“ is the literal word, as Spanish's „enterrar“, and in German also means giving something up for good |
| suspended | Anki `browsing-suspended` | suspendidas | ausgeschlossen |
| Default (the deck) | Anki `deck-config-default-name` | Predeterminado | Standard |
| retrievability | Anki `card-stats-fsrs-retrievability` | recuperabilidad | Abrufbarkeit |
| stability | Anki `card-stats-fsrs-stability` | estabilidad | Stabilität |
| difficulty | Anki `card-stats-fsrs-difficulty` | dificultad | Schwierigkeitsgrad |
| New cards per day (the setting) | Anki `scheduling-new-cardsday` | Tarjetas nuevas/día, its label in Settings; in a sentence, tarjetas nuevas por día, ours, where the slash reads wrong | Tageshöchstwert für neue Karten, its label in Settings; in a sentence, neue Karten pro Tag, ours |
| Scheduling (Settings' tab) | Anki `preferences-scheduling` | Programación | Zeitplanung |
| created | Anki `browsing-created` | creada | erstellt |
| notes (Anki's) | Anki `browsing-notes` | notas | Notizen |
| Import, Export | Anki `actions-import`, `actions-export` | Importar, Exportar | Importieren, Exportieren |
| Support older Anki versions | Anki `exporting-support-older-anki-versions` | Compatibilidad con versiones anteriores de Anki | Unterstütze ältere Anki-Versionen |
| Notes in Plain Text | Anki `exporting-notes-in-plain-text` | Notas en texto plano | Notizen als einfache Textdatei |
| Image Occlusion | Anki `notetypes-image-occlusion-name` | Oclusión de imagen | Bildverdeckung |
| template (a card's, in Anki) | Anki `card-templates-template-box` | plantilla | Vorlage |
| Media (a card's images and sounds) | Anki `editing-media` | Multimedia | Medien |
| review ahead | Anki `custom-study-review-ahead` | repasar por adelantado, un repaso por adelantado | im Voraus wiederholen, eine Wiederholung im Voraus |
| graduate (a card leaving its steps) | Anki `scheduling-graduating-interval` | graduarse, as Anki's "Intervalo de graduación" | aufsteigen, as Anki's „Aufstiegsintervall“ |
| discard | Anki `actions-discard` | descartar | verwerfen |

## Apple's terms

| English | Source | Spanish (es) | German (de) |
|---|---|---|---|
| Settings… | Apple | Configuración… | Einstellungen … (a no-break space before the ellipsis, as Apple's German writes every …) |
| settings (an app's) | Apple | configuración | Einstellungen |
| System Settings | Apple | Configuración del Sistema | Systemeinstellungen |
| Login Items | Apple | Elementos de inicio | Anmeldeobjekte |
| Open at Login | Apple | Abrir al iniciar sesión | Bei der Anmeldung öffnen |
| Quit | Apple | Salir | Beenden |
| Cancel | Apple | Cancelar | Abbrechen |
| OK | Apple | OK | OK |
| Done | Apple | Listo | Fertig |
| Add | Apple | Agregar, as Apple's Spanish (Latin America) and Rioplatense Spanish say it, where Anki's `actions-add` says Añadir | Hinzufügen |
| Restore | Apple | Restaurar | Wiederherstellen |
| Close | Apple | Cerrar | Schließen |
| Undo | Apple | Deshacer | Widerrufen |
| Delete | Apple | Eliminar | Löschen |
| Edit | Apple | Editar | Bearbeiten |
| Paste | Apple | Pegar | Einsetzen |
| Find | Apple | Buscar | Suchen |
| Rename | Apple | Renombrar | Umbenennen |
| Show in Finder | Apple | Mostrar en el Finder | Im Finder anzeigen |
| Move to Trash, Trash | Apple | Transferir al basurero, basurero | In den Papierkorb legen, Papierkorb |
| Downloads | Apple | Descargas | Downloads |
| sidebar | Apple | barra lateral | Seitenleiste |
| menu bar | Apple | barra de menús | Menüleiste |
| Emoji & Symbols | Apple | Emoji y símbolos | Emoji & Symbole |
| Focus, Focus filter | Apple | enfoque, filtro de enfoque | Fokus, Fokusfilter |
| full screen | Apple | pantalla completa | Vollbild |
| backup, backups | Apple | respaldo, respaldos | Backup, Backups |
| About | Apple | Acerca de | Info, as the About pane of System Settings › General |
| Privacy Policy | Apple | Política de privacidad | Datenschutzrichtlinie |
| Finder's tag colors: Red, Orange, Yellow, Green, Blue, Purple, Gray | Apple | Rojo, Naranja, Amarillo, Verde, Azul, Morado, Gris | Rot, Orange, Gelb, Grün, Blau, Lila, Grau |

## Ficha's own terms

| English | Source | Spanish (es) | German (de) |
|---|---|---|---|
| review (noun) | Ficha | repaso | Wiederholung, Anki's German word for a review |
| review (verb) | Ficha | repasar | wiederholen, Anki's |
| Review now | Ficha | Repasar ahora | Jetzt wiederholen |
| review panel | Ficha | panel de repaso | Wiederholungsfenster |
| review log | Ficha | historial de repasos | Wiederholungsverlauf, the word Anki's German uses for a card's review history |
| capture (noun, verb) | Ficha | captura, capturar | Erfassung, erfassen. Not „Notiz“, which is Anki's note and appears beside it in the Import sheet |
| inbox | Ficha | bandeja | Eingang, Apple Mail's word for Inbox |
| approve (a capture into cards) | Ficha | aprobar | übernehmen |
| flag, flagged | Ficha | marcar, marcada | markieren, markiert, Apple Mail's word for flag; Anki's „Flagge“ names Anki's colored flags, another thing |
| expand, expansion | Ficha | ampliar, ampliación | erweitern, Erweiterung |
| follow-up (a question about a card) | Ficha | consulta | Rückfrage |
| refine, refine session | Ficha | refinar, sesión de refinado | ausarbeiten, Sitzung zum Ausarbeiten. Over the literal „verfeinern“: turning raw notes into finished ones is „ausarbeiten“ in German |
| appearance (a card showing up on its own) | Ficha | aparición | Einblendung |
| hold back appearances | Ficha | frenar las apariciones | Einblendungen zurückhalten |
| snoozed | Ficha | pospuesta | verschoben. Not Apple's „Schlummern“, an alarm's, nor „aufgeschoben“, Anki's word for buried |
| idle | Ficha | inactivo | inaktiv |
| priority deck, Prioritize | Ficha | mazo prioritario, Priorizar | Prioritätsstapel, Priorisieren |
| set aside | Ficha | apartar, apartada | zurückstellen, zurückgestellt |
| Both ways | Ficha | En ambos sentidos | In beide Richtungen |
| front first, back first | Ficha | anverso primero, reverso primero | Vorderseite zuerst, Rückseite zuerst; after a column's or a detail row's noun, short: (Rückseite), as „Fällig (Rückseite)“ |
| way (front first or back first) | Ficha | sentido | Richtung |
| learned | Ficha | aprendida; Learned in the sidebar: Aprendidas | gelernt; Learned in the sidebar: Gelernt |
| card type; Word, Concept, Quote, Question | Ficha | tipo; Palabra, Concepto, Frase, Pregunta | Typ; Wort, Konzept, Zitat, Frage |
| source (of a card) | Ficha | fuente | Quelle |
| note (on a capture or a flag) | Ficha | nota | Anmerkung. Not „Notiz“, Anki's note |
| pin to the sidebar | Ficha | fijar en la barra lateral | in der Seitenleiste anpinnen; unpin: lösen, Apple's „anpinnen“ and „lösen“ |
| capture shortcut | Ficha | atajo de captura | Kurzbefehl zum Erfassen, with Apple's „Kurzbefehl“ |
| Flip | Ficha | Dar vuelta | Umdrehen |
| Diagnostics | Ficha | Diagnóstico | Diagnose |
| sync | Ficha | sincronización, sincronizar | Synchronisierung, synchronisieren |
| an AI | Ficha | una IA | eine KI |
| tick, untick (a checkbox), since flag is marcar | Ficha | tildar, destildar | anhaken, Häkchen entfernen, since flag is markieren |
