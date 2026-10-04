#!/usr/bin/env bash
# Cuentas de testnet (paso B.3): despliegue, operaciones de la plataforma y
# una por bodega de demostración, más la dirección de un consumidor de prueba.
#
#   scripts/docker.sh scripts/cuentas-testnet.sh [--bodega <alias>]…
#
# - Genera cada identidad en la configuración local de `stellar keys` (en
#   Docker, el volumen doc-contracts-stellar) si no existe, y la fondea con
#   Friendbot. Nunca escribe claves en el repo ni las imprime.
# - El consumidor de prueba es una dirección G… sin fondear que nunca firma
#   (A-28): se genera, se guarda su dirección y se descarta su clave.
# - Registra las direcciones públicas en deployments/testnet.json.
#
# Por defecto, las bodegas de demostración altos-de-calamuchita y
# destileria-cinti-viejo (los slugs de la plataforma).
#
# Para la CI, cada clave se copia a un secreto del repo desde la máquina
# local, sin imprimirla (ver docs/testnet.md):
#   scripts/docker.sh stellar keys show testnet-plataforma \
#     | gh secret set TESTNET_PLATFORM_SECRET --repo drinks-on-chain/drinks-on-chain-contracts
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/red.sh

BODEGAS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --bodega) BODEGAS+=("$2"); shift 2 ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) falla "Opción desconocida: $1" ;;
  esac
done
[ ${#BODEGAS[@]} -gt 0 ] || BODEGAS=(altos-de-calamuchita destileria-cinti-viejo)

configurar_red testnet
iniciar_despliegues

asegurar_identidad() {
  local id="$1"
  if ! stellar keys address "$id" >/dev/null 2>&1; then
    echo "Generando la identidad $id…" >&2
    stellar keys generate "$id" --network "$RED" >/dev/null 2>&1
  fi
  fondear "$(direccion "$id")"
  direccion "$id"
}

paso "Cuenta de despliegue"
DESPLIEGUE="$(asegurar_identidad "$(identidad_de despliegue)")"
actualizar_despliegues '.accounts.deployer = $g' --arg g "$DESPLIEGUE"
echo "$DESPLIEGUE"

paso "Cuenta de operaciones de la plataforma (rol operator)"
PLATAFORMA="$(asegurar_identidad "$(identidad_de plataforma)")"
actualizar_despliegues '.accounts.platform_operator = $g' --arg g "$PLATAFORMA"
echo "$PLATAFORMA"

for alias in "${BODEGAS[@]}"; do
  paso "Cuenta de la bodega $alias (admin y minter)"
  G="$(asegurar_identidad "$(identidad_de "bodega:$alias")")"
  actualizar_despliegues '.accounts.winery_admins[$a] = $g' --arg a "$alias" --arg g "$G"
  echo "$G"
done

paso "Dirección del consumidor de prueba (sin fondear, sin clave)"
CONSUMIDOR="$(leer_despliegues '.accounts.demo_consumer // empty')"
if [ -z "$CONSUMIDOR" ]; then
  # Configuración temporal y desechable: la clave no llega a la local.
  TMP_CFG="$(mktemp -d)"
  stellar --config-dir "$TMP_CFG" keys generate consumidor >/dev/null 2>&1
  CONSUMIDOR="$(stellar --config-dir "$TMP_CFG" keys address consumidor)"
  rm -rf "$TMP_CFG"
  actualizar_despliegues '.accounts.demo_consumer = $g' --arg g "$CONSUMIDOR"
fi
echo "$CONSUMIDOR"

paso "Registrado en $DESPLIEGUES"
jq '.accounts' "$DESPLIEGUES"
