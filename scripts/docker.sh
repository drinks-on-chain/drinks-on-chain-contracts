#!/usr/bin/env bash
# Ejecuta un comando en la imagen de desarrollo (Rust + stellar-cli), con el
# repo montado en /work y cachés de cargo, rustup y target en volúmenes.
#
#   scripts/docker.sh scripts/verificar.sh
#   scripts/docker.sh cargo test
#
# La primera vez construye la imagen `drinks-on-chain-contracts-dev`.
set -euo pipefail
export MSYS_NO_PATHCONV=1

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
IMAGEN=drinks-on-chain-contracts-dev

# En Git Bash de Windows, `pwd -W` da la ruta que entiende Docker Desktop.
MONTAJE="$(cd "$RAIZ" && (pwd -W 2>/dev/null || pwd))"

if ! docker image inspect "$IMAGEN" >/dev/null 2>&1; then
  docker build -t "$IMAGEN" -f "$MONTAJE/scripts/Dockerfile.dev" "$MONTAJE/scripts"
fi

exec docker run --rm \
  -v "$MONTAJE:/work" \
  -v doc-contracts-cargo-registry:/usr/local/cargo/registry \
  -v doc-contracts-cargo-git:/usr/local/cargo/git \
  -v doc-contracts-rustup:/usr/local/rustup \
  -v doc-contracts-target:/work/target \
  -w /work "$IMAGEN" bash -c "$*"
