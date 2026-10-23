# Zips through ZIPFoundation

Cards with images travel in a zip, with the text file and the images (ADR 0012), and Anki's packages, which Ficha imports too (ADR 0013), are zips. Apple's frameworks have no public API that reads or writes a zip: the Compression framework deflates and inflates, but knows nothing of the zip around the data; `NSFileCoordinator` zips a whole folder for sharing, but reads none; and `ditto` or `unzip` are Mac command-line tools, which the iPhone lacks. ZIPFoundation, the zip library most Swift apps use, reads and writes zips in Swift over the Compression framework, in memory or on disk, and builds for macOS and iOS. We picked it over a zip reader and writer of our own on the Compression framework: the format is public (PKWARE's APPNOTE), but its variants, such as ZIP64, data descriptors and names that aren't UTF-8, are where a homemade one fails on files other tools made.

## Considered options

- A zip reader and writer of our own, as above.
- Exporting a folder, or a Ficha document package, instead of a zip: Finder and AirDrop handle one, but mail and most chat apps send a single file, and Anki's packages would still need a zip reader.

## Consequences

- ZIPFoundation is Ficha's third dependency, pinned to an exact version, 0.9.20, in `Package.swift`, with `Package.resolved` committed; this is the ADR that `CODING_STANDARDS.md` asks for. It's under the MIT license, as GRDB is, which lets an app on the App Store link it, as long as its copyright notice goes with the app: the App Store release (#160) has to show the notices of every dependency, which the app doesn't yet.
- It's in FichaData, which the iPhone app links too: its manifest supports macOS 10.13 and iOS 12 on, below Ficha's macOS 26 and iOS 26.
- It keeps the app 100% local (ADR 0001): it reads and writes files and memory, and has no network code. Its privacy manifest declares only reading files' dates, as GRDB's does.
- Standard practice: the zip format itself, which Finder, Windows and every zip tool open; the text compressed and JPEGs and PNGs stored as they are, which zip tools leave alone since they're compressed already; and ZIPFoundation used as its README shows.
- Our own: what a zip of cards holds, one text file of cards, at its top or in a folder, with the images beside it, which its Front image and Back image columns name; leaving out what Finder adds when it zips a folder (`__MACOSX` and files whose name starts with a dot); finding an image's name in any case, as a Mac finds a file; and keeping an image as it is when it's one Ficha shrank and named, so cards passed from one Ficha to another keep their images byte for byte.
- Dependabot updates it monthly with the other dependencies.
