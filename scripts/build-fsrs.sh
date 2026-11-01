#!/bin/bash
# Builds our crate, and fsrs-rs with it, into the XCFramework that FichaKit
# links (ADR 0026): `make fsrs`, which every target that builds FichaKit runs
# first. It holds a static library for the Mac, for Apple silicon and Intel,
# whose archive is universal, one for an iPhone, and one for its simulator, on
# Apple silicon and Intel too (ADR 0015), beside the header cbindgen wrote and
# the crate's module map. The crate's .cargo/config.toml says where Cargo
# builds, the worktree's .build/cargo, and for which deployment targets.
#
# It builds only when the crate's files, its lock and rust-toolchain.toml
# among them, or this script changed since the XCFramework was built, which a
# digest of them beside it records: so the next `make check` doesn't build
# fsrs-rs again, nor does a CI run that restored both from its cache.
# Building the libraries with Cargo, joining each platform's architectures with
# lipo and making the XCFramework with xcodebuild are the documented way; the
# digest is our own.
#
# Usage: scripts/build-fsrs.sh <crate folder> <XCFramework>

set -euo pipefail

(($# == 2)) || {
  echo "Usage: scripts/build-fsrs.sh <crate folder> <XCFramework>: run it through make fsrs, which passes both." >&2
  exit 1
}
crate=$1
xcframework=$2
module=$(basename "$xcframework" .xcframework)
frameworks=$(dirname "$xcframework")
digest_file=$frameworks/$module.digest

# The digest of the crate's files that git tracks or would add, with their
# paths, and of this script.
digest=$(
  {
    git ls-files -z --cached --others --exclude-standard -- "$crate" | sort -z | xargs -0 shasum -a 256
    shasum -a 256 "$0"
  } | shasum -a 256 | cut -d ' ' -f 1
)
if [[ -d $xcframework && -f $digest_file && $(<"$digest_file") == "$digest" ]]; then
  exit 0
fi

command -v cargo >/dev/null || {
  echo "There's no cargo to build fsrs-rs with: run make bootstrap, which installs rustup and the Rust toolchain that $crate/rust-toolchain.toml pins." >&2
  exit 1
}

mac=(aarch64-apple-darwin x86_64-apple-darwin)
iphone=(aarch64-apple-ios)
simulator=(aarch64-apple-ios-sim x86_64-apple-ios)
targets=()
for target in "${mac[@]}" "${iphone[@]}" "${simulator[@]}"; do
  targets+=(--target "$target")
done

echo "Building fsrs-rs for the Mac, the iPhone and its simulator, as the crate, its lock or the toolchain changed."
messages=$(mktemp)
trap 'rm -f "$messages"' EXIT
# Cargo's messages as JSON, which name the folder where build.rs wrote the
# header for each target; its diagnostics, rendered, go to standard error.
(cd "$crate" && cargo build --locked --release "${targets[@]}" --message-format=json-render-diagnostics) >"$messages" || {
  echo "Cargo couldn't build fsrs-rs, as it says above: fix the crate in $crate, or, when the toolchain is missing, run make bootstrap." >&2
  exit 1
}
target_folder=$(cd "$crate" && cargo metadata --locked --format-version 1 --no-deps | jq -r .target_directory) || {
  echo "Cargo built fsrs-rs, but cargo metadata couldn't say where, as it says above: run make fsrs again, and if it fails the same way, check the crate's Cargo.toml and .cargo/config.toml in $crate, which it reads." >&2
  exit 1
}
header_folder=$(jq -r 'select(.reason == "build-script-executed" and (.package_id | contains("ficha-fsrs"))) | .out_dir' "$messages" | head -n 1)
[[ -f $header_folder/ficha_fsrs.h ]] || {
  echo "Cargo built fsrs-rs, but its messages name no header that build.rs wrote: check that build.rs still writes ficha_fsrs.h to OUT_DIR." >&2
  exit 1
}

# Each platform's library, its architectures joined, and the headers, in a
# folder of the module's name, built beside the XCFramework and put in its
# place once it's whole.
mkdir -p "$frameworks"
work=$(mktemp -d "$frameworks/.$module.XXXXXX")
trap 'rm -f "$messages"; rm -rf "$work"' EXIT
library() {
  local platform=$1
  shift
  mkdir -p "$work/$platform"
  local libraries=()
  for target in "$@"; do
    libraries+=("$target_folder/$target/release/libficha_fsrs.a")
  done
  lipo -create "${libraries[@]}" -output "$work/$platform/libficha_fsrs.a" || {
    echo "lipo couldn't join the libraries Cargo built for $platform ($*), as it says above: check that $crate/Cargo.toml still builds a static library named ficha_fsrs, whose libficha_fsrs.a this script joins, and run make fsrs again." >&2
    exit 1
  }
}
library macos "${mac[@]}"
library ios "${iphone[@]}"
library ios-simulator "${simulator[@]}"
mkdir -p "$work/include/$module"
cp "$header_folder/ficha_fsrs.h" "$crate/module.modulemap" "$work/include/$module/"
xcodebuild -create-xcframework -output "$work/$module.xcframework" \
  -library "$work/macos/libficha_fsrs.a" -headers "$work/include" \
  -library "$work/ios/libficha_fsrs.a" -headers "$work/include" \
  -library "$work/ios-simulator/libficha_fsrs.a" -headers "$work/include" >/dev/null || {
  echo "xcodebuild couldn't make the XCFramework from the libraries Cargo built, as it says above: check that the selected Xcode (xcode-select -p) is the one .xcode-version names, which make xcode-check checks, and run make fsrs again." >&2
  exit 1
}

rm -rf "$xcframework"
mv "$work/$module.xcframework" "$xcframework"
echo "$digest" >"$digest_file"
echo "Built $xcframework."
