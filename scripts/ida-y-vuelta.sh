#!/usr/bin/env bash
# Prueba de ida y vuelta en la red (paso B.3) sobre el contrato de una bodega
# ya desplegada (scripts/desplegar-bodega.sh):
#
#   1. mint_batch de un lote corto, firmado por la bodega (admin y minter)
#   2. operator_transfer de los primeros tokens a un consumidor de prueba,
#      firmado por la plataforma (operator)
#   3. lecturas: owner_of, balance, token_uri, total_minted
#   4. redeem_burn del primer token, firmado por la plataforma
#   5. eventos del contrato desde el ledger de inicio (Stellar RPC getEvents)
#   6. coste real de cada transacción (comisión cobrada y renta), leído de la
#      red con getTransaction
#
#   scripts/docker.sh scripts/ida-y-vuelta.sh --alias altos-de-calamuchita \
#     [--red testnet] [--cantidad 3] [--entregas 1] [--lote CODIGO] \
#     [--consumidor G…] [--informe dir]
#
# Deja en <informe>/ (por defecto informes/<red>-<fecha>/): costes.jsonl,
# eventos-<alias>.json e ida-y-vuelta-<alias>.md con los enlaces al
# explorador. Nunca escribe claves: firma con las identidades locales
# (testnet-bodega-<alias>, testnet-plataforma) o, en la CI, con las
# variables TESTNET_WINERY_<ALIAS>_SECRET y TESTNET_PLATFORM_SECRET.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/red.sh

RED_ARG=testnet
ALIAS=""
CANTIDAD=3
ENTREGAS=1
LOTE=""
CONSUMIDOR=""
INFORME="${INFORME:-}"

uso() { sed -n '2,23p' "$0"; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --red) RED_ARG="$2"; shift 2 ;;
    --alias) ALIAS="$2"; shift 2 ;;
    --cantidad) CANTIDAD="$2"; shift 2 ;;
    --entregas) ENTREGAS="$2"; shift 2 ;;
    --lote) LOTE="$2"; shift 2 ;;
    --consumidor) CONSUMIDOR="$2"; shift 2 ;;
    --informe) INFORME="$2"; shift 2 ;;
    -h|--help) uso ;;
    *) echo "Opción desconocida: $1" >&2; uso ;;
  esac
done

configurar_red "$RED_ARG"
[ -f "$DESPLIEGUES" ] || falla "No existe $DESPLIEGUES: despliega antes la bodega"
[ -n "$ALIAS" ] || { echo "Falta --alias" >&2; uso; }
[[ "$CANTIDAD" =~ ^[0-9]+$ ]] && [ "$CANTIDAD" -ge 1 ] && [ "$CANTIDAD" -le 32000 ] \
  || falla "--cantidad entre 1 y 32000"
[[ "$ENTREGAS" =~ ^[0-9]+$ ]] && [ "$ENTREGAS" -ge 1 ] && [ "$ENTREGAS" -le "$CANTIDAD" ] \
  || falla "--entregas entre 1 y --cantidad"

C="$(leer_despliegues --arg a "$ALIAS" '.wineries[$a].contract // empty')"
BODEGA="$(leer_despliegues --arg a "$ALIAS" '.wineries[$a].admin // empty')"
URI_BASE="$(leer_despliegues --arg a "$ALIAS" '.wineries[$a].base_uri // empty')"
PLATAFORMA="$(leer_despliegues '.accounts.platform_operator // empty')"
[ -n "$CONSUMIDOR" ] || CONSUMIDOR="$(leer_despliegues '.accounts.demo_consumer // empty')"
for v in C BODEGA URI_BASE PLATAFORMA CONSUMIDOR; do
  [ -n "${!v}" ] || falla "Falta $v en $DESPLIEGUES para $ALIAS"
done
export LECTOR="$PLATAFORMA"

FECHA="$(date -u +%Y%m%dT%H%M%SZ)"
SIMBOLO="$(leer_despliegues --arg a "$ALIAS" '.wineries[$a].symbol // "NFT"')"
[ -n "$LOTE" ] || LOTE="DEMO-$SIMBOLO-$FECHA"
INFORME="${INFORME:-informes/$RED-$FECHA}"
mkdir -p "$INFORME"
export INFORME
MD="$INFORME/ida-y-vuelta-$ALIAS.md"

fondear "$BODEGA"
fondear "$PLATAFORMA"

sin_comillas() { sed -e 's/^"//' -e 's/"$//'; }
enlace_tx() { echo "[\`${1:0:12}…\`]($EXPLORADOR/tx/$1)"; }
FILAS=()
fila() { # operación, tx, detalle
  local c
  c="$(coste_tx "$2")"
  jq -c --arg op "$1" --arg b "$ALIAS" --arg d "$3" '{operation: $op, winery: $b, detail: $d} + .' \
    <<<"$c" >> "$INFORME/costes.jsonl"
  FILAS+=("| \`$1\` | $3 | $(enlace_tx "$2") | $(jq -r .fee_charged <<<"$c") | $(jq -r .rent_fee <<<"$c") | $(xlm "$(jq -r .fee_charged <<<"$c")") |")
}

INICIO="$(ultimo_ledger)"
ANTES="$(leer "$C" total_minted)"
paso "Contrato $C ($ALIAS) · ledger $INICIO · total_minted=$ANTES"

# 1. Emisión
paso "mint_batch: $CANTIDAD tokens del lote $LOTE a la bodega"
enviar firmar_como "bodega:$ALIAS" stellar contract invoke --id "$C" --network "$RED" \
  -- mint_batch --to "$BODEGA" --amount "$CANTIDAD" --lot "$LOTE" --minter "$BODEGA"
ULTIMO="$SALIDA"; TX_MINT="$TX"
PRIMERO=$((ULTIMO - CANTIDAD + 1))
[ "$PRIMERO" = "$ANTES" ] || falla "Primer id $PRIMERO, se esperaba $ANTES"
echo "Tokens $PRIMERO..$ULTIMO · $EXPLORADOR/tx/$TX_MINT"
fila mint_batch "$TX_MINT" "$CANTIDAD tokens, lote \`$LOTE\`"

# 2. Entregas
for i in $(seq 0 $((ENTREGAS - 1))); do
  ID=$((PRIMERO + i))
  paso "operator_transfer del token $ID a $CONSUMIDOR"
  enviar firmar_como plataforma stellar contract invoke --id "$C" --network "$RED" \
    -- operator_transfer --from "$BODEGA" --to "$CONSUMIDOR" --token_id "$ID" --operator "$PLATAFORMA"
  echo "$EXPLORADOR/tx/$TX"
  if [ "$i" = 0 ]; then fila operator_transfer "$TX" "token $ID (primera venta del lote)"
  else fila operator_transfer "$TX" "token $ID"; fi
  DUENO="$(leer "$C" owner_of --token_id "$ID" | sin_comillas)"
  [ "$DUENO" = "$CONSUMIDOR" ] || falla "owner_of($ID) = $DUENO"
done

# 3. Lecturas
paso "Lecturas"
URI="$(leer "$C" token_uri --token_id "$PRIMERO" | sin_comillas)"
[ "$URI" = "$URI_BASE$PRIMERO" ] || falla "token_uri($PRIMERO) = $URI (se esperaba $URI_BASE$PRIMERO)"
SALDO_C="$(leer "$C" balance --account "$CONSUMIDOR")"
[ "$SALDO_C" -ge "$ENTREGAS" ] || falla "balance(consumidor) = $SALDO_C"
TOTAL="$(leer "$C" total_minted)"
[ "$TOTAL" = "$((ANTES + CANTIDAD))" ] || falla "total_minted = $TOTAL"
echo "token_uri($PRIMERO) = $URI"
echo "balance(consumidor) = $SALDO_C · total_minted = $TOTAL"

# 4. Canje
paso "redeem_burn del token $PRIMERO"
enviar firmar_como plataforma stellar contract invoke --id "$C" --network "$RED" \
  -- redeem_burn --token_id "$PRIMERO" --operator "$PLATAFORMA"
TX_BURN="$TX"
echo "$EXPLORADOR/tx/$TX_BURN"
fila redeem_burn "$TX_BURN" "token $PRIMERO"
if leer "$C" owner_of --token_id "$PRIMERO" >/dev/null; then
  falla "owner_of($PRIMERO) debería fallar tras la quema"
fi
SALDO_C2="$(leer "$C" balance --account "$CONSUMIDOR")"
[ "$SALDO_C2" = "$((SALDO_C - 1))" ] || falla "balance(consumidor) tras la quema = $SALDO_C2"
echo "owner_of($PRIMERO) falla (quemado) · balance(consumidor) = $SALDO_C2"

# 5. Eventos
paso "Eventos desde el ledger $INICIO"
EVENTOS="$INFORME/eventos-$ALIAS.json"
for intento in 1 2 3 4 5; do
  stellar events --network "$RED" --start-ledger "$INICIO" --id "$C" --output json --count 200 \
    2>/dev/null | jq -s '.' > "$EVENTOS" || true
  NOMBRES="$(jq -r '[.[] | .prefix_topics[0] // empty] | join(" ")' "$EVENTOS" 2>/dev/null || true)"
  [[ "$NOMBRES" == *burn* ]] && break
  sleep 3
done
echo "${NOMBRES:-sin eventos}"
for e in consecutive_mint lot_minted transfer burn; do
  [[ " $NOMBRES " == *" $e "* ]] || aviso "No se encontró el evento $e (revisar $EVENTOS)"
done

# 6. Informe
{
  echo "# Ida y vuelta en $RED · $ALIAS"
  echo
  echo "- Fecha: $(ahora) · ledger inicial $INICIO"
  echo "- Contrato: [\`$C\`]($EXPLORADOR/contract/$C)"
  echo "- Bodega (admin y minter): [\`$BODEGA\`]($EXPLORADOR/account/$BODEGA)"
  echo "- Plataforma (operator): [\`$PLATAFORMA\`]($EXPLORADOR/account/$PLATAFORMA)"
  echo "- Consumidor de prueba (sin fondear): \`$CONSUMIDOR\`"
  echo "- Lote \`$LOTE\`: tokens $PRIMERO..$ULTIMO; entregados $PRIMERO..$((PRIMERO + ENTREGAS - 1)); quemado $PRIMERO"
  echo "- \`token_uri($PRIMERO)\` = \`$URI\` · \`total_minted\` = $TOTAL · \`balance(consumidor)\` = $SALDO_C2"
  echo "- Eventos: $NOMBRES"
  echo
  echo "| Operación | Detalle | Transacción | Comisión cobrada (stroops) | De ella, renta | XLM |"
  echo "|---|---|---|---|---|---|"
  printf '%s\n' "${FILAS[@]}"
  echo
  echo "Eventos del contrato (\`stellar events\`, decodificados con la interfaz del contrato):"
  echo
  echo "| Ledger | Evento | Parámetros |"
  echo "|---|---|---|"
  jq -r '.[] | "| \(.ledger) | `\(.prefix_topics[0])` | `\(.params | tojson)` |"' "$EVENTOS"
} > "$MD"

paso "Resultado"
cat "$MD"
