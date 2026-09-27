# drinks-on-chain-contracts

Contratos Soroban (Stellar) de **Drinks on Chain**: un NFT por botella y **un contrato por bodega**, construido sobre [OpenZeppelin Stellar Contracts](https://github.com/OpenZeppelin/stellar-contracts) 0.7.2 (extensión *Consecutive*, control de acceso y pausa).

- La **bodega** administra su contrato y emite los lotes (`mint_batch`).
- La **plataforma** es la operadora: entrega el token al comprador (`operator_transfer`) y lo quema al canjear (`redeem_burn`). Los consumidores tienen direcciones custodiales que no firman.
- Precios, pases y reglas de canje viven en el backend; el contrato solo registra de quién es cada botella y cuándo se canjea.

| Documento | Contenido |
|---|---|
| [docs/arquitectura.md](docs/arquitectura.md) | Qué hay en la red, un contrato por bodega, ciclo de un NFT |
| [docs/funciones.md](docs/funciones.md) | Funciones, roles, eventos y errores |
| [docs/decisiones.md](docs/decisiones.md) | Versiones elegidas y decisiones de implementación, preguntas abiertas |
| [docs/costes.md](docs/costes.md) | Costes estimados por operación |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Pasos B.1–B.4 |

El diseño completo está en `docs-back/06-tokens-billeteras-y-cadena.md` (repo `drinks-on-chain-docsback`).

## Uso

Requisitos: Rust (se instala solo con `rust-toolchain.toml`: 1.98.1 y `wasm32v1-none`) y [stellar-cli](https://github.com/stellar/stellar-cli) ≥ 25.2 para compilar el WASM.

```bash
cargo test                                   # pruebas nativas
stellar contract build --package winery-nft  # WASM optimizado en target/wasm32v1-none/release/
scripts/verificar.sh                         # todas las puertas, como la CI
```

Sin Rust (p. ej. en Windows), con Docker:

```bash
scripts/docker.sh scripts/verificar.sh
```

Despliegue por bodega (borrador, paso B.3): `scripts/desplegar-bodega.sh --help`.

## Licencia

[Apache-2.0](LICENSE).
