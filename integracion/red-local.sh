#!/usr/bin/env bash
# Red local de Stellar para las pruebas de integración (O3-SC-1): un contenedor
# stellar/quickstart en modo --local con Core, RPC y Friendbot (sin Horizon),
# en el protocolo vigente de testnet. La red es efímera: al parar el contenedor
# se pierde todo.
#
#   integracion/red-local.sh arrancar   # arranca y espera al RPC y a Friendbot
#   integracion/red-local.sh parar
#
# Variables: PUERTO (8000), PROTOCOLO (29), IMAGEN, CONTENEDOR.
set -euo pipefail

# Etiqueta fija (canal «testing» = lo que corre testnet) y su resumen: una
# etiqueta móvil cambiaría el protocolo por sorpresa.
IMAGEN="${IMAGEN:-stellar/quickstart:v676-b1505.1-testing@sha256:66a19476f2ce2ed09c4dccf3f1af4d438209eee9ee05eb113a02dd926e2b03f5}"
PROTOCOLO="${PROTOCOLO:-29}"
PUERTO="${PUERTO:-8000}"
CONTENEDOR="${CONTENEDOR:-doc-red-local}"

rpc() {
  curl -fsS -m 5 -X POST "http://localhost:$PUERTO/rpc" -H 'content-type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$1\"}" 2>/dev/null
}

case "${1:-}" in
  arrancar)
    docker rm -f "$CONTENEDOR" >/dev/null 2>&1 || true
    inicio=$(date +%s)
    # La imagen trae el protocolo 28 por defecto aunque su Core admite el 29:
    # hay que pedirlo. `--enable core,rpc` evita Horizon, Lab y Galexie
    # (Friendbot arranca igual y no necesita Horizon).
    docker run -d --name "$CONTENEDOR" -p "$PUERTO:8000" "$IMAGEN" \
      --local --enable core,rpc --protocol-version "$PROTOCOLO" >/dev/null
    for _ in $(seq 1 120); do
      if rpc getHealth | grep -q '"healthy"'; then break; fi
      sleep 1
    done
    rpc getHealth | grep -q '"healthy"' || { echo "El RPC no arrancó" >&2; docker logs --tail 40 "$CONTENEDOR" >&2; exit 1; }
    echo "RPC listo en $(( $(date +%s) - inicio )) s"
    # Friendbot tarda algo más que el RPC (crea su cuenta al arrancar).
    for _ in $(seq 1 120); do
      codigo=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://localhost:$PUERTO/friendbot" || true)
      # Sin ?addr responde 400 cuando ya atiende; 502 mientras arranca.
      if [ "$codigo" = "400" ] || [ "$codigo" = "200" ]; then break; fi
      sleep 1
    done
    echo "Friendbot listo en $(( $(date +%s) - inicio )) s"
    rpc getNetwork; echo
    ;;
  parar)
    docker rm -f "$CONTENEDOR" >/dev/null 2>&1 || true
    ;;
  *)
    echo "Uso: $0 arrancar|parar" >&2
    exit 2
    ;;
esac
