use soroban_sdk::{contract, contractimpl, panic_with_error, Address, Env, String, Symbol, Vec};
use stellar_access::access_control::{self as access_control, AccessControl};
use stellar_contract_utils::pausable::{self as pausable, Pausable};
use stellar_macros::{only_admin, only_role, when_not_paused};
use stellar_tokens::non_fungible::{
    burnable::emit_burn,
    consecutive::{Consecutive, NonFungibleConsecutive},
    emit_transfer, sequential, Base, ContractOverrides, NonFungibleToken,
};

use crate::{
    errors::WineryNftError,
    events::{BaseUriUpdated, LotMinted},
};

/// Rol que puede emitir lotes. Se concede a la bodega (admin) al crear el
/// contrato; la bodega puede concederlo a otra cuenta (p. ej. la plataforma)
/// con `grant_role`.
pub const MINTER_ROLE: &str = "minter";
/// Rol de la plataforma: entrega (`operator_transfer`), quema al canjear
/// (`redeem_burn`) y pausa de emergencia.
pub const OPERATOR_ROLE: &str = "operator";
/// Longitud máxima, en bytes, del identificador de lote de `mint_batch`.
pub const MAX_LOT_LEN: u32 = 64;

const DAY_IN_LEDGERS: u32 = 17_280;
/// La instancia (metadatos, admin, pausa) se extiende a 120 días en cada
/// operación de escritura si le quedan menos de 90. El trabajo programado del
/// backend (CHN-13) la mantiene viva aunque no haya actividad.
const INSTANCE_EXTEND_AMOUNT: u32 = 120 * DAY_IN_LEDGERS;
const INSTANCE_TTL_THRESHOLD: u32 = 90 * DAY_IN_LEDGERS;

#[contract]
pub struct WineryNft;

fn bump_instance(e: &Env) {
    e.storage().instance().extend_ttl(INSTANCE_TTL_THRESHOLD, INSTANCE_EXTEND_AMOUNT);
}

#[contractimpl]
impl WineryNft {
    /// Crea el contrato de una bodega.
    ///
    /// - `admin`: cuenta de la bodega. Administra roles, URI base y pausa, y
    ///   recibe el rol `minter`.
    /// - `operator`: cuenta de operaciones de la plataforma (rol `operator`).
    /// - `name` (≤ 40 bytes), `symbol` (≤ 10 bytes) y `base_uri` (≤ 200 bytes):
    ///   metadatos de la colección; `token_uri(id)` = `base_uri` + `id`.
    pub fn __constructor(
        e: &Env,
        admin: Address,
        operator: Address,
        name: String,
        symbol: String,
        base_uri: String,
    ) {
        if admin == operator {
            panic_with_error!(e, WineryNftError::SameAdminAndOperator);
        }
        Base::set_metadata(e, base_uri, name, symbol);
        access_control::set_admin(e, &admin);
        access_control::grant_role_no_auth(e, &admin, &Symbol::new(e, MINTER_ROLE), &admin);
        access_control::grant_role_no_auth(e, &operator, &Symbol::new(e, OPERATOR_ROLE), &admin);
        bump_instance(e);
    }

    /// Emite `amount` tokens con identificadores consecutivos a nombre de
    /// `to` para el lote `lot`. Devuelve el identificador del último token.
    ///
    /// Solo una cuenta con rol `minter` (la bodega), que debe firmar. Falla si
    /// el contrato está pausado, si `amount` es 0 o mayor que 32 000 (límite de
    /// OpenZeppelin por transacción) o si `lot` está vacío o supera
    /// `MAX_LOT_LEN`.
    #[when_not_paused]
    #[only_role(minter, "minter")]
    pub fn mint_batch(e: &Env, to: Address, amount: u32, lot: String, minter: Address) -> u32 {
        if lot.is_empty() || lot.len() > MAX_LOT_LEN {
            panic_with_error!(e, WineryNftError::InvalidLot);
        }
        let last_token_id = Consecutive::batch_mint(e, &to, amount);
        LotMinted { lot, to, first_token_id: last_token_id + 1 - amount, last_token_id, minter }
            .publish(e);
        bump_instance(e);
        last_token_id
    }

    /// La plataforma entrega `token_id` de `from` a `to` sin la firma de
    /// `from` (direcciones custodiales que no firman). `from` debe ser el
    /// dueño actual. Emite el evento estándar `transfer`.
    ///
    /// Solo una cuenta con rol `operator`, que debe firmar. Falla si el
    /// contrato está pausado o si el token no existe o está quemado.
    #[when_not_paused]
    #[only_role(operator, "operator")]
    pub fn operator_transfer(
        e: &Env,
        from: Address,
        to: Address,
        token_id: u32,
        operator: Address,
    ) {
        Consecutive::update(e, Some(&from), Some(&to), token_id);
        emit_transfer(e, &from, &to, token_id);
        bump_instance(e);
    }

    /// La plataforma quema `token_id` al confirmar el canje, sea quien sea su
    /// dueño. Emite el evento estándar `burn` con el dueño.
    ///
    /// Solo una cuenta con rol `operator`, que debe firmar. Falla si el
    /// contrato está pausado o si el token no existe o ya está quemado.
    #[when_not_paused]
    #[only_role(operator, "operator")]
    pub fn redeem_burn(e: &Env, token_id: u32, operator: Address) {
        let owner = Consecutive::owner_of(e, token_id);
        Consecutive::update(e, Some(&owner), None, token_id);
        emit_burn(e, &owner, token_id);
        bump_instance(e);
    }

    /// Cambia la URI base de los metadatos (≤ 200 bytes). Solo el admin.
    #[only_admin]
    pub fn set_token_uri_base(e: &Env, base_uri: String) {
        Base::set_metadata(e, base_uri.clone(), Base::name(e), Base::symbol(e));
        BaseUriUpdated { base_uri }.publish(e);
        bump_instance(e);
    }

    /// Número de tokens emitidos desde el inicio (quemados incluidos). El
    /// siguiente `mint_batch` empieza en este identificador.
    pub fn total_minted(e: &Env) -> u32 {
        sequential::next_token_id(e)
    }
}

// ################## NFT estándar (SEP-0050) ##################

/// Interfaz estándar de OpenZeppelin con la implementación *Consecutive*. Las
/// operaciones que cambian estado respetan la pausa.
#[contractimpl]
impl NonFungibleToken for WineryNft {
    type ContractType = Consecutive;

    fn balance(e: &Env, account: Address) -> u32 {
        Self::ContractType::balance(e, &account)
    }

    fn owner_of(e: &Env, token_id: u32) -> Address {
        Self::ContractType::owner_of(e, token_id)
    }

    #[when_not_paused]
    fn transfer(e: &Env, from: Address, to: Address, token_id: u32) {
        Self::ContractType::transfer(e, &from, &to, token_id);
    }

    #[when_not_paused]
    fn transfer_from(e: &Env, spender: Address, from: Address, to: Address, token_id: u32) {
        Self::ContractType::transfer_from(e, &spender, &from, &to, token_id);
    }

    #[when_not_paused]
    fn approve(
        e: &Env,
        approver: Address,
        approved: Address,
        token_id: u32,
        live_until_ledger: u32,
    ) {
        Self::ContractType::approve(e, &approver, &approved, token_id, live_until_ledger);
    }

    #[when_not_paused]
    fn approve_for_all(e: &Env, owner: Address, operator: Address, live_until_ledger: u32) {
        Self::ContractType::approve_for_all(e, &owner, &operator, live_until_ledger);
    }

    fn get_approved(e: &Env, token_id: u32) -> Option<Address> {
        Self::ContractType::get_approved(e, token_id)
    }

    fn is_approved_for_all(e: &Env, owner: Address, operator: Address) -> bool {
        Self::ContractType::is_approved_for_all(e, &owner, &operator)
    }

    fn name(e: &Env) -> String {
        Self::ContractType::name(e)
    }

    fn symbol(e: &Env) -> String {
        Self::ContractType::symbol(e)
    }

    fn token_uri(e: &Env, token_id: u32) -> String {
        Self::ContractType::token_uri(e, token_id)
    }
}

impl NonFungibleConsecutive for WineryNft {}

// ################## Pausa ##################

#[contractimpl]
impl Pausable for WineryNft {
    fn paused(e: &Env) -> bool {
        pausable::paused(e)
    }

    /// Pausa de emergencia: el admin (bodega) o una cuenta con rol
    /// `operator` (plataforma), que debe firmar.
    fn pause(e: &Env, caller: Address) {
        caller.require_auth();
        if access_control::get_admin(e).as_ref() != Some(&caller) {
            access_control::ensure_role(e, &Symbol::new(e, OPERATOR_ROLE), &caller);
        }
        pausable::pause(e);
    }

    /// Reanudar es más sensible que pausar: solo el admin.
    fn unpause(e: &Env, caller: Address) {
        caller.require_auth();
        if access_control::get_admin(e).as_ref() != Some(&caller) {
            panic_with_error!(e, access_control::AccessControlError::Unauthorized);
        }
        pausable::unpause(e);
    }
}

// ################## Roles ##################

/// Control de acceso de OpenZeppelin: `grant_role`, `revoke_role`,
/// `renounce_role`, `has_role`, transferencia del admin en dos pasos, etc.
/// `renounce_admin` está desactivado.
#[contractimpl(contracttrait)]
impl AccessControl for WineryNft {
    fn renounce_admin(e: &Env) {
        panic_with_error!(e, WineryNftError::AdminRenounceDisabled);
    }
}
