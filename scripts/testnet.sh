#!/usr/bin/env bash
# Despliegue + ida y vuelta de las bodegas registradas en
# deployments/testnet.json (lo que ejecuta el workflow "Testnet").
#
#   scripts/docker.sh scripts/testnet.sh [--bodegas "a b"] [--cantidad 3] \
#     [--entregas 1] [--informe dir]
#
# 1. Fondea con Friendbot las cuentas registradas que no existan en la red
#    (tras un reinicio de testnet).
# 2. Ejecuta scripts/desplegar-bodega.sh para cada bodega con su nombre,
#    símbolo y URI registrados: si el contrato existe, solo lo comprueba; si
#    testnet se reinició, lo vuelve a crear en la misma dirección.
# 3. Ejecuta scripts/ida-y-vuelta.sh para cada bodega.
# 4. Escribe <informe>/README.md con los contratos, los enlaces al explorador
#    y los costes medidos. El informe no contiene claves.
#
# En la CI las claves llegan por variables de entorno (secretos del repo):
# TESTNET_DEPLOYER_SECRET, TESTNET_PLATFORM_SECRET y
# TESTNET_WINERY_<ALIAS>_SECRET por bodega. En local, las identidades de
# `stellar keys` (scripts/cuentas-testnet.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/red.sh

BODEGAS=""
CANTIDAD=3
ENTREGAS=1
INFORME="${INFORME:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --bodegas) BODEGAS="$2"; shift 2 ;;
    --cantidad) CANTIDAD="$2"; shift 2 ;;
    --entregas) ENTREGAS="$2"; shift 2 ;;
    --informe) INFORME="$2"; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) falla "Opción desconocida: $1" ;;
  esac
done

configurar_red testnet
[ -f "$DESPLIEGUES" ] || falla "No existe $DESPLIEGUES"
[ -n "$BODEGAS" ] || BODEGAS="$(leer_despliegues '.wineries | keys | join(" ")')"
[ -n "$BODEGAS" ] || falla "No hay bodegas registradas en $DESPLIEGUES"
INFORME="${INFORME:-informes/testnet-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$INFORME"
export INFORME

# En la CI, comprobar que están los secretos (solo sus nombres).
if [ "${GITHUB_ACTIONS:-}" = true ]; then
  FALTAN=()
  for papel in despliegue plataforma $(for b in $BODEGAS; do echo "bodega:$b"; done); do
    v="$(variable_de "$papel")"
    [ -n "${!v:-}" ] || FALTAN+=("$v")
  done
  [ ${#FALTAN[@]} = 0 ] || falla "Faltan los secretos del repo: ${FALTAN[*]}"
fi

paso "Cuentas"
for g in $(leer_despliegues '[.accounts.deployer, .accounts.platform_operator, (.accounts.winery_admins // {} | .[])] | .[] | select(. != null)'); do
  fondear "$g"
done
echo "Cuentas registradas presentes en $RED."

for b in $BODEGAS; do
  scripts/desplegar-bodega.sh --alias "$b" \
    --nombre "$(leer_despliegues --arg a "$b" '.wineries[$a].name')" \
    --simbolo "$(leer_despliegues --arg a "$b" '.wineries[$a].symbol')" \
    --uri-base "$(leer_despliegues --arg a "$b" '.wineries[$a].base_uri')"
done

for b in $BODEGAS; do
  scripts/ida-y-vuelta.sh --alias "$b" --cantidad "$CANTIDAD" --entregas "$ENTREGAS"
done

paso "Informe"
{
  echo "# Testnet · despliegue e ida y vuelta"
  echo
  echo "- Fecha: $(ahora)"
  echo "- Commit: \`$(git -c safe.directory="$PWD" rev-parse --short HEAD 2>/dev/null || echo desconocido)\`"
  echo "- Código: \`$(leer_despliegues '.wasm.hash')\` ($(leer_despliegues '.wasm.size_bytes') bytes)"
  echo
  echo "| Bodega | Contrato | Admin (bodega) | Operador (plataforma) |"
  echo "|---|---|---|---|"
  for b in $BODEGAS; do
    leer_despliegues --arg a "$b" '.wineries[$a] as $w
      | "| \($a) | [`\($w.contract)`](\($w.explorer)) | `\($w.admin)` | `\($w.operator)` |"'
  done
  if [ -s "$INFORME/costes.jsonl" ] && jq -e -s 'map(select(.operation == "upload" or .operation == "deploy")) | length > 0' "$INFORME/costes.jsonl" >/dev/null; then
    echo
    echo "Código subido o contratos creados en esta ejecución:"
    echo
    echo "| Operación | Bodega | Transacción | Comisión (stroops) | Renta |"
    echo "|---|---|---|---|---|"
    jq -r 'select(.operation == "upload" or .operation == "deploy")
      | "| `\(.operation)` | \(.winery) | [`\(.tx[0:12])…`](\(.explorer)) | \(.fee_charged) | \(.rent_fee) |"' \
      "$INFORME/costes.jsonl"
  fi
  for b in $BODEGAS; do
    echo
    sed '1s/^# /## /' "$INFORME/ida-y-vuelta-$b.md"
  done
} > "$INFORME/README.md"
cp "$DESPLIEGUES" "$INFORME/"
echo "Informe en $INFORME/README.md"
