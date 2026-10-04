# shellcheck shell=bash
# Funciones comunes de los scripts de red (testnet). Se cargan con
#   source "$(dirname "$0")/lib/red.sh"
#
# Ninguna función recibe, imprime ni escribe claves secretas: las cuentas se
# nombran por su identidad de `stellar keys` y las transacciones las firma
# stellar-cli con la clave guardada en su configuración (~/.config/stellar).

set -euo pipefail

paso() { echo; echo "── $*" >&2; }
aviso() { echo "Aviso: $*" >&2; }
falla() { echo "Error: $*" >&2; exit 1; }

# Parámetros de la red. Solo testnet (y local/futurenet para pruebas); mainnet
# queda cerrada hasta la revisión externa (B.4).
configurar_red() {
  RED="$1"
  case "$RED" in
    testnet)
      RPC_URL="${STELLAR_RPC_URL:-https://soroban-testnet.stellar.org}"
      PASSPHRASE="Test SDF Network ; September 2015"
      EXPLORADOR="https://stellar.expert/explorer/testnet" ;;
    futurenet)
      RPC_URL="${STELLAR_RPC_URL:-https://rpc-futurenet.stellar.org}"
      PASSPHRASE="Test SDF Future Network ; October 2022"
      EXPLORADOR="https://stellar.expert/explorer/futurenet" ;;
    mainnet)
      [ "${CONFIRMO_MAINNET:-}" = "si" ] \
        || falla "mainnet requiere la revisión externa (B.4) y CONFIRMO_MAINNET=si"
      RPC_URL="${STELLAR_RPC_URL:?Falta STELLAR_RPC_URL para mainnet}"
      PASSPHRASE="Public Global Stellar Network ; September 2015"
      EXPLORADOR="https://stellar.expert/explorer/public" ;;
    *) falla "Red no soportada: $RED" ;;
  esac
  DESPLIEGUES="deployments/$RED.json"
  export RED RPC_URL PASSPHRASE EXPLORADOR DESPLIEGUES
}

# Crea deployments/<red>.json si no existe.
iniciar_despliegues() {
  mkdir -p deployments
  [ -f "$DESPLIEGUES" ] && return 0
  jq -n --arg red "$RED" --arg pp "$PASSPHRASE" --arg rpc "$RPC_URL" --arg exp "$EXPLORADOR" \
    '{network: $red, network_passphrase: $pp, rpc_url: $rpc, explorer: $exp,
      wasm: null, accounts: {}, wineries: {}}' > "$DESPLIEGUES"
}

# Aplica un filtro jq a deployments/<red>.json (escritura atómica).
# Uso: actualizar_despliegues '<filtro>' [--arg …]
actualizar_despliegues() {
  local filtro="$1"; shift
  local tmp
  tmp="$(mktemp)"
  jq "$@" "$filtro" "$DESPLIEGUES" > "$tmp"
  mv "$tmp" "$DESPLIEGUES"
}

leer_despliegues() { jq -r "$@" "$DESPLIEGUES"; }

direccion() { stellar keys address "$1"; }

ahora() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Llamada JSON-RPC al Stellar RPC.
rpc() {
  local metodo="$1" params="$2"
  curl -fsS --retry 3 --retry-delay 2 "$RPC_URL" -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$metodo\",\"params\":$params}"
}

ultimo_ledger() { rpc getLatestLedger '{}' | jq -r '.result.sequence'; }

# Coste real de una transacción ya confirmada, en stroops, leído de la red
# (getTransaction con xdrFormat=json). Imprime un objeto JSON.
coste_tx() {
  local hash="$1" intento r estado
  for intento in 1 2 3 4 5 6 7 8 9 10; do
    r="$(rpc getTransaction "{\"hash\":\"$hash\",\"xdrFormat\":\"json\"}")"
    estado="$(jq -r '.result.status' <<<"$r")"
    [ "$estado" = "SUCCESS" ] && break
    [ "$estado" = "FAILED" ] && falla "La transacción $hash falló en la red"
    sleep 2
  done
  [ "$estado" = "SUCCESS" ] || falla "No se encontró la transacción $hash en el RPC"
  jq --arg hash "$hash" --arg exp "$EXPLORADOR" '
    .result as $t
    | ($t.resultMetaJson | (.v4 // .v3).soroban_meta.ext.v1) as $m
    | ($t.envelopeJson.tx.tx.ext.v1.resources // {}) as $res
    | {
        tx: $hash,
        explorer: "\($exp)/tx/\($hash)",
        ledger: $t.ledger,
        fee_charged: ($t.resultJson.fee_charged | tonumber),
        resource_fee_non_refundable: ($m.total_non_refundable_resource_fee_charged | tonumber),
        resource_fee_refundable: ($m.total_refundable_resource_fee_charged | tonumber),
        rent_fee: ($m.rent_fee_charged | tonumber),
        inclusion_fee: (($t.resultJson.fee_charged | tonumber)
          - ($m.total_non_refundable_resource_fee_charged | tonumber)
          - ($m.total_refundable_resource_fee_charged | tonumber)),
        instructions: $res.instructions,
        disk_read_bytes: $res.disk_read_bytes,
        write_bytes: $res.write_bytes
      }' <<<"$r"
}

# Ejecuta un comando de stellar-cli que envía una transacción. Deja en
# $SALIDA lo que imprime el comando (valor devuelto) y en $TX el hash de la
# transacción, o vacío si no se envió nada (p. ej. código ya subido).
enviar() {
  local err
  err="$(mktemp)"
  if ! SALIDA="$("$@" 2>"$err")"; then
    cat "$err" >&2; rm -f "$err"
    echo "Error: falló ${*:1:4}…" >&2
    return 1
  fi
  TX="$(grep -oE 'explorer/[a-z]+/tx/[0-9a-f]{64}' "$err" | tail -1 | grep -oE '[0-9a-f]{64}$' || true)"
  if [ -z "$TX" ]; then
    TX="$(grep -oE 'Signing transaction: [0-9a-f]{64}' "$err" | tail -1 | grep -oE '[0-9a-f]{64}$' || true)"
  fi
  rm -f "$err"
  export SALIDA TX
}

# reintentar <n> <comando…>: solo para operaciones idempotentes.
reintentar() {
  local n="$1" i; shift
  for i in $(seq 1 "$n"); do
    if "$@"; then return 0; fi
    [ "$i" = "$n" ] || { aviso "reintento $i de $((n - 1))…"; sleep 5; }
  done
  return 1
}

# Lectura sin enviar (simulación) de una función del contrato. Imprime el
# valor devuelto. La cuenta de origen de la simulación es una dirección
# pública (no firma nada): LECTOR, por defecto la de despliegue.
# Uso: leer <contrato> <función> [--arg valor]…
leer() {
  local c="$1"; shift
  STELLAR_ACCOUNT="${LECTOR:?Falta LECTOR}" \
    stellar contract invoke --network "$RED" --send=no --id "$c" -- "$@" 2>/dev/null
}

# Registra el coste de una transacción en <informe>/costes.jsonl.
# Uso: registrar_coste <operación> <bodega> <tx> [detalle]
registrar_coste() {
  local op="$1" bodega="$2" tx="$3" detalle="${4:-}"
  [ -n "${INFORME:-}" ] || return 0
  [ -n "$tx" ] || return 0
  mkdir -p "$INFORME"
  coste_tx "$tx" | jq -c --arg op "$op" --arg b "$bodega" --arg d "$detalle" \
    '{operation: $op, winery: $b, detail: $d} + .' >> "$INFORME/costes.jsonl"
}

xlm() { awk -v s="$1" 'BEGIN { printf "%.7f", s / 10000000 }'; }

# ── Cuentas ──────────────────────────────────────────────────────────────
# Cada papel tiene una identidad local de `stellar keys` (máquina del
# desarrollador) y una variable de entorno con su clave (CI, desde los
# secretos del repo). stellar-cli lee la cuenta de STELLAR_ACCOUNT, que admite
# tanto un nombre de identidad como una clave: la clave nunca va en la línea
# de comandos ni en un archivo.
#
#   despliegue       testnet-despliegue            TESTNET_DEPLOYER_SECRET
#   plataforma       testnet-plataforma            TESTNET_PLATFORM_SECRET
#   bodega:<alias>   testnet-bodega-<alias>        TESTNET_WINERY_<ALIAS>_SECRET
#                    (alias en mayúsculas, guiones como _)

identidad_de() {
  case "$1" in
    despliegue) echo "$RED-despliegue" ;;
    plataforma) echo "$RED-plataforma" ;;
    bodega:*) echo "$RED-bodega-${1#bodega:}" ;;
    *) falla "Papel desconocido: $1" ;;
  esac
}

variable_de() {
  local r
  r="$(echo "$RED" | tr 'a-z' 'A-Z')"
  case "$1" in
    despliegue) echo "${r}_DEPLOYER_SECRET" ;;
    plataforma) echo "${r}_PLATFORM_SECRET" ;;
    bodega:*) echo "${r}_WINERY_$(echo "${1#bodega:}" | tr 'a-z-' 'A-Z_')_SECRET" ;;
  esac
}

# firmar_como <papel> <comando…>: ejecuta el comando con la cuenta del papel
# como origen y firmante de la transacción.
firmar_como() {
  local papel="$1"; shift
  local var
  var="$(variable_de "$papel")"
  if [ -n "${!var:-}" ]; then
    STELLAR_ACCOUNT="${!var}" "$@"
  else
    STELLAR_ACCOUNT="$(identidad_de "$papel")" "$@"
  fi
}

# Fondea una cuenta con Friendbot si no existe en la red (solo testnet).
# Solo necesita la dirección pública.
fondear() {
  local g="$1"
  [ "$RED" = testnet ] || return 0
  if rpc getLedgerEntries "{\"keys\":[\"$(clave_cuenta "$g")\"]}" \
      | jq -e '.result.entries | length > 0' >/dev/null; then
    return 0
  fi
  echo "Fondeando $g con Friendbot…" >&2
  curl -fsS --retry 3 "https://friendbot.stellar.org/?addr=$g" >/dev/null
}

# LedgerKey (XDR base64) de una cuenta.
clave_cuenta() {
  stellar xdr encode --type LedgerKey --input json --output single-base64 \
    <<<"{\"account\":{\"account_id\":\"$1\"}}"
}
