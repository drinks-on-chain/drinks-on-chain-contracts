#!/usr/bin/env bash
# Puertas locales de los contratos (plan/04 §1), las mismas que la CI:
# formato, clippy, pruebas, WASM optimizado y simulación del despliegue.
# Requiere Rust (rust-toolchain.toml) y stellar-cli >= 25.2 en el PATH; en
# Windows: scripts/docker.sh scripts/verificar.sh
set -euo pipefail
cd "$(dirname "$0")/.."

paso() { echo; echo "── $*"; }

paso "cargo fmt --all --check"
cargo fmt --all --check

paso "cargo clippy --all-targets -- -D warnings"
cargo clippy --all-targets -- -D warnings

paso "cargo test"
cargo test

paso "stellar contract build (WASM optimizado)"
stellar contract build --package winery-nft --locked --out-dir dist

paso "simulación del despliegue sobre el WASM"
cargo clippy --all-targets --features wasm-tests -- -D warnings
cargo test -p winery-nft --features wasm-tests test_wasm

paso "resultado"
ls -l dist/winery_nft.wasm
sha256sum dist/winery_nft.wasm
