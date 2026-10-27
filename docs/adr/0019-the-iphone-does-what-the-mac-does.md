# The iPhone app does what the Mac app does

Ficha sells for the Mac and the iPhone together (#160), and the Mac is built first. Until now some features stayed off the iPhone: #97, the iPhone's spec, left making, editing and importing cards to #86, which built them for the Mac alone, and #160 keeps some things on one platform by design. Lucas decided that the iPhone app does what the Mac app does, the same or as close as the platform allows, with no compromise between the two, so that someone with only an iPhone can make, import and review cards as on a Mac. The two apps share their code as far as it goes: what a feature decides lives in `FichaKit`, which both apps build (ADR 0005), and so do the views both platforms can draw alike; an app keeps apart only what its platform alone needs.

## Considered options

- A lighter iPhone app, which reviews and captures while cards are made and imported on the Mac and reach the phone by sync: less to build, but it leaves out whoever has no Mac, and the two apps drift apart.
- Code of its own for each app, fitted to each platform: every feature built twice, and two versions that drift apart.

## Consequences

- A difference between the apps stays only where the platform rules a feature out, and it's written down with its reason, in an ADR or in the spec. Where the other platform has its own way to the same end, the feature takes it, as an appearance comes as card notifications on the iPhone (ADR 0010).
- When #97 resumes, its lists of what stays off the iPhone, and #160's list of what stays on one platform by design, are checked item by item against that rule. Making, editing and importing cards come to the iPhone: #97's comment of 2026-10-27 notes importing, with what it leaves to that grilling.
- Each Mac feature becomes an iPhone ticket when #97 resumes, as #160 orders.
- The same holds in the code: code that builds for the Mac alone, such as drawing SVG images (`SVGImages.swift`), is a difference like any other, and stays only for the platform's reason.
- Standard practice: one Swift package that builds for macOS and iOS, which both apps link. Our own: the rule that the two apps differ only where the platform forces it.
