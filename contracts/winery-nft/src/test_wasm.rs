//! Simulación del despliegue: carga el `.wasm` compilado (el mismo artefacto
//! que se subiría a la red), lo instancia como lo haría el script de despliegue
//! y recorre emitir → entregar → quemar. Se ejecuta con
//! `cargo test -p winery-nft --features wasm-tests` después de
//! `stellar contract build`.
extern crate std;

use soroban_sdk::{
    testutils::{Address as _, EnvTestConfig},
    Address, Env, String,
};

mod wasm {
    soroban_sdk::contractimport!(file = "../../target/wasm32v1-none/release/winery_nft.wasm");
}

#[test]
fn deploy_wasm_and_round_trip() {
    let e = Env::new_with_config(EnvTestConfig { capture_snapshot_at_drop: false });
    e.mock_all_auths();
    let admin = Address::generate(&e);
    let operator = Address::generate(&e);
    let buyer = Address::generate(&e);

    let id = e.register(
        wasm::WASM,
        (
            admin.clone(),
            operator.clone(),
            String::from_str(&e, "Bodega Demo"),
            String::from_str(&e, "BDEMO"),
            String::from_str(&e, "https://api.drinksonchain.test/v1/nft/bodega-demo/"),
        ),
    );
    let client = wasm::Client::new(&e, &id);

    assert_eq!(client.mint_batch(&admin, &100, &String::from_str(&e, "CVJ26SGR001"), &admin), 99);
    client.operator_transfer(&admin, &buyer, &57, &operator);
    assert_eq!(client.owner_of(&57), buyer);
    client.redeem_burn(&57, &operator);
    assert!(client.try_owner_of(&57).is_err());
    assert_eq!(client.balance(&admin), 99);
    assert_eq!(client.total_minted(), 100);
    assert_eq!(
        client.token_uri(&1),
        String::from_str(&e, "https://api.drinksonchain.test/v1/nft/bodega-demo/1")
    );
}

/// Informe de costes estimados por operación sobre el WASM real, con las
/// tarifas de pubnet que trae `soroban-sdk` (instantánea de 2024-12 ajustada a
/// p23) y los límites de recursos de una transacción de mainnet. Orientativo:
/// no incluye el tamaño de la transacción ni la comisión base.
/// `cargo test -p winery-nft --features wasm-tests cost_report -- --nocapture`
#[test]
fn cost_report() {
    let e = Env::new_with_config(EnvTestConfig { capture_snapshot_at_drop: false });
    // `Env` aplica por defecto los límites de recursos de mainnet por
    // transacción: si una operación los superase, la prueba fallaría.
    e.mock_all_auths();
    let admin = Address::generate(&e);
    let operator = Address::generate(&e);
    let buyer = Address::generate(&e);
    let lot = String::from_str(&e, "CVJ26SGR001");
    let id = e.register(
        wasm::WASM,
        (
            admin.clone(),
            operator.clone(),
            String::from_str(&e, "Bodega Demo"),
            String::from_str(&e, "BDEMO"),
            String::from_str(&e, "https://api.drinksonchain.test/v1/nft/bodega-demo/"),
        ),
    );
    let client = wasm::Client::new(&e, &id);

    let report = |label: &str| {
        let fee = e.cost_estimate().fee();
        let res = e.cost_estimate().resources();
        std::println!(
            "| {label} | {} | {} | {} | {} | {:.5} |",
            res.instructions,
            res.write_entries,
            fee.persistent_entry_rent,
            fee.total,
            fee.total as f64 / 10_000_000.0
        );
    };

    std::println!("| Operación | Instrucciones | Entradas escritas | Renta (stroops) | Total (stroops) | Total (XLM) |");
    std::println!("|---|---|---|---|---|---|");
    client.mint_batch(&admin, &1, &lot, &admin);
    report("mint_batch de 1");
    client.mint_batch(&admin, &100, &lot, &admin);
    report("mint_batch de 100");
    client.mint_batch(&admin, &1_000, &lot, &admin);
    report("mint_batch de 1.000");
    client.mint_batch(&admin, &32_000, &lot, &admin);
    report("mint_batch de 32.000 (máximo)");
    client.operator_transfer(&admin, &buyer, &50, &operator);
    report("operator_transfer (primera venta)");
    client.operator_transfer(&admin, &buyer, &51, &operator);
    report("operator_transfer (siguiente del lote)");
    client.redeem_burn(&50, &operator);
    report("redeem_burn");
    client.owner_of(&20_000);
    report("owner_of (lectura, peor caso)");
    client.pause(&operator);
    report("pause");
}
