# Costes

> Versión 2 · 27-09-2026 · Tarea O2-SC-1 (paso B.3). **Medidos en testnet** el 27-09-2026 (protocolo 28, WASM de 29 188 bytes `eb9f75b2…`) y estimados para mainnet con los parámetros de red vigentes. Responde a la pregunta P-SC-3 ([decisiones.md](decisiones.md)). La versión 1 (estimaciones locales con el SDK) queda al final como referencia.

## Cómo se miden

`scripts/ida-y-vuelta.sh` y `scripts/desplegar-bodega.sh` leen de la red el coste real de cada transacción (Stellar RPC `getTransaction` con `xdrFormat=json`): la **comisión cobrada** (`fee_charged`) y, dentro de ella, la **renta** (`rent_fee_charged`), la parte de recursos no reembolsable y la comisión de inclusión (100 stroops, la mínima; sube si la red se congestiona). Los guardan en `informes/<red>-<fecha>/costes.jsonl`. 1 XLM = 10 000 000 stroops. Los enlaces llevan a cada transacción en stellar.expert.

## Medido en testnet

| Operación | Comisión cobrada (XLM) | De ella, renta | Transacción |
|---|---|---|---|
| Subir el código (29 188 bytes) | 5,2831 | 5,2656 | [`07c02acc…`](https://stellar.expert/explorer/testnet/tx/07c02acca56eea7aeb870234280709c409f3db60f6dd527ecba74be14aa8a96a) |
| Crear el **primer** contrato sobre ese código (Altos de Calamuchita) | 85,4196 | 85,4163 | [`c4fa8920…`](https://stellar.expert/explorer/testnet/tx/c4fa892045b64341576e0c67e4a14e4e74f8303d135fd439ddf3b0c2efca78a6) |
| Crear otro contrato (Destilería Cinti Viejo) | 0,3465 | 0,3431 | [`67704449…`](https://stellar.expert/explorer/testnet/tx/67704449f4750f092d617327b7ec86a0b79fe746b39885681acb3c4469f5a9fe) |
| `mint_batch` de 3 (primer lote del contrato) | 0,1389 | 0,1368 | [`1f867d64…`](https://stellar.expert/explorer/testnet/tx/1f867d6467c1122d32d132d33a1f9b91862461023a9fa5406accd4d11b287934) |
| `mint_batch` de **1 000** (primer lote del contrato) | 0,1390 | 0,1369 | [`54659f02…`](https://stellar.expert/explorer/testnet/tx/54659f02e00224ee1356d4340bc1ed61b21461c8f54048c2e5948cfe1da059a1) |
| `mint_batch` de 3 (lote siguiente) | 0,0073 | 0,0052 | [`9d6fe94f…`](https://stellar.expert/explorer/testnet/tx/9d6fe94f0a7f1ba3735860eb5a4666a089cabff2c41f803b59f5ed5362fe0f57) |
| `operator_transfer` (primera entrega del contrato) | 0,2204 | 0,2181 | [`5c6fe4b4…`](https://stellar.expert/explorer/testnet/tx/5c6fe4b4904ddb46d6ad603de1b07c2628181fb9901e8c559611a582a917d40d) |
| `operator_transfer` (siguientes) | 0,0241–0,0405 | 0,0217–0,0381 | [`0ada5102…`](https://stellar.expert/explorer/testnet/tx/0ada51028f5d35a6443a0d9294b1c51569976c6d4f10fa136c430a531dfd2f5e) · [`9d752af3…`](https://stellar.expert/explorer/testnet/tx/9d752af37ad7a1ebbede373e1e63d0360a7eedcbf494fffa75700fd1a4efedf6) |
| `redeem_burn` | 0,0058 | 0,0040 | [`2be4038b…`](https://stellar.expert/explorer/testnet/tx/2be4038b064e3f4561325e49132b40e7ca1bc12004faa2c4c1fc82f39a0200c4) |
| Extender la entrada de dueño de un NFT (128 bytes) ≈ 113 días | 0,0803 | 0,0802 | [`37eb0c62…`](https://stellar.expert/explorer/testnet/tx/37eb0c62b45b7ba0873946a7ba916cfd0eb86f8e64a6d1a392edfd682a1b4d0f) |

Sin la renta, cada llamada al contrato cuesta **0,0018–0,0034 XLM** (instrucciones, lecturas, escrituras, eventos y tamaño), en línea con el doc 06 §9 ("transferir o quemar ≈ 0,001–0,005 XLM").

## Qué explica las cifras

- **La renta es casi todo el coste.** Se paga al crear una entrada (por el TTL con que nace) y al extenderla. Su precio por byte y ledger depende del tamaño del estado de cada red: con los parámetros leídos el 27-09-2026 (`stellar network settings`), testnet cobra ≈ **3 700–4 000** stroops por KB (estado de 3,07 GB frente a un objetivo de 4 GB) y mainnet el **mínimo, 1 000** (1,85 GB frente a 3 GB). Mainnet es ≈ **4 veces más barata por byte y día** (13,9 stroops por byte y día).
- **TTL mínimo distinto**: en testnet una entrada persistente nace con 120 960 ledgers (≈ 7 días); en mainnet con 2 073 600 (≈ **120 días**). El máximo es ≈ 180 días en ambas.
- **El código es caro de mantener**: desde el protocolo 23 la renta del código se cobra por su tamaño en memoria, no por el del WASM. Las dos medidas coinciden en un "tamaño de renta" de **≈ 145 KB** para los 29 KB del WASM. La subida pagó 7 días; el primer contrato pagó el resto hasta 120 días, porque el constructor extiende la instancia y **extender una instancia extiende también el código**. El segundo contrato ya encontró el código extendido y costó 0,35 XLM.
- **La emisión cuesta por lote y solo el primero es caro**: 3 o 1 000 tokens cuestan lo mismo (0,139 XLM) porque *Consecutive* escribe las mismas entradas; el segundo lote del mismo contrato costó 0,007 XLM. La primera entrega del contrato crea el saldo del consumidor y la entrada de dueño; las siguientes, una o dos entradas de 129 bytes.
- **OpenZeppelin extiende al leer, no al escribir** (`get_persistent_entry` de *Consecutive*): una entrada recién escrita vive el TTL mínimo de la red hasta que otra llamada la lee (entonces pasa a 30 días). En testnet eso son 7 días; lo recoge [testnet.md](testnet.md) §6 para el trabajo de TTL (CHN-13).

## Estimación para mainnet

Modelo: renta = bytes × días × 13,9 stroops (tarifa mínima vigente) + 0,002–0,003 XLM de ejecución por llamada. Tamaños medidos en testnet: código ≈ 145 KB de renta, instancia ≈ 430 bytes, dueño o saldo 129 bytes, cubo de propiedad 906 bytes, token quemado 96 bytes. Todas las entradas nuevas nacen con 120 días en mainnet.

| Operación | Mainnet (estimado) | Doc 06 §9 | Lectura |
|---|---|---|---|
| Subir el código (una vez por versión) | **≈ 24 XLM** (120 días de renta del código) | ≈ 1,5 XLM | Muy por encima: la renta del código se cobra por tamaño en memoria |
| Mantener vivo el código | **≈ 74 XLM/año** (≈ 6 XLM cada 30 días), **compartido** por todas las bodegas | — | Nuevo. Lo paga la transacción que extiende una instancia cuando al código le quedan < 90 días |
| Crear el contrato de una bodega | ≈ 0,08 XLM | ≈ 0,05–0,1 XLM | Coincide (con el código ya extendido) |
| Emitir un lote (1 a 32 000 botellas) | ≈ 0,2 XLM el primero del contrato; ≈ 0,01–0,15 XLM los siguientes | ≈ 0,05 XLM **por NFT** | Mucho menor: se paga por lote, no por botella |
| Entregar (`operator_transfer`) | ≈ 0,02–0,05 XLM (+ 0,02 si el consumidor es nuevo en esa bodega) | ≈ 0,001–0,005 XLM | Mayor: la entrega crea las entradas de dueño que la emisión no crea |
| Quemar al canjear (`redeem_burn`) | ≈ 0,02 XLM | ≈ 0,001–0,005 XLM | Mayor: crea la marca de token quemado |
| Mantener vivo un NFT un año más | ≈ 0,065 XLM por entrada (1–2 por token vendido) | ≈ 0,07 XLM | Coincide |

**Preventa de 1 000 botellas canjeada en un año**: emisión ≈ 0,2 + entregas ≈ 35 + quemas ≈ 20 + mantenimiento de lo que siga vivo pasados 120 días ≈ 0–65 → **≈ 55–120 XLM**, más la parte que le toque del código (≈ 74 XLM/año para toda la plataforma). El orden de magnitud del doc 06 (≈ 120 XLM) se mantiene, pero el coste se desplaza de la emisión a la entrega y la quema, y aparece el mantenimiento del código.

**Propuesta para el doc 06 §9** (P-SC-3; `docs-back` no se toca desde aquí): sustituir la tabla por la de esta sección y añadir la fila del mantenimiento del código. Confirmar en mainnet en B.4 con una simulación (`stellar contract upload --build-only` + `stellar tx simulate`) antes de fijar presupuestos; la tarifa de renta de mainnet sube si su estado crece por encima del objetivo.

## Anexo · versión 1 (27-09-2026): estimación local

`cargo test -p winery-nft --features wasm-tests cost_report -- --nocapture` (tras `stellar contract build`) instancia el WASM en el entorno de pruebas de `soroban-sdk 26.1.1` con los límites de mainnet y las tarifas de referencia del SDK (instantánea de pubnet de 2024). Sirve para comparar versiones del contrato, no como precio: no cobra la renta del código y parte siempre del TTL mínimo.

| Operación | Instrucciones | Entradas escritas | Renta (stroops) | Total (stroops) | Total (XLM) |
|---|---|---|---|---|---|
| `mint_batch` de 1 (primera llamada del contrato) | 976 912 | 5 | 1 865 292 | 3 235 425 | 0,32 |
| `mint_batch` de 100 | 809 781 | 5 | 3 025 517 | 4 395 232 | 0,44 |
| `mint_batch` de 1 000 | 799 467 | 5 | 13 178 | 1 382 867 | 0,14 |
| `mint_batch` de 32 000 (máximo) | 1 018 643 | 5 | 44 152 | 1 414 389 | 0,14 |
| `operator_transfer` (primera venta del lote) | 1 124 041 | 7 | 1 717 377 | 3 117 295 | 0,31 |
| `operator_transfer` (siguiente token) | 1 043 213 | 6 | 790 106 | 2 173 121 | 0,22 |
| `redeem_burn` | 970 999 | 5 | 401 003 | 1 763 494 | 0,18 |
| `pause` | 621 199 | 2 | 426 143 | 1 739 107 | 0,17 |
