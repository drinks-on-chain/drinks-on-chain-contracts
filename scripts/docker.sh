#!/usr/bin/env bash
# Ejecuta un comando en la imagen de desarrollo (Rust + stellar-cli + jq), con
# el repo montado en /work y cachés de cargo, rustup y target en volúmenes.
#
#   scripts/docker.sh scripts/verificar.sh
#   scripts/docker.sh cargo test
#   scripts/docker.sh scripts/cuentas-testnet.sh
#
# La imagen se etiqueta con el hash de scripts/Dockerfile.dev: si el Dockerfile
# cambia, se construye de nuevo.
#
# Las identidades de `stellar keys` (cuentas de testnet) viven en el volumen
# `doc-contracts-stellar`, montado en ~/.config/stellar del contenedor: fuera
# del repo y fuera de la imagen. Para pasar una clave a un secreto de GitHub
# sin imprimirla ni ponerla en la línea de comandos:
#
#   scripts/docker.sh stellar keys show dc-testnet-despliegue \
#     | gh secret set TESTNET_DEPLOYER_SECRET --repo drinks-on-chain/drinks-on-chain-contracts
set -euo pipefail
export MSYS_NO_PATHCONV=1

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"

# En Git Bash de Windows, `pwd -W` da la ruta que entiende Docker Desktop.
MONTAJE="$(cd "$RAIZ" && (pwd -W 2>/dev/null || pwd))"

ETIQUETA="$(sha256sum "$RAIZ/scripts/Dockerfile.dev" | cut -c1-12)"
IMAGEN="drinks-on-chain-contracts-dev:$ETIQUETA"

if ! docker image inspect "$IMAGEN" >/dev/null 2>&1; then
  docker build -q -t "$IMAGEN" -f "$MONTAJE/scripts/Dockerfile.dev" "$MONTAJE/scripts" >&2
fi

exec docker run --rm -i \
  -v "$MONTAJE:/work" \
  -v doc-contracts-cargo-registry:/usr/local/cargo/registry \
  -v doc-contracts-cargo-git:/usr/local/cargo/git \
  -v doc-contracts-rustup:/usr/local/rustup \
  -v doc-contracts-target:/work/target \
  -v doc-contracts-stellar:/root/.config/stellar \
  -w /work "$IMAGEN" bash -c "$*"
