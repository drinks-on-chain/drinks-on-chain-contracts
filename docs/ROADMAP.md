# Roadmap de los contratos (pista B)

Detalle de `docs-back/08-roadmap.md` §6 y de las tareas SC del plan maestro (`PLAN-MAESTRO.md`). Se marca con fecha cuando el paso cumple lo previsto y está en `dev` con la CI en verde.

## B.1 · Repositorio (O1-SC-1)

- [x] Repo `drinks-on-chain/drinks-on-chain-contracts` con `main` (README + Apache-2.0) y `dev` · 2026-09-27
- [x] Espacio de trabajo Rust/Soroban: `Cargo.toml`, `rust-toolchain.toml` (1.98.1, `wasm32v1-none`), crate `contracts/winery-nft` · 2026-09-27
- [x] OpenZeppelin Stellar Contracts `=0.7.2` y `soroban-sdk =26.1.1` fijados, elección documentada en `docs/decisiones.md` (DS-01) · 2026-09-27
- [x] CI: `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test`, WASM con `stellar contract build`, simulación del despliegue sobre el WASM y artefacto `.wasm` + SHA-256 · 2026-09-27
- [x] Puertas locales (`scripts/verificar.sh`) y entorno Docker para Windows (`scripts/docker.sh`) · 2026-09-27

## B.2 · Contrato (O1-SC-1)

- [x] NFT *Consecutive* con constructor (admin = bodega, operador = plataforma, nombre, símbolo, URI base) · 2026-09-27
- [x] `mint_batch` (rol `minter`), `operator_transfer` y `redeem_burn` (rol `operator`), `token_uri`, `set_token_uri_base`, `total_minted` · 2026-09-27
- [x] Pausa (bodega u operador pausan, solo la bodega reanuda) y roles de OpenZeppelin (conceder/revocar operador, admin en dos pasos, `renounce_admin` desactivado) · 2026-09-27
- [x] Eventos para el indexador (`lot_minted`, `base_uri_updated` + los estándar) documentados en `docs/funciones.md` · 2026-09-27
- [x] 44 pruebas nativas (felices, roles no autorizados, firmas ausentes, pausa, token inexistente, quema doble, transferencia de quemado, límites de `mint_batch`) y 2 sobre el WASM (recorrido y costes) · 2026-09-27
- [x] WASM optimizado: 29 188 bytes · costes estimados en `docs/costes.md` · 2026-09-27
- [ ] Respuestas de la coordinación a P-SC-1…P-SC-5 (`docs/decisiones.md`)

## B.3 · Testnet (O2-SC-1, Ola 2)

- [ ] Cuenta de despliegue de testnet (Friendbot) en la configuración local o en el custodio, nunca en el repo
- [ ] Código subido una vez; hash en `deployments/testnet/wasm.json`
- [ ] Script de despliegue por bodega revisado (`scripts/desplegar-bodega.sh`) y contrato de la bodega de demostración
- [ ] Direcciones registradas por entorno (`deployments/<red>/`)
- [ ] Prueba de ida y vuelta en testnet: emitir, transferir, quemar; costes reales frente a `docs/costes.md` y `docs-back/06` §9

## B.4 · Revisión y mainnet (O6-SC-1, Ola 6)

- [ ] Decisión sobre actualización del contrato (P-SC-2)
- [ ] Revisión externa de las funciones propias (`contract.rs`)
- [ ] Despliegue en mainnet con las claves del custodio (D7)
