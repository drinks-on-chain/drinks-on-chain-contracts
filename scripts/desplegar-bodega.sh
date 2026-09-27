#!/usr/bin/env bash
# BORRADOR (paso B.3, Ola 2) · despliegue del contrato NFT de una bodega.
# No se ha ejecutado contra ninguna red. Revisar en B.3 antes de usarlo.
#
# Qué hace:
#   1. Compila el WASM optimizado (stellar contract build) si no existe.
#   2. Sube el código a la red UNA vez (stellar contract upload) y guarda el
#      hash en deployments/<red>/wasm.json. Si el hash ya está, no lo sube.
#   3. Crea la instancia de la bodega (stellar contract deploy) con su
#      constructor y guarda la dirección C… en deployments/<red>/<alias>.json.
#
# Requisitos: stellar-cli >= 25.2 (la CI usa 28.1.0) y una identidad de
# despliegue en `stellar keys` que pague comisiones. En testnet:
#   stellar keys generate despliegue-testnet --network testnet --fund
# (Friendbot la fondea). Nunca escribas claves secretas en este repo: las
# identidades viven en la configuración local de stellar-cli o en el custodio.
#
# Uso:
#   scripts/desplegar-bodega.sh \
#     --red testnet --fuente despliegue-testnet \
#     --alias bodega-demo \
#     --admin G...CUENTA_DE_LA_BODEGA --operador G...CUENTA_DE_OPERACIONES \
#     --nombre "Bodega Demo" --simbolo BDEMO \
#     --uri-base "https://api.example.test/v1/nft/bodega-demo/" \
#     [--solo-construir]
#
#   --solo-construir  construye las transacciones sin firmarlas ni enviarlas
#                     (stellar --build-only) para revisarlas.
set -euo pipefail
cd "$(dirname "$0")/.."

RED=testnet
FUENTE=""
ALIAS=""
ADMIN=""
OPERADOR=""
NOMBRE=""
SIMBOLO=""
URI_BASE=""
SOLO_CONSTRUIR=0
WASM=dist/winery_nft.wasm

uso() { sed -n '2,32p' "$0"; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --red) RED="$2"; shift 2 ;;
    --fuente) FUENTE="$2"; shift 2 ;;
    --alias) ALIAS="$2"; shift 2 ;;
    --admin) ADMIN="$2"; shift 2 ;;
    --operador) OPERADOR="$2"; shift 2 ;;
    --nombre) NOMBRE="$2"; shift 2 ;;
    --simbolo) SIMBOLO="$2"; shift 2 ;;
    --uri-base) URI_BASE="$2"; shift 2 ;;
    --solo-construir) SOLO_CONSTRUIR=1; shift ;;
    -h|--help) uso ;;
    *) echo "Opción desconocida: $1" >&2; uso ;;
  esac
done

for v in FUENTE ALIAS ADMIN OPERADOR NOMBRE SIMBOLO URI_BASE; do
  [ -n "${!v}" ] || { echo "Falta --$(echo "$v" | tr 'A-Z_' 'a-z-')" >&2; uso; }
done

case "$RED" in
  testnet|futurenet|local) ;;
  mainnet)
    # B.4: solo tras la revisión externa y con confirmación explícita.
    [ "${CONFIRMO_MAINNET:-}" = "si" ] || {
      echo "mainnet requiere la revisión externa (B.4) y CONFIRMO_MAINNET=si" >&2; exit 1; }
    ;;
  *) echo "Red no soportada: $RED" >&2; exit 1 ;;
esac

[ "$ADMIN" != "$OPERADOR" ] || { echo "La bodega y el operador deben ser cuentas distintas" >&2; exit 1; }

EXTRA=()
[ "$SOLO_CONSTRUIR" = 1 ] && EXTRA+=(--build-only)

mkdir -p "deployments/$RED"

# 1. WASM
if [ ! -f "$WASM" ]; then
  stellar contract build --package winery-nft --locked --out-dir dist
fi
HASH_LOCAL="$(sha256sum "$WASM" | cut -d' ' -f1)"

# 2. Código (una vez por red y versión del WASM)
WASM_JSON="deployments/$RED/wasm.json"
if [ -f "$WASM_JSON" ] && grep -q "\"$HASH_LOCAL\"" "$WASM_JSON"; then
  WASM_HASH="$HASH_LOCAL"
  echo "Código ya subido a $RED: $WASM_HASH"
else
  echo "Subiendo el código a $RED…"
  WASM_HASH="$(stellar contract upload --wasm "$WASM" \
    --source-account "$FUENTE" --network "$RED" "${EXTRA[@]}")"
  if [ "$SOLO_CONSTRUIR" = 1 ]; then
    echo "Transacción de subida (sin firmar):"; echo "$WASM_HASH"; exit 0
  fi
  [ "$WASM_HASH" = "$HASH_LOCAL" ] || echo "Aviso: el hash devuelto ($WASM_HASH) no coincide con el local ($HASH_LOCAL)" >&2
  printf '{\n  "red": "%s",\n  "wasm_hash": "%s",\n  "subido": "%s"\n}\n' \
    "$RED" "$WASM_HASH" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$WASM_JSON"
fi

# 3. Instancia de la bodega
echo "Creando el contrato de $ALIAS en $RED…"
CONTRATO="$(stellar contract deploy --wasm-hash "$WASM_HASH" \
  --source-account "$FUENTE" --network "$RED" --alias "$ALIAS" "${EXTRA[@]}" \
  -- \
  --admin "$ADMIN" \
  --operator "$OPERADOR" \
  --name "$NOMBRE" \
  --symbol "$SIMBOLO" \
  --base_uri "$URI_BASE")"

if [ "$SOLO_CONSTRUIR" = 1 ]; then
  echo "Transacción de despliegue (sin firmar):"; echo "$CONTRATO"; exit 0
fi

printf '{\n  "red": "%s",\n  "alias": "%s",\n  "contrato": "%s",\n  "wasm_hash": "%s",\n  "admin": "%s",\n  "operador": "%s",\n  "nombre": "%s",\n  "simbolo": "%s",\n  "uri_base": "%s",\n  "desplegado": "%s"\n}\n' \
  "$RED" "$ALIAS" "$CONTRATO" "$WASM_HASH" "$ADMIN" "$OPERADOR" "$NOMBRE" "$SIMBOLO" "$URI_BASE" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "deployments/$RED/$ALIAS.json"

echo "Contrato de $ALIAS: $CONTRATO (deployments/$RED/$ALIAS.json)"
echo "Comprobación: stellar contract invoke --id $CONTRATO --network $RED --source-account $FUENTE --send=no -- name"
