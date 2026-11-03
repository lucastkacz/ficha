# Ficha's words in each language

Every text the app shows is translated into Ficha's languages, which `scripts/languages.txt` lists, each from the change that first translates the catalogs into it (ADR 0027), and a term reads the same on every screen. This list holds the word each language uses for each term the UI shows: a new text uses the words here, and a new term gets a row in the change that brings it.

A term's source says where its words come from:

- **Anki**: Anki's own translation, from its Fluent files in [`ankitects/anki-core-i18n`](https://github.com/ankitects/anki-core-i18n), `core/<locale>/*.ftl`, under the message ID the row names. Where Anki has two words for one term, the row picks one.
- **Apple**: the word macOS uses in that language, in its own menus, System Settings and Finder. For Spanish, a Mac in Spanish (Latin America), `es_419` in macOS's own files, whose words are the ones Rioplatense Spanish uses ("Configuración", "Agregar", "respaldo"), not a Mac in Spain's Spanish ("Ajustes", "Añadir", "copia de seguridad"): Lucas's call, on 2 November 2026. For Portuguese, a Mac in Portuguese, which is Brazil's (`pt` in macOS's own files, where `pt_PT` is Portugal's).
- **Ficha**: our own word, chosen in the first translation into that language.

A language gets its column here in the change that translates the catalogs into it. Spanish is Rioplatense, with "vos" in what the app asks of the user ("Elegí", "Revisá", "Tenés"), and Anki's words stay as Anki's Spanish has them, but where a row says otherwise. Quotes are « ». German says "du", as Apple's German does, with quotes „ “; French says "vous", as Apple's French does, with quotes « » and a no-break space inside them and before : ; ? and !; Italian says "tu", as Apple's Italian does, with quotes “ ”; and Portuguese is Brazil's, with "você" and quotes “ ”, and Anki's words from Anki's `pt-BR`.

## Anki's terms

| English | Source | Spanish (es) | German (de) | Italian (it) | Portuguese (pt) | French (fr) |
|---|---|---|---|---|---|---|
| Again | Anki `studying-again` | Otra vez | Nochmal | Ripeti | De novo | À revoir |
| Hard | Anki `studying-hard` | Difícil | Schwer | Difficile | Difícil | Difficile |
| Good | Anki `studying-good` | Bien | Gut | Normale | Bom | Correct |
| Easy | Anki `studying-easy` | Fácil | Einfach | Facile | Fácil | Facile |
| deck | Anki `decks-deck` | mazo | Stapel | mazzo | baralho | paquet |
| card | Anki `browsing-card` | tarjeta | Karte | carta | cartão | carte |
| tags | Anki `editing-tags` | etiquetas | Schlagwörter, a tag: Schlagwort | etichette | etiquetas | étiquettes |
| new (a card) | Anki `actions-new` | nueva; New in the sidebar: Nuevas | neu; New in the sidebar: Neu | nuova; New in the sidebar: Nuove | novo; New in the sidebar: Novos | nouvelle; New in the sidebar: Nouvelles |
| learning | Anki `scheduling-learning` | Aprendiendo | Lernen | In apprendimento | aprendizagem, as in etapas de aprendizagem; a card in its steps shows Aprendendo in the Interval columns, as Anki's Browse says it (`browsing-learning`) | en apprentissage, from Anki's Browse “(apprentissage)” (`browsing-learning`) and “Étapes d’apprentissage”: Anki's `scheduling-learning` says “À repasser”, which reads as “to go over again” beside Again's “À revoir” |
| interval | Anki `browsing-interval` | intervalo | Intervall | intervallo | intervalo | intervalle |
| learning steps | Anki `deck-config-learning-steps` | pasos en la etapa de aprendizaje | Lernstufen; a step: Stufe | passi di apprendimento | etapas de aprendizagem | étapes d’apprentissage |
| relearning steps | Anki `deck-config-relearning-steps` | pasos de reaprendizaje | Lernstufen für das Wiedererlernen; in a sentence beside the learning steps: Lern- und Wiedererlernstufen | passi di riapprendimento | etapas de reaprendizagem | étapes de réapprentissage: Anki writes “ré-apprentissage” here and “réapprentissage” in its review log (`card-stats-review-log-type-relearn`); the second is the dictionary's |
| desired retention | Anki `deck-config-desired-retention` | retención deseada | Gewünschte Erinnerungsquote | ritenzione desiderata | retenção desejada | rétention souhaitée |
| longest interval | Anki `scheduling-maximum-interval` | intervalo máximo | Höchstintervall | intervallo massimo | intervalo máximo | intervalle maximum |
| forgotten (lapses) | Anki `scheduling-lapses` | olvidada, as Anki's "Olvidos" | vergessen, as in „Nach 8-maligem Vergessen“: ours, since Ficha's English always says forget and shows no Lapses label, where Anki's „Fehlversuche“ (failed attempts) would fit | dimenticata, ours: Anki's "Errori" names the count, not the card | esquecido, esquecer; Anki's count is «Falhas», but Ficha's texts speak of forgetting, not a count's label | oubliée, ours: Anki's “Échecs” names the count, not the card |
| due | Anki `browsing-sidebar-due-today` | pendiente; Due in the sidebar: Pendientes | fällig; Due in the sidebar: Fällig | in scadenza, as Anki's `browsing-sidebar-due-today`; Due in the sidebar: In scadenza; the Due columns: Scadenza, as Anki's `statistics-due-date` | a revisar, as Anki's «A Revisar» (`statistics-due-date`); Due in the sidebar: A revisar. Anki's `browsing-sidebar-due-today` says «Revisar», which beside Revisar agora reads as the verb | à réviser, as Anki's `decks-review-header` and `statistics-due-count`; Due in the sidebar: À réviser; the Due columns: Échéance, as Anki's “date d’échéance” and Apple's Reminders. Anki's `browsing-sidebar-due-today` says “Dû”, which reads as “owed” |
| front | Anki `notetypes-front-field` | anverso | Vorderseite | fronte | frente | recto |
| back | Anki `notetypes-back-field` | reverso | Rückseite | retro | verso | verso |
| bury, buried | Anki `studying-bury`, `browsing-buried` | enterrar, enterrada | begraben, begraben; unbury: ausgraben. Ours, not Anki's: Anki's German says „Bis morgen aufschieben“ and „Aufgeschoben“ (put off until tomorrow), which would tell the user a buried card comes back, while Ficha's bury is for good; „begraben“ is the literal word, as Spanish's „enterrar“, and in German also means giving something up for good | seppellire, seppellita; Buried in the sidebar: Seppellite; unbury: disseppellire, as Anki's `studying-unbury` | ocultar, oculto; unbury: desocultar (`studying-unbury`) | enfouir, enfouie; Buried in the sidebar: Enfouies; unbury: déterrer, as Anki's `studying-unbury` |
| suspended | Anki `browsing-suspended` | suspendidas | ausgeschlossen | sospese | suspensos | suspendues |
| Default (the deck) | Anki `deck-config-default-name` | Predeterminado | Standard | Predefinito | Padrão | Par défaut, in « » inside a sentence, where it would read as “by default” |
| retrievability | Anki `card-stats-fsrs-retrievability` | recuperabilidad | Abrufbarkeit | rammentabilità | recuperabilidade | retrouvabilité |
| stability | Anki `card-stats-fsrs-stability` | estabilidad | Stabilität | stabilità | estabilidade | stabilité |
| difficulty | Anki `card-stats-fsrs-difficulty` | dificultad | Schwierigkeitsgrad | difficoltà | dificuldade | difficulté |
| New cards per day (the setting) | Anki `scheduling-new-cardsday` | Tarjetas nuevas/día, its label in Settings; in a sentence, tarjetas nuevas por día, ours, where the slash reads wrong | Tageshöchstwert für neue Karten, its label in Settings; in a sentence, neue Karten pro Tag, ours | Carte nuove/giorno, its label in Settings; in a sentence, carte nuove al giorno, ours, where the slash reads wrong | Novos cartões/dia, its label in Settings; in a sentence, novos cartões por dia | Nouvelles cartes par jour, Anki's label, which has no slash; in a sentence: nouvelles cartes par jour |
| Scheduling (Settings' tab) | Anki `preferences-scheduling` | Programación | Zeitplanung | Pianificazione | Agendamento | Planification, as Anki's “Planification personnalisée” and “données de planification”: Anki's `preferences-scheduling` says “Replanifier”, the verb reschedule |
| created | Anki `browsing-created` | creada | erstellt | creata; the Created column: Data di creazione, as Anki's column says it | criado | créée |
| notes (Anki's) | Anki `browsing-notes` | notas | Notizen | note | notas | notes |
| Import, Export | Anki `actions-import`, `actions-export` | Importar, Exportar | Importieren, Exportieren | Importa, Esporta | Importar, Exportar | Importer, Exporter |
| Support older Anki versions | Anki `exporting-support-older-anki-versions` | Compatibilidad con versiones anteriores de Anki | Unterstütze ältere Anki-Versionen | Supportare vecchie versioni di Anki | Suporta versões antigas do Anki, Anki's label without its «(lento/arquivos grandes)», as the English leaves out «(slower/larger files)» | Gérer la compatibilité avec les versions antérieures d’Anki, Anki's label without its parenthesis |
| Notes in Plain Text | Anki `exporting-notes-in-plain-text` | Notas en texto plano | Notizen als einfache Textdatei | Note in testo semplice | Notas em Texto Puro | Notes en texte |
| Image Occlusion | Anki `notetypes-image-occlusion-name` | Oclusión de imagen | Bildverdeckung | Occludi Immagine | Oclusão de Imagem | Schéma à remplir |
| template (a card's, in Anki) | Anki `card-templates-template-box` | plantilla | Vorlage | modello | modelo | modèle |
| Media (a card's images and sounds) | Anki `editing-media` | Multimedia | Medien | File multimediali, Anki's `preferences-media`: Anki has it singular too, "File multimediale" (`editing-media`), and a card's images and sounds are several; the Cards window's column says Multimedia, which leaves the other columns room beside it | Mídia | Médias |
| review ahead | Anki `custom-study-review-ahead` | repasar por adelantado, un repaso por adelantado | im Voraus wiederholen, eine Wiederholung im Voraus | ripassare in anticipo, un ripasso in anticipo: Anki's "Ripeti in anticipo" says ripetere, which Ficha's Italian keeps for Again (Ripeti), so the verb is Ficha's review, ripassare, with Anki's "in anticipo" | Antecipar a revisão (Anki's button), uma revisão antecipada; its badge: Antecipada | avancer la révision, Anki's button; a review ahead: une révision anticipée; the Ahead badge: En avance |
| graduate (a card leaving its steps) | Anki `scheduling-graduating-interval` | graduarse, as Anki's "Intervalo de graduación" | aufsteigen, as Anki's „Aufstiegsintervall“ | essere promossa, as Anki's "Intervallo di promozione" | graduar-se, as Anki's «Intervalo de graduação» | obtenir sa graduation, as Anki's “intervalle de graduation”: French graduer means to calibrate |
| discard | Anki `actions-discard` | descartar | verwerfen | scartare | descartar | abandonner |

## Apple's terms

| English | Source | Spanish (es) | German (de) | Italian (it) | Portuguese (pt) | French (fr) |
|---|---|---|---|---|---|---|
| Settings… | Apple | Configuración… | Einstellungen … (a no-break space before the ellipsis, as Apple's German writes every …) | Impostazioni… | Ajustes… | Réglages… |
| settings (an app's) | Apple | configuración | Einstellungen | impostazioni | ajustes | réglages |
| System Settings | Apple | Configuración del Sistema | Systemeinstellungen | Impostazioni di Sistema | Ajustes do Sistema | Réglages Système |
| Login Items | Apple | Elementos de inicio | Anmeldeobjekte | Elementi login | Itens de Início, the heading in System Settings, whose pane is «Itens de Início de Sessão e Extensões» | Ouverture, the pane of Réglages Système › Général, as macOS's French names it |
| Open at Login | Apple | Abrir al iniciar sesión | Bei der Anmeldung öffnen | Apri al login | Abrir no Início da Sessão, as the Dock says it | Ouvrir avec la session |
| Quit | Apple | Salir | Beenden | Esci | Encerrar | Quitter |
| Cancel | Apple | Cancelar | Abbrechen | Annulla | Cancelar | Annuler |
| OK | Apple | OK | OK | OK | OK | OK |
| Done | Apple | Listo | Fertig | Fine | OK, as Apple's Portuguese says Done | Terminé |
| Add | Apple | Agregar, as Apple's Spanish (Latin America) and Rioplatense Spanish say it, where Anki's `actions-add` says Añadir | Hinzufügen | Aggiungi, as Apple's and Anki's `actions-add` both say it | Adicionar, Apple's and Anki's alike | Ajouter, as Apple's and Anki's `actions-add` both say it |
| Restore | Apple | Restaurar | Wiederherstellen | Ripristina | Restaurar | Restaurer |
| Close | Apple | Cerrar | Schließen | Chiudi | Fechar | Fermer |
| Undo | Apple | Deshacer | Widerrufen | Annulla, as Apple's Edit menu says it, the same word as Cancel | Desfazer | Annuler, as Apple's Edit menu says it, the same word as Cancel |
| Delete | Apple | Eliminar | Löschen | Elimina | Apagar | Supprimer |
| Edit | Apple | Editar | Bearbeiten | Modifica | Editar | Modifier |
| Paste | Apple | Pegar | Einsetzen | Incolla | Colar | Coller |
| Find | Apple | Buscar | Suchen | Trova | Buscar | Rechercher |
| Rename | Apple | Renombrar | Umbenennen | Rinomina | Renomear | Renommer |
| Show in Finder | Apple | Mostrar en el Finder | Im Finder anzeigen | Mostra nel Finder | Mostrar no Finder | Afficher dans le Finder |
| Move to Trash, Trash | Apple | Transferir al basurero, basurero | In den Papierkorb legen, Papierkorb | Sposta nel Cestino, Cestino | Mover para o Lixo, Lixo | Placer dans la corbeille, corbeille |
| Downloads | Apple | Descargas | Downloads | Download | Downloads | Téléchargements |
| sidebar | Apple | barra lateral | Seitenleiste | barra laterale | barra lateral | barre latérale |
| menu bar | Apple | barra de menús | Menüleiste | barra dei menu | barra de menus | barre des menus |
| Emoji & Symbols | Apple | Emoji y símbolos | Emoji & Symbole | Emoji e simboli | Emoji e Símbolos | Emoji et symboles |
| Focus, Focus filter | Apple | enfoque, filtro de enfoque | Fokus, Fokusfilter | full immersion, filtro full immersion | Foco, Filtro de Foco | mode de concentration, filtre de concentration |
| full screen | Apple | pantalla completa | Vollbild | a tutto schermo | tela cheia | plein écran |
| backup, backups | Apple | respaldo, respaldos | Backup, Backups | backup, backup | backup, backups; Back Up Now: Fazer Backup Agora | sauvegarde, sauvegardes |
| About | Apple | Acerca de | Info, as the About pane of System Settings › General | Informazioni | Sobre | Informations, as Réglages Système › Général › Informations |
| Privacy Policy | Apple | Política de privacidad | Datenschutzrichtlinie | Informativa sulla privacy | Política de Privacidade | Politique de confidentialité |
| Finder's tag colors: Red, Orange, Yellow, Green, Blue, Purple, Gray | Apple | Rojo, Naranja, Amarillo, Verde, Azul, Morado, Gris | Rot, Orange, Gelb, Grün, Blau, Lila, Grau | Rosso, Arancione, Giallo, Verde, Blu, Viola, Grigio | Vermelho, Laranja, Amarelo, Verde, Azul, Roxo, Cinza | Rouge, Orange, Jaune, Vert, Bleu, Violet, Gris |

## Ficha's own terms

| English | Source | Spanish (es) | German (de) | Italian (it) | Portuguese (pt) | French (fr) |
|---|---|---|---|---|---|---|
| review (noun) | Ficha | repaso | Wiederholung, Anki's German word for a review | ripasso: Anki's Italian says both ripasso (a card's Review state, the review log's Review entries) and ripetizione (its review counts); ripasso stays clear of Again's Ripeti | revisão, Anki's word too | révision, Anki's (`scheduling-review`, `card-stats-review-count`) |
| review (verb) | Ficha | repasar | wiederholen, Anki's | ripassare | revisar | réviser |
| Review now | Ficha | Repasar ahora | Jetzt wiederholen | Ripassa ora | Revisar agora; Revisar Agora as the action's name in Shortcuts and Spotlight, as the English capitalizes it there | Réviser maintenant |
| review panel | Ficha | panel de repaso | Wiederholungsfenster | pannello di ripasso | painel de revisão | panneau de révision |
| review log | Ficha | historial de repasos | Wiederholungsverlauf, the word Anki's German uses for a card's review history | cronologia dei ripassi, with Apple's and Anki's cronologia for a history | histórico de revisões | historique des révisions, as Anki's “historique des révisions” |
| capture (noun, verb) | Ficha | captura, capturar | Erfassung, erfassen. Not „Notiz“, which is Anki's note and appears beside it in the Import sheet | cattura, catturare | captura, capturar | capture, capturer |
| inbox | Ficha | bandeja | Eingang, Apple Mail's word for Inbox | casella in entrata; Inbox in the sidebar: In entrata, as Apple's Italian Mail names its inbox and says it in a sentence | caixa de entrada | boîte de réception; Inbox in the sidebar: Réception, as Apple's Mail names it |
| approve (a capture into cards) | Ficha | aprobar | übernehmen | approvare | aprovar | approuver |
| flag, flagged | Ficha | marcar, marcada | markieren, markiert, Apple Mail's word for flag; Anki's „Flagge“ names Anki's colored flags, another thing | contrassegnare, contrassegnata; Flagged in the sidebar: Contrassegnate. Apple's Mail flag; Anki's bandiera is its colored flags, another thing | sinalizar, sinalizado, as Apple's Mail in Brazil; Anki's «Bandeira» is the flag itself, not the act, and marcar stays free for a checkbox | marquer, marquée; Flagged in the sidebar: Marquées, as Anki's `browsing-flag` “Marquer” and “Marquée”; Apple's Mail drapeau is a colored flag |
| expand, expansion | Ficha | ampliar, ampliación | erweitern, Erweiterung | ampliare, ampliamento: Apple's Espandi is a disclosure's, and ampliare says adding to a card | ampliar, ampliação | compléter, complément: Apple's Développer is a disclosure's |
| follow-up (a question about a card) | Ficha | consulta | Rückfrage | approfondimento: domanda is the Question type's, so it can't name the follow-up too | dúvida, plain in Brazil and Portugal, and apart from Perguntar (the Ask button) and Pergunta (the card type) | demande; Ask: Demander: question is the Question type's, so it can't name the follow-up too |
| refine, refine session | Ficha | refinar, sesión de refinado | ausarbeiten, Sitzung zum Ausarbeiten. Over the literal „verfeinern“: turning raw notes into finished ones is „ausarbeiten“ in German | rifinire, sessione di rifinitura | refinar, sessão de refinamento | affiner, session d’affinage |
| appearance (a card showing up on its own) | Ficha | aparición | Einblendung | apparizione | aparição | apparition |
| hold back appearances | Ficha | frenar las apariciones | Einblendungen zurückhalten | trattenere le apparizioni | pausar as aparições; held back: pausada. Conter would read as contain («Contém as aparições»), and pausar is free, since sounds play and stop | retenir les apparitions |
| snoozed | Ficha | pospuesta | verschoben. Not Apple's „Schlummern“, an alarm's, nor „aufgeschoben“, Anki's word for buried | posticipata | adiada (an appearance) | reportée |
| idle | Ficha | inactivo | inaktiv | inattivo | inativo | inactif |
| priority deck, Prioritize | Ficha | mazo prioritario, Priorizar | Prioritätsstapel, Priorisieren | mazzo prioritario, Dai priorità | baralho prioritário, Priorizar | paquet prioritaire, Prioriser |
| set aside | Ficha | apartar, apartada | zurückstellen, zurückgestellt | accantonare, accantonata: one word, which fits the Due column, where "messa da parte" would take three | pôr de lado, posto de lado; the menu item: Pôr de Lado | mettre de côté, mis de côté (mise de côté for a card) |
| Both ways | Ficha | En ambos sentidos | In beide Richtungen | In entrambi i sensi | Nos dois sentidos | Dans les deux sens; Turn On Both Ways: Activer les deux sens |
| front first, back first | Ficha | anverso primero, reverso primero | Vorderseite zuerst, Rückseite zuerst; after a column's or a detail row's noun, short: (Rückseite), as „Fällig (Rückseite)“ | prima il fronte, prima il retro | frente primeiro, verso primeiro | recto d’abord, verso d’abord |
| way (front first or back first) | Ficha | sentido | Richtung | senso | sentido | sens |
| learned | Ficha | aprendida; Learned in the sidebar: Aprendidas | gelernt; Learned in the sidebar: Gelernt | appresa; Learned in the sidebar: Apprese | aprendido; Learned in the sidebar: Aprendidos | apprise; Learned in the sidebar: Apprises |
| card type; Word, Concept, Quote, Question | Ficha | tipo; Palabra, Concepto, Frase, Pregunta | Typ; Wort, Konzept, Zitat, Frage | tipo; Parola, Concetto, Citazione, Domanda | tipo; Palavra, Conceito, Citação, Pergunta | type; Mot, Concept, Citation, Question |
| source (of a card) | Ficha | fuente | Quelle | fonte: Apple's sorgente is a technical source, fonte is where a quote comes from | fonte | source |
| note (on a capture or a flag) | Ficha | nota | Anmerkung. Not „Notiz“, Anki's note | nota | nota | note |
| pin to the sidebar | Ficha | fijar en la barra lateral | in der Seitenleiste anpinnen; unpin: lösen, Apple's „anpinnen“ and „lösen“ | fissare nella barra laterale; Pinned: Fissata; Unpin from Sidebar: Rimuovi dalla barra laterale. Apple's "Metti in evidenza" is Notes' pin to a list's top | fixar na barra lateral; unpin: desafixar | épingler dans la barre latérale; Pinned: Épinglée; Unpin from Sidebar: Détacher de la barre latérale, as Apple's Épingler and Détacher |
| capture shortcut | Ficha | atajo de captura | Kurzbefehl zum Erfassen, with Apple's „Kurzbefehl“ | abbreviazione di cattura, with Apple's abbreviazione da tastiera | atalho de captura | raccourci de capture |
| Flip | Ficha | Dar vuelta | Umdrehen | Gira | Virar | Retourner, as Apple's and Anki's `card-templates-flip` |
| Diagnostics | Ficha | Diagnóstico | Diagnose | Diagnosi, as Apple says it | Diagnóstico | Diagnostic, as Apple says it |
| sync | Ficha | sincronización, sincronizar | Synchronisierung, synchronisieren | sincronizzazione, sincronizzare | sincronização, sincronizar | synchronisation, synchroniser |
| an AI | Ficha | una IA | eine KI | un’IA | uma IA | une IA |
| tick, untick (a checkbox), since flag is marcar | Ficha | tildar, destildar | anhaken, Häkchen entfernen, since flag is markieren | spuntare, togliere la spunta: selezionare is selecting rows, and contrassegnare is flag | marcar, desmarcar, free in Portuguese, since flag is sinalizar | cocher, décocher |
