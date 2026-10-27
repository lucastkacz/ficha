# The iPhone app does what the Mac app does

Ficha sells for the Mac and the iPhone together (#160), and the Mac is built first. The iPhone's spec (#97) left some of the Mac's features out of the iPhone, such as making, editing and importing cards, which it left to the Mac. Lucas decided that the iPhone app does what the Mac app does, the same or as close as the platform allows, with no compromise between the two: someone with only an iPhone gets all of Ficha, as AnkiMobile lets its users import a deck without a computer. The two apps share their code as far as it goes: what a feature decides lives in `FichaKit`, which both apps build (ADR 0005), and each app holds only what its platform needs, its screens and its hooks into the system.

## Considered options

- A lighter iPhone app, which reviews and captures while cards are made and imported on the Mac and reach the phone by sync: less to build, but it leaves out whoever has no Mac, and the two apps drift apart.
- Code of its own for each app, fitted to each platform: every feature built twice, and two versions that drift apart.

## Consequences

- When #97 resumes, its lists of what stays off the iPhone are checked against this ADR: an item stays off only where the platform rules it out, and the spec says why. Making, editing and importing cards come to the iPhone, which #97's comment of 2026-10-27 notes for importing.
- A difference the platform forces is written down with its reason, in an ADR or in the spec, as ADR 0010 does for appearances, which come as notifications on the iPhone. The suppressions, idle time, the capture shortcut and starting at login stay on the Mac for that reason: iOS's Focus silences notifications, and iOS has neither a menu bar nor a global shortcut.
- A feature is never planned or described as being for the Mac alone. Each Mac feature becomes an iPhone ticket when #97 resumes, as #160 orders.
- Code that is Mac-only today, such as drawing an Anki deck's SVG images (`SVGImages.swift`, and #306's XPC service), gets an iPhone counterpart when the iPhone's turn comes.
- Work that weighs on the device adapts to it rather than staying off the phone: sounds convert as many at once as the device has cores (#329).
