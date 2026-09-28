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
| [docs/costes.md](docs/costes.md) | Costes medidos en testnet y estimados para mainnet |
| [docs/testnet.md](docs/testnet.md) | Contratos desplegados en testnet, cómo desplegar una bodega, verificación, lo que necesita el backend |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Pasos B.1–B.4 |
| [deployments/testnet.json](deployments/testnet.json) | Direcciones públicas en testnet (código, contratos, cuentas) |

El diseño completo está en `docs-back/06-tokens-billeteras-y-cadena.md` (repo `drinks-on-chain-docsback`).

## Uso

Requisitos: Rust (se instala solo con `rust-toolchain.toml`: 1.98.1 y `wasm32v1-none`) y [stellar-cli](https://github.com/stellar/stellar-cli) ≥ 25.2 para compilar el WASM; `jq` para los scripts de red.

```bash
cargo test                                   # pruebas nativas
stellar contract build --package winery-nft  # WASM optimizado en target/wasm32v1-none/release/
scripts/verificar.sh                         # todas las puertas, como la CI
```

Sin Rust (p. ej. en Windows), con Docker:

```bash
scripts/docker.sh scripts/verificar.sh
```

## Testnet

| Bodega | Contrato |
|---|---|
| Bodega Altos de Calamuchita | [`CDUUCPA5JQVDP6EEI3CWT5MS4SGEPD2WS2SN6XSZCGPATTJSO2SZQS6M`](https://stellar.expert/explorer/testnet/contract/CDUUCPA5JQVDP6EEI3CWT5MS4SGEPD2WS2SN6XSZCGPATTJSO2SZQS6M) |
| Destilería Cinti Viejo | [`CC5M35BGIVRDZ5HEXMORAFO2D6RGOARJ7MLOGU56JCX5J5C66HFJKDFF`](https://stellar.expert/explorer/testnet/contract/CC5M35BGIVRDZ5HEXMORAFO2D6RGOARJ7MLOGU56JCX5J5C66HFJKDFF) |

```bash
scripts/docker.sh scripts/cuentas-testnet.sh --bodega <alias>          # cuentas (Friendbot)
scripts/docker.sh scripts/desplegar-bodega.sh --alias <alias>   --nombre "…" --simbolo … --uri-base "…"                              # contrato (idempotente)
scripts/docker.sh scripts/ida-y-vuelta.sh --alias <alias>             # emitir, entregar, quemar, costes
scripts/docker.sh scripts/testnet.sh                                   # todo, como el workflow «Testnet»
```

Detalle, claves y CI en [docs/testnet.md](docs/testnet.md). Mainnet queda cerrada hasta la revisión externa (B.4).

## Licencia

[Apache-2.0](LICENSE).
