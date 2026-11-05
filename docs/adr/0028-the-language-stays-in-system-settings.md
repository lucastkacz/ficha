# The language stays in System Settings, with no picker of Ficha's own

ADR 0009 says Ficha has no language setting of its own, since System Settings sets a language per app. In #444 Lucas asked for a picker in Ficha, in Settings and at the first launch, as in Anki, since his family shares his Mac and doesn't read much English. Apple advises against setting an app's language in code and points to Settings (WWDC19 session 403). On hearing that, on 2026-11-05, Lucas chose to do as Apple proposes, so ADR 0009 stands. This is a difference from Anki on purpose.

## Considered options

- A picker of Ficha's own that writes `AppleLanguages`, as Lucas first chose. In an unsandboxed probe with no UI, on macOS 26.3.1, that changed Foundation's strings at the next launch; SwiftUI and the sandbox went untested. Apple's technical support called that way unsupported, speaking of iOS (developer forums, thread 679934, 2021).
- A translation mechanism of Ficha's own, which could change the language with no relaunch: it repeats what macOS does.
- A button that lands on Language & Region, through a URL third parties report: Apple documents no such URL, and calls undocumented ones unsupported.
- Nothing in Ficha, as today: few people would learn that System Settings can set a language for one app.

## Consequences

- Ficha's Settings has a Language row that says where to change the language, with a button that opens System Settings at no pane in particular, since no documented URL reaches one app's language on the Mac.
- Someone who doesn't read the Mac's language can't easily change Ficha's alone: someone else sets it for them.
- Relaunching after a change is left to macOS, and Ficha adds no code for it. Apple documents nothing on whether the per-app language reaches a widget on the Mac, so a hand check says what happens, and the widget stays as macOS leaves it.
- The iPhone does the same (ADR 0019): its row opens the app's page in the system's Settings (`openSettingsURLString`), the route WWDC19 session 403 recommends. When iOS shows a language row there today wasn't established, so that ticket checks it.
- Standard practice: the per-app language in the system's settings, and `openSettingsURLString`. Our own: the row that says where it is.
