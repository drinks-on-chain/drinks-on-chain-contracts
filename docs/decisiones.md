# Decisiones del repositorio de contratos

> Versión 3 · 08-10-2026 · Tareas O1-SC-1 (pasos B.1 y B.2 de `docs-back/08-roadmap.md` §6), O2-SC-1 (B.3, testnet: DS-15 a DS-19, correcciones en DS-12 y DS-14) y O3-SC-1 (soporte a la integración del backend: DS-20 a DS-23, actualización de DS-07, DS-12 y DS-18). Las decisiones de producto viven en `docs-back/04-decisiones-y-preguntas.md` (A-01, A-02, A-22, A-28) y el diseño en `docs-back/06-tokens-billeteras-y-cadena.md`. Aquí solo lo que se decidió **al implementar**, con lo que difiere del doc 06 marcado como pregunta para la coordinación. Nada de esto modifica `docs-back`.

## DS-01 · OpenZeppelin Stellar Contracts 0.7.2 y soroban-sdk 26.1.1

**Decisión**: dependencias fijadas con `=` en `Cargo.toml`:

| Crate | Versión | Publicada |
|---|---|---|
| `stellar-tokens` (NFT, extensión *Consecutive*) | `=0.7.2` | 09-06-2026 |
| `stellar-access` (control de acceso por roles) | `=0.7.2` | 09-06-2026 |
| `stellar-contract-utils` (pausa) | `=0.7.2` | 09-06-2026 |
| `stellar-macros` (`only_role`, `only_admin`, `when_not_paused`) | `=0.7.2` | 09-06-2026 |
| `soroban-sdk` | `=26.1.1` | 21-07-2026 |

**Por qué** (consultado el 27-09-2026):

- **0.7.2 es la última versión estable.** Después solo hay candidatas `0.8.0-rc.1` a `rc.3` (junio de 2026), que no se usan en un contrato que irá a mainnet. [Releases](https://github.com/OpenZeppelin/stellar-contracts/releases) · [v0.7.2](https://github.com/OpenZeppelin/stellar-contracts/releases/tag/v0.7.2).
- **Auditoría**: la última publicada es la de **v0.7.0** ([`audits/Stellar Contracts Library v0.7.0 Audit.pdf`](https://github.com/OpenZeppelin/stellar-contracts/tree/main/audits)). Se comprobó con `git diff v0.7.0 v0.7.2` que **no cambia ninguna línea de código Rust** en los módulos que usamos (`packages/tokens/src/non_fungible`, `packages/access/src`, `packages/contract-utils/src/pausable`, `packages/macros/src`): solo metadatos de `Cargo.toml`, README y la subida de `soroban-sdk` de 25 a 26.1 (arreglo de [rs-soroban-sdk#1875](https://github.com/stellar/rs-soroban-sdk/issues/1875), que afecta al paquete de cuentas, no a nosotros). Coincide con lo que pide el doc 06 §2.1 ("versión estable 0.7.x; la 0.7.0 tiene auditoría publicada").
- **soroban-sdk**: `stellar-tokens 0.7.2` exige `^26.1.0`; 26.1.1 es el último parche de la serie (solo corrige una restricción de versión de `stellar-env-*`). La 28.0.0 (18-09-2026) no es compatible con OpenZeppelin 0.7.x.
- Módulos que ofrece OpenZeppelin para NFT ([docs](https://docs.openzeppelin.com/stellar-contracts/tokens/non-fungible/non-fungible)): base, *Burnable*, *Enumerable*, *Consecutive*, *Royalties* y *Votes*; control de acceso ([docs](https://docs.openzeppelin.com/stellar-contracts/access/access-control)) y pausa ([docs](https://docs.openzeppelin.com/stellar-contracts/utils/pausable)). Usamos **Consecutive** ([docs](https://docs.openzeppelin.com/stellar-contracts/tokens/non-fungible/nft-consecutive)) como propone el doc 06 §2.1; es incompatible con *Enumerable* (los listados salen del indexador).

**Revisar** al publicarse una 0.8.0 estable con auditoría: subir en un PR propio, con el diff de los módulos usados.

## DS-02 · Rust 1.98.1 y objetivo `wasm32v1-none`

`rust-toolchain.toml` fija **1.98.1** (estable del 01-09-2026). `soroban-sdk 26` exige Rust ≥ 1.91 (`rust-version` del crate) y el objetivo `wasm32v1-none`, que no activa extensiones de WASM que Soroban no admite. OpenZeppelin usa `stable` sin fijar; fijamos para que la CI y las máquinas locales produzcan el mismo WASM.

## DS-03 · El WASM se construye con `stellar contract build`

`stellar-tokens 0.7.2` activa la característica `experimental_spec_shaking_v2` de `soroban-sdk`, y su script de compilación **rechaza** `cargo build --target wasm32v1-none --release` a secas ("requires stellar-cli v25.2.0+"). Por eso la CI y `scripts/verificar.sh` usan `stellar contract build` (stellar-cli **28.1.0**, 26-09-2026), que ejecuta ese mismo `cargo rustc … --target=wasm32v1-none --release` con la variable que lo habilita y además **optimiza** el WASM. Las pruebas nativas (`cargo test`, `cargo clippy`) no necesitan la CLI.

## DS-04 · Roles: la bodega administra y emite, la plataforma opera

| Quién | En el contrato | Puede |
|---|---|---|
| Cuenta de la **bodega** | `admin` de `AccessControl` + rol `minter` | Emitir (`mint_batch`), conceder y revocar roles, cambiar la URI base, pausar y reanudar, transferir la administración en dos pasos |
| Cuenta de **operaciones de la plataforma** | Rol `operator` | Entregar (`operator_transfer`), quemar al canjear (`redeem_burn`), pausar |
| Dirección del consumidor | Dueña de sus tokens | Nada en el MVP (no firma; A-04, A-28) |

"El operador con autorización de la bodega" (doc 06 §2.2 y la tarea) se resuelve sin lógica propia: si hiciera falta que la plataforma emita, la bodega le concede el rol `minter` con `grant_role` (queda en la red y es revocable). Por defecto solo la bodega emite, y es la bodega la que aparece como origen (A-02).

## DS-05 · Pausa: bodega u operador pausan; solo la bodega reanuda — **pregunta P-SC-1**

El doc 06 §2.2 asigna `pause`/`unpause` al "dueño del contrato". Implementado: **pausar** lo puede el admin **o** el operador; **reanudar**, solo el admin. Motivos: el doc 06 §3.2 dice que "revocar una bodega es pausar su contrato" (lo hace la plataforma) y el §11 pide pausa ante el compromiso de una clave (si se compromete la de la bodega, la plataforma debe poder pausar sin ella). Reanudar es lo sensible, por eso solo el admin. **Confirmar** con la coordinación.

## DS-06 · Quien firma va como último parámetro

Soroban no tiene `msg.sender`: cada función protegida recibe la dirección que firma y el contrato comprueba su firma (`require_auth`) y su rol, como en los ejemplos de OpenZeppelin (`#[only_role(caller, "…")]`). Firmas resultantes frente al doc 06 §2.2:

| Doc 06 | Implementado | Diferencia |
|---|---|---|
| `mint_batch(to, cantidad, lote)` | `mint_batch(to, amount, lot, minter) -> u32` | `minter` explícito; devuelve el último id |
| `operator_transfer(id, to)` | `operator_transfer(from, to, token_id, operator)` | Pide `from` (el dueño esperado): si la base de datos y la red no coinciden, falla (`IncorrectOwner`) en vez de mover un token de otra persona. Es la firma que pide la tarea |
| `redeem_burn(id)` | `redeem_burn(token_id, operator)` | `operator` explícito |
| `set_token_uri_base(url)` | `set_token_uri_base(base_uri)` | Igual (solo admin) |
| `pause` / `unpause` | `pause(caller)` / `unpause(caller)` | Interfaz `Pausable` de OpenZeppelin |

## DS-07 · El lote va en la emisión y en un evento, no en el almacenamiento

El doc 06 §2.2 incluye el lote en `mint_batch`; la tarea no. Se incluye `lot: String` (1–64 bytes; p. ej. el código `CVJ26SGR001`) y se publica en el evento `lot_minted` junto al rango de ids. **No se guarda** en el contrato (sería una entrada más con renta): el indexador enlaza rango ↔ lote leyendo la red, y el `token_uri` lleva al JSON del lote (doc 06 §2.3). **P-SC-5, actualizada el 08-10-2026** (S-12 del contrato de la Ola 3, adoptado por la coordinación): `lot` es la **referencia estable del lote**, `{lotPrefix}-L{año}-{NNN}` (p. ej. `CVJ-L2026-004`), la que nace al crear el lote en el ERP. No es el código de lote de la etiqueta, que no existe hasta el embotellado, y la preventa ocurre antes. El contrato no cambia: sigue aceptando cualquier texto de 1 a 64 bytes y no comprueba el formato (es una regla del backend).

## DS-08 · Los ids empiezan en 0

La numeración de OpenZeppelin (`sequential`) empieza en **0** y es continua entre lotes (el doc 06 §5 habla de "tokens 1..N" de forma ilustrativa). Número de botella dentro del lote = `token_id - first_token_id + 1`, con `first_token_id` del evento `lot_minted`. `total_minted()` devuelve el siguiente id libre.

## DS-09 · Interfaz SEP-0050 completa, quema solo por el operador

Se exponen las funciones estándar (`balance`, `owner_of`, `transfer`, `transfer_from`, `approve`, `approve_for_all`, `get_approved`, `is_approved_for_all`, `name`, `symbol`, `token_uri`) para que exploradores y billeteras entiendan el contrato; las que cambian estado respetan la pausa. En el MVP nadie las usa (el consumidor no firma), pero dejan abierto el paso a autocustodia (Fase 2). **No** se expone la quema del dueño (`Burnable`): la única quema es `redeem_burn`.

## DS-10 · `renounce_admin` desactivado

Renunciar a la administración dejaría el contrato sin nadie que pueda reanudarlo, cambiar la URI o gestionar roles. Falla con `AdminRenounceDisabled` (3002). La transferencia del admin en dos pasos de OpenZeppelin sigue disponible.

## DS-11 · Contrato no actualizable — **pregunta P-SC-2**

No se incluye el módulo `upgradeable` de OpenZeppelin: el código de una bodega no puede cambiar tras desplegarse, y eso es lo que se revisa en B.4. Consecuencia: un fallo en las funciones propias obligaría a desplegar un contrato nuevo y reemitir (el operador quemaría en el viejo). **Decidir antes de mainnet** si se prefiere actualizable con el admin (bodega, clave custodiada) como único que puede actualizar.

## DS-12 · Vida de los datos (TTL)

- La **instancia** (metadatos, admin, pausa, contador) se extiende a 120 días en cada escritura si le quedan menos de 90.
- OpenZeppelin extiende a **30 días** las entradas de dueño, cubos de propiedad, tokens quemados y saldos cada vez que **se leen** (no al escribirlas: una entrada recién escrita vive el TTL mínimo de la red, 7 días en testnet y 120 en mainnet, hasta que otra llamada la lee; medido en testnet en B.3, ver [testnet.md](testnet.md) §6); los roles, a 90 días.
- **Qué entradas `Owner` existen** (comprobado en la red local el 08-10-2026; corrige lo escrito en B.3): *Consecutive* infiere el dueño **hacia delante**. Una emisión escribe `Owner(último id del lote)`; una entrega de `id` escribe `Owner(id)` y, si el anterior no tiene dueño propio ni está quemado, `Owner(id − 1)` a nombre del dueño anterior. El dueño de un token sin entrada propia es el de la primera entrada `Owner` que haya a partir de su id: si se archivara `Owner(último id del lote)`, los tokens sin vender de ese lote dejarían de resolverse hasta restaurarla.
- Lo demás lo cubre el trabajo programado del backend (CHN-13). **Pregunta P-SC-4**: el doc 06 §9 habla de "renta de 120 días" por NFT; con *Consecutive* un token sin vender no tiene entrada propia (se infiere del final del lote), y las entradas `Owner(id)`, `OwnershipBucket(i)`, `BurnedToken(id)` y `Balance(dirección)` son las que el trabajo de extensión debe recorrer.

## DS-13 · Límites

- `mint_batch`: 1 a **32 000** tokens por llamada (límite de OpenZeppelin); la prueba sobre el WASM confirma que 32 000 cabe en los límites de una transacción de mainnet.
- Metadatos (OpenZeppelin): nombre ≤ 40 bytes, símbolo ≤ 10 bytes, URI base ≤ 200 bytes. `token_uri(id)` = URI base + id en decimal (sin `.json`): el servidor de metadatos debe responder en `<uri_base><id>`.
- El constructor rechaza que la bodega y el operador sean la misma cuenta (`SameAdminAndOperator`, 3000).

## DS-14 · Costes: la emisión cuesta por lote, no por botella — **pregunta P-SC-3**

Con *Consecutive*, `mint_batch` escribe las mismas entradas para 1 que para 32 000 tokens; el coste por botella aparece en la **primera transferencia** de cada token (nueva entrada de dueño). El doc 06 §9 estima ≈ 0,05 XLM por NFT emitido; las mediciones locales (ver [costes.md](costes.md)) dan del orden de 0,14–0,44 XLM por **lote** y 0,2–0,3 XLM por entrega, pero con tarifas de referencia del SDK y renta calculada desde el TTL mínimo, así que sobrestiman el caso real. Medir en testnet en B.3 y actualizar el doc 06 §9 si procede.

**Medido en B.3** ([costes.md](costes.md)): confirmado que la emisión cuesta por lote (3 y 1 000 tokens, 0,139 XLM; el segundo lote de un contrato, 0,007 XLM). En mainnet se estiman ≈ 0,02–0,05 XLM por entrega y ≈ 0,02 por quema (más que en el doc 06), ≈ 24 XLM por subir el código (el doc dice 1,5) y un coste nuevo: mantener vivo el código, ≈ 74 XLM/año compartidos (pregunta P-SC-6).

## DS-15 · Cuentas y claves de testnet

- Cuatro papeles: despliegue (paga la subida del código y la creación de contratos), operaciones de la plataforma (`operator`), una cuenta por bodega (admin y `minter`) y un consumidor de prueba. Todas fondeadas con Friendbot salvo el consumidor, que no se fondea (A-28): su clave se genera en una configuración temporal y se descarta, porque nunca firma.
- Las claves se generan dentro del contenedor y viven en la configuración local de `stellar keys` (volumen Docker `doc-contracts-stellar`, fuera del repo), como prevé el `CLAUDE.md` del repo, y como **secretos de GitHub Actions** (`TESTNET_DEPLOYER_SECRET`, `TESTNET_PLATFORM_SECRET`, `TESTNET_WINERY_<ALIAS>_SECRET`), copiadas por una tubería de `stellar keys show` a `gh secret set` (`scripts/secretos-github.sh`).
- Los scripts no reciben claves: firman con la variable `STELLAR_ACCOUNT` de stellar-cli, que admite un nombre de identidad (local) o una clave (CI). Así la clave nunca va como argumento de un proceso ni se escribe en disco en la CI.
- Si la coordinación prefiere que la única copia esté en GitHub, basta `docker volume rm doc-contracts-stellar` (se pierde la posibilidad de operar desde la máquina local; la CI sigue funcionando).

## DS-16 · Despliegue idempotente con sal determinista y registro por red

- Un archivo por red, `deployments/<red>.json` (en lugar de `deployments/testnet/wasm.json` + uno por bodega que proponía el borrador): red, código (`hash`, tamaño, transacción de subida), cuentas públicas y contratos por bodega. Solo datos públicos.
- La dirección de cada contrato se deriva de la cuenta de despliegue y de `sha256("drinks-on-chain/winery-nft/<alias>/<hash del WASM>")`. Repetir el despliegue no crea un segundo contrato y, tras un reinicio de testnet, lo recrea en la misma dirección. Cambiar el código da otra dirección; el script no lo hace sin `--nueva-version` (DS-11).
- El WASM que construye la CI es idéntico bit a bit al del contenedor local (mismo hash), así que la CI reconoce el código ya subido.

## DS-17 · Bodegas de demostración

Alias = *slug* de la plataforma (`altos-de-calamuchita`, `destileria-cinti-viejo`), nombre comercial ("Bodega Altos de Calamuchita", "Destilería Cinti Viejo") y símbolos `ALTOS` y `CINTI`. URI base **provisional** `https://api.drinks-on-chain.test/v1/public/nft/<alias>/` (dominio reservado, no resuelve) hasta que el backend publique la ruta de metadatos (Ola 3); se cambia con `set_token_uri_base`. Lotes de prueba con código `DEMO-<símbolo>-<fecha>` (P-SC-5: código legible).

## DS-18 · En la prueba, cada papel paga su transacción

La bodega es origen (y paga) de `mint_batch`; la plataforma, de `operator_transfer` y `redeem_burn`. El doc 06 §5 quiere que pague siempre la cuenta de operaciones: para eso el backend firmará la entrada de autorización de Soroban con la clave de la bodega y el sobre con la de operaciones. stellar-cli 28.1 no lo permite en un solo comando (`--sign-with-key` sustituye la firma del sobre: `TxBadAuth`), así que queda para el firmante del backend (Ola 3). El importe de la comisión no depende de quién la pague. **Verificado el 08-10-2026 con el SDK de JavaScript: DS-20.**

## DS-19 · Nombres de los scripts

Los scripts siguen el español del repo (`verificar.sh`, `docker.sh`): `desplegar-bodega.sh` (el borrador de B.2, ya documentado), `ida-y-vuelta.sh` (la tarea lo llamaba `roundtrip.*`), `cuentas-testnet.sh`, `secretos-github.sh` y `testnet.sh` (lo que ejecuta la CI). Las claves de `deployments/*.json` van en inglés, como los identificadores de código.

## DS-20 · Firma separada verificada: autoriza la bodega, paga operaciones (S-3)

Comprobado el 08-10-2026 en una red local `stellar/quickstart` en el **protocolo 29** (el de testnet) con `@stellar/stellar-sdk` **17.2.1** y el WASM de testnet sin cambios (`integracion/verificar.mjs`, que la CI ejecuta en cada push):

- `mint_batch`, `set_token_uri_base`, `unpause` y las funciones de roles y de administración se ejecutan con el **sobre** originado, firmado y pagado por la cuenta de operaciones y la **entrada de autorización de Soroban** firmada por la cuenta de la bodega con `authorizeEntry`. La bodega no paga nada ni consume número de secuencia (su saldo y su secuencia quedan intactos). No hace falta *fee-bump*.
- El *fee-bump* (interna de la bodega, externa de operaciones) también funciona, pero consume un número de secuencia de la bodega y obliga a que la bodega firme un sobre: queda como alternativa documentada, no como camino principal.
- Una autorización sin firmar no pasa la simulación; una firmada por otra clave entra en un ledger y acaba `FAILED` (cobrando la comisión a operaciones), sin emitir nada.
- **Versión del SDK**: la 13.3.0 que tiene hoy el backend **no sirve** (`rpc.Server.getTransaction` falla con `Bad union switch: 4` al leer el resultado de cualquier transacción). Las 14.6.1, 15.1.0 y 16.3.1 completaron el recorrido con credenciales de dirección v1; la 17 pide por defecto las v2 (CAP-71). Se recomienda **17.2.1** fijada (o 16.3.1, la rama `lts-16`, con soporte anunciado hasta marzo de 2027, si se prefiere la API de XDR anterior). Detalle y secuencia de llamadas en [testnet.md](testnet.md) §6.

## DS-21 · El WASM se versiona en `artefactos/`

El backend necesita `winery_nft.wasm` en su CI sin token. Los artefactos de un workflow exigen autenticación incluso en un repo público y el repo no publica Releases, así que el WASM optimizado (29 188 bytes) se versiona en `artefactos/winery_nft.wasm` con su `artefactos/winery_nft.wasm.sha256`. `scripts/verificar.sh` y la CI comprueban que es **idéntico bit a bit** al que construye el commit, y `integracion/verificar.mjs`, que su SHA-256 es el `wasm.hash` de `deployments/testnet.json`. Quien cambie el contrato debe copiar `dist/winery_nft.wasm` a `artefactos/` y regenerar el `.sha256` en el mismo PR (las puertas fallan si no). Cuando haya una versión candidata a mainnet (B.4) se publicará además como Release.

## DS-22 · Red local fijada por etiqueta y resumen

`integracion/red-local.sh` arranca `stellar/quickstart:v676-b1505.1-testing` (fijada también por su resumen `sha256:66a19476…`) con `--local --enable core,rpc --protocol-version 29`. La imagen trae el protocolo 28 por defecto aunque su Core es el 29: sin `--protocol-version` la red local no se parece a testnet. Friendbot arranca sin Horizon. Al subir testnet de protocolo se actualizan la etiqueta, el resumen y el número, en un PR propio.

## DS-23 · Los ejemplos de eventos se generan, no se escriben a mano

`integracion/eventos/*.json` y `integracion/claves-ttl.json` los escribe `integracion/verificar.mjs` desde una red local efímera: cada archivo trae el evento tal como lo devuelve `getEvents` (`rpc`) y su forma decodificada. Las direcciones y los hashes cambian en cada ejecución (claves al vuelo); la CI ejecuta el script con `ESCRIBIR_EJEMPLOS=0`, y los archivos versionados se regeneran a mano solo cuando cambian el contrato, el protocolo o la forma de la respuesta del RPC.

## Preguntas abiertas para la coordinación

| # | Pregunta | Propuesta |
|---|---|---|
| P-SC-1 | ¿Puede la plataforma pausar el contrato de una bodega? (DS-05) | Sí pausar, no reanudar |
| P-SC-2 | ¿Contrato actualizable antes de mainnet? (DS-11) | No en testnet; decidir en B.4 |
| P-SC-3 | Revisar el coste por NFT del doc 06 §9 con *Consecutive* (DS-14) | Medir en testnet (B.3) |
| P-SC-4 | Claves que debe extender el trabajo de TTL (CHN-13) (DS-12) | Las de DS-12 |
| P-SC-5 | Formato del identificador de lote en `mint_batch` (DS-07) | Código legible del lote |
| P-SC-6 | Mantener vivo el código en mainnet cuesta ≈ 74 XLM/año (renta por tamaño en memoria, ≈ 145 KB) y lo paga la transacción que extiende una instancia cuando al código le quedan < 90 días ([costes.md](costes.md)) | Que el trabajo de TTL (CHN-13) extienda el código por su cuenta (`stellar contract extend --wasm-hash`) y presupuestarlo como coste fijo de la plataforma; revisar en B.4 si reducir el WASM compensa |
| P-SC-3 (seguimiento) | Corregir el doc 06 §9 con las cifras de [costes.md](costes.md) | Sustituir la tabla por la estimación de mainnet de costes.md |

## Respuestas de la coordinación (27-09-2026)

| ID | Respuesta |
|---|---|
| P-SC-1 | Se adopta la recomendación: la plataforma (operador) puede pausar; solo la bodega (admin) reanuda |
| P-SC-2 | Pendiente del usuario (pregunta U-3 del plan maestro). Hasta entonces, no actualizable; se decide en B.4 |
| P-SC-3 | Medir en testnet en B.3 (Ola 2) y proponer la corrección del doc 06 §9 con las cifras reales |
| P-SC-4 | Las claves de DS-12; el trabajo CHN-13 del backend (Ola 3) las recorre |
| P-SC-5 | Código legible del lote (el mismo que imprime el ERP), máximo 64 bytes |

## Revisión de la coordinación del contrato de la Ola 3 (27-09-2026, anotada el 08-10-2026)

| ID | Respuesta |
|---|---|
| P-SC-5 | **Actualizada** (S-12): `lot` = referencia estable del lote, `{lotPrefix}-L{año}-{NNN}`; sustituye a la respuesta anterior (DS-07) |
| P-SC-4 | El trabajo de TTL del backend recorre las claves de DS-12, con la corrección de qué entradas `Owner` existen; `BurnedToken` no se extiende (S-21) |
| P-SC-6 | Adoptada la propuesta: el trabajo de TTL extiende el código por su cuenta (procedimiento en [testnet.md](testnet.md) §6); el coste sigue pendiente del usuario (U-9) |
| S-2 | Cada entorno del backend despliega sus propios contratos; `deployments/testnet.json` queda como registro de las pruebas de este repo |
| S-3 | Verificada la firma separada (DS-20); el *fee-bump* no hace falta |

