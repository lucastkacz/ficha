# Ficha's words in each language

Every text the app shows is translated into the languages `scripts/languages.txt` lists (ADR 0027), and a term reads the same on every screen. This list holds the word each language uses for each term the UI shows: a new text uses the words here, and a new term gets a row in the change that brings it.

A term's source says where its words come from:

- **Anki**: Anki's own translation, from its Fluent files in [`ankitects/anki-core-i18n`](https://github.com/ankitects/anki-core-i18n), `core/<locale>/*.ftl`, under the message ID the row names. Where Anki has two words for one term, the row picks one.
- **Apple**: the word macOS uses in that language, in its own menus, System Settings and Finder.
- **Ficha**: our own word, chosen in the first translation into that language.

A language joins with a column here, beside its line in `scripts/languages.txt`. Spanish is Rioplatense, with "vos" in what the app asks of the user ("Elegí", "Revisá", "Tenés"), and Anki's words stay as Anki's Spanish has them. Quotes are « ».

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
| new cards per day | Anki `scheduling-new-cardsday` | tarjetas nuevas por día |
| Scheduling (Settings' tab) | Anki `preferences-scheduling` | Programación |
| created | Anki `browsing-created` | creada |
| notes (Anki's) | Anki `browsing-notes` | notas |
| Import, Export | Anki `actions-import`, `actions-export` | Importar, Exportar |
| Support older Anki versions | Anki `exporting-support-older-anki-versions` | Compatibilidad con versiones anteriores de Anki |

## Apple's terms

| English | Source | Spanish (es) |
|---|---|---|
| Settings… | Apple | Ajustes… |
| System Settings | Apple | Ajustes del Sistema |
| Login Items | Apple | Ítems de inicio |
| Open at Login | Apple | Abrir al iniciar sesión |
| Quit | Apple | Salir |
| Cancel | Apple | Cancelar |
| OK | Apple | Aceptar |
| Done | Apple | OK |
| Close | Apple | Cerrar |
| Undo | Apple | Deshacer |
| Delete | Apple | Eliminar |
| Edit | Apple | Editar |
| Paste | Apple | Pegar |
| Find | Apple | Buscar |
| Rename | Apple | Renombrar |
| Show in Finder | Apple | Mostrar en el Finder |
| Move to Trash, Trash | Apple | Trasladar a la papelera, papelera |
| Downloads | Apple | Descargas |
| sidebar | Apple | barra lateral |
| menu bar | Apple | barra de menús |
| Emoji & Symbols | Apple | Emojis y símbolos |
| Focus | Apple | modo de Concentración |
| full screen | Apple | pantalla completa |
| backups | Apple | copias de seguridad |
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
