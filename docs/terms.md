# Ficha's words in each language

Every text the app shows is translated into Ficha's languages, which `scripts/languages.txt` lists, each from the change that first translates the catalogs into it (ADR 0027), and a term reads the same on every screen. This list holds the word each language uses for each term the UI shows: a new text uses the words here, and a new term gets a row in the change that brings it.

A term's source says where its words come from:

- **Anki**: Anki's own translation, from its Fluent files in [`ankitects/anki-core-i18n`](https://github.com/ankitects/anki-core-i18n), `core/<locale>/*.ftl`, under the message ID the row names. Where Anki has two words for one term, the row picks one.
- **Apple**: the word macOS uses in that language, in its own menus, System Settings and Finder. For Spanish, a Mac in Spanish (Latin America), `es_419` in macOS's own files, whose words are the ones Rioplatense Spanish uses ("Configuración", "Agregar", "respaldo"), not a Mac in Spain's Spanish ("Ajustes", "Añadir", "copia de seguridad"): Lucas's call, on 2 November 2026. For Portuguese, a Mac in Portuguese, which is Brazil's (`pt` in macOS's own files, where `pt_PT` is Portugal's).
- **Ficha**: our own word, chosen in the first translation into that language.

A language gets its column here in the change that translates the catalogs into it. Spanish is Rioplatense, with "vos" in what the app asks of the user ("Elegí", "Revisá", "Tenés"), and Anki's words stay as Anki's Spanish has them, but where a row says otherwise. Quotes are « ». German says "du", as Apple's German does, with quotes „ “; Italian says "tu", as Apple's Italian does, with quotes “ ”; and Portuguese is Brazil's, with "você" and quotes “ ”, and Anki's words from Anki's `pt-BR`.

## Anki's terms

| English | Source | Spanish (es) | German (de) | Italian (it) | Portuguese (pt) |
|---|---|---|---|---|---|
| Again | Anki `studying-again` | Otra vez | Nochmal | Ripeti | De novo |
| Hard | Anki `studying-hard` | Difícil | Schwer | Difficile | Difícil |
| Good | Anki `studying-good` | Bien | Gut | Normale | Bom |
| Easy | Anki `studying-easy` | Fácil | Einfach | Facile | Fácil |
| deck | Anki `decks-deck` | mazo | Stapel | mazzo | baralho |
| card | Anki `browsing-card` | tarjeta | Karte | carta | cartão |
| tags | Anki `editing-tags` | etiquetas | Schlagwörter, a tag: Schlagwort | etichette | etiquetas |
| new (a card) | Anki `actions-new` | nueva; New in the sidebar: Nuevas | neu; New in the sidebar: Neu | nuova; New in the sidebar: Nuove | novo; New in the sidebar: Novos |
| learning | Anki `scheduling-learning` | Aprendiendo | Lernen | In apprendimento | aprendizagem, as in etapas de aprendizagem; a card in its steps shows Aprendendo in the Interval columns, as Anki's Browse says it (`browsing-learning`) |
| interval | Anki `browsing-interval` | intervalo | Intervall | intervallo | intervalo |
| learning steps | Anki `deck-config-learning-steps` | pasos en la etapa de aprendizaje | Lernstufen; a step: Stufe | passi di apprendimento | etapas de aprendizagem |
| relearning steps | Anki `deck-config-relearning-steps` | pasos de reaprendizaje | Lernstufen für das Wiedererlernen; in a sentence beside the learning steps: Lern- und Wiedererlernstufen | passi di riapprendimento | etapas de reaprendizagem |
| desired retention | Anki `deck-config-desired-retention` | retención deseada | Gewünschte Erinnerungsquote | ritenzione desiderata | retenção desejada |
| longest interval | Anki `scheduling-maximum-interval` | intervalo máximo | Höchstintervall | intervallo massimo | intervalo máximo |
| forgotten (lapses) | Anki `scheduling-lapses` | olvidada, as Anki's "Olvidos" | vergessen, as in „Nach 8-maligem Vergessen“: ours, since Ficha's English always says forget and shows no Lapses label, where Anki's „Fehlversuche“ (failed attempts) would fit | dimenticata, ours: Anki's "Errori" names the count, not the card | esquecido, esquecer; Anki's count is «Falhas», but Ficha's texts speak of forgetting, not a count's label |
| due | Anki `browsing-sidebar-due-today` | pendiente; Due in the sidebar: Pendientes | fällig; Due in the sidebar: Fällig | in scadenza, as Anki's `browsing-sidebar-due-today`; Due in the sidebar: In scadenza; the Due columns: Scadenza, as Anki's `statistics-due-date` | a revisar, as Anki's «A Revisar» (`statistics-due-date`); Due in the sidebar: A revisar. Anki's `browsing-sidebar-due-today` says «Revisar», which beside Revisar agora reads as the verb |
| front | Anki `notetypes-front-field` | anverso | Vorderseite | fronte | frente |
| back | Anki `notetypes-back-field` | reverso | Rückseite | retro | verso |
| bury, buried | Anki `studying-bury`, `browsing-buried` | enterrar, enterrada | begraben, begraben; unbury: ausgraben. Ours, not Anki's: Anki's German says „Bis morgen aufschieben“ and „Aufgeschoben“ (put off until tomorrow), which would tell the user a buried card comes back, while Ficha's bury is for good; „begraben“ is the literal word, as Spanish's „enterrar“, and in German also means giving something up for good | seppellire, seppellita; Buried in the sidebar: Seppellite; unbury: disseppellire, as Anki's `studying-unbury` | ocultar, oculto; unbury: desocultar (`studying-unbury`) |
| suspended | Anki `browsing-suspended` | suspendidas | ausgeschlossen | sospese | suspensos |
| Default (the deck) | Anki `deck-config-default-name` | Predeterminado | Standard | Predefinito | Padrão |
| retrievability | Anki `card-stats-fsrs-retrievability` | recuperabilidad | Abrufbarkeit | rammentabilità | recuperabilidade |
| stability | Anki `card-stats-fsrs-stability` | estabilidad | Stabilität | stabilità | estabilidade |
| difficulty | Anki `card-stats-fsrs-difficulty` | dificultad | Schwierigkeitsgrad | difficoltà | dificuldade |
| New cards per day (the setting) | Anki `scheduling-new-cardsday` | Tarjetas nuevas/día, its label in Settings; in a sentence, tarjetas nuevas por día, ours, where the slash reads wrong | Tageshöchstwert für neue Karten, its label in Settings; in a sentence, neue Karten pro Tag, ours | Carte nuove/giorno, its label in Settings; in a sentence, carte nuove al giorno, ours, where the slash reads wrong | Novos cartões/dia, its label in Settings; in a sentence, novos cartões por dia |
| Scheduling (Settings' tab) | Anki `preferences-scheduling` | Programación | Zeitplanung | Pianificazione | Agendamento |
| created | Anki `browsing-created` | creada | erstellt | creata; the Created column: Data di creazione, as Anki's column says it | criado |
| notes (Anki's) | Anki `browsing-notes` | notas | Notizen | note | notas |
| Import, Export | Anki `actions-import`, `actions-export` | Importar, Exportar | Importieren, Exportieren | Importa, Esporta | Importar, Exportar |
| Support older Anki versions | Anki `exporting-support-older-anki-versions` | Compatibilidad con versiones anteriores de Anki | Unterstütze ältere Anki-Versionen | Supportare vecchie versioni di Anki | Suporta versões antigas do Anki, Anki's label without its «(lento/arquivos grandes)», as the English leaves out «(slower/larger files)» |
| Notes in Plain Text | Anki `exporting-notes-in-plain-text` | Notas en texto plano | Notizen als einfache Textdatei | Note in testo semplice | Notas em Texto Puro |
| Image Occlusion | Anki `notetypes-image-occlusion-name` | Oclusión de imagen | Bildverdeckung | Occludi Immagine | Oclusão de Imagem |
| template (a card's, in Anki) | Anki `card-templates-template-box` | plantilla | Vorlage | modello | modelo |
| Media (a card's images and sounds) | Anki `editing-media` | Multimedia | Medien | File multimediali, Anki's `preferences-media`: Anki has it singular too, "File multimediale" (`editing-media`), and a card's images and sounds are several | Mídia |
| review ahead | Anki `custom-study-review-ahead` | repasar por adelantado, un repaso por adelantado | im Voraus wiederholen, eine Wiederholung im Voraus | ripassare in anticipo, un ripasso in anticipo: Anki's "Ripeti in anticipo" says ripetere, which Ficha's Italian keeps for Again (Ripeti), so the verb is Ficha's review, ripassare, with Anki's "in anticipo" | Antecipar a revisão (Anki's button), uma revisão antecipada; its badge: Antecipada |
| graduate (a card leaving its steps) | Anki `scheduling-graduating-interval` | graduarse, as Anki's "Intervalo de graduación" | aufsteigen, as Anki's „Aufstiegsintervall“ | essere promossa, as Anki's "Intervallo di promozione" | graduar-se, as Anki's «Intervalo de graduação» |
| discard | Anki `actions-discard` | descartar | verwerfen | scartare | descartar |

## Apple's terms

| English | Source | Spanish (es) | German (de) | Italian (it) | Portuguese (pt) |
|---|---|---|---|---|---|
| Settings… | Apple | Configuración… | Einstellungen … (a no-break space before the ellipsis, as Apple's German writes every …) | Impostazioni… | Ajustes… |
| settings (an app's) | Apple | configuración | Einstellungen | impostazioni | ajustes |
| System Settings | Apple | Configuración del Sistema | Systemeinstellungen | Impostazioni di Sistema | Ajustes do Sistema |
| Login Items | Apple | Elementos de inicio | Anmeldeobjekte | Elementi login | Itens de Início, the heading in System Settings, whose pane is «Itens de Início de Sessão e Extensões» |
| Open at Login | Apple | Abrir al iniciar sesión | Bei der Anmeldung öffnen | Apri al login | Abrir no Início da Sessão, as the Dock says it |
| Quit | Apple | Salir | Beenden | Esci | Encerrar |
| Cancel | Apple | Cancelar | Abbrechen | Annulla | Cancelar |
| OK | Apple | OK | OK | OK | OK |
| Done | Apple | Listo | Fertig | Fine | OK, as Apple's Portuguese says Done |
| Add | Apple | Agregar, as Apple's Spanish (Latin America) and Rioplatense Spanish say it, where Anki's `actions-add` says Añadir | Hinzufügen | Aggiungi, as Apple's and Anki's `actions-add` both say it | Adicionar, Apple's and Anki's alike |
| Restore | Apple | Restaurar | Wiederherstellen | Ripristina | Restaurar |
| Close | Apple | Cerrar | Schließen | Chiudi | Fechar |
| Undo | Apple | Deshacer | Widerrufen | Annulla, as Apple's Edit menu says it, the same word as Cancel | Desfazer |
| Delete | Apple | Eliminar | Löschen | Elimina | Apagar |
| Edit | Apple | Editar | Bearbeiten | Modifica | Editar |
| Paste | Apple | Pegar | Einsetzen | Incolla | Colar |
| Find | Apple | Buscar | Suchen | Trova | Buscar |
| Rename | Apple | Renombrar | Umbenennen | Rinomina | Renomear |
| Show in Finder | Apple | Mostrar en el Finder | Im Finder anzeigen | Mostra nel Finder | Mostrar no Finder |
| Move to Trash, Trash | Apple | Transferir al basurero, basurero | In den Papierkorb legen, Papierkorb | Sposta nel Cestino, Cestino | Mover para o Lixo, Lixo |
| Downloads | Apple | Descargas | Downloads | Download | Downloads |
| sidebar | Apple | barra lateral | Seitenleiste | barra laterale | barra lateral |
| menu bar | Apple | barra de menús | Menüleiste | barra dei menu | barra de menus |
| Emoji & Symbols | Apple | Emoji y símbolos | Emoji & Symbole | Emoji e simboli | Emoji e Símbolos |
| Focus, Focus filter | Apple | enfoque, filtro de enfoque | Fokus, Fokusfilter | full immersion, filtro full immersion | Foco, Filtro de Foco |
| full screen | Apple | pantalla completa | Vollbild | a tutto schermo | tela cheia |
| backup, backups | Apple | respaldo, respaldos | Backup, Backups | backup, backup | backup, backups; Back Up Now: Fazer Backup Agora |
| About | Apple | Acerca de | Info, as the About pane of System Settings › General | Informazioni | Sobre |
| Privacy Policy | Apple | Política de privacidad | Datenschutzrichtlinie | Informativa sulla privacy | Política de Privacidade |
| Finder's tag colors: Red, Orange, Yellow, Green, Blue, Purple, Gray | Apple | Rojo, Naranja, Amarillo, Verde, Azul, Morado, Gris | Rot, Orange, Gelb, Grün, Blau, Lila, Grau | Rosso, Arancione, Giallo, Verde, Blu, Viola, Grigio | Vermelho, Laranja, Amarelo, Verde, Azul, Roxo, Cinza |

## Ficha's own terms

| English | Source | Spanish (es) | German (de) | Italian (it) | Portuguese (pt) |
|---|---|---|---|---|---|
| review (noun) | Ficha | repaso | Wiederholung, Anki's German word for a review | ripasso: Anki's Italian says both ripasso (a card's Review state, the review log's Review entries) and ripetizione (its review counts); ripasso stays clear of Again's Ripeti | revisão, Anki's word too |
| review (verb) | Ficha | repasar | wiederholen, Anki's | ripassare | revisar |
| Review now | Ficha | Repasar ahora | Jetzt wiederholen | Ripassa ora | Revisar agora; Revisar Agora as the action's name in Shortcuts and Spotlight, as the English capitalizes it there |
| review panel | Ficha | panel de repaso | Wiederholungsfenster | pannello di ripasso | painel de revisão |
| review log | Ficha | historial de repasos | Wiederholungsverlauf, the word Anki's German uses for a card's review history | cronologia dei ripassi, with Apple's and Anki's cronologia for a history | histórico de revisões |
| capture (noun, verb) | Ficha | captura, capturar | Erfassung, erfassen. Not „Notiz“, which is Anki's note and appears beside it in the Import sheet | cattura, catturare | captura, capturar |
| inbox | Ficha | bandeja | Eingang, Apple Mail's word for Inbox | casella in entrata; Inbox in the sidebar: In entrata, as Apple's Italian Mail names its inbox and says it in a sentence | caixa de entrada |
| approve (a capture into cards) | Ficha | aprobar | übernehmen | approvare | aprovar |
| flag, flagged | Ficha | marcar, marcada | markieren, markiert, Apple Mail's word for flag; Anki's „Flagge“ names Anki's colored flags, another thing | contrassegnare, contrassegnata; Flagged in the sidebar: Contrassegnate. Apple's Mail flag; Anki's bandiera is its colored flags, another thing | sinalizar, sinalizado, as Apple's Mail in Brazil; Anki's «Bandeira» is the flag itself, not the act, and marcar stays free for a checkbox |
| expand, expansion | Ficha | ampliar, ampliación | erweitern, Erweiterung | ampliare, ampliamento: Apple's Espandi is a disclosure's, and ampliare says adding to a card | ampliar, ampliação |
| follow-up (a question about a card) | Ficha | consulta | Rückfrage | approfondimento: domanda is the Question type's, so it can't name the follow-up too | dúvida, plain in Brazil and Portugal, and apart from Perguntar (the Ask button) and Pergunta (the card type) |
| refine, refine session | Ficha | refinar, sesión de refinado | ausarbeiten, Sitzung zum Ausarbeiten. Over the literal „verfeinern“: turning raw notes into finished ones is „ausarbeiten“ in German | rifinire, sessione di rifinitura | refinar, sessão de refinamento |
| appearance (a card showing up on its own) | Ficha | aparición | Einblendung | apparizione | aparição |
| hold back appearances | Ficha | frenar las apariciones | Einblendungen zurückhalten | trattenere le apparizioni | pausar as aparições; held back: pausada. Conter would read as contain («Contém as aparições»), and pausar is free, since sounds play and stop |
| snoozed | Ficha | pospuesta | verschoben. Not Apple's „Schlummern“, an alarm's, nor „aufgeschoben“, Anki's word for buried | posticipata | adiada (an appearance) |
| idle | Ficha | inactivo | inaktiv | inattivo | inativo |
| priority deck, Prioritize | Ficha | mazo prioritario, Priorizar | Prioritätsstapel, Priorisieren | mazzo prioritario, Dai priorità | baralho prioritário, Priorizar |
| set aside | Ficha | apartar, apartada | zurückstellen, zurückgestellt | accantonare, accantonata: one word, which fits the Due column, where "messa da parte" would take three | pôr de lado, posto de lado; the menu item: Pôr de Lado |
| Both ways | Ficha | En ambos sentidos | In beide Richtungen | In entrambi i sensi | Nos dois sentidos |
| front first, back first | Ficha | anverso primero, reverso primero | Vorderseite zuerst, Rückseite zuerst; after a column's or a detail row's noun, short: (Rückseite), as „Fällig (Rückseite)“ | prima il fronte, prima il retro | frente primeiro, verso primeiro |
| way (front first or back first) | Ficha | sentido | Richtung | senso | sentido |
| learned | Ficha | aprendida; Learned in the sidebar: Aprendidas | gelernt; Learned in the sidebar: Gelernt | appresa; Learned in the sidebar: Apprese | aprendido; Learned in the sidebar: Aprendidos |
| card type; Word, Concept, Quote, Question | Ficha | tipo; Palabra, Concepto, Frase, Pregunta | Typ; Wort, Konzept, Zitat, Frage | tipo; Parola, Concetto, Citazione, Domanda | tipo; Palavra, Conceito, Citação, Pergunta |
| source (of a card) | Ficha | fuente | Quelle | fonte: Apple's sorgente is a technical source, fonte is where a quote comes from | fonte |
| note (on a capture or a flag) | Ficha | nota | Anmerkung. Not „Notiz“, Anki's note | nota | nota |
| pin to the sidebar | Ficha | fijar en la barra lateral | in der Seitenleiste anpinnen; unpin: lösen, Apple's „anpinnen“ and „lösen“ | fissare nella barra laterale; Pinned: Fissata; Unpin from Sidebar: Rimuovi dalla barra laterale. Apple's "Metti in evidenza" is Notes' pin to a list's top | fixar na barra lateral; unpin: desafixar |
| capture shortcut | Ficha | atajo de captura | Kurzbefehl zum Erfassen, with Apple's „Kurzbefehl“ | abbreviazione di cattura, with Apple's abbreviazione da tastiera | atalho de captura |
| Flip | Ficha | Dar vuelta | Umdrehen | Gira | Virar |
| Diagnostics | Ficha | Diagnóstico | Diagnose | Diagnosi, as Apple says it | Diagnóstico |
| sync | Ficha | sincronización, sincronizar | Synchronisierung, synchronisieren | sincronizzazione, sincronizzare | sincronização, sincronizar |
| an AI | Ficha | una IA | eine KI | un’IA | uma IA |
| tick, untick (a checkbox), since flag is marcar | Ficha | tildar, destildar | anhaken, Häkchen entfernen, since flag is markieren | spuntare, togliere la spunta: selezionare is selecting rows, and contrassegnare is flag | marcar, desmarcar, free in Portuguese, since flag is sinalizar |
