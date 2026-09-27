# drinks-on-chain-contracts · guía de trabajo

Contratos Soroban (Stellar) de Drinks on Chain: `winery-nft`, un NFT por botella y **un contrato por bodega** sobre OpenZeppelin Stellar Contracts. Lee antes el `CLAUDE.md` de la carpeta paraguas, `docs-back/06-tokens-billeteras-y-cadena.md` (diseño), `docs-back/04` (A-01, A-02, A-22, A-28) y `docs/decisiones.md`, `docs/funciones.md` y `docs/ROADMAP.md` de este repo.

- Marca única Drinks on Chain. Textos, documentación y mensajes de commit en español; identificadores de código en inglés, como OpenZeppelin.
- Git: trabajo en `dev`, ramas `feat/o<ola>-<tarea>` desde `dev`, PR `dev → main` al cerrar cada ola (lo fusiona el usuario). Conventional Commits con alcance (`feat(winery-nft): …`, `ci: …`, `docs: …`) y `Refs: <paso> · <tarea>` en el cuerpo. Autor `brayan gomez <brayankgr@gmail.com>`; push con la cuenta `BrianKGR01` de `gh`.
- Puertas antes de integrar (las mismas que la CI): `scripts/verificar.sh` (fmt, clippy `-D warnings`, `cargo test`, `stellar contract build`, pruebas sobre el WASM). En Windows, sin Rust: `scripts/docker.sh scripts/verificar.sh`.
- El WASM se construye con `stellar contract build` (stellar-cli ≥ 25.2; la CI usa 28.1.0), no con `cargo build` a secas: `stellar-tokens` activa `experimental_spec_shaking_v2` (DS-03).
- Versiones fijadas con `=` (DS-01). Subir OpenZeppelin o `soroban-sdk` es un PR propio con el diff de los módulos usados frente a la última versión auditada.
- El contrato es mínimo: nada de precios, pases, ventanas de canje ni reglas del lote (viven en la base de datos). Toda función nueva necesita pruebas de cada rama de autorización (rol ausente, firma ausente, pausa) y su evento documentado en `docs/funciones.md`.
- Las funciones propias (`contracts/winery-nft/src/contract.rs`) son la única parte sin auditar: cortas, sin `unwrap` fuera de pruebas, errores propios desde 3000.
- Si algo difiere de `docs-back/06`, se anota en `docs/decisiones.md` como decisión o pregunta; `docs-back` no se toca desde aquí.
- Nunca claves secretas en el repo, en commits ni en los informes. Testnet con cuentas de Friendbot en la configuración local de `stellar keys`; mainnet solo tras la revisión externa (B.4).
- Marca las casillas de `docs/ROADMAP.md` (`- [x] … · fecha`) al terminar cada paso.
