# Testnet

> Versión 1 · 27-09-2026 · Tarea O2-SC-1 (paso B.3). Qué hay desplegado en testnet, cómo desplegar el contrato de una bodega nueva, cómo verificarlo y qué necesita el backend (Ola 3). Costes medidos en [costes.md](costes.md).

## 1. Qué hay desplegado

Fuente de verdad: [`deployments/testnet.json`](../deployments/testnet.json) (direcciones públicas, hash del código, transacciones). Resumen al 27-09-2026:

| Qué | Dirección | Explorador |
|---|---|---|
| Código `winery-nft` (29 188 bytes) | hash `eb9f75b2a17117cab0c44d318ffd2f0f7642c488f56b31167998795ce22089d8` | [subida](https://stellar.expert/explorer/testnet/tx/07c02acca56eea7aeb870234280709c409f3db60f6dd527ecba74be14aa8a96a) |
| Contrato **Bodega Altos de Calamuchita** (`ALTOS`) | `CDUUCPA5JQVDP6EEI3CWT5MS4SGEPD2WS2SN6XSZCGPATTJSO2SZQS6M` | [contrato](https://stellar.expert/explorer/testnet/contract/CDUUCPA5JQVDP6EEI3CWT5MS4SGEPD2WS2SN6XSZCGPATTJSO2SZQS6M) |
| Contrato **Destilería Cinti Viejo** (`CINTI`) | `CC5M35BGIVRDZ5HEXMORAFO2D6RGOARJ7MLOGU56JCX5J5C66HFJKDFF` | [contrato](https://stellar.expert/explorer/testnet/contract/CC5M35BGIVRDZ5HEXMORAFO2D6RGOARJ7MLOGU56JCX5J5C66HFJKDFF) |
| Cuenta de despliegue (paga la subida y la creación de contratos) | `GDW3Y44FGL26ZGUKNICDFSPNLKO375WI6HT742XTPHKZQ7NIAL62OI6E` | [cuenta](https://stellar.expert/explorer/testnet/account/GDW3Y44FGL26ZGUKNICDFSPNLKO375WI6HT742XTPHKZQ7NIAL62OI6E) |
| Cuenta de operaciones de la plataforma (rol `operator` en los dos contratos) | `GDN3CAF7KKD72Q5EPDYKBK2MCCANJWQ344OZKSL6GAYULDCOPMQZ4SB6` | [cuenta](https://stellar.expert/explorer/testnet/account/GDN3CAF7KKD72Q5EPDYKBK2MCCANJWQ344OZKSL6GAYULDCOPMQZ4SB6) |
| Cuenta de Altos de Calamuchita (admin y `minter`) | `GADMLY63WAUFDTW3IVCWNFYSYUOGJMN6UL7AALJMQU443AZOA5Z3G563` | [cuenta](https://stellar.expert/explorer/testnet/account/GADMLY63WAUFDTW3IVCWNFYSYUOGJMN6UL7AALJMQU443AZOA5Z3G563) |
| Cuenta de Cinti Viejo (admin y `minter`) | `GBCHIELZEVH4ZGBD5XCPMXX7NS4P2DWDJWGQVEBCVD2ADTPDSDXIEVN5` | [cuenta](https://stellar.expert/explorer/testnet/account/GBCHIELZEVH4ZGBD5XCPMXX7NS4P2DWDJWGQVEBCVD2ADTPDSDXIEVN5) |
| Consumidor de prueba (sin fondear, nadie guarda su clave, A-28) | `GAQQH2UNAJHLRGVVKKWNIWV4WQMACAEPODZ7D2VWAOJLAR2IT6NCQAVP` | — |

Los alias son los *slugs* de la plataforma (`altos-de-calamuchita`, `destileria-cinti-viejo`). La URI base de los metadatos es provisional (`https://api.drinks-on-chain.test/v1/public/nft/<alias>/`, dominio reservado que no resuelve): la bodega la cambia con `set_token_uri_base` cuando el backend publique la ruta de metadatos (Ola 3).

## 2. Cuentas y claves

| Papel | Identidad local (`stellar keys`) | Secreto de GitHub Actions |
|---|---|---|
| Despliegue | `testnet-despliegue` | `TESTNET_DEPLOYER_SECRET` |
| Operaciones de la plataforma | `testnet-plataforma` | `TESTNET_PLATFORM_SECRET` |
| Bodega `<alias>` | `testnet-bodega-<alias>` | `TESTNET_WINERY_<ALIAS>_SECRET` (mayúsculas, `-` → `_`) |

- Las claves se generan **dentro del contenedor** (`scripts/docker.sh scripts/cuentas-testnet.sh`) y viven en el volumen Docker `doc-contracts-stellar` (la configuración de `stellar keys` del contenedor), nunca en el repo.
- A la CI llegan como secretos del repo, copiados por una tubería desde `stellar keys show` hasta `gh secret set` (`scripts/secretos-github.sh`): no se imprimen, no se escriben en archivos y no van como argumento de ningún comando.
- Los scripts nunca reciben una clave: firman con `STELLAR_ACCOUNT`, que stellar-cli acepta como nombre de identidad (local) o como clave (CI, desde la variable del secreto).
- Son claves **solo de testnet**. Las de mainnet las custodia el backend (doc 06 §8, D7) y se crean en B.4.

## 3. Desplegar el contrato de una bodega nueva

Requisitos: Docker (o Rust + stellar-cli ≥ 25.2 + jq). En Windows, cada script se ejecuta con `scripts/docker.sh`.

```bash
# 1. Cuenta de la bodega (y, la primera vez, las de despliegue y plataforma)
scripts/docker.sh scripts/cuentas-testnet.sh --bodega vinedos-del-guadalquivir

# 2. Contrato (idempotente; sube el código si la red no lo tiene)
scripts/docker.sh scripts/desplegar-bodega.sh \
  --alias vinedos-del-guadalquivir \
  --nombre "Viñedos del Guadalquivir" --simbolo GUADAL \
  --uri-base "https://api.drinks-on-chain.test/v1/public/nft/vinedos-del-guadalquivir/"

# 3. Prueba de ida y vuelta (emitir, entregar, quemar, eventos, costes)
scripts/docker.sh scripts/ida-y-vuelta.sh --alias vinedos-del-guadalquivir

# 4. Para la CI: su clave como secreto del repo (y añadir la variable
#    TESTNET_WINERY_VINEDOS_DEL_GUADALQUIVIR_SECRET al paso del workflow)
scripts/secretos-github.sh --bodega vinedos-del-guadalquivir

# 5. Commit de deployments/testnet.json
```

Límites: nombre ≤ 40 bytes, símbolo ≤ 10 bytes, URI base ≤ 200 bytes (DS-13). La bodega y el operador deben ser cuentas distintas.

**Idempotencia.** La dirección del contrato sale de la cuenta de despliegue y de una sal determinista, `sha256("drinks-on-chain/winery-nft/<alias>/<hash del WASM>")`. Repetir el script comprueba el contrato existente (nombre, símbolo, admin, roles) sin crear otro. Si el código cambió y la bodega ya tiene contrato, el script avisa y no hace nada salvo que se pida `--nueva-version` (el contrato no es actualizable, DS-11: una versión nueva es un contrato nuevo con otra dirección).

**Reinicios de testnet.** Testnet se reinicia periódicamente y borra cuentas y contratos. Tras un reinicio, `scripts/testnet.sh` (o el workflow) vuelve a fondear las cuentas registradas con Friendbot, sube el código y recrea cada contrato **en la misma dirección** (misma cuenta de despliegue, misma sal). Los tokens emitidos antes del reinicio se pierden.

## 4. Verificar

- **Explorador**: los enlaces de la tabla del §1 (stellar.expert muestra las llamadas, los eventos y el almacenamiento del contrato).
- **Lecturas** (simulación, sin firmar ni pagar):
  ```bash
  scripts/docker.sh 'STELLAR_ACCOUNT=GDN3CAF7KKD72Q5EPDYKBK2MCCANJWQ344OZKSL6GAYULDCOPMQZ4SB6 \
    stellar contract invoke --network testnet --send=no \
    --id CDUUCPA5JQVDP6EEI3CWT5MS4SGEPD2WS2SN6XSZCGPATTJSO2SZQS6M -- total_minted'
  ```
  Igual con `name`, `symbol`, `get_admin`, `owner_of --token_id N`, `token_uri --token_id N`, `balance --account G…`, `paused`.
- **Eventos**: `stellar events --network testnet --id <contrato> --start-ledger <ledger> --output json` (el RPC guarda ≈ 7 días).
- **Ida y vuelta completa**: `scripts/docker.sh scripts/testnet.sh` o el workflow **Testnet** (§5). El informe queda en `informes/` (ignorado por git) o como artefacto de la ejecución.

Primera ida y vuelta (27-09-2026), Altos de Calamuchita, lote `DEMO-ALTOS-20260927T235102Z` (tokens 0–2):
[`mint_batch`](https://stellar.expert/explorer/testnet/tx/1f867d6467c1122d32d132d33a1f9b91862461023a9fa5406accd4d11b287934) ·
[`operator_transfer` 0](https://stellar.expert/explorer/testnet/tx/5c6fe4b4904ddb46d6ad603de1b07c2628181fb9901e8c559611a582a917d40d) ·
[`operator_transfer` 1](https://stellar.expert/explorer/testnet/tx/0ada51028f5d35a6443a0d9294b1c51569976c6d4f10fa136c430a531dfd2f5e) ·
[`redeem_burn` 0](https://stellar.expert/explorer/testnet/tx/2be4038b064e3f4561325e49132b40e7ca1bc12004faa2c4c1fc82f39a0200c4).
Cinti Viejo, lote de 1 000 (tokens 0–999):
[`mint_batch`](https://stellar.expert/explorer/testnet/tx/54659f02e00224ee1356d4340bc1ed61b21461c8f54048c2e5948cfe1da059a1) ·
[`redeem_burn` 0](https://stellar.expert/explorer/testnet/tx/901e3c1417e812c16395dbdc78d230aae225719941d2aa214d7b090f0c45f0c9).
En ambos: `token_uri(0)` = URI base + `0`, `owner_of(0)` falla tras la quema (error 200), `total_minted` = tokens emitidos, eventos `consecutive_mint`, `lot_minted`, `transfer` y `burn` presentes.

## 5. CI: workflow «Testnet»

`.github/workflows/testnet.yml`, solo manual (`workflow_dispatch`; GitHub lo ofrece cuando el archivo está en `main`). Entradas: bodegas (vacío = todas las registradas), tokens del lote y entregas. Construye el WASM, avisa si su hash no es el registrado, ejecuta `scripts/testnet.sh` con los cuatro secretos como variables de entorno y publica el informe (Markdown + `costes.jsonl` + eventos + `testnet.json` resultante) como artefacto `informe-testnet-<id>` y en el resumen de la ejecución. El informe no contiene claves. Cada ejecución deja un lote de prueba en cada contrato.

## 6. Lo que necesita el backend (Ola 3)

- **Direcciones**: cuentas `G…` (56 caracteres, StrKey Ed25519) y contratos `C…` (56 caracteres). El backend guarda por bodega la dirección del contrato y la cuenta admin; `deployments/testnet.json` es la referencia para testnet. Los ids de token son `u32` desde 0, continuos entre lotes (DS-08).
- **Firmas**: `mint_batch` necesita la autorización de la cuenta de la bodega (`minter`); `operator_transfer` y `redeem_burn`, la de la plataforma (`operator`). En la prueba cada papel firmó como origen de su transacción y pagó su comisión. Para que pague siempre la cuenta de operaciones (doc 06 §5), el firmante del backend debe firmar la **entrada de autorización de Soroban** con la clave de la bodega y el sobre con la de operaciones (p. ej. `authorizeEntry` del SDK de JS). **No verificado aquí**: stellar-cli 28.1 no firma las dos cosas por separado (`--sign-with-key` sustituye la firma del sobre y la red devolvió `TxBadAuth`).
- **Comisiones**: usar siempre la simulación (`simulateTransaction`) para fijar la comisión de recursos. Una llamada normal cuesta céntimos de XLM, pero la que extienda la instancia cuando al código le queden < 90 días paga ≈ 30 días de renta del código (≈ 6 XLM estimados en mainnet, ≈ 20 XLM en testnet): el límite de comisión del firmante debe admitirlo o el trabajo de TTL debe extender el código antes.
- **Eventos** (Stellar RPC `getEvents`, filtro por `contractIds`; retención ≈ 7 días, consultar cada pocos minutos). Primer *topic* = nombre del evento (símbolo). Ejemplo real decodificado por stellar-cli:
  ```json
  {"ledger":4905901,"contract_id":"CDUUCPA5…QS6M","prefix_topics":["lot_minted"],
   "params":{"lot":"DEMO-ALTOS-20260927T235102Z","to":"GADMLY63…G563",
             "first_token_id":0,"last_token_id":2,"minter":"GADMLY63…G563"}}
  ```
  El RPC devuelve los *topics* y los datos como `ScVal` en XDR base64 (o JSON con `xdrFormat=json`); la forma de los datos de cada evento (mapa con los campos de [funciones.md](funciones.md) o valor suelto) está en la especificación del contrato, que es la que usa stellar-cli para decodificarlos: el indexador puede leerla del propio contrato o fijarla con estas pruebas. Un `mint_batch` emite `consecutive_mint` + `lot_minted` en la misma transacción; `operator_transfer` emite `transfer`; `redeem_burn` emite `burn` con el dueño en el momento de la quema.
- **TTL** (CHN-13, P-SC-4). Medido en testnet tras la ida y vuelta:

  | Entrada | TTL observado | Nota |
  |---|---|---|
  | Instancia (metadatos, roles, contador, pausa) | 120 días | El contrato la extiende en cada escritura si le quedan < 90 |
  | Código (compartido) | 120 días | Se extiende con la instancia de cualquier contrato |
  | `Owner(id)`, `OwnershipBucket(i)`, `Balance(cuenta)` leídos por una llamada | 30 días | OpenZeppelin extiende **al leer** |
  | `Owner(id)` recién escrito sin leer, `BurnedToken(id)` | TTL mínimo de la red (7 días en testnet, 120 en mainnet) | OpenZeppelin **no** extiende al escribir |

  El trabajo de TTL debe recorrer, por contrato: la instancia (que arrastra el código), `Owner(id)` de cada token vendido y del siguiente id de cada entrega, `OwnershipBucket(i)` de los lotes con tokens vivos y `Balance(cuenta)` de bodegas y consumidores con saldo. Claves como `ScVal`: `["Owner", u32]`, `["OwnershipBucket", u32]`, `["BurnedToken", u32]`, `["Balance", Address]` (vector con el símbolo de la variante), durabilidad persistente. Una entrada archivada no da un resultado falso: la simulación pide restaurarla (`RestoreFootprint`) antes de usarla.
- **Testnet no guarda datos para siempre**: los contratos de demostración no tienen trabajo de TTL; pasados 7 días sin uso, parte de sus entradas se archivan y hay que restaurarlas (`stellar contract restore`, pagando) antes de volver a usarlas; los lotes nuevos de la ida y vuelta no dependen de ellas salvo el contador y el cubo de propiedad abierto.
