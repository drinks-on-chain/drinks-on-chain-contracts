use soroban_sdk::contracterror;

/// Errores propios del contrato. Empiezan en 3000 para no chocar con los de
/// OpenZeppelin (NFT 200–214, pausa 1000–1001, control de acceso 2000–2010).
#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[repr(u32)]
pub enum WineryNftError {
    /// La bodega (admin) y la plataforma (operador) no pueden ser la misma
    /// cuenta.
    SameAdminAndOperator = 3000,
    /// El identificador del lote está vacío o supera `MAX_LOT_LEN` bytes.
    InvalidLot = 3001,
    /// Renunciar a la administración dejaría el contrato sin nadie que pueda
    /// reanudarlo ni gestionar roles: está desactivado.
    AdminRenounceDisabled = 3002,
}
