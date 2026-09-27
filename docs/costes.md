# Costes estimados

> Versión 1 · 27-09-2026. Estimaciones locales, **no** medidas en la red. Se miden de nuevo en testnet en el paso B.3 y se comparan con `docs-back/06` §9.

## Cómo se obtienen

`cargo test -p winery-nft --features wasm-tests cost_report -- --nocapture` (después de `stellar contract build`) instancia el **WASM optimizado** en el entorno de pruebas de `soroban-sdk 26.1.1`, con los **límites de recursos de una transacción de mainnet**, y muestra el coste de cada operación con las tarifas de referencia que trae el SDK (instantánea de pubnet del 11-12-2024 ajustada al protocolo 23). No incluye el tamaño de la transacción ni la comisión de inclusión, y la renta depende del TTL que tenga cada entrada en ese momento: son órdenes de magnitud.

## Resultado (27-09-2026, WASM de 29 188 bytes)

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

## Lectura

- **La emisión cuesta por lote, no por botella**: 1 000 o 32 000 tokens escriben las mismas cinco entradas (contador, saldo, dueño del último id, un cubo de propiedad, instancia). El doc 06 §9 supone ≈ 0,05 XLM **por NFT emitido**; con *Consecutive* ese coste se desplaza a la **primera transferencia** de cada token, que crea su entrada de dueño (y la del anterior para conservar la inferencia).
- La **renta** domina el total: cada escritura paga la extensión de TTL de las entradas que toca (30 días en las de OpenZeppelin, 120 en la instancia). En el entorno de pruebas las entradas nacen con el TTL mínimo, por eso las primeras llamadas pagan más.
- **No sumar la tabla para estimar una preventa**: en la red, una entrada ya extendida a 30 días no vuelve a pagar renta hasta que baja del umbral, así que las entregas y quemas de un mismo lote pagarán bastante menos renta que en esta medición, donde cada llamada parte del TTL mínimo. Tampoco se sabe cuánto difieren las tarifas de referencia del SDK (2024) de las vigentes. Se mide en testnet (B.3) antes de corregir la cifra del doc 06 §9 (≈ 120 XLM por 1 000 botellas; pregunta P-SC-3 en [decisiones.md](decisiones.md)).
- Subir el código (una vez por versión) depende del tamaño del WASM (29 KB); crear el contrato de cada bodega es una instancia sobre ese código. Ambos se miden en B.3 con `stellar contract upload/deploy --cost`.
