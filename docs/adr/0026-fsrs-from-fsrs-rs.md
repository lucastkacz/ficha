# FSRS's arithmetic comes from fsrs-rs, the Rust library Anki ships

ADR 0025 has Ficha schedule with FSRS, as Anki does. Spec #404 first planned FSRS-6 as our own Swift code. On 2026-11-01 Lucas decided not to reinvent the wheel: FSRS's arithmetic comes from fsrs-rs, the Rust library of the FSRS authors, which Anki ships. Anki pins it to 6.6.2, and so does Ficha. That arithmetic is a card's memory state after a rating, the interval for a desired retention, a memory state started from an SM-2 interval and ease, retrievability and the default parameters. Later it also covers Optimize's fitting of the parameters, which only fsrs-rs and a Python package offer. Anki's own rules around FSRS stay Swift: its learning and relearning steps, rounding, the order of the buttons' intervals and the fuzz. Anki keeps those in its own code (rslib), not in fsrs-rs. Ficha links fsrs-rs through a small Rust crate of its own, which exports the few functions Ficha calls as a C interface. That crate is built into an XCFramework, which FichaKit links for the Mac and the iPhone.

## Considered options

- **FSRS-6 written in Swift, as #404 first planned.** The scheduler's formulas are short. Optimize isn't: fsrs-rs computes its gradients by hand, in thousands of lines that would have to be ported and kept right. Each FSRS release, such as FSRS-7, which models hours, would be another port.
- **swift-fsrs (MIT), the FSRS authors' Swift port.** It defaults to FSRS-5's parameters, and it has no optimizer.
- **fsrs-rs-c, the FSRS authors' C binding.** It's built on fsrs 5.2.0, not the 6.6.2 Anki ships. It's a dynamic library, which an iOS app can ship only wrapped in a framework of its own. And it hands out heap pointers to free.
- **UniFFI, Mozilla's bindings generator, in place of a C interface.** It generates the Swift side, and that generated code would have to pass Ficha's lint and Swift 6's checks with warnings as errors. It's worth it for a large surface, not for a handful of functions on numbers.

## Consequences

- **fsrs-rs is Ficha's fifth dependency.** It's pinned exactly, `=6.6.2`, with `Cargo.lock` committed and builds run with `--locked`. This is the ADR that `CODING_STANDARDS.md` asks for.
  - It brings its own crates: ndarray, rayon, rand, serde, itertools, snafu, strum, log and priority-queue. burn, the ML framework, is only a development dependency of fsrs-rs, so Ficha doesn't build it.
  - Its BSD-3-Clause notice, and the notices of the crates it brings, go with the app as every dependency's do for the App Store release (ADR 0015, #160).
- **Upgrading fsrs-rs is a PR of its own, `risk:high`.** A new version can change intervals, so it comes deliberately, as Anki moves its own pin.
- **The build gains Rust.**
  - A `rust-toolchain.toml` pins Rust and lists the targets: the Mac, the iPhone and its simulator, in every architecture each builds for.
  - `make bootstrap` installs rustup, and CI caches Cargo's downloads and builds, so the builds stay fast.
  - The XCFramework is built from source, never committed, and rebuilt only when the crate, its lock or the toolchain change.
  - Our crate is the only Rust of ours, and it passes rustfmt and clippy with warnings as errors in `make check`.
- **The C interface passes plain values.** Memory states, intervals and parameters go across as numbers and structs, with no pointer kept across a call. Every exported function returns a status instead of letting a panic cross into Swift. cbindgen writes the header.
- **This changes ADR 0005.** FichaCore, still pure logic with time injected, now links fsrs-rs through a FichaKit target that wraps the C interface. fsrs-rs's scheduling is arithmetic alone: no file, network, clock or threads in what FichaCore calls. `swift test` still runs without building the app, once the XCFramework is built.
- **It keeps the app 100% local (ADR 0001).** Cargo downloads crates at build time, as SwiftPM does packages, and nothing at run time.
- **The tests check our use of fsrs-rs, not fsrs-rs itself.** A few tests keep fsrs-rs's expected values, so an upgrade that changes them fails loudly.
- **Optimize, a later issue, is planned on fsrs-rs's `compute_parameters`.** ADR 0025 left it out because nobody has reviews yet, which still holds.
- **Standard practice:**
  - fsrs-rs as Anki ships it, at Anki's version;
  - a Rust static library behind a C interface whose header cbindgen writes, as Rust's FFI documentation and cbindgen describe;
  - an XCFramework of static libraries linked as a SwiftPM binary target, as Apple and SwiftPM document;
  - `rust-toolchain.toml`, as rustup documents.
- **Our own:**
  - the wrapper crate and its few functions;
  - which of Anki's rules stay in Swift: the steps, rounding, the buttons' order and the fuzz;
  - building the XCFramework from source rather than committing it.
