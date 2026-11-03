# Ficha's words in each language

Every text the app shows is translated into Ficha's languages, which `scripts/languages.txt` lists, each from the change that first translates the catalogs into it (ADR 0027), and a term reads the same on every screen. This list holds the word each language uses for each term the UI shows: a new text uses the words here, and a new term gets a row in the change that brings it.

A term's source says where its words come from:

- **Anki**: Anki's own translation, from its Fluent files in [`ankitects/anki-core-i18n`](https://github.com/ankitects/anki-core-i18n), `core/<locale>/*.ftl`, under the message ID the row names. Where Anki has two words for one term, the row picks one.
- **Apple**: the word macOS uses in that language, in its own menus, System Settings and Finder. For Spanish, a Mac in Spanish (Latin America), `es_419` in macOS's own files, whose words are the ones Rioplatense Spanish uses ("Configuración", "Agregar", "respaldo"), not a Mac in Spain's Spanish ("Ajustes", "Añadir", "copia de seguridad"): Lucas's call, on 2 November 2026.
- **Ficha**: our own word, chosen in the first translation into that language.

A language gets its column here in the change that translates the catalogs into it. Spanish is Rioplatense, with "vos" in what the app asks of the user ("Elegí", "Revisá", "Tenés"), and Anki's words stay as Anki's Spanish has them, but where a row says otherwise. Quotes are « ».

## Anki's terms

| English | Source | Spanish (es) |
|---|---|---|
| Again | Anki `studying-again` | Otra vez |
| Hard | Anki `studying-hard` | Difícil |
| Good | Anki `studying-good` | Bien |
| Easy | Anki `studying-easy` | Fácil |
| deck | Anki `decks-deck` | mazo |
| card | Anki `browsing-card` | tarjeta |
| tags | Anki `editing-tags` | etiquetas |
| new (a card) | Anki `actions-new` | nueva; New in the sidebar: Nuevas |
| learning | Anki `scheduling-learning` | Aprendiendo |
| interval | Anki `browsing-interval` | intervalo |
| learning steps | Anki `deck-config-learning-steps` | pasos en la etapa de aprendizaje |
| relearning steps | Anki `deck-config-relearning-steps` | pasos de reaprendizaje |
| desired retention | Anki `deck-config-desired-retention` | retención deseada |
| longest interval | Anki `scheduling-maximum-interval` | intervalo máximo |
| forgotten (lapses) | Anki `scheduling-lapses` | olvidada, as Anki's "Olvidos" |
| due | Anki `browsing-sidebar-due-today` | pendiente; Due in the sidebar: Pendientes |
| front | Anki `notetypes-front-field` | anverso |
| back | Anki `notetypes-back-field` | reverso |
| bury, buried | Anki `studying-bury`, `browsing-buried` | enterrar, enterrada |
| suspended | Anki `browsing-suspended` | suspendidas |
| Default (the deck) | Anki `deck-config-default-name` | Predeterminado |
| retrievability | Anki `card-stats-fsrs-retrievability` | recuperabilidad |
| stability | Anki `card-stats-fsrs-stability` | estabilidad |
| difficulty | Anki `card-stats-fsrs-difficulty` | dificultad |
| New cards per day (the setting) | Anki `scheduling-new-cardsday` | Tarjetas nuevas/día, its label in Settings; in a sentence, tarjetas nuevas por día, ours, where the slash reads wrong |
| Scheduling (Settings' tab) | Anki `preferences-scheduling` | Programación |
| created | Anki `browsing-created` | creada |
| notes (Anki's) | Anki `browsing-notes` | notas |
| Import, Export | Anki `actions-import`, `actions-export` | Importar, Exportar |
| Support older Anki versions | Anki `exporting-support-older-anki-versions` | Compatibilidad con versiones anteriores de Anki |
| Notes in Plain Text | Anki `exporting-notes-in-plain-text` | Notas en texto plano |
| Image Occlusion | Anki `notetypes-image-occlusion-name` | Oclusión de imagen |
| template (a card's, in Anki) | Anki `card-templates-template-box` | plantilla |
| Media (a card's images and sounds) | Anki `editing-media` | Multimedia |
| review ahead | Anki `custom-study-review-ahead` | repasar por adelantado, un repaso por adelantado |
| graduate (a card leaving its steps) | Anki `scheduling-graduating-interval` | graduarse, as Anki's "Intervalo de graduación" |
| discard | Anki `actions-discard` | descartar |

## Apple's terms

| English | Source | Spanish (es) |
|---|---|---|
| Settings… | Apple | Configuración… |
| settings (an app's) | Apple | configuración |
| System Settings | Apple | Configuración del Sistema |
| Login Items | Apple | Elementos de inicio |
| Open at Login | Apple | Abrir al iniciar sesión |
| Quit | Apple | Salir |
| Cancel | Apple | Cancelar |
| OK | Apple | OK |
| Done | Apple | Listo |
| Add | Apple | Agregar, as Apple's Spanish (Latin America) and Rioplatense Spanish say it, where Anki's `actions-add` says Añadir |
| Restore | Apple | Restaurar |
| Close | Apple | Cerrar |
| Undo | Apple | Deshacer |
| Delete | Apple | Eliminar |
| Edit | Apple | Editar |
| Paste | Apple | Pegar |
| Find | Apple | Buscar |
| Rename | Apple | Renombrar |
| Show in Finder | Apple | Mostrar en el Finder |
| Move to Trash, Trash | Apple | Transferir al basurero, basurero |
| Downloads | Apple | Descargas |
| sidebar | Apple | barra lateral |
| menu bar | Apple | barra de menús |
| Emoji & Symbols | Apple | Emoji y símbolos |
| Focus, Focus filter | Apple | enfoque, filtro de enfoque |
| full screen | Apple | pantalla completa |
| backup, backups | Apple | respaldo, respaldos |
| About | Apple | Acerca de |
| Privacy Policy | Apple | Política de privacidad |
| Finder's tag colors: Red, Orange, Yellow, Green, Blue, Purple, Gray | Apple | Rojo, Naranja, Amarillo, Verde, Azul, Morado, Gris |

## Ficha's own terms

| English | Source | Spanish (es) |
|---|---|---|
| review (noun) | Ficha | repaso |
| review (verb) | Ficha | repasar |
| Review now | Ficha | Repasar ahora |
| review panel | Ficha | panel de repaso |
| review log | Ficha | historial de repasos |
| capture (noun, verb) | Ficha | captura, capturar |
| inbox | Ficha | bandeja |
| approve (a capture into cards) | Ficha | aprobar |
| flag, flagged | Ficha | marcar, marcada |
| expand, expansion | Ficha | ampliar, ampliación |
| follow-up (a question about a card) | Ficha | consulta |
| refine, refine session | Ficha | refinar, sesión de refinado |
| appearance (a card showing up on its own) | Ficha | aparición |
| hold back appearances | Ficha | frenar las apariciones |
| snoozed | Ficha | pospuesta |
| idle | Ficha | inactivo |
| priority deck, Prioritize | Ficha | mazo prioritario, Priorizar |
| set aside | Ficha | apartar, apartada |
| Both ways | Ficha | En ambos sentidos |
| front first, back first | Ficha | anverso primero, reverso primero |
| way (front first or back first) | Ficha | sentido |
| learned | Ficha | aprendida; Learned in the sidebar: Aprendidas |
| card type; Word, Concept, Quote, Question | Ficha | tipo; Palabra, Concepto, Frase, Pregunta |
| source (of a card) | Ficha | fuente |
| note (on a capture or a flag) | Ficha | nota |
| pin to the sidebar | Ficha | fijar en la barra lateral |
| capture shortcut | Ficha | atajo de captura |
| Flip | Ficha | Dar vuelta |
| Diagnostics | Ficha | Diagnóstico |
| sync | Ficha | sincronización, sincronizar |
| an AI | Ficha | una IA |
| tick, untick (a checkbox), since flag is marcar | Ficha | tildar, destildar |
