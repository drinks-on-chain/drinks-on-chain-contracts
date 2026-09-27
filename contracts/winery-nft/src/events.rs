//! Eventos propios. El resto de eventos los emite OpenZeppelin y siguen
//! SEP-0050: `consecutive_mint`, `transfer`, `burn`, `approve`,
//! `approve_for_all`, `paused`, `unpaused`, `role_granted`, `role_revoked`,
//! `admin_transfer_initiated`, `admin_transfer_completed`, etc.

use soroban_sdk::{contractevent, Address, String};

/// Emisión de un lote de botellas. Acompaña al `consecutive_mint` de
/// OpenZeppelin y añade el lote, para que el indexador enlace el rango de
/// tokens con el expediente sin depender de la base de datos.
///
/// - topics: `["lot_minted", lot: String, to: Address]`
/// - data: `{ first_token_id: u32, last_token_id: u32, minter: Address }`
#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LotMinted {
    #[topic]
    pub lot: String,
    #[topic]
    pub to: Address,
    pub first_token_id: u32,
    pub last_token_id: u32,
    pub minter: Address,
}

/// Cambio de la URI base de los metadatos.
///
/// - topics: `["base_uri_updated"]`
/// - data: `{ base_uri: String }`
#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BaseUriUpdated {
    pub base_uri: String,
}
