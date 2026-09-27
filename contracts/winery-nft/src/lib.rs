//! # winery-nft
//!
//! Contrato NFT de **una bodega** en Drinks on Chain: un token por botella,
//! emitido en lotes consecutivos (extensión *Consecutive* de OpenZeppelin
//! Stellar Contracts).
//!
//! - La **bodega** es la administradora (`admin`) y emisora (rol `minter`):
//!   firma las emisiones con su cuenta custodiada por el backend.
//! - La **plataforma** es la operadora (rol `operator`): entrega el token al
//!   comprador (`operator_transfer`) y lo quema al canjear (`redeem_burn`). Las
//!   direcciones de los consumidores son custodiales y no firman nada.
//! - Nada de precios, pases ni reglas de canje: viven en la base de datos del
//!   backend. El contrato solo registra de quién es cada token y cuándo se
//!   quema.
//!
//! Ver `docs/arquitectura.md` y `docs/funciones.md`.
#![no_std]

mod contract;
mod errors;
mod events;

pub use contract::{WineryNft, WineryNftClient, MAX_LOT_LEN, MINTER_ROLE, OPERATOR_ROLE};
pub use errors::WineryNftError;
pub use events::{BaseUriUpdated, LotMinted};

#[cfg(test)]
mod test;

#[cfg(all(test, feature = "wasm-tests"))]
mod test_wasm;
