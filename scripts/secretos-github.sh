#!/usr/bin/env bash
# Copia las claves de testnet de la configuración local de `stellar keys`
# (volumen Docker doc-contracts-stellar) a los secretos de GitHub Actions del
# repo, para el workflow "Testnet". Se ejecuta en la máquina local (necesita
# `gh` con permiso sobre el repo y Docker).
#
#   scripts/secretos-github.sh [--bodega <alias>]…
#
# Cada clave va de `stellar keys show` a `gh secret set` por una tubería: no
# se imprime, no se escribe en ningún archivo y no aparece en la línea de
# comandos de ningún proceso. Por defecto, las bodegas de demostración.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="${REPO:-drinks-on-chain/drinks-on-chain-contracts}"
BODEGAS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --bodega) BODEGAS+=("$2"); shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Opción desconocida: $1" >&2; exit 2 ;;
  esac
done
[ ${#BODEGAS[@]} -gt 0 ] || BODEGAS=(altos-de-calamuchita destileria-cinti-viejo)
for b in "${BODEGAS[@]}"; do
  [[ "$b" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || { echo "Alias no válido: $b" >&2; exit 2; }
done

copiar() { # identidad, secreto
  scripts/docker.sh "stellar keys show $1 2>/dev/null | tr -d '\n'" \
    | gh secret set "$2" --repo "$REPO"
  echo "$2 ← identidad $1"
}

copiar testnet-despliegue TESTNET_DEPLOYER_SECRET
copiar testnet-plataforma TESTNET_PLATFORM_SECRET
for b in "${BODEGAS[@]}"; do
  copiar "testnet-bodega-$b" "TESTNET_WINERY_$(echo "$b" | tr 'a-z-' 'A-Z_')_SECRET"
done
gh secret list --repo "$REPO"
