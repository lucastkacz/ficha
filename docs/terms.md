# Ficha's words in each language

Every text the app shows is translated into Ficha's languages, which `scripts/languages.txt` lists, each from the change that first translates the catalogs into it (ADR 0027), and a term reads the same on every screen. This list holds the word each language uses for each term the UI shows: a new text uses the words here, and a new term gets a row in the change that brings it.

A term's source says where its words come from:

- **Anki**: Anki's own translation, from its Fluent files in [`ankitects/anki-core-i18n`](https://github.com/ankitects/anki-core-i18n), `core/<locale>/*.ftl`, under the message ID the row names. Where Anki has two words for one term, the row picks one.
- **Apple**: the word macOS uses in that language, in its own menus, System Settings and Finder. For Spanish, a Mac in Spanish (Latin America), `es_419` in macOS's own files, whose words are the ones Rioplatense Spanish uses ("Configuración", "Agregar", "respaldo"), not a Mac in Spain's Spanish ("Ajustes", "Añadir", "copia de seguridad"): Lucas's call, on 2 November 2026.
- **Ficha**: our own word, chosen in the first translation into that language.

A language gets its column here in the change that translates the catalogs into it. Spanish is Rioplatense, with "vos" in what the app asks of the user ("Elegí", "Revisá", "Tenés"), and Anki's words stay as Anki's Spanish has them, but where a row says otherwise. Quotes are « ».

## Anki's terms

| English | Source | Spanish (es) | German (de) | Italian (it) |
|---|---|---|---|---|
| Again | Anki `studying-again` | Otra vez | Nochmal | Ripeti |
| Hard | Anki `studying-hard` | Difícil | Schwer | Difficile |
| Good | Anki `studying-good` | Bien | Gut | Normale |
| Easy | Anki `studying-easy` | Fácil | Einfach | Facile |
| deck | Anki `decks-deck` | mazo | Stapel | mazzo |
| card | Anki `browsing-card` | tarjeta | Karte | carta |
| tags | Anki `editing-tags` | etiquetas | Schlagwörter, a tag: Schlagwort | etichette |
| new (a card) | Anki `actions-new` | nueva; New in the sidebar: Nuevas | neu; New in the sidebar: Neu | nuova; New in the sidebar: Nuove |
| learning | Anki `scheduling-learning` | Aprendiendo | Lernen | In apprendimento |
| interval | Anki `browsing-interval` | intervalo | Intervall | intervallo |
| learning steps | Anki `deck-config-learning-steps` | pasos en la etapa de aprendizaje | Lernstufen; a step: Stufe | passi di apprendimento |
| relearning steps | Anki `deck-config-relearning-steps` | pasos de reaprendizaje | Lernstufen für das Wiedererlernen; in a sentence beside the learning steps: Lern- und Wiedererlernstufen | passi di riapprendimento |
| desired retention | Anki `deck-config-desired-retention` | retención deseada | Gewünschte Erinnerungsquote | ritenzione desiderata |
| longest interval | Anki `scheduling-maximum-interval` | intervalo máximo | Höchstintervall | intervallo massimo |
| forgotten (lapses) | Anki `scheduling-lapses` | olvidada, as Anki's "Olvidos" | vergessen, as in „Nach 8-maligem Vergessen“: ours, since Ficha's English always says forget and shows no Lapses label, where Anki's „Fehlversuche“ (failed attempts) would fit | dimenticata, ours: Anki's "Errori" names the count, not the card |
| due | Anki `browsing-sidebar-due-today` | pendiente; Due in the sidebar: Pendientes | fällig; Due in the sidebar: Fällig | in scadenza, as Anki's `browsing-sidebar-due-today`; Due in the sidebar: In scadenza; the Due columns: Scadenza, as Anki's `statistics-due-date` |
| front | Anki `notetypes-front-field` | anverso | Vorderseite | fronte |
| back | Anki `notetypes-back-field` | reverso | Rückseite | retro |
| bury, buried | Anki `studying-bury`, `browsing-buried` | enterrar, enterrada | begraben, begraben; unbury: ausgraben. Ours, not Anki's: Anki's German says „Bis morgen aufschieben“ and „Aufgeschoben“ (put off until tomorrow), which would tell the user a buried card comes back, while Ficha's bury is for good; „begraben“ is the literal word, as Spanish's „enterrar“, and in German also means giving something up for good | seppellire, seppellita; Buried in the sidebar: Seppellite; unbury: disseppellire, as Anki's `studying-unbury` |
| suspended | Anki `browsing-suspended` | suspendidas | ausgeschlossen | sospese |
| Default (the deck) | Anki `deck-config-default-name` | Predeterminado | Standard | Predefinito |
| retrievability | Anki `card-stats-fsrs-retrievability` | recuperabilidad | Abrufbarkeit | rammentabilità |
| stability | Anki `card-stats-fsrs-stability` | estabilidad | Stabilität | stabilità |
| difficulty | Anki `card-stats-fsrs-difficulty` | dificultad | Schwierigkeitsgrad | difficoltà |
| New cards per day (the setting) | Anki `scheduling-new-cardsday` | Tarjetas nuevas/día, its label in Settings; in a sentence, tarjetas nuevas por día, ours, where the slash reads wrong | Tageshöchstwert für neue Karten, its label in Settings; in a sentence, neue Karten pro Tag, ours | Carte nuove/giorno, its label in Settings; in a sentence, carte nuove al giorno, ours, where the slash reads wrong |
| Scheduling (Settings' tab) | Anki `preferences-scheduling` | Programación | Zeitplanung | Pianificazione |
| created | Anki `browsing-created` | creada | erstellt | creata; the Created column: Data di creazione, as Anki's column says it |
| notes (Anki's) | Anki `browsing-notes` | notas | Notizen | note |
| Import, Export | Anki `actions-import`, `actions-export` | Importar, Exportar | Importieren, Exportieren | Importa, Esporta |
| Support older Anki versions | Anki `exporting-support-older-anki-versions` | Compatibilidad con versiones anteriores de Anki | Unterstütze ältere Anki-Versionen | Supportare vecchie versioni di Anki |
| Notes in Plain Text | Anki `exporting-notes-in-plain-text` | Notas en texto plano | Notizen als einfache Textdatei | Note in testo semplice |
| Image Occlusion | Anki `notetypes-image-occlusion-name` | Oclusión de imagen | Bildverdeckung | Occludi Immagine |
| template (a card's, in Anki) | Anki `card-templates-template-box` | plantilla | Vorlage | modello |
| Media (a card's images and sounds) | Anki `editing-media` | Multimedia | Medien | File multimediali, Anki's `preferences-media`: Anki has it singular too, "File multimediale" (`editing-media`), and a card's images and sounds are several |
| review ahead | Anki `custom-study-review-ahead` | repasar por adelantado, un repaso por adelantado | im Voraus wiederholen, eine Wiederholung im Voraus | ripassare in anticipo, un ripasso in anticipo: Anki's "Ripeti in anticipo" says ripetere, which Ficha's Italian keeps for Again (Ripeti), so the verb is Ficha's review, ripassare, with Anki's "in anticipo" |
| graduate (a card leaving its steps) | Anki `scheduling-graduating-interval` | graduarse, as Anki's "Intervalo de graduación" | aufsteigen, as Anki's „Aufstiegsintervall“ | essere promossa, as Anki's "Intervallo di promozione" |
| discard | Anki `actions-discard` | descartar | verwerfen | scartare |

## Apple's terms

| English | Source | Spanish (es) | German (de) | Italian (it) |
|---|---|---|---|---|
| Settings… | Apple | Configuración… | Einstellungen … (a no-break space before the ellipsis, as Apple's German writes every …) | Impostazioni… |
| settings (an app's) | Apple | configuración | Einstellungen | impostazioni |
| System Settings | Apple | Configuración del Sistema | Systemeinstellungen | Impostazioni di Sistema |
| Login Items | Apple | Elementos de inicio | Anmeldeobjekte | Elementi login |
| Open at Login | Apple | Abrir al iniciar sesión | Bei der Anmeldung öffnen | Apri al login |
| Quit | Apple | Salir | Beenden | Esci |
| Cancel | Apple | Cancelar | Abbrechen | Annulla |
| OK | Apple | OK | OK | OK |
| Done | Apple | Listo | Fertig | Fine |
| Add | Apple | Agregar, as Apple's Spanish (Latin America) and Rioplatense Spanish say it, where Anki's `actions-add` says Añadir | Hinzufügen | Aggiungi, as Apple's and Anki's `actions-add` both say it |
| Restore | Apple | Restaurar | Wiederherstellen | Ripristina |
| Close | Apple | Cerrar | Schließen | Chiudi |
| Undo | Apple | Deshacer | Widerrufen | Annulla, as Apple's Edit menu says it, the same word as Cancel |
| Delete | Apple | Eliminar | Löschen | Elimina |
| Edit | Apple | Editar | Bearbeiten | Modifica |
| Paste | Apple | Pegar | Einsetzen | Incolla |
| Find | Apple | Buscar | Suchen | Trova |
| Rename | Apple | Renombrar | Umbenennen | Rinomina |
| Show in Finder | Apple | Mostrar en el Finder | Im Finder anzeigen | Mostra nel Finder |
| Move to Trash, Trash | Apple | Transferir al basurero, basurero | In den Papierkorb legen, Papierkorb | Sposta nel Cestino, Cestino |
| Downloads | Apple | Descargas | Downloads | Download |
| sidebar | Apple | barra lateral | Seitenleiste | barra laterale |
| menu bar | Apple | barra de menús | Menüleiste | barra dei menu |
| Emoji & Symbols | Apple | Emoji y símbolos | Emoji & Symbole | Emoji e simboli |
| Focus, Focus filter | Apple | enfoque, filtro de enfoque | Fokus, Fokusfilter | full immersion, filtro full immersion |
| full screen | Apple | pantalla completa | Vollbild | a tutto schermo |
| backup, backups | Apple | respaldo, respaldos | Backup, Backups | backup, backup |
| About | Apple | Acerca de | Info, as the About pane of System Settings › General | Informazioni |
| Privacy Policy | Apple | Política de privacidad | Datenschutzrichtlinie | Informativa sulla privacy |
| Finder's tag colors: Red, Orange, Yellow, Green, Blue, Purple, Gray | Apple | Rojo, Naranja, Amarillo, Verde, Azul, Morado, Gris | Rot, Orange, Gelb, Grün, Blau, Lila, Grau | Rosso, Arancione, Giallo, Verde, Blu, Viola, Grigio |

## Ficha's own terms

| English | Source | Spanish (es) | German (de) | Italian (it) |
|---|---|---|---|---|
| review (noun) | Ficha | repaso | Wiederholung, Anki's German word for a review | ripasso: Anki's Italian says both ripasso (a card's Review state, the review log's Review entries) and ripetizione (its review counts); ripasso stays clear of Again's Ripeti |
| review (verb) | Ficha | repasar | wiederholen, Anki's | ripassare |
| Review now | Ficha | Repasar ahora | Jetzt wiederholen | Ripassa ora |
| review panel | Ficha | panel de repaso | Wiederholungsfenster | pannello di ripasso |
| review log | Ficha | historial de repasos | Wiederholungsverlauf, the word Anki's German uses for a card's review history | cronologia dei ripassi, with Apple's and Anki's cronologia for a history |
| capture (noun, verb) | Ficha | captura, capturar | Erfassung, erfassen. Not „Notiz“, which is Anki's note and appears beside it in the Import sheet | cattura, catturare |
| inbox | Ficha | bandeja | Eingang, Apple Mail's word for Inbox | casella in entrata; Inbox in the sidebar: In entrata, as Apple's Italian Mail names its inbox and says it in a sentence |
| approve (a capture into cards) | Ficha | aprobar | übernehmen | approvare |
| flag, flagged | Ficha | marcar, marcada | markieren, markiert, Apple Mail's word for flag; Anki's „Flagge“ names Anki's colored flags, another thing | contrassegnare, contrassegnata; Flagged in the sidebar: Contrassegnate. Apple's Mail flag; Anki's bandiera is its colored flags, another thing |
| expand, expansion | Ficha | ampliar, ampliación | erweitern, Erweiterung | ampliare, ampliamento: Apple's Espandi is a disclosure's, and ampliare says adding to a card |
| follow-up (a question about a card) | Ficha | consulta | Rückfrage | approfondimento: domanda is the Question type's, so it can't name the follow-up too |
| refine, refine session | Ficha | refinar, sesión de refinado | ausarbeiten, Sitzung zum Ausarbeiten. Over the literal „verfeinern“: turning raw notes into finished ones is „ausarbeiten“ in German | rifinire, sessione di rifinitura |
| appearance (a card showing up on its own) | Ficha | aparición | Einblendung | apparizione |
| hold back appearances | Ficha | frenar las apariciones | Einblendungen zurückhalten | trattenere le apparizioni |
| snoozed | Ficha | pospuesta | verschoben. Not Apple's „Schlummern“, an alarm's, nor „aufgeschoben“, Anki's word for buried | posticipata |
| idle | Ficha | inactivo | inaktiv | inattivo |
| priority deck, Prioritize | Ficha | mazo prioritario, Priorizar | Prioritätsstapel, Priorisieren | mazzo prioritario, Dai priorità |
| set aside | Ficha | apartar, apartada | zurückstellen, zurückgestellt | accantonare, accantonata: one word, which fits the Due column, where "messa da parte" would take three |
| Both ways | Ficha | En ambos sentidos | In beide Richtungen | In entrambi i sensi |
| front first, back first | Ficha | anverso primero, reverso primero | Vorderseite zuerst, Rückseite zuerst; after a column's or a detail row's noun, short: (Rückseite), as „Fällig (Rückseite)“ | prima il fronte, prima il retro |
| way (front first or back first) | Ficha | sentido | Richtung | senso |
| learned | Ficha | aprendida; Learned in the sidebar: Aprendidas | gelernt; Learned in the sidebar: Gelernt | appresa; Learned in the sidebar: Apprese |
| card type; Word, Concept, Quote, Question | Ficha | tipo; Palabra, Concepto, Frase, Pregunta | Typ; Wort, Konzept, Zitat, Frage | tipo; Parola, Concetto, Citazione, Domanda |
| source (of a card) | Ficha | fuente | Quelle | fonte: Apple's sorgente is a technical source, fonte is where a quote comes from |
| note (on a capture or a flag) | Ficha | nota | Anmerkung. Not „Notiz“, Anki's note | nota |
| pin to the sidebar | Ficha | fijar en la barra lateral | in der Seitenleiste anpinnen; unpin: lösen, Apple's „anpinnen“ and „lösen“ | fissare nella barra laterale; Pinned: Fissata; Unpin from Sidebar: Rimuovi dalla barra laterale. Apple's "Metti in evidenza" is Notes' pin to a list's top |
| capture shortcut | Ficha | atajo de captura | Kurzbefehl zum Erfassen, with Apple's „Kurzbefehl“ | abbreviazione di cattura, with Apple's abbreviazione da tastiera |
| Flip | Ficha | Dar vuelta | Umdrehen | Gira |
| Diagnostics | Ficha | Diagnóstico | Diagnose | Diagnosi, as Apple says it |
| sync | Ficha | sincronización, sincronizar | Synchronisierung, synchronisieren | sincronizzazione, sincronizzare |
| an AI | Ficha | una IA | eine KI | un’IA |
| tick, untick (a checkbox), since flag is marcar | Ficha | tildar, destildar | anhaken, Häkchen entfernen, since flag is markieren | spuntare, togliere la spunta: selezionare is selecting rows, and contrassegnare is flag |
