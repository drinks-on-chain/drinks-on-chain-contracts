//! Pruebas del contrato `winery-nft`.
//!
//! Convenciones:
//! - `assert_contract_error(res, código)` comprueba el error exacto de un
//!   `try_*`. Códigos: NFT de OpenZeppelin 200 (token inexistente), 201 (dueño
//!   incorrecto), 207 (cantidad inválida), 211 (URI base demasiado larga);
//!   pausa 1000 (pausado), 1001 (no pausado); control de acceso 2000 (sin
//!   permiso); propios 3000–3002.
//! - `assert_auth_error(res)` comprueba que falta la firma de la cuenta que
//!   el contrato exige (`require_auth`).
//! - Las pruebas de rol usan `mock_all_auths` (todas las firmas presentes) para
//!   aislar la comprobación del rol; las de firma usan `set_auths(&[])` o
//!   `mock_auths` con una firma concreta.
extern crate std;

use soroban_sdk::{
    testutils::{
        Address as _, AuthorizedFunction, AuthorizedInvocation, EnvTestConfig, Events, MockAuth,
        MockAuthInvoke,
    },
    xdr::{ScErrorCode, ScErrorType},
    Address, Env, Error, Event, IntoVal, InvokeError, String, Symbol,
};
use stellar_contract_utils::pausable::{Paused, Unpaused};
use stellar_tokens::non_fungible::{burnable::Burn, consecutive::ConsecutiveMint, Transfer};

use crate::{
    BaseUriUpdated, LotMinted, WineryNft, WineryNftClient, MAX_LOT_LEN, MINTER_ROLE, OPERATOR_ROLE,
};

const BASE_URI: &str = "https://api.drinksonchain.test/v1/nft/bodega-demo/";

struct Ctx<'a> {
    e: Env,
    client: WineryNftClient<'a>,
    id: Address,
    admin: Address,
    operator: Address,
}

/// Entorno de prueba sin instantáneas JSON al terminar (no se versionan y
/// ralentizan las pruebas).
fn env() -> Env {
    Env::new_with_config(EnvTestConfig { capture_snapshot_at_drop: false })
}

fn setup<'a>() -> Ctx<'a> {
    let e = env();
    let admin = Address::generate(&e);
    let operator = Address::generate(&e);
    let id = e.register(
        WineryNft,
        (
            admin.clone(),
            operator.clone(),
            String::from_str(&e, "Bodega Demo"),
            String::from_str(&e, "BDEMO"),
            String::from_str(&e, BASE_URI),
        ),
    );
    let client = WineryNftClient::new(&e, &id);
    Ctx { e, client, id, admin, operator }
}

fn s(e: &Env, v: &str) -> String {
    String::from_str(e, v)
}

fn role(e: &Env, name: &str) -> Symbol {
    Symbol::new(e, name)
}

fn lot(e: &Env) -> String {
    s(e, "CVJ26SGR001")
}

type TryResult<T> = Result<Result<T, soroban_sdk::ConversionError>, Result<Error, InvokeError>>;

fn assert_contract_error<T: core::fmt::Debug>(res: TryResult<T>, code: u32) {
    match res {
        Err(Ok(err)) => assert_eq!(err, Error::from_contract_error(code), "error inesperado"),
        other => panic!("se esperaba el error de contrato #{code}, se obtuvo {other:?}"),
    }
}

fn assert_auth_error<T: core::fmt::Debug>(res: TryResult<T>) {
    match res {
        // El host informa la firma que falta como `Auth` o, al propagarla
        // fuera de la invocación, como `Context`, ambos con `InvalidAction`.
        Err(Ok(err)) => assert!(
            err == Error::from_type_and_code(ScErrorType::Auth, ScErrorCode::InvalidAction)
                || err
                    == Error::from_type_and_code(ScErrorType::Context, ScErrorCode::InvalidAction),
            "se esperaba un error de autorización, se obtuvo {err:?}"
        ),
        other => panic!("se esperaba un error de autorización, se obtuvo {other:?}"),
    }
}

/// Emite `amount` tokens a la bodega con todas las firmas simuladas.
fn mint_to_admin(c: &Ctx, amount: u32) -> u32 {
    c.e.mock_all_auths();
    c.client.mint_batch(&c.admin, &amount, &lot(&c.e), &c.admin)
}

// ################## Constructor ##################

#[test]
fn constructor_sets_metadata_admin_and_roles() {
    let c = setup();
    assert_eq!(c.client.name(), s(&c.e, "Bodega Demo"));
    assert_eq!(c.client.symbol(), s(&c.e, "BDEMO"));
    assert_eq!(c.client.get_admin(), Some(c.admin.clone()));
    assert!(c.client.has_role(&c.admin, &role(&c.e, MINTER_ROLE)).is_some());
    assert!(c.client.has_role(&c.operator, &role(&c.e, OPERATOR_ROLE)).is_some());
    assert!(c.client.has_role(&c.operator, &role(&c.e, MINTER_ROLE)).is_none());
    assert!(c.client.has_role(&c.admin, &role(&c.e, OPERATOR_ROLE)).is_none());
    assert_eq!(c.client.total_minted(), 0);
    assert!(!c.client.paused());
}

#[test]
#[should_panic(expected = "Error(Contract, #3000)")]
fn constructor_rejects_same_admin_and_operator() {
    let e = env();
    let admin = Address::generate(&e);
    e.register(WineryNft, (admin.clone(), admin, s(&e, "Bodega"), s(&e, "BOD"), s(&e, BASE_URI)));
}

#[test]
#[should_panic(expected = "Error(Contract, #211)")]
fn constructor_rejects_base_uri_too_long() {
    let e = env();
    let long = "x".repeat(201);
    e.register(
        WineryNft,
        (Address::generate(&e), Address::generate(&e), s(&e, "Bodega"), s(&e, "BOD"), s(&e, &long)),
    );
}

#[test]
#[should_panic(expected = "Error(Contract, #214)")]
fn constructor_rejects_symbol_too_long() {
    let e = env();
    e.register(
        WineryNft,
        (
            Address::generate(&e),
            Address::generate(&e),
            s(&e, "Bodega"),
            s(&e, "SIMBOLOLARGO"),
            s(&e, BASE_URI),
        ),
    );
}

// ################## mint_batch ##################

#[test]
fn mint_batch_mints_consecutive_ids_to_recipient() {
    let c = setup();
    c.e.mock_all_auths();
    let last = c.client.mint_batch(&c.admin, &10, &lot(&c.e), &c.admin);
    assert_eq!(last, 9);
    assert_eq!(
        c.e.events().all().filter_by_contract(&c.id),
        [
            ConsecutiveMint { to: c.admin.clone(), from_token_id: 0, to_token_id: 9 }
                .to_xdr(&c.e, &c.id),
            LotMinted {
                lot: lot(&c.e),
                to: c.admin.clone(),
                first_token_id: 0,
                last_token_id: 9,
                minter: c.admin.clone(),
            }
            .to_xdr(&c.e, &c.id),
        ]
    );
    // La bodega firmó la emisión (y nadie más).
    assert_eq!(
        c.e.auths(),
        std::vec![(
            c.admin.clone(),
            AuthorizedInvocation {
                function: AuthorizedFunction::Contract((
                    c.id.clone(),
                    Symbol::new(&c.e, "mint_batch"),
                    (c.admin.clone(), 10_u32, lot(&c.e), c.admin.clone()).into_val(&c.e),
                )),
                sub_invocations: std::vec![],
            }
        )]
    );
    for id in 0..10 {
        assert_eq!(c.client.owner_of(&id), c.admin);
    }
    assert_eq!(c.client.balance(&c.admin), 10);
    assert_eq!(c.client.total_minted(), 10);

    // El segundo lote continúa la numeración y puede ir a otra dirección.
    let other = Address::generate(&c.e);
    let last = c.client.mint_batch(&other, &5, &s(&c.e, "CVJ26SGR002"), &c.admin);
    assert_eq!(last, 14);
    assert_eq!(c.client.owner_of(&10), other);
    assert_eq!(c.client.owner_of(&14), other);
    assert_eq!(c.client.owner_of(&9), c.admin);
    assert_eq!(c.client.balance(&other), 5);
    assert_eq!(c.client.total_minted(), 15);
}

#[test]
fn mint_batch_accepts_max_batch_and_max_lot_len() {
    let c = setup();
    c.e.mock_all_auths();
    let max_lot = "L".repeat(MAX_LOT_LEN as usize);
    let last = c.client.mint_batch(&c.admin, &32_000, &s(&c.e, &max_lot), &c.admin);
    assert_eq!(last, 31_999);
    assert_eq!(c.client.owner_of(&0), c.admin);
    assert_eq!(c.client.owner_of(&31_999), c.admin);
}

#[test]
fn mint_batch_rejects_invalid_amounts() {
    let c = setup();
    c.e.mock_all_auths();
    assert_contract_error(c.client.try_mint_batch(&c.admin, &0, &lot(&c.e), &c.admin), 207);
    assert_contract_error(c.client.try_mint_batch(&c.admin, &32_001, &lot(&c.e), &c.admin), 207);
    assert_contract_error(c.client.try_mint_batch(&c.admin, &u32::MAX, &lot(&c.e), &c.admin), 207);
    assert_eq!(c.client.total_minted(), 0);
}

#[test]
fn mint_batch_rejects_invalid_lot() {
    let c = setup();
    c.e.mock_all_auths();
    assert_contract_error(c.client.try_mint_batch(&c.admin, &1, &s(&c.e, ""), &c.admin), 3001);
    let long = "L".repeat(MAX_LOT_LEN as usize + 1);
    assert_contract_error(c.client.try_mint_batch(&c.admin, &1, &s(&c.e, &long), &c.admin), 3001);
}

#[test]
fn mint_batch_rejects_accounts_without_minter_role() {
    let c = setup();
    c.e.mock_all_auths();
    let stranger = Address::generate(&c.e);
    assert_contract_error(c.client.try_mint_batch(&stranger, &1, &lot(&c.e), &stranger), 2000);
    // La plataforma no emite sin que la bodega le conceda el rol.
    assert_contract_error(c.client.try_mint_batch(&c.admin, &1, &lot(&c.e), &c.operator), 2000);
    assert_eq!(c.client.total_minted(), 0);
}

#[test]
fn mint_batch_requires_minter_signature() {
    let c = setup();
    c.e.set_auths(&[]);
    assert_auth_error(c.client.try_mint_batch(&c.admin, &1, &lot(&c.e), &c.admin));
    // Firmar otra cuenta (la plataforma) no basta.
    c.e.mock_auths(&[MockAuth {
        address: &c.operator,
        invoke: &MockAuthInvoke {
            contract: &c.id,
            fn_name: "mint_batch",
            args: (c.admin.clone(), 1_u32, lot(&c.e), c.admin.clone()).into_val(&c.e),
            sub_invokes: &[],
        },
    }]);
    assert_auth_error(c.client.try_mint_batch(&c.admin, &1, &lot(&c.e), &c.admin));
    // Con la firma exacta de la bodega, sí.
    c.e.mock_auths(&[MockAuth {
        address: &c.admin,
        invoke: &MockAuthInvoke {
            contract: &c.id,
            fn_name: "mint_batch",
            args: (c.admin.clone(), 1_u32, lot(&c.e), c.admin.clone()).into_val(&c.e),
            sub_invokes: &[],
        },
    }]);
    assert_eq!(c.client.mint_batch(&c.admin, &1, &lot(&c.e), &c.admin), 0);
}

#[test]
fn operator_can_mint_once_the_winery_grants_minter_role() {
    let c = setup();
    c.e.mock_all_auths();
    c.client.grant_role(&c.operator, &role(&c.e, MINTER_ROLE), &c.admin);
    assert_eq!(c.client.mint_batch(&c.admin, &3, &lot(&c.e), &c.operator), 2);
    c.client.revoke_role(&c.operator, &role(&c.e, MINTER_ROLE), &c.admin);
    assert_contract_error(c.client.try_mint_batch(&c.admin, &1, &lot(&c.e), &c.operator), 2000);
}

#[test]
fn mint_batch_fails_when_paused() {
    let c = setup();
    c.e.mock_all_auths();
    c.client.pause(&c.admin);
    assert_contract_error(c.client.try_mint_batch(&c.admin, &1, &lot(&c.e), &c.admin), 1000);
    c.client.unpause(&c.admin);
    assert_eq!(c.client.mint_batch(&c.admin, &1, &lot(&c.e), &c.admin), 0);
}

// ################## operator_transfer ##################

#[test]
fn operator_transfer_moves_token_without_owner_signature() {
    let c = setup();
    mint_to_admin(&c, 10);
    let buyer = Address::generate(&c.e);

    c.e.mock_auths(&[MockAuth {
        address: &c.operator,
        invoke: &MockAuthInvoke {
            contract: &c.id,
            fn_name: "operator_transfer",
            args: (c.admin.clone(), buyer.clone(), 3_u32, c.operator.clone()).into_val(&c.e),
            sub_invokes: &[],
        },
    }]);
    c.client.operator_transfer(&c.admin, &buyer, &3, &c.operator);

    assert_eq!(
        c.e.events().all().filter_by_contract(&c.id),
        [Transfer { from: c.admin.clone(), to: buyer.clone(), token_id: 3 }.to_xdr(&c.e, &c.id)]
    );
    assert_eq!(c.client.owner_of(&3), buyer);
    // Los vecinos siguen siendo de la bodega (inferencia de Consecutive).
    assert_eq!(c.client.owner_of(&2), c.admin);
    assert_eq!(c.client.owner_of(&4), c.admin);
    assert_eq!(c.client.owner_of(&0), c.admin);
    assert_eq!(c.client.balance(&c.admin), 9);
    assert_eq!(c.client.balance(&buyer), 1);

    // Migración administrada (p. ej. a una cuenta inteligente en Fase 2).
    let smart_account = Address::generate(&c.e);
    c.e.mock_all_auths();
    c.client.operator_transfer(&buyer, &smart_account, &3, &c.operator);
    assert_eq!(c.client.owner_of(&3), smart_account);
    assert_eq!(c.client.balance(&buyer), 0);
}

#[test]
fn operator_transfer_rejects_accounts_without_operator_role() {
    let c = setup();
    mint_to_admin(&c, 5);
    let buyer = Address::generate(&c.e);
    let stranger = Address::generate(&c.e);
    assert_contract_error(c.client.try_operator_transfer(&c.admin, &buyer, &0, &stranger), 2000);
    // La bodega (admin) tampoco es operadora.
    assert_contract_error(c.client.try_operator_transfer(&c.admin, &buyer, &0, &c.admin), 2000);
    // Ni el comprador sobre su propio token.
    c.client.operator_transfer(&c.admin, &buyer, &0, &c.operator);
    assert_contract_error(c.client.try_operator_transfer(&buyer, &stranger, &0, &buyer), 2000);
    assert_eq!(c.client.owner_of(&0), buyer);
}

#[test]
fn operator_transfer_requires_operator_signature() {
    let c = setup();
    mint_to_admin(&c, 5);
    let buyer = Address::generate(&c.e);
    c.e.set_auths(&[]);
    assert_auth_error(c.client.try_operator_transfer(&c.admin, &buyer, &0, &c.operator));
    // La firma del dueño no sustituye a la del operador.
    c.e.mock_auths(&[MockAuth {
        address: &c.admin,
        invoke: &MockAuthInvoke {
            contract: &c.id,
            fn_name: "operator_transfer",
            args: (c.admin.clone(), buyer.clone(), 0_u32, c.operator.clone()).into_val(&c.e),
            sub_invokes: &[],
        },
    }]);
    assert_auth_error(c.client.try_operator_transfer(&c.admin, &buyer, &0, &c.operator));
    assert_eq!(c.client.owner_of(&0), c.admin);
}

#[test]
fn operator_transfer_rejects_wrong_owner_and_missing_tokens() {
    let c = setup();
    mint_to_admin(&c, 5);
    let buyer = Address::generate(&c.e);
    let stranger = Address::generate(&c.e);
    // `from` no es el dueño.
    assert_contract_error(c.client.try_operator_transfer(&stranger, &buyer, &1, &c.operator), 201);
    // Token que no existe (fuera de rango).
    assert_contract_error(c.client.try_operator_transfer(&c.admin, &buyer, &5, &c.operator), 200);
    assert_contract_error(
        c.client.try_operator_transfer(&c.admin, &buyer, &u32::MAX, &c.operator),
        200,
    );
}

#[test]
fn operator_transfer_fails_on_empty_contract() {
    let c = setup();
    c.e.mock_all_auths();
    let buyer = Address::generate(&c.e);
    assert_contract_error(c.client.try_operator_transfer(&c.admin, &buyer, &0, &c.operator), 200);
}

#[test]
fn operator_transfer_of_burned_token_fails() {
    let c = setup();
    mint_to_admin(&c, 5);
    let buyer = Address::generate(&c.e);
    c.client.redeem_burn(&2, &c.operator);
    assert_contract_error(c.client.try_operator_transfer(&c.admin, &buyer, &2, &c.operator), 200);
}

#[test]
fn operator_transfer_fails_when_paused_and_after_role_revoked() {
    let c = setup();
    mint_to_admin(&c, 5);
    let buyer = Address::generate(&c.e);
    c.client.pause(&c.operator);
    assert_contract_error(c.client.try_operator_transfer(&c.admin, &buyer, &0, &c.operator), 1000);
    c.client.unpause(&c.admin);
    c.client.operator_transfer(&c.admin, &buyer, &0, &c.operator);

    c.client.revoke_role(&c.operator, &role(&c.e, OPERATOR_ROLE), &c.admin);
    assert_contract_error(c.client.try_operator_transfer(&c.admin, &buyer, &1, &c.operator), 2000);
}

// ################## redeem_burn ##################

#[test]
fn redeem_burn_burns_token_of_any_owner() {
    let c = setup();
    mint_to_admin(&c, 10);
    let buyer = Address::generate(&c.e);
    c.client.operator_transfer(&c.admin, &buyer, &5, &c.operator);

    c.e.mock_auths(&[MockAuth {
        address: &c.operator,
        invoke: &MockAuthInvoke {
            contract: &c.id,
            fn_name: "redeem_burn",
            args: (5_u32, c.operator.clone()).into_val(&c.e),
            sub_invokes: &[],
        },
    }]);
    c.client.redeem_burn(&5, &c.operator);
    assert_eq!(
        c.e.events().all().filter_by_contract(&c.id),
        [Burn { from: buyer.clone(), token_id: 5 }.to_xdr(&c.e, &c.id)]
    );
    assert_eq!(c.client.balance(&buyer), 0);
    assert_contract_error(c.client.try_owner_of(&5), 200);
    assert_contract_error(c.client.try_token_uri(&5), 200);
    // Los vecinos no cambian.
    assert_eq!(c.client.owner_of(&4), c.admin);
    assert_eq!(c.client.owner_of(&6), c.admin);
    // Se quema también un token que sigue en manos de la bodega (faltante).
    c.e.mock_all_auths();
    c.client.redeem_burn(&0, &c.operator);
    assert_eq!(c.client.balance(&c.admin), 8);
    assert_eq!(c.client.total_minted(), 10);
}

#[test]
fn redeem_burn_of_last_token_in_batch_keeps_previous_owners() {
    let c = setup();
    mint_to_admin(&c, 10);
    // El último del lote es donde OpenZeppelin guarda el dueño del rango.
    c.client.redeem_burn(&9, &c.operator);
    for id in 0..9 {
        assert_eq!(c.client.owner_of(&id), c.admin);
    }
    assert_contract_error(c.client.try_owner_of(&9), 200);
}

#[test]
fn redeem_burn_twice_fails() {
    let c = setup();
    mint_to_admin(&c, 3);
    c.client.redeem_burn(&1, &c.operator);
    assert_contract_error(c.client.try_redeem_burn(&1, &c.operator), 200);
}

#[test]
fn redeem_burn_of_missing_token_fails() {
    let c = setup();
    c.e.mock_all_auths();
    assert_contract_error(c.client.try_redeem_burn(&0, &c.operator), 200);
    mint_to_admin(&c, 3);
    assert_contract_error(c.client.try_redeem_burn(&3, &c.operator), 200);
}

#[test]
fn redeem_burn_rejects_accounts_without_operator_role() {
    let c = setup();
    mint_to_admin(&c, 3);
    let stranger = Address::generate(&c.e);
    assert_contract_error(c.client.try_redeem_burn(&0, &stranger), 2000);
    assert_contract_error(c.client.try_redeem_burn(&0, &c.admin), 2000);
    assert_eq!(c.client.owner_of(&0), c.admin);
}

#[test]
fn redeem_burn_requires_operator_signature() {
    let c = setup();
    mint_to_admin(&c, 3);
    c.e.set_auths(&[]);
    assert_auth_error(c.client.try_redeem_burn(&0, &c.operator));
    assert_eq!(c.client.owner_of(&0), c.admin);
}

#[test]
fn redeem_burn_fails_when_paused() {
    let c = setup();
    mint_to_admin(&c, 3);
    c.client.pause(&c.operator);
    assert_contract_error(c.client.try_redeem_burn(&0, &c.operator), 1000);
}

// ################## token_uri y URI base ##################

#[test]
fn token_uri_appends_token_id_to_base_uri() {
    let c = setup();
    mint_to_admin(&c, 124);
    assert_eq!(c.client.token_uri(&0), s(&c.e, &std::format!("{BASE_URI}0")));
    assert_eq!(c.client.token_uri(&123), s(&c.e, &std::format!("{BASE_URI}123")));
    assert_contract_error(c.client.try_token_uri(&124), 200);
}

#[test]
fn token_uri_of_missing_token_fails() {
    let c = setup();
    assert_contract_error(c.client.try_token_uri(&0), 200);
}

#[test]
fn set_token_uri_base_by_admin() {
    let c = setup();
    mint_to_admin(&c, 1);
    let new_uri = s(&c.e, "https://nft.drinksonchain.test/bodega-demo/");
    c.e.mock_auths(&[MockAuth {
        address: &c.admin,
        invoke: &MockAuthInvoke {
            contract: &c.id,
            fn_name: "set_token_uri_base",
            args: (new_uri.clone(),).into_val(&c.e),
            sub_invokes: &[],
        },
    }]);
    c.client.set_token_uri_base(&new_uri);
    assert_eq!(
        c.e.events().all().filter_by_contract(&c.id),
        [BaseUriUpdated { base_uri: new_uri.clone() }.to_xdr(&c.e, &c.id)]
    );
    assert_eq!(c.client.token_uri(&0), s(&c.e, "https://nft.drinksonchain.test/bodega-demo/0"));
    // Nombre y símbolo no cambian.
    assert_eq!(c.client.name(), s(&c.e, "Bodega Demo"));
    assert_eq!(c.client.symbol(), s(&c.e, "BDEMO"));
}

#[test]
fn set_token_uri_base_requires_admin_signature() {
    let c = setup();
    let new_uri = s(&c.e, "https://malicioso.test/");
    c.e.set_auths(&[]);
    assert_auth_error(c.client.try_set_token_uri_base(&new_uri));
    // La firma del operador no sirve.
    c.e.mock_auths(&[MockAuth {
        address: &c.operator,
        invoke: &MockAuthInvoke {
            contract: &c.id,
            fn_name: "set_token_uri_base",
            args: (new_uri.clone(),).into_val(&c.e),
            sub_invokes: &[],
        },
    }]);
    assert_auth_error(c.client.try_set_token_uri_base(&new_uri));
}

#[test]
fn set_token_uri_base_rejects_too_long_uri() {
    let c = setup();
    c.e.mock_all_auths();
    let long = "x".repeat(201);
    assert_contract_error(c.client.try_set_token_uri_base(&s(&c.e, &long)), 211);
}

// ################## Pausa ##################

#[test]
fn operator_and_admin_can_pause_only_admin_can_unpause() {
    let c = setup();
    c.e.mock_all_auths();
    c.client.pause(&c.operator);
    assert_eq!(c.e.events().all().filter_by_contract(&c.id), [Paused {}.to_xdr(&c.e, &c.id)]);
    assert!(c.client.paused());
    assert_contract_error(c.client.try_unpause(&c.operator), 2000);
    c.client.unpause(&c.admin);
    assert_eq!(c.e.events().all().filter_by_contract(&c.id), [Unpaused {}.to_xdr(&c.e, &c.id)]);
    assert!(!c.client.paused());
    c.client.pause(&c.admin);
    assert!(c.client.paused());
}

#[test]
fn pause_rejects_accounts_without_role() {
    let c = setup();
    c.e.mock_all_auths();
    let stranger = Address::generate(&c.e);
    assert_contract_error(c.client.try_pause(&stranger), 2000);
    c.client.pause(&c.admin);
    assert_contract_error(c.client.try_unpause(&stranger), 2000);
}

#[test]
fn pause_and_unpause_require_signature() {
    let c = setup();
    c.e.set_auths(&[]);
    assert_auth_error(c.client.try_pause(&c.operator));
    assert_auth_error(c.client.try_pause(&c.admin));
    c.e.mock_all_auths();
    c.client.pause(&c.admin);
    c.e.set_auths(&[]);
    assert_auth_error(c.client.try_unpause(&c.admin));
    assert!(c.client.paused());
}

#[test]
fn pause_twice_and_unpause_when_active_fail() {
    let c = setup();
    c.e.mock_all_auths();
    assert_contract_error(c.client.try_unpause(&c.admin), 1001);
    c.client.pause(&c.admin);
    assert_contract_error(c.client.try_pause(&c.operator), 1000);
}

#[test]
fn paused_contract_blocks_standard_transfers_but_not_reads() {
    let c = setup();
    mint_to_admin(&c, 3);
    let buyer = Address::generate(&c.e);
    c.client.pause(&c.admin);
    assert_contract_error(c.client.try_transfer(&c.admin, &buyer, &0), 1000);
    assert_contract_error(c.client.try_transfer_from(&c.operator, &c.admin, &buyer, &0), 1000);
    assert_contract_error(c.client.try_approve(&c.admin, &buyer, &0, &100), 1000);
    assert_contract_error(c.client.try_approve_for_all(&c.admin, &buyer, &100), 1000);
    // Lecturas y configuración siguen disponibles.
    assert_eq!(c.client.owner_of(&0), c.admin);
    assert_eq!(c.client.balance(&c.admin), 3);
    assert_eq!(c.client.token_uri(&0), s(&c.e, &std::format!("{BASE_URI}0")));
    c.client.set_token_uri_base(&s(&c.e, "https://nft.drinksonchain.test/b/"));
    assert_eq!(c.client.token_uri(&1), s(&c.e, "https://nft.drinksonchain.test/b/1"));
}

// ################## Interfaz estándar (SEP-0050) ##################

#[test]
fn owner_can_transfer_and_approve_with_own_signature() {
    let c = setup();
    mint_to_admin(&c, 3);
    let buyer = Address::generate(&c.e);
    let spender = Address::generate(&c.e);

    c.client.transfer(&c.admin, &buyer, &0);
    assert_eq!(c.client.owner_of(&0), buyer);

    c.client.approve(&c.admin, &spender, &1, &1000);
    assert_eq!(c.client.get_approved(&1), Some(spender.clone()));
    c.client.transfer_from(&spender, &c.admin, &buyer, &1);
    assert_eq!(c.client.owner_of(&1), buyer);
    assert_eq!(c.client.get_approved(&1), None);

    c.client.approve_for_all(&buyer, &spender, &1000);
    assert!(c.client.is_approved_for_all(&buyer, &spender));
    assert_eq!(c.client.balance(&buyer), 2);
}

#[test]
fn standard_transfer_requires_owner_signature() {
    let c = setup();
    mint_to_admin(&c, 1);
    let buyer = Address::generate(&c.e);
    c.e.set_auths(&[]);
    assert_auth_error(c.client.try_transfer(&c.admin, &buyer, &0));
    // El operador no puede usar `transfer` en nombre del dueño.
    c.e.mock_auths(&[MockAuth {
        address: &c.operator,
        invoke: &MockAuthInvoke {
            contract: &c.id,
            fn_name: "transfer",
            args: (c.admin.clone(), buyer.clone(), 0_u32).into_val(&c.e),
            sub_invokes: &[],
        },
    }]);
    assert_auth_error(c.client.try_transfer(&c.admin, &buyer, &0));
    assert_eq!(c.client.owner_of(&0), c.admin);
}

// ################## Roles ##################

#[test]
fn admin_grants_and_revokes_operator() {
    let c = setup();
    mint_to_admin(&c, 3);
    let new_operator = Address::generate(&c.e);
    let buyer = Address::generate(&c.e);
    c.client.grant_role(&new_operator, &role(&c.e, OPERATOR_ROLE), &c.admin);
    c.client.operator_transfer(&c.admin, &buyer, &0, &new_operator);
    assert_eq!(c.client.owner_of(&0), buyer);
    assert_eq!(c.client.get_role_member_count(&role(&c.e, OPERATOR_ROLE)), 2);

    c.client.revoke_role(&new_operator, &role(&c.e, OPERATOR_ROLE), &c.admin);
    assert!(c.client.has_role(&new_operator, &role(&c.e, OPERATOR_ROLE)).is_none());
    assert_contract_error(c.client.try_redeem_burn(&0, &new_operator), 2000);
    // El operador original sigue activo.
    c.client.redeem_burn(&0, &c.operator);
}

#[test]
fn only_admin_manages_roles() {
    let c = setup();
    c.e.mock_all_auths();
    let stranger = Address::generate(&c.e);
    assert_contract_error(
        c.client.try_grant_role(&stranger, &role(&c.e, OPERATOR_ROLE), &stranger),
        2000,
    );
    // El operador no puede darse ni dar el rol de emisor.
    assert_contract_error(
        c.client.try_grant_role(&c.operator, &role(&c.e, MINTER_ROLE), &c.operator),
        2000,
    );
    assert_contract_error(
        c.client.try_revoke_role(&c.admin, &role(&c.e, MINTER_ROLE), &c.operator),
        2000,
    );
    // Sin la firma del admin, tampoco.
    c.e.set_auths(&[]);
    assert_auth_error(c.client.try_grant_role(&stranger, &role(&c.e, OPERATOR_ROLE), &c.admin));
}

#[test]
fn renounce_admin_is_disabled() {
    let c = setup();
    c.e.mock_all_auths();
    assert_contract_error(c.client.try_renounce_admin(), 3002);
    assert_eq!(c.client.get_admin(), Some(c.admin.clone()));
}

#[test]
fn admin_transfer_is_two_step() {
    let c = setup();
    c.e.mock_all_auths();
    let new_admin = Address::generate(&c.e);
    c.client.transfer_admin_role(&new_admin, &1000);
    // Hasta aceptar, el admin sigue siendo el anterior.
    assert_eq!(c.client.get_admin(), Some(c.admin.clone()));
    c.client.accept_admin_transfer();
    assert_eq!(c.client.get_admin(), Some(new_admin.clone()));
    c.client.pause(&c.operator);
    assert_contract_error(c.client.try_unpause(&c.admin), 2000);
    c.client.unpause(&new_admin);
}

#[test]
fn operator_can_renounce_its_role() {
    let c = setup();
    c.e.mock_all_auths();
    c.client.renounce_role(&role(&c.e, OPERATOR_ROLE), &c.operator);
    assert!(c.client.has_role(&c.operator, &role(&c.e, OPERATOR_ROLE)).is_none());
    assert_contract_error(c.client.try_pause(&c.operator), 2000);
}

// ################## Recorrido completo ##################

#[test]
fn full_lifecycle_mint_sell_redeem() {
    let c = setup();
    c.e.mock_all_auths();
    // Preventa: la bodega emite 100 botellas del lote.
    assert_eq!(c.client.mint_batch(&c.admin, &100, &lot(&c.e), &c.admin), 99);
    // Compra: la plataforma entrega la 57 al comprador.
    let buyer = Address::generate(&c.e);
    c.client.operator_transfer(&c.admin, &buyer, &57, &c.operator);
    assert_eq!(c.client.owner_of(&57), buyer);
    // Canje: la plataforma quema la 57.
    c.client.redeem_burn(&57, &c.operator);
    assert_contract_error(c.client.try_owner_of(&57), 200);
    assert_eq!(c.client.balance(&buyer), 0);
    assert_eq!(c.client.balance(&c.admin), 99);
    assert_eq!(c.client.owner_of(&56), c.admin);
    assert_eq!(c.client.owner_of(&58), c.admin);
}
