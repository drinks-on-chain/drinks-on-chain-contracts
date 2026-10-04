#!/usr/bin/env bash
# Despliegue del contrato NFT de una bodega (paso B.3). Idempotente.
#
#   scripts/docker.sh scripts/desplegar-bodega.sh \
#     --alias altos-de-calamuchita \
#     --nombre "Bodega Altos de Calamuchita" --simbolo ALTOS \
#     --uri-base "https://api.drinks-on-chain.test/v1/public/nft/altos-de-calamuchita/" \
#     [--red testnet] [--admin G…] [--operador G…] [--nueva-version] [--informe dir]
#
#   --alias      slug de la bodega en la plataforma; nombra el registro en
#                deployments/<red>.json y la identidad testnet-bodega-<alias>
#   --admin      cuenta de la bodega (admin y minter). Por defecto, la
#                registrada en accounts.winery_admins.<alias>
#   --operador   cuenta de operaciones de la plataforma (rol operator). Por
#                defecto, accounts.platform_operator
#   --nueva-version  despliega un contrato nuevo aunque la bodega ya tenga
#                uno de una versión anterior del código (el contrato no es
#                actualizable, DS-11)
#   --informe    carpeta donde se añaden los costes medidos (costes.jsonl)
#
# Qué hace:
#   1. Construye el WASM optimizado si no existe (dist/winery_nft.wasm).
#   2. Sube el código si la red no lo tiene (stellar-cli lo omite si ya está)
#      y registra su hash en deployments/<red>.json (.wasm).
#   3. Si la bodega ya tiene contrato en la red con el mismo código, solo lo
#      comprueba. Si no, lo crea con una sal determinista
#      (sha256("drinks-on-chain/winery-nft/<alias>/<hash del WASM>")): la
#      dirección depende solo de la cuenta de despliegue, la bodega y el
#      código, así que repetir el script (o repetirlo tras un reinicio de
#      testnet) da la misma dirección y nunca crea un segundo contrato.
#   4. Comprueba nombre, símbolo, admin y rol del operador, y registra el
#      contrato en deployments/<red>.json (.wineries.<alias>).
#
# Firma la cuenta de despliegue: identidad local testnet-despliegue o, en la
# CI, la variable TESTNET_DEPLOYER_SECRET (nunca como argumento).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/red.sh

RED_ARG=testnet
ALIAS=""
ADMIN=""
OPERADOR=""
NOMBRE=""
SIMBOLO=""
URI_BASE=""
NUEVA_VERSION=0
INFORME="${INFORME:-}"
WASM=dist/winery_nft.wasm

uso() { sed -n '2,37p' "$0"; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --red) RED_ARG="$2"; shift 2 ;;
    --alias) ALIAS="$2"; shift 2 ;;
    --admin) ADMIN="$2"; shift 2 ;;
    --operador) OPERADOR="$2"; shift 2 ;;
    --nombre) NOMBRE="$2"; shift 2 ;;
    --simbolo) SIMBOLO="$2"; shift 2 ;;
    --uri-base) URI_BASE="$2"; shift 2 ;;
    --nueva-version) NUEVA_VERSION=1; shift ;;
    --informe) INFORME="$2"; shift 2 ;;
    -h|--help) uso ;;
    *) echo "Opción desconocida: $1" >&2; uso ;;
  esac
done

configurar_red "$RED_ARG"
iniciar_despliegues

[ -n "$ALIAS" ] || { echo "Falta --alias" >&2; uso; }
[[ "$ALIAS" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || falla "--alias debe ser un slug (minúsculas, cifras y guiones)"
[ -n "$ADMIN" ] || ADMIN="$(leer_despliegues --arg a "$ALIAS" '.accounts.winery_admins[$a] // empty')"
[ -n "$OPERADOR" ] || OPERADOR="$(leer_despliegues '.accounts.platform_operator // empty')"
DESPLIEGUE="$(leer_despliegues '.accounts.deployer // empty')"
for v in ADMIN OPERADOR NOMBRE SIMBOLO URI_BASE DESPLIEGUE; do
  [ -n "${!v}" ] || falla "Falta $v (argumento o deployments/$RED.json; ver scripts/cuentas-testnet.sh)"
done
[ "$ADMIN" != "$OPERADOR" ] || falla "La bodega y el operador deben ser cuentas distintas"
export LECTOR="$DESPLIEGUE"

fondear "$DESPLIEGUE"

# 1. WASM
if [ ! -f "$WASM" ]; then
  paso "Construyendo el WASM"
  stellar contract build --package winery-nft --locked --out-dir dist
fi
WASM_HASH="$(sha256sum "$WASM" | cut -d' ' -f1)"
WASM_BYTES="$(stat -c %s "$WASM")"

# 2. Código
paso "Código winery-nft $WASM_HASH ($WASM_BYTES bytes)"
# Subir es idempotente (stellar-cli omite el envío si la red ya tiene el
# código): se reintenta ante errores transitorios del RPC.
reintentar 3 enviar firmar_como despliegue stellar contract upload --wasm "$WASM" --network "$RED"
[ "$SALIDA" = "$WASM_HASH" ] || falla "La red devolvió el hash $SALIDA y el WASM local es $WASM_HASH"
if [ -n "$TX" ]; then
  echo "Subido: $EXPLORADOR/tx/$TX"
  registrar_coste upload "" "$TX" "$WASM_BYTES bytes"
  actualizar_despliegues '.wasm = {hash: $h, size_bytes: ($b | tonumber), uploaded_at: $t, upload_tx: $tx}' \
    --arg h "$WASM_HASH" --arg b "$WASM_BYTES" --arg t "$(ahora)" --arg tx "$TX"
else
  echo "La red ya tiene este código."
  if [ "$(leer_despliegues '.wasm.hash // empty')" != "$WASM_HASH" ]; then
    actualizar_despliegues '.wasm = {hash: $h, size_bytes: ($b | tonumber), uploaded_at: null, upload_tx: null}' \
      --arg h "$WASM_HASH" --arg b "$WASM_BYTES"
  fi
fi

# 3. Contrato de la bodega
existe() { leer "$1" name >/dev/null; }

REGISTRO_C="$(leer_despliegues --arg a "$ALIAS" '.wineries[$a].contract // empty')"
REGISTRO_H="$(leer_despliegues --arg a "$ALIAS" '.wineries[$a].wasm_hash // empty')"
if [ -n "$REGISTRO_C" ] && [ "$REGISTRO_H" != "$WASM_HASH" ] && [ "$NUEVA_VERSION" = 0 ] && existe "$REGISTRO_C"; then
  aviso "$ALIAS ya tiene el contrato $REGISTRO_C con el código $REGISTRO_H."
  aviso "El contrato no es actualizable: para crear uno con el código actual, repite con --nueva-version."
  exit 0
fi

SAL="$(printf 'drinks-on-chain/winery-nft/%s/%s' "$ALIAS" "$WASM_HASH" | sha256sum | cut -d' ' -f1)"
CONTRATO="$(stellar contract id wasm --salt "$SAL" --source-account "$DESPLIEGUE" --network "$RED")"
paso "Contrato de $ALIAS: $CONTRATO"

DEPLOY_TX=""
if existe "$CONTRATO"; then
  echo "Ya existe en $RED; se comprueba sin desplegar."
else
  echo "Creando el contrato…"
  enviar firmar_como despliegue stellar contract deploy --wasm-hash "$WASM_HASH" --salt "$SAL" \
    --network "$RED" \
    -- \
    --admin "$ADMIN" \
    --operator "$OPERADOR" \
    --name "$NOMBRE" \
    --symbol "$SIMBOLO" \
    --base_uri "$URI_BASE"
  [ "$SALIDA" = "$CONTRATO" ] || falla "Dirección inesperada: $SALIDA (se esperaba $CONTRATO)"
  DEPLOY_TX="$TX"
  echo "Creado: $EXPLORADOR/tx/$DEPLOY_TX"
  registrar_coste deploy "$ALIAS" "$DEPLOY_TX"
fi

# 4. Comprobaciones
paso "Comprobando $CONTRATO"
sin_comillas() { sed -e 's/^"//' -e 's/"$//'; }
N="$(leer "$CONTRATO" name | sin_comillas)"
S="$(leer "$CONTRATO" symbol | sin_comillas)"
A="$(leer "$CONTRATO" get_admin | sin_comillas)"
R="$(leer "$CONTRATO" has_role --account "$OPERADOR" --role operator)"
M="$(leer "$CONTRATO" has_role --account "$ADMIN" --role minter)"
[ "$N" = "$NOMBRE" ] || falla "name = $N (se esperaba $NOMBRE)"
[ "$S" = "$SIMBOLO" ] || falla "symbol = $S (se esperaba $SIMBOLO)"
[ "$A" = "$ADMIN" ] || falla "admin = $A (se esperaba $ADMIN)"
[ "$R" != "null" ] || falla "$OPERADOR no tiene el rol operator"
[ "$M" != "null" ] || falla "$ADMIN no tiene el rol minter"
echo "name=$N · symbol=$S · admin=$A · operator ✓ · minter ✓"

ANTERIOR_TX="$(leer_despliegues --arg a "$ALIAS" --arg c "$CONTRATO" \
  'if .wineries[$a].contract == $c then .wineries[$a].deploy_tx // "" else "" end')"
ANTERIOR_T="$(leer_despliegues --arg a "$ALIAS" --arg c "$CONTRATO" \
  'if .wineries[$a].contract == $c then .wineries[$a].deployed_at // "" else "" end')"
actualizar_despliegues '.wineries[$a] = {
    contract: $c, explorer: "\(.explorer)/contract/\($c)",
    admin: $admin, operator: $op, name: $n, symbol: $s, base_uri: $u,
    wasm_hash: $h, salt: $sal,
    deploy_tx: (if $tx == "" then null else $tx end),
    deployed_at: (if $t == "" then null else $t end)
  }' \
  --arg a "$ALIAS" --arg c "$CONTRATO" --arg admin "$ADMIN" --arg op "$OPERADOR" \
  --arg n "$NOMBRE" --arg s "$SIMBOLO" --arg u "$URI_BASE" --arg h "$WASM_HASH" --arg sal "$SAL" \
  --arg tx "${DEPLOY_TX:-$ANTERIOR_TX}" --arg t "$([ -n "$DEPLOY_TX" ] && ahora || echo "$ANTERIOR_T")"

echo
echo "Contrato de $ALIAS: $CONTRATO"
echo "Explorador: $EXPLORADOR/contract/$CONTRATO"
echo "Registrado en $DESPLIEGUES"
