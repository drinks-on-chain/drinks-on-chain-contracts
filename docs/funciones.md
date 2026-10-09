# Funciones, roles, eventos y errores de `winery-nft`

> Versión 2 · 08-10-2026. Referencia para el backend (firmante e indexador). Código en `contracts/winery-nft/src/`. Un ejemplo real de cada evento (XDR del RPC y decodificado) en [`integracion/eventos/`](../integracion/eventos/).

## Roles

| Rol | Símbolo | Quién lo tiene al crear el contrato | Quién lo concede o revoca |
|---|---|---|---|
| Admin | (admin de `AccessControl`) | Cuenta de la bodega | Transferencia en dos pasos: `transfer_admin_role` + `accept_admin_transfer` |
| Emisor | `minter` | Cuenta de la bodega | El admin (`grant_role` / `revoke_role`) |
| Operador | `operator` | Cuenta de operaciones de la plataforma | El admin (`grant_role` / `revoke_role`) |

Cada función protegida recibe la dirección que actúa como **último parámetro**; el contrato exige su firma (`require_auth`) **y** su rol. Una cuenta con el rol pero sin firma falla; una firma válida de una cuenta sin el rol falla con `Unauthorized` (2000).

## Funciones propias

| Función | Quién | Pausa | Qué hace | Eventos |
|---|---|---|---|---|
| `__constructor(admin, operator, name, symbol, base_uri)` | Quien despliega | — | Guarda metadatos, fija el admin, da `minter` al admin y `operator` al operador. Falla si `admin == operator` | `role_granted` ×2 |
| `mint_batch(to, amount, lot, minter) -> u32` | `minter` | Bloqueada | Emite `amount` (1–32 000) tokens con ids consecutivos a `to`; devuelve el último id. `lot` es la referencia estable del lote, `{lotPrefix}-L{año}-{NNN}` (1–64 bytes; DS-07) | `consecutive_mint`, `lot_minted` |
| `operator_transfer(from, to, token_id, operator)` | `operator` | Bloqueada | Mueve el token de `from` (debe ser su dueño) a `to` sin la firma de `from` | `transfer` |
| `redeem_burn(token_id, operator)` | `operator` | Bloqueada | Quema el token, sea quien sea su dueño | `burn` (con el dueño) |
| `set_token_uri_base(base_uri)` | admin | Permitida | Cambia la URI base (≤ 200 bytes) | `base_uri_updated` |
| `total_minted() -> u32` | Cualquiera | — | Tokens emitidos desde el inicio (quemados incluidos) = siguiente id | — |

## Interfaz estándar (OpenZeppelin, SEP-0050)

| Función | Notas |
|---|---|
| `balance(account) -> u32`, `owner_of(token_id) -> Address`, `token_uri(token_id) -> String`, `name()`, `symbol()` | Lectura. `owner_of` y `token_uri` fallan con 200 si el token no existe o está quemado. `token_uri` = URI base + id |
| `get_approved(token_id)`, `is_approved_for_all(owner, operator)` | Lectura |
| `transfer(from, to, token_id)` | Firma del dueño; bloqueada en pausa. No se usa en el MVP |
| `transfer_from(spender, from, to, token_id)`, `approve(approver, approved, token_id, live_until_ledger)`, `approve_for_all(owner, operator, live_until_ledger)` | Firma del dueño o aprobado; bloqueadas en pausa. No se usan en el MVP |

## Pausa y administración

| Función | Quién | Eventos |
|---|---|---|
| `paused() -> bool` | Cualquiera | — |
| `pause(caller)` | admin **o** `operator` | `paused` |
| `unpause(caller)` | solo admin | `unpaused` |
| `grant_role(account, role, caller)` / `revoke_role(account, role, caller)` | admin (o el admin del rol, si se configura) | `role_granted` / `role_revoked` |
| `renounce_role(role, caller)` | La propia cuenta | `role_revoked` |
| `transfer_admin_role(new_admin, live_until_ledger)` / `accept_admin_transfer()` | admin / nuevo admin | `admin_transfer_initiated` / `admin_transfer_completed` |
| `set_role_admin(role, admin_role)` | admin | `role_admin_changed` |
| `has_role`, `get_admin`, `get_role_member_count`, `get_role_member`, `get_role_admin`, `get_existing_roles` | Cualquiera | — |
| `renounce_admin()` | — | **Desactivada**: falla con 3002 |

## Eventos que lee el indexador

Formato de Soroban (`#[contractevent]`): el primer *topic* es el nombre del evento en `snake_case` (símbolo) y los datos son siempre un **mapa** de símbolo a valor con las claves en orden alfabético (vacío, `{}`, en `paused` y `unpaused`). Direcciones como `Address`, ids y ledgers como `u32`, `lot` y `base_uri` como `String`, roles como `Symbol`.

| Evento | Topics | Datos | Cuándo |
|---|---|---|---|
| `consecutive_mint` | `to` | `from_token_id`, `to_token_id` | `mint_batch` (OpenZeppelin) |
| `lot_minted` | `lot`, `to` | `first_token_id`, `last_token_id`, `minter` | `mint_batch` (propio) |
| `transfer` | `from`, `to` | `token_id` | `operator_transfer`, `transfer`, `transfer_from` |
| `burn` | `from` | `token_id` | `redeem_burn` |
| `approve` | `approver`, `token_id` | `approved`, `live_until_ledger` | `approve` |
| `approve_for_all` | `owner` | `operator`, `live_until_ledger` | `approve_for_all` |
| `paused` / `unpaused` | — | — (mapa vacío) | `pause` / `unpause` |
| `role_granted` / `role_revoked` | `role`, `account` | `caller` | constructor, `grant_role`, `revoke_role`, `renounce_role` |
| `admin_transfer_initiated` / `admin_transfer_completed` | admin actual / nuevo | `new_admin`, `live_until_ledger` / `previous_admin` | transferencia del admin |
| `role_admin_changed` | `role` | `previous_admin_role` (símbolo vacío si no había), `new_admin_role` | `set_role_admin` |
| `base_uri_updated` | — | `base_uri` | `set_token_uri_base` |

Para distinguir una entrega de la plataforma de una transferencia del dueño, el indexador cruza el `transfer` con la transacción (función invocada) o con la intención registrada por el firmante.

## Errores

| Código | Nombre | Origen |
|---|---|---|
| 200 | `NonExistentToken` | Token no emitido o quemado |
| 201 | `IncorrectOwner` | `from` no es el dueño |
| 207 | `InvalidAmount` | `mint_batch` con 0 o más de 32 000 |
| 210–214 | Metadatos sin fijar o demasiado largos | Constructor, `set_token_uri_base` |
| 1000 / 1001 | `EnforcedPause` / `ExpectedPause` | Operación en pausa / reanudar sin pausa |
| 2000 | `Unauthorized` | Cuenta sin el rol necesario |
| 2006–2010 | Otros de control de acceso | Transferencia del admin, roles |
| 3000 | `SameAdminAndOperator` | Constructor |
| 3001 | `InvalidLot` | `lot` vacío o de más de 64 bytes |
| 3002 | `AdminRenounceDisabled` | `renounce_admin` |

Una firma que falta no devuelve código de contrato: la transacción falla en la autorización del host.
