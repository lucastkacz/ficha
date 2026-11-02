//! Writes the C header of the crate's functions with cbindgen, as cbindgen's
//! documentation shows for a build script, to Cargo's output folder for the
//! crate, where `scripts/build-fsrs.sh` takes it from for the XCFramework.

use std::env;
use std::path::PathBuf;

fn main() {
    let crate_folder = env::var("CARGO_MANIFEST_DIR").expect("Cargo sets CARGO_MANIFEST_DIR");
    let output_folder = env::var("OUT_DIR").expect("Cargo sets OUT_DIR");
    let config = cbindgen::Config::from_file(PathBuf::from(&crate_folder).join("cbindgen.toml"))
        .expect("cbindgen.toml beside Cargo.toml is cbindgen's configuration");
    cbindgen::Builder::new()
        .with_crate(&crate_folder)
        .with_config(config)
        .generate()
        .expect("cbindgen writes the header from src/lib.rs")
        .write_to_file(PathBuf::from(output_folder).join("ficha_fsrs.h"));
    println!("cargo::rerun-if-changed=src");
    println!("cargo::rerun-if-changed=cbindgen.toml");
}
