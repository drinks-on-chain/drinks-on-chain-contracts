# Testnet

> Versión 2 · 08-10-2026 · Tareas O2-SC-1 (paso B.3) y O3-SC-1 (§6 y §7: firma separada, SDK, eventos, TTL y red local, verificados en el protocolo 29). Qué hay desplegado en testnet, cómo desplegar el contrato de una bodega nueva, cómo verificarlo y qué necesita el backend (Ola 3). Costes medidos en [costes.md](costes.md).

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
- **Contratos por entorno (S-2)**: los de `deployments/testnet.json` son los de las pruebas de este repo. **Cada entorno del backend despliega los suyos** con la cuenta de operaciones como desplegador, el código `wasm.hash` de ese archivo (ya subido en testnet; en una red local lo sube el propio backend desde [`artefactos/winery_nft.wasm`](../artefactos/), §7) y la sal `sha256("drinks-on-chain/winery-nft/{entorno}/{wineryId}/{wasmHash}")` (texto UTF-8, hash en hexadecimal en minúsculas). Constructor, en este orden: `(admin: Address, operator: Address, name: String, symbol: String, base_uri: String)`, con `admin` = cuenta de la bodega y `operator` = cuenta de operaciones (deben ser distintas). Con el SDK: `Operation.createCustomContract({ address: operaciones, wasmHash, salt, constructorArgs })`; la dirección resultante se puede calcular antes de desplegar (`HashIdPreimage` de tipo `contractId` con el desplegador y la sal), así que repetir el despliegue es detectable sin estado propio. La cuenta de la bodega debe **existir** en la red antes de autorizar nada (`createAccount` desde operaciones; 2 XLM bastan y no se gastan).
- **Firmas (verificado el 08-10-2026, DS-20)**: `mint_batch` necesita la autorización de la cuenta de la bodega (`minter`); `set_token_uri_base`, `unpause` y la gestión de roles, la del admin (la bodega); `operator_transfer`, `redeem_burn` y `pause(operaciones)`, la de la plataforma (`operator`). **Paga siempre la cuenta de operaciones**: el sobre lo origina y firma operaciones, y la bodega solo firma su **entrada de autorización de Soroban**. Secuencia con `@stellar/stellar-sdk` 17 (la ejecuta [`integracion/verificar.mjs`](../integracion/verificar.mjs), función `prepararConFirmaSeparada`):
  1. Construir la transacción con origen en operaciones y `contract.call('mint_batch', to, amount, lot, minter)`; `sim = await server.simulateTransaction(tx)` (modo de registro). `sim.result.auth` trae **una** entrada, con credenciales de dirección de la bodega.
  2. `firmada = await authorizeEntry(entrada, firmante, sim.latestLedger + N, networkPassphrase)`. `firmante` es un `Keypair` o una función `(preimagen, payload) => ({ signature, publicKey })`: `payload` son los 32 bytes que hay que firmar con Ed25519 (el SHA-256 del XDR de la preimagen), justo lo que recibe `KeyCustody.sign(ref, payload)`; la clave no sale del custodio. `N` es la caducidad de la firma en ledgers (≈ 5 s cada uno); una entrada firmada lleva un *nonce* y solo vale una vez.
  3. Reconstruir la operación con `Operation.invokeHostFunction({ func: tx.operations[0].func, auth: [firmada] })`, **simular otra vez** (con la entrada ya firmada el RPC simula en modo estricto y devuelve la huella y los recursos definitivos, incluido el *nonce*) y `rpc.assembleTransaction(tx2, sim2).build()`.
  4. Firmar el sobre con la clave de operaciones (`tx.hash()` son los 32 bytes para el custodio), `sendTransaction` y sondear `getTransaction`.

  Comprobado: el sobre lleva una sola firma (operaciones), la comisión sale de operaciones y la bodega conserva saldo y número de secuencia. Cuando quien autoriza es la propia cuenta de origen (`pause`, `operator_transfer`, `redeem_burn` con operaciones) la entrada llega con credenciales de cuenta de origen y no se firma aparte. Una entrada sin firmar no pasa la segunda simulación; una firmada por otra clave llega a la red y la transacción acaba `FAILED` (se cobra la comisión). `sendTransaction` puede fallar de forma transitoria (`-32603 could not submit transaction to stellar-core`) o responder `TRY_AGAIN_LATER`: reenviar la **misma** transacción es inocuo (mismo hash; `DUPLICATE` significa que ya había llegado).

  **Alternativa *fee-bump*** (también verificada, no hace falta): transacción interna con origen en la bodega y firmada por ella, envuelta con `TransactionBuilder.buildFeeBumpTransaction(operaciones, BASE_FEE, interna, networkPassphrase)` y firmada por operaciones. La bodega tampoco paga, pero consume un número de secuencia suyo (una transacción en vuelo por bodega) y firma un sobre entero en vez de una autorización acotada.
- **Versión del SDK de JavaScript** (probadas contra el protocolo 29 de la red local, 08-10-2026):

  | `@stellar/stellar-sdk` | Resultado |
  |---|---|
  | 13.3.0 (la del backend hoy) | **No sirve**: simula, firma y envía, pero `rpc.Server.getTransaction` falla con `Bad union switch: 4` (no conoce la meta de transacción v4): no puede leer el resultado de ninguna transacción |
  | 14.6.1 · 15.1.0 · 16.3.1 | Completan subida, despliegue, `mint_batch` con firma separada, `getTransaction`, `getEvents` y `getLedgerEntries`. Reciben credenciales de dirección **v1**. La 16 es la rama `lts-16` (soporte anunciado hasta marzo de 2027); las 14 y 15 quedan fuera del soporte que anuncia el README del SDK |
  | **17.2.1** (recomendada, fijada) | Todo el recorrido de `integracion/verificar.mjs`. Pide por defecto credenciales **v2** (CAP-71: la firma queda atada a la dirección que autoriza); la red acepta las dos |

  Cambios de API de la 17 que afectan a quien escriba el firmante: `@stellar/stellar-base` queda dentro del SDK; los objetos XDR son inmutables y con **campos** en vez de métodos (`entrada.credentials.type`, `resultado.feeCharged`), los enteros de 64 bits son `bigint`, las uniones se crean con su fábrica por variante y exponen `.type` y `.value`, los enumerados son propiedades (`xdr.ContractDataDurability.persistent`), `toXdr`/`fromXdr` sustituyen a `toXDR`/`fromXDR` y `hash()` devuelve `Uint8Array`. `simulateTransaction(tx, recursos, modoAuth, useUpgradedAuth = true)` pide las credenciales v2; el tipo de la entrada puede ser `sorobanCredentialsAddress` o `sorobanCredentialsAddressV2` y `authorizeEntry` firma la preimagen que corresponda a cada una (el firmante no debe construirla a mano). La función de firma recibe ahora `(preimagen, payload)`.
- **Comisiones**: usar siempre la simulación (`simulateTransaction`) para fijar la comisión de recursos. Una llamada normal cuesta céntimos de XLM, pero la que extienda la instancia cuando al código le queden < 90 días paga ≈ 30 días de renta del código (≈ 6 XLM estimados en mainnet, ≈ 20 XLM en testnet): el límite de comisión del firmante debe admitirlo o el trabajo de TTL debe extender el código antes.
- **Eventos** (Stellar RPC `getEvents`, filtro por `contractIds`; retención ≈ 7 días, consultar cada pocos minutos). Primer *topic* = nombre del evento (símbolo). Ejemplo real decodificado por stellar-cli:
  ```json
  {"ledger":4905901,"contract_id":"CDUUCPA5…QS6M","prefix_topics":["lot_minted"],
   "params":{"lot":"DEMO-ALTOS-20260927T235102Z","to":"GADMLY63…G563",
             "first_token_id":0,"last_token_id":2,"minter":"GADMLY63…G563"}}
  ```
  El RPC devuelve los *topics* y los datos como `ScVal` en XDR base64 (o JSON con `xdrFormat=json`). **Un ejemplo real de cada uno de los 14 eventos** está en [`integracion/eventos/`](../integracion/eventos/) (`<evento>.json`: `rpc` es el objeto tal como lo devuelve `getEvents` del RPC 29 —`id`, `ledger`, `ledgerClosedAt`, `contractId`, `txHash`, `operationIndex`, `transactionIndex`, `inSuccessfulContractCall`, `topic[]`, `value`— y `decodificado`, sus *topics* y su valor con `scValToNative`; `otros` trae más apariciones del mismo evento, y `_red.json`, la red, las cuentas y los campos de paginación de la respuesta: `cursor`, `latestLedger`, `oldestLedger`). Los datos son siempre un mapa (vacío en `paused` y `unpaused`); los tipos, en [funciones.md](funciones.md). El `txHash` permite casar cada evento con la transacción propia que lo originó. Un `mint_batch` emite `consecutive_mint` + `lot_minted` en la misma transacción; `operator_transfer` emite `transfer`; `redeem_burn` emite `burn` con el dueño en el momento de la quema.
- **TTL** (CHN-13, P-SC-4). Medido en testnet tras la ida y vuelta:

  | Entrada | TTL observado | Nota |
  |---|---|---|
  | Instancia (metadatos, roles, contador, pausa) | 120 días | El contrato la extiende en cada escritura si le quedan < 90 |
  | Código (compartido) | 120 días | Se extiende con la instancia de cualquier contrato |
  | `Owner(id)`, `OwnershipBucket(i)`, `Balance(cuenta)` leídos por una llamada | 30 días | OpenZeppelin extiende **al leer** |
  | `Owner(id)` recién escrito sin leer, `BurnedToken(id)` | TTL mínimo de la red (7 días en testnet, 120 en mainnet) | OpenZeppelin **no** extiende al escribir |

  **Claves confirmadas** con `getLedgerEntries` en la red local (08-10-2026; en XDR base64 en [`integracion/claves-ttl.json`](../integracion/claves-ttl.json)). Todas son `LedgerKey::ContractData { contract, key, durability: Persistent }` salvo el código:

  | Entrada | `key` (`ScVal`) | Cuándo existe |
  |---|---|---|
  | Instancia | `ScVal::LedgerKeyContractInstance` | Siempre |
  | Código | `LedgerKey::ContractCode { hash: wasmHash }` (no es `ContractData`) | Siempre; compartido por todos los contratos |
  | `Owner(id)` | `Vec([Symbol("Owner"), U32(id)])` | Último id de **cada emisión**; cada token entregado; y el id **anterior** a cada entrega si no tenía dueño propio ni estaba quemado |
  | `OwnershipBucket(i)` | `Vec([Symbol("OwnershipBucket"), U32(i)])`, `i = id / 3200` (división entera) | Un cubo por cada 3 200 ids con alguna entrada `Owner` |
  | `Balance(dirección)` | `Vec([Symbol("Balance"), Address])` | Bodega y cada consumidor con saldo |
  | `BurnedToken(id)` | `Vec([Symbol("BurnedToken"), U32(id)])` | Cada token quemado (no se extiende, S-21) |

  **Corrección** respecto a la versión 1 (y a la tabla del §8.3 del contrato de la Ola 3): no existe una entrada para «el id siguiente a cada entrega». *Consecutive* infiere el dueño hacia delante: el de un token sin entrada propia es el de la primera entrada `Owner` a partir de su id. Por eso el trabajo de TTL debe recorrer, por contrato: la instancia, el código, **`Owner(último id)` de cada emisión con tokens sin vender** (si se archiva, esos tokens dejan de resolverse hasta restaurarla), `Owner(id)` de cada token vendido, `Owner(id − 1)` de cada entrega, los `OwnershipBucket` de esos ids y `Balance` de la bodega y de los consumidores con saldo. Una entrada archivada no da un resultado falso: la simulación pide restaurarla (`RestoreFootprint`) antes de usarla.

  **Extender (P-SC-6, verificado)**: una transacción de operaciones con `Operation.extendFootprintTtl({ extendTo })` y las claves en la huella de **solo lectura** (`new SorobanDataBuilder().setReadOnly([claves…]).build()` con `setSorobanData`), simulada y montada con `assembleTransaction` como cualquier otra. `extendTo` son ledgers contados desde el actual (17 280 por día; máximo ≈ 180 días); no hace nada con las entradas que ya viven más. El **código se extiende por su cuenta**, con su `LedgerKey::ContractCode` como única clave, para que no lo pague por sorpresa la primera transacción que extienda una instancia; varias entradas de datos caben en una misma transacción. Con stellar-cli: `stellar contract extend --wasm-hash <hash> --ledgers-to-extend <n>` (código) y `stellar contract extend --id <contrato> --key-xdr <ScVal> --durability persistent --ledgers-to-extend <n>` (datos). En la red local, llevar el código de 120 a 150 días costó ≈ 6,5 XLM y llevar siete entradas de datos a 120 días, ≈ 0,2 XLM (tarifas de la red local, no de mainnet; ver [costes.md](costes.md)): el tope de comisión del firmante debe admitir la del código.
- **Testnet no guarda datos para siempre**: los contratos de demostración no tienen trabajo de TTL; pasados 7 días sin uso, parte de sus entradas se archivan y hay que restaurarlas (`stellar contract restore`, pagando) antes de volver a usarlas; los lotes nuevos de la ida y vuelta no dependen de ellas salvo el contador y el cubo de propiedad abierto.

## 7. Red local para la CI del backend

- **Imagen**: `stellar/quickstart:v676-b1505.1-testing` (resumen `sha256:66a19476f2ce2ed09c4dccf3f1af4d438209eee9ee05eb113a02dd926e2b03f5`, 529 MB comprimida; Core 29.0.0, RPC 29.0.0). **Opciones**: `--local --enable core,rpc --protocol-version 29`, puerto 8000 publicado. Sin `--protocol-version 29` arranca en el 28. `--enable core,rpc` deja fuera Horizon, Lab y Galexie; Friendbot funciona igual. Es lo que hace [`integracion/red-local.sh`](../integracion/red-local.sh) `arrancar` / `parar`.
- **Direcciones**: RPC `http://localhost:8000/rpc`, Friendbot `http://localhost:8000/friendbot?addr=G…`, frase de red `Standalone Network ; February 2017`. La red es efímera y cierra un ledger por segundo.
- **Arranque** (con la imagen ya descargada): RPC sano (`getHealth`) en ≈ 15 s y Friendbot en ≈ 20 s; mientras tanto Friendbot responde 502, así que hay que esperar a los dos. El recorrido completo de `verificar.mjs` (≈ 30 transacciones) tarda ≈ 40 s.
- **WASM**: `artefactos/winery_nft.wasm` y `artefactos/winery_nft.wasm.sha256` de este repo (público), descargables sin token desde `https://raw.githubusercontent.com/drinks-on-chain/drinks-on-chain-contracts/<commit>/artefactos/winery_nft.wasm` (fijar el commit, no una rama). Su SHA-256 es el `wasm.hash` de `deployments/testnet.json` (`eb9f75b2…89d8`); las puertas de este repo comprueban que es idéntico al que construye el commit (DS-21). Se sube y se ejecuta **sin cambios** en el protocolo 29.
- **Reproducir aquí**: `integracion/red-local.sh arrancar && (cd integracion && npm ci && node verificar.mjs); integracion/red-local.sh parar`. Las claves se generan al vuelo; el script se niega a ejecutarse si la frase de red no es la local. Con `ESCRIBIR_EJEMPLOS=0` no reescribe los JSON versionados (así lo ejecuta el job «integración» de la CI).
- **No probado**: archivar y restaurar entradas (la red local no adelanta ledgers; S-25 del contrato de la Ola 3).
