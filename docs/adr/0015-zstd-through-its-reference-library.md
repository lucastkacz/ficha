# zstd through its reference library, and protobuf by hand

Current Anki exports a deck, by default, as a package whose collection, media list and media files are each compressed with zstd, and whose `meta` and media list are protobuf messages (ADR 0013). Apple's Compression framework has no zstd, so Ficha links zstd's reference library, the C code Facebook publishes in `facebook/zstd`, which Anki itself uses through Rust's `zstd` crate. That repository ships its own `Package.swift`, which exposes the library to SwiftPM as the module `libzstd`, so Ficha depends on it directly, with no wrapper in between, and calls zstd's streaming API from Swift. Protobuf gets no library: Ficha reads the few fields it needs, a package's version, its media files' names, a note type's kind and stock kind, and a template's two formats, with a reader of its own of about a hundred lines, which follows protobuf's documented wire format and skips the fields it doesn't know.

## Considered options

- A Swift wrapper around zstd, such as SwiftZSTD: someone else's code around the same C library, often a copy of an older zstd, for the few calls Ficha makes.
- A zstd decoder of our own in Swift: the format is public (RFC 8878), but its entropy coders and sequences run to thousands of lines, where a homemade decoder fails on files zstd's own encoder made.
- Apple's swift-protobuf, with Swift generated from Anki's `.proto` files: a second dependency, and a code generator to rerun when Anki's messages change, to read a handful of fields.

## Consequences

- zstd is Ficha's fourth dependency, pinned to an exact version, 1.5.7, in `Package.swift`, with `Package.resolved` committed; this is the ADR that `CODING_STANDARDS.md` asks for. It's dual-licensed, BSD or GPLv2 at our choice, and Ficha takes the BSD license, which lets an app on the App Store link it, as long as its copyright notice goes with the app, as the notices of every dependency must for the App Store release (#160).
- It's in FichaData, which the iPhone app links too: its manifest supports macOS 10.10 and iOS 9 on, below Ficha's macOS 26 and iOS 26, and SwiftPM builds it for the Mac and for the iPhone's simulator, the Intel one included, whose build takes zstd's x86-64 assembly.
- It keeps the app 100% local (ADR 0001): the library works on memory alone, with no file, network or threading code in what Ficha builds, so it needs no privacy manifest.
- SwiftPM clones the whole repository, about 40 MB, once; CI keeps it in its cache.
- The library compresses too. The app only decompresses, while the tests compress the packages they write, streamed as Anki streams them, so a frame never says its size and the tests fail where a reader that relied on it would fail on Anki's files.
- Standard practice: the zstd format and its reference library, through the library's own manifest; decompressing as a stream, as zstd's own example does, since Anki's frames don't say how large they are; and protobuf's wire format, as its encoding guide describes it.
- Our own: reading protobuf by hand, and which fields; reading a whole member into memory, as zips are read (ADR 0014); and, for the collection, a database Anki leaves in WAL mode with its names declared with a collation of Anki's own, opening a copy for writing, since SQLite can't read a WAL database read-only without its `-shm` file, and registering a case-insensitive comparison under Anki's collation's name, `unicase`.
- Dependabot updates it monthly with the other dependencies.
