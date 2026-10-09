// Verificación de integración de `winery-nft` contra una red local (O3-SC-1).
//
//   integracion/red-local.sh arrancar
//   (cd integracion && npm ci && node verificar.mjs)
//
// Qué demuestra, con el SDK de JavaScript (`@stellar/stellar-sdk` 17: XDR con
// campos de solo lectura, `toXdr`/`fromXdr` y `bigint`; no vale para ≤ 16):
//   1. Firma separada (DS-18 / S-3): en `mint_batch`, `set_token_uri_base` y
//      `unpause` la entrada de autorización de Soroban la firma la cuenta de
//      la bodega y el sobre lo origina, firma y paga la cuenta de operaciones.
//      La bodega no gasta ni un stroop ni un número de secuencia.
//   2. Una autorización firmada por otra clave falla en la red (FAILED).
//   3. La alternativa fee-bump (interna de la bodega, externa de operaciones).
//   4. Un ejemplo real de cada evento tal como lo devuelve `getEvents`
//      (`eventos/*.json`) y las claves de TTL con `getLedgerEntries`
//      (`claves-ttl.json`), más la extensión del código y de las entradas.
//
// Las claves se generan al vuelo y se descartan: nada secreto se escribe en
// disco ni se imprime. Solo se ejecuta contra una red local (frase de red
// «Standalone»); nunca contra mainnet.
//
// Variables: STELLAR_RPC_URL (http://localhost:8000/rpc), STELLAR_FRIENDBOT_URL
// (la que anuncia el RPC), WASM_PATH (../artefactos/winery_nft.wasm),
// ESCRIBIR_EJEMPLOS=0 para no reescribir los JSON versionados.
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  Address,
  BASE_FEE,
  Contract,
  Keypair,
  Operation,
  SorobanDataBuilder,
  StrKey,
  TransactionBuilder,
  authorizeEntry,
  hash,
  nativeToScVal,
  rpc,
  scValToNative,
  xdr,
} from '@stellar/stellar-sdk';

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, '..');
const RPC_URL = process.env.STELLAR_RPC_URL ?? 'http://localhost:8000/rpc';
const WASM_PATH = process.env.WASM_PATH ?? join(RAIZ, 'artefactos', 'winery_nft.wasm');
const ESCRIBIR = process.env.ESCRIBIR_EJEMPLOS !== '0';
const FRASE_LOCAL = 'Standalone Network ; February 2017';
const DIA_EN_LEDGERS = 17_280;

const versionSdk = JSON.parse(
  readFileSync(join(AQUI, 'node_modules', '@stellar', 'stellar-sdk', 'package.json'), 'utf8'),
).version;
const server = new rpc.Server(RPC_URL, { allowHttp: true });

// ── utilidades ──────────────────────────────────────────────────────────────

const hechos = []; // comprobaciones superadas, para el resumen
const avisos = []; // incompatibilidades del SDK que se han esquivado

function comprobar(condicion, texto) {
  if (!condicion) throw new Error(`Comprobación fallida: ${texto}`);
  hechos.push(texto);
  console.log(`  ✓ ${texto}`);
}

function paso(titulo) {
  console.log(`\n── ${titulo}`);
}

const esperar = (ms) => new Promise((r) => setTimeout(r, ms));

/** Llamada JSON-RPC sin pasar por el SDK: la respuesta exacta del RPC. */
async function rpcCrudo(method, params) {
  const r = await fetch(RPC_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }),
  });
  const cuerpo = await r.json();
  if (cuerpo.error) throw new Error(`${method}: ${JSON.stringify(cuerpo.error)}`);
  return cuerpo.result;
}

/** JSON estable: BigInt como texto y bytes en hexadecimal. */
function aJson(valor) {
  return JSON.stringify(
    valor,
    (_, v) => {
      if (typeof v === 'bigint') return v.toString();
      if (v && v.type === 'Buffer' && Array.isArray(v.data)) return Buffer.from(v.data).toString('hex');
      if (v instanceof Uint8Array) return Buffer.from(v).toString('hex');
      return v;
    },
    2,
  );
}

function escribir(relativa, valor) {
  if (!ESCRIBIR) return;
  const destino = join(AQUI, relativa);
  mkdirSync(dirname(destino), { recursive: true });
  writeFileSync(destino, `${aJson(valor)}\n`);
}

const u32 = (n) => nativeToScVal(n, { type: 'u32' });
const texto = (s) => nativeToScVal(s, { type: 'string' });
const simbolo = (s) => nativeToScVal(s, { type: 'symbol' });
const direccion = (g) => new Address(g).toScVal();

async function saldoYSecuencia(g) {
  const clave = xdr.LedgerKey.account(new xdr.LedgerKeyAccount({ accountId: Keypair.fromPublicKey(g).xdrAccountId() }));
  const r = await rpcCrudo('getLedgerEntries', { keys: [clave.toXdr('base64')] });
  const cuenta = xdr.LedgerEntryData.fromXdr(r.entries[0].xdr, 'base64').value;
  return { saldo: cuenta.balance, secuencia: cuenta.seqNum };
}

/** Envía una transacción ya firmada y espera a que entre en un ledger. */
async function enviar(tx, { esperarFallo = false } = {}) {
  // Reenviar la misma transacción es inocuo (mismo hash): se reintenta si el
  // RPC no pudo entregarla a Core (-32603) o pide esperar; DUPLICATE significa
  // que un intento anterior sí llegó.
  let envio;
  for (let intento = 1; ; intento += 1) {
    try {
      envio = await server.sendTransaction(tx);
      if (envio.status !== 'TRY_AGAIN_LATER') break;
    } catch (e) {
      if (intento >= 5) throw e;
      const aviso = `sendTransaction reintentado: ${e.message ?? JSON.stringify(e)}`;
      if (!avisos.includes(aviso)) avisos.push(aviso);
    }
    if (intento >= 5) break;
    await esperar(1000);
  }
  if (envio.status !== 'PENDING' && envio.status !== 'DUPLICATE') {
    throw new Error(`sendTransaction: ${envio.status} ${envio.errorResult?.toXdr('base64') ?? ''}`);
  }
  for (let i = 0; i < 60; i += 1) {
    await esperar(500);
    let estado;
    let respuesta;
    try {
      respuesta = await server.getTransaction(envio.hash);
      estado = respuesta.status;
    } catch (e) {
      // SDK que no entiende el XDR del protocolo vigente: se anota y se lee el
      // estado de la respuesta sin decodificar.
      const aviso = `rpc.Server.getTransaction no decodifica la respuesta: ${e.message}`;
      if (!avisos.includes(aviso)) avisos.push(aviso);
      respuesta = await rpcCrudo('getTransaction', { hash: envio.hash });
      estado = respuesta.status;
    }
    if (estado === 'NOT_FOUND') continue;
    const crudo = await rpcCrudo('getTransaction', { hash: envio.hash });
    const comision = xdr.TransactionResult.fromXdr(crudo.resultXdr, 'base64').feeCharged;
    if (estado === 'SUCCESS' && esperarFallo) throw new Error(`${envio.hash}: se esperaba FAILED`);
    if (estado !== 'SUCCESS' && !esperarFallo) {
      throw new Error(`${envio.hash}: ${estado} ${crudo.resultXdr}`);
    }
    return { hash: envio.hash, estado, ledger: crudo.ledger, comision, retorno: respuesta.returnValue };
  }
  throw new Error(`${envio.hash}: sin resultado tras 30 s`);
}

async function construir(origen, operacion) {
  const cuenta = await server.getAccount(origen);
  return new TransactionBuilder(cuenta, { fee: BASE_FEE, networkPassphrase: red.passphrase })
    .addOperation(operacion)
    .setTimeout(120)
    .build();
}

async function simular(tx, { credencialesV1 = false } = {}) {
  // Cuarto parámetro (`useUpgradedAuth`, por defecto `true` en el SDK 17): pide
  // al RPC credenciales de dirección v2 (CAP-71); con `false`, las v1 de
  // siempre, que son las que reciben los SDK ≤ 16. La red acepta las dos.
  const sim = await server.simulateTransaction(tx, undefined, undefined, !credencialesV1);
  if (rpc.Api.isSimulationError(sim)) throw new Error(`simulación: ${sim.error}`);
  if (rpc.Api.isSimulationRestore(sim)) throw new Error('simulación: hay entradas archivadas que restaurar');
  return sim;
}

/** Transacción clásica o de Soroban sin autorizaciones de terceros. */
async function ejecutar(firmante, operacion, { soroban = true } = {}) {
  let tx = await construir(firmante.publicKey(), operacion);
  if (soroban) tx = rpc.assembleTransaction(tx, await simular(tx)).build();
  tx.sign(firmante);
  return enviar(tx);
}

/**
 * Firmante con la forma de la custodia del backend (`KeyCustody.sign(ref,
 * payload)`): recibe la preimagen de la autorización y devuelve la firma
 * Ed25519 de su SHA-256 (32 bytes). La clave no sale de aquí.
 */
const firmanteDeCustodia = (clave) => async (preimagen, payload) => {
  if (!Buffer.from(hash(preimagen.toXdr())).equals(Buffer.from(payload))) throw new Error('payload ≠ SHA-256(preimagen)');
  return { signature: clave.sign(payload), publicKey: clave.publicKey() };
};

/**
 * Lo mismo que `authorizeEntry`, a mano: sirve para ver qué bytes se firman y
 * para fabricar una autorización firmada por una clave que no es la de la
 * dirección (prueba negativa; `authorizeEntry` se niega a construirla).
 */
function firmarEntradaAMano(entrada, clave, validaHastaLedger) {
  const { type: tipo, value: credencial } = entrada.credentials;
  const comun = {
    networkId: hash(Buffer.from(red.passphrase)),
    nonce: credencial.nonce,
    signatureExpirationLedger: validaHastaLedger,
    invocation: entrada.rootInvocation,
  };
  // Protocolo 29 (CAP-71): las credenciales `…AddressV2` atan además la firma
  // a la dirección que autoriza; las `…Address` de siempre, no.
  const preimagen =
    tipo === 'sorobanCredentialsAddressV2'
      ? xdr.HashIdPreimage.envelopeTypeSorobanAuthorizationWithAddress(
          new xdr.HashIdPreimageSorobanAuthorizationWithAddress({ ...comun, address: credencial.address }),
        )
      : xdr.HashIdPreimage.envelopeTypeSorobanAuthorization(new xdr.HashIdPreimageSorobanAuthorization(comun));
  const firma = clave.sign(hash(preimagen.toXdr()));
  const firmada = new xdr.SorobanAddressCredentials({
    address: credencial.address,
    nonce: credencial.nonce,
    signatureExpirationLedger: validaHastaLedger,
    signature: nativeToScVal([{ public_key: clave.rawPublicKey(), signature: firma }], {
      type: { public_key: ['symbol', null], signature: ['symbol', null] },
    }),
  });
  return new xdr.SorobanAuthorizationEntry({
    credentials: xdr.SorobanCredentials[tipo](firmada),
    rootInvocation: entrada.rootInvocation,
  });
}

const TIPOS_DE_DIRECCION = ['sorobanCredentialsAddress', 'sorobanCredentialsAddressV2'];
const esCredencialDeDireccion = (entrada) => TIPOS_DE_DIRECCION.includes(entrada.credentials.type);

const direccionDe = (entrada) => Address.fromScAddress(entrada.credentials.value.address).toString();

/**
 * Firma separada: el sobre es de `pagador`; cada entrada de autorización con
 * credenciales de dirección la firma quien diga `firmantes[dirección]` (un
 * `Keypair` o una función de custodia).
 *
 *   1. simular sin firmas (modo de registro) → entradas de autorización;
 *   2. `authorizeEntry(entrada, firmante, ledgerDeCaducidad, fraseDeRed)`;
 *   3. simular otra vez con las entradas firmadas (modo estricto) → huella,
 *      recursos y comisión definitivos (incluye el nonce de la bodega);
 *   4. `assembleTransaction`, firma del sobre con la clave del pagador, envío.
 */
async function prepararConFirmaSeparada(pagador, llamada, firmantes, opciones = {}) {
  const borrador = await construir(pagador.publicKey(), llamada);
  const registro = await simular(borrador, opciones);
  const validaHasta = registro.latestLedger + 100; // ≈ 8 min a 5 s por ledger
  const entradas = registro.result?.auth ?? [];
  const firmadas = [];
  for (const entrada of entradas) {
    if (entrada.credentials.type === 'sorobanCredentialsSourceAccount') {
      firmadas.push(entrada); // credencial de la cuenta de origen: basta la firma del sobre
      continue;
    }
    if (!esCredencialDeDireccion(entrada)) throw new Error(`Credencial no prevista: ${entrada.credentials.type}`);
    const quien = direccionDe(entrada);
    const firmante = firmantes[quien];
    if (!firmante) throw new Error(`Nadie firma la autorización de ${quien}`);
    firmadas.push(await authorizeEntry(entrada, firmante, validaHasta, red.passphrase));
  }
  const operacion = Operation.invokeHostFunction({ func: borrador.operations[0].func, auth: firmadas });
  const conAuth = await construir(pagador.publicKey(), operacion);
  const estricta = await simular(conAuth);
  const tx = rpc.assembleTransaction(conAuth, estricta).build();
  return { tx, entradas, firmadas, validaHasta, estricta, func: borrador.operations[0].func };
}

async function ejecutarConFirmaSeparada(pagador, llamada, firmantes, opciones = {}) {
  const preparado = await prepararConFirmaSeparada(pagador, llamada, firmantes, opciones);
  preparado.tx.sign(pagador);
  return { ...preparado, ...(await enviar(preparado.tx)) };
}

async function leer(contrato, funcion, ...args) {
  const tx = await construir(operaciones.publicKey(), contrato.call(funcion, ...args));
  const sim = await simular(tx);
  return scValToNative(sim.result.retval);
}

// ── red ─────────────────────────────────────────────────────────────────────

paso(`Red local · SDK de JavaScript ${versionSdk} · Node ${process.version}`);
const red = await rpcCrudo('getNetwork');
const versionRpc = await rpcCrudo('getVersionInfo');
if (red.passphrase !== FRASE_LOCAL) {
  throw new Error(`Este script solo se ejecuta en una red local; el RPC anuncia «${red.passphrase}»`);
}
const FRIENDBOT_URL = process.env.STELLAR_FRIENDBOT_URL ?? red.friendbotUrl;
console.log(`  RPC ${versionRpc.version} · protocolo ${red.protocolVersion} · ${red.passphrase}`);
const ledgerInicial = (await rpcCrudo('getLatestLedger')).sequence;

const registro = JSON.parse(readFileSync(join(RAIZ, 'deployments', 'testnet.json'), 'utf8'));
const wasm = readFileSync(WASM_PATH);
const hashWasm = createHash('sha256').update(wasm).digest('hex');
comprobar(hashWasm === registro.wasm.hash, `el WASM local (${wasm.length} bytes) es el de testnet: ${hashWasm}`);

// ── cuentas (claves al vuelo, nunca en disco) ───────────────────────────────

paso('Cuentas');
const operaciones = Keypair.random(); // paga todo; rol `operator`; despliega
const bodega = Keypair.random(); // admin y `minter`; solo firma autorizaciones
const bodegaNueva = Keypair.random(); // recibe la administración al final
const intruso = Keypair.random(); // firma lo que no debe
const consumidor = Keypair.random().publicKey(); // dirección custodial: no existe en la red ni firma (A-28)

for (let i = 0; ; i += 1) {
  const r = await fetch(`${FRIENDBOT_URL}?addr=${operaciones.publicKey()}`);
  if (r.ok) break;
  if (i >= 60) throw new Error(`Friendbot: ${r.status}`);
  await esperar(1000);
}
// Como en el backend (CREATE_WINERY_ACCOUNT, S-6): operaciones crea la cuenta
// de la bodega con 2 XLM. Debe existir para que `require_auth` la acepte.
for (const cuenta of [bodega, bodegaNueva]) {
  await ejecutar(operaciones, Operation.createAccount({ destination: cuenta.publicKey(), startingBalance: '2' }), {
    soroban: false,
  });
}
const bodegaAlCrear = await saldoYSecuencia(bodega.publicKey());
comprobar(bodegaAlCrear.saldo === 20_000_000n, 'la cuenta de la bodega nace con 2 XLM, creada por operaciones');

// ── código y contrato ───────────────────────────────────────────────────────

paso('Código y contrato');
const subida = await ejecutar(operaciones, Operation.uploadContractWasm({ wasm }));
comprobar(
  Buffer.from(scValToNative(subida.retorno)).toString('hex') === hashWasm,
  `el código se sube sin cambios en el protocolo ${red.protocolVersion} y la red devuelve el mismo hash`,
);

// Sal determinista del backend (S-2): entorno + bodega + código.
const entorno = 'local';
const wineryId = '00000000-0000-4000-8000-000000000001';
const sal = Buffer.from(hash(Buffer.from(`drinks-on-chain/winery-nft/${entorno}/${wineryId}/${hashWasm}`)));
const uriBase = 'http://localhost:4000/v1/public/nft/destileria-cinti-viejo/';
const despliegue = await ejecutar(
  operaciones,
  Operation.createCustomContract({
    address: new Address(operaciones.publicKey()),
    wasmHash: Buffer.from(hashWasm, 'hex'),
    salt: sal,
    constructorArgs: [
      direccion(bodega.publicKey()),
      direccion(operaciones.publicKey()),
      texto('Destilería Cinti Viejo'),
      texto('CVJ'),
      texto(uriBase),
    ],
  }),
);
const idContrato = Address.fromScVal(despliegue.retorno).toString();
const contrato = new Contract(idContrato);
// La dirección se puede calcular antes de desplegar (idempotencia).
const idPrevisto = StrKey.encodeContract(
  hash(
    xdr.HashIdPreimage.envelopeTypeContractId(
      new xdr.HashIdPreimageContractId({
        networkId: hash(Buffer.from(red.passphrase)),
        contractIdPreimage: xdr.ContractIdPreimage.contractIdPreimageFromAddress(
          new xdr.ContractIdPreimageFromAddress({ address: new Address(operaciones.publicKey()).toScAddress(), salt: sal }),
        ),
      }),
    ).toXdr(),
  ),
);
comprobar(idContrato === idPrevisto, `contrato ${idContrato} en la dirección derivada del desplegador y la sal`);
comprobar((await leer(contrato, 'get_admin')) === bodega.publicKey(), 'get_admin = cuenta de la bodega');
comprobar(
  (await leer(contrato, 'has_role', direccion(operaciones.publicKey()), simbolo('operator'))) !== undefined,
  'operaciones tiene el rol operator',
);

// ── 1. firma separada ───────────────────────────────────────────────────────

paso('Firma separada: mint_batch (autoriza la bodega, paga operaciones)');
const lote = 'CVJ-L2026-004'; // referencia estable del lote (S-12)
const cantidad = 100;
const antesDeEmitir = await saldoYSecuencia(operaciones.publicKey());
const emision = await ejecutarConFirmaSeparada(
  operaciones,
  contrato.call('mint_batch', direccion(bodega.publicKey()), u32(cantidad), texto(lote), direccion(bodega.publicKey())),
  { [bodega.publicKey()]: firmanteDeCustodia(bodega) },
);
comprobar(
  emision.entradas.length === 1 && esCredencialDeDireccion(emision.entradas[0]) && direccionDe(emision.entradas[0]) === bodega.publicKey(),
  `la simulación pide una sola autorización, con credenciales de dirección de la bodega (${emision.entradas[0].credentials.type})`,
);
comprobar(emision.tx.source === operaciones.publicKey(), 'el origen del sobre es operaciones');
comprobar(
  emision.tx.signatures.length === 1 && Buffer.from(emision.tx.signatures[0].hint.toXdr()).equals(Buffer.from(operaciones.signatureHint())),
  'el sobre lleva una sola firma, la de operaciones',
);
comprobar(scValToNative(emision.retorno) === cantidad - 1, `mint_batch confirmado: devuelve el último id (${cantidad - 1})`);
const trasEmitir = await saldoYSecuencia(operaciones.publicKey());
comprobar(antesDeEmitir.saldo - trasEmitir.saldo === emision.comision, `la comisión (${emision.comision} stroops) sale de operaciones`);
comprobar((await leer(contrato, 'total_minted')) === cantidad, `total_minted = ${cantidad}`);
comprobar((await leer(contrato, 'balance', direccion(bodega.publicKey()))) === cantidad, `balance(bodega) = ${cantidad}`);

paso('Firma separada: set_token_uri_base (autoriza la bodega con un Keypair)');
const uriNueva = 'http://localhost:4000/v1/public/nft/cinti-viejo/';
await ejecutarConFirmaSeparada(operaciones, contrato.call('set_token_uri_base', texto(uriNueva)), {
  [bodega.publicKey()]: bodega,
});
comprobar((await leer(contrato, 'token_uri', u32(7))) === `${uriNueva}7`, 'token_uri(7) usa la URI nueva');
{
  const v1 = await ejecutarConFirmaSeparada(operaciones, contrato.call('set_token_uri_base', texto(uriNueva)), { [bodega.publicKey()]: bodega }, { credencialesV1: true });
  comprobar(
    v1.entradas[0].credentials.type === 'sorobanCredentialsAddress',
    'la firma separada también funciona con credenciales v1 (useUpgradedAuth = false), las de los SDK ≤ 16',
  );
}

paso('Pausa (operaciones, credencial de origen) y firma separada: unpause (bodega)');
const pausa = await prepararConFirmaSeparada(operaciones, contrato.call('pause', direccion(operaciones.publicKey())), {});
comprobar(
  pausa.entradas.length === 1 && !esCredencialDeDireccion(pausa.entradas[0]),
  'pause(operaciones) no necesita firma de autorización: credencial de la cuenta de origen',
);
pausa.tx.sign(operaciones);
await enviar(pausa.tx);
comprobar((await leer(contrato, 'paused')) === true, 'contrato pausado');
await ejecutarConFirmaSeparada(operaciones, contrato.call('unpause', direccion(bodega.publicKey())), {
  [bodega.publicKey()]: firmanteDeCustodia(bodega),
});
comprobar((await leer(contrato, 'paused')) === false, 'contrato reanudado con la autorización de la bodega');

const bodegaTrasFirmar = await saldoYSecuencia(bodega.publicKey());
comprobar(
  bodegaTrasFirmar.saldo === bodegaAlCrear.saldo && bodegaTrasFirmar.secuencia === bodegaAlCrear.secuencia,
  'tras tres autorizaciones, la bodega conserva su saldo (2 XLM) y su número de secuencia',
);

// ── 2. pruebas negativas ────────────────────────────────────────────────────

paso('Autorización inválida');
const llamadaExtra = contrato.call('mint_batch', direccion(bodega.publicKey()), u32(1), texto('CVJ-L2026-005'), direccion(bodega.publicKey()));
{
  // Sin firmar: la simulación estricta ya la rechaza (no se llega a enviar).
  const borrador = await construir(operaciones.publicKey(), llamadaExtra);
  const sinFirmar = (await simular(borrador)).result.auth;
  const tx = await construir(operaciones.publicKey(), Operation.invokeHostFunction({ func: borrador.operations[0].func, auth: sinFirmar }));
  const sim = await server.simulateTransaction(tx);
  comprobar(rpc.Api.isSimulationError(sim), 'una entrada de autorización sin firmar no pasa la simulación');
}
{
  // Firmada por otra clave, con la huella y los recursos de una válida: la
  // red la incluye, cobra la comisión a operaciones y la marca FAILED.
  const valido = await prepararConFirmaSeparada(operaciones, llamadaExtra, { [bodega.publicKey()]: bodega });
  const falsa = valido.entradas.map((e) => firmarEntradaAMano(e, intruso, valido.validaHasta));
  const conFalsa = await construir(operaciones.publicKey(), Operation.invokeHostFunction({ func: valido.func, auth: falsa }));
  const tx = rpc.assembleTransaction(conFalsa, valido.estricta).build(); // conserva la autorización que ya lleva
  tx.sign(operaciones);
  const r = await enviar(tx, { esperarFallo: true });
  comprobar(r.estado === 'FAILED', 'una autorización firmada por otra clave acaba en FAILED en la red');
  comprobar((await leer(contrato, 'total_minted')) === cantidad, 'y no emite nada');
  // La firma a mano con la clave correcta equivale a authorizeEntry.
  const aMano = valido.entradas.map((e) => firmarEntradaAMano(e, bodega, valido.validaHasta));
  comprobar(
    aMano[0].toXdr('base64') === valido.firmadas[0].toXdr('base64'),
    `authorizeEntry firma el SHA-256 de la HashIdPreimage de la autorización (${valido.entradas[0].credentials.type}): reproducido a mano`,
  );
}

// ── eventos restantes ───────────────────────────────────────────────────────

paso('Entrega, quema, roles y aprobaciones (para los ejemplos de eventos)');
const op = (funcion, ...args) => contrato.call(funcion, ...args);
const yo = direccion(operaciones.publicKey());
const deLaBodega = { [bodega.publicKey()]: bodega };
const caducidad = (await rpcCrudo('getLatestLedger')).sequence + DIA_EN_LEDGERS;
await ejecutarConFirmaSeparada(operaciones, op('operator_transfer', direccion(bodega.publicKey()), direccion(consumidor), u32(0), yo), {});
await ejecutarConFirmaSeparada(operaciones, op('operator_transfer', direccion(bodega.publicKey()), direccion(consumidor), u32(2), yo), {});
await ejecutarConFirmaSeparada(operaciones, op('redeem_burn', u32(0), yo), {});
comprobar((await leer(contrato, 'owner_of', u32(2))) === consumidor, 'operator_transfer entrega a una dirección que no existe como cuenta');
await ejecutarConFirmaSeparada(operaciones, op('grant_role', direccion(intruso.publicKey()), simbolo('minter'), direccion(bodega.publicKey())), deLaBodega);
await ejecutarConFirmaSeparada(operaciones, op('revoke_role', direccion(intruso.publicKey()), simbolo('minter'), direccion(bodega.publicKey())), deLaBodega);
await ejecutarConFirmaSeparada(operaciones, op('approve', direccion(bodega.publicKey()), yo, u32(1), u32(caducidad)), deLaBodega);
await ejecutarConFirmaSeparada(operaciones, op('approve_for_all', direccion(bodega.publicKey()), yo, u32(caducidad)), deLaBodega);
await ejecutarConFirmaSeparada(operaciones, op('set_role_admin', simbolo('minter'), simbolo('operator')), deLaBodega);

// ── 3. alternativa fee-bump ─────────────────────────────────────────────────

paso('Alternativa fee-bump: interna de la bodega, externa de operaciones');
{
  const antes = await saldoYSecuencia(bodega.publicKey());
  const llamada = contrato.call('mint_batch', direccion(bodega.publicKey()), u32(3), texto('CVJ-L2026-006'), direccion(bodega.publicKey()));
  const borrador = await construir(bodega.publicKey(), llamada);
  const interna = rpc.assembleTransaction(borrador, await simular(borrador)).build();
  interna.sign(bodega);
  const externa = TransactionBuilder.buildFeeBumpTransaction(operaciones, BASE_FEE, interna, red.passphrase);
  externa.sign(operaciones);
  await enviar(externa);
  const despues = await saldoYSecuencia(bodega.publicKey());
  comprobar(despues.saldo === antes.saldo, 'fee-bump: la bodega tampoco paga');
  comprobar(BigInt(despues.secuencia) === BigInt(antes.secuencia) + 1n, 'fee-bump: pero consume un número de secuencia de la bodega');
  comprobar((await leer(contrato, 'total_minted')) === cantidad + 3, 'fee-bump: emisión confirmada');
}

// ── 4. claves de TTL y extensión ────────────────────────────────────────────

paso('Claves de TTL (getLedgerEntries) y extensión');
const claveDeContrato = (clave) =>
  xdr.LedgerKey.contractData(
    new xdr.LedgerKeyContractData({
      contract: new Address(idContrato).toScAddress(),
      key: clave,
      durability: xdr.ContractDataDurability.persistent,
    }),
  );
const variante = (nombre, valor) => xdr.ScVal.scvVec([simbolo(nombre), valor]);
const claves = {
  instancia: claveDeContrato(xdr.ScVal.scvLedgerKeyContractInstance()),
  codigo: xdr.LedgerKey.contractCode(new xdr.LedgerKeyContractCode({ hash: Buffer.from(hashWasm, 'hex') })),
  'Owner(2) · token vendido': claveDeContrato(variante('Owner', u32(2))),
  'Owner(1) · id anterior a la entrega': claveDeContrato(variante('Owner', u32(1))),
  'Owner(99) · último id del lote': claveDeContrato(variante('Owner', u32(cantidad - 1))),
  'OwnershipBucket(0) · ids 0–3199': claveDeContrato(variante('OwnershipBucket', u32(0))),
  'Balance(bodega)': claveDeContrato(variante('Balance', direccion(bodega.publicKey()))),
  'Balance(consumidor)': claveDeContrato(variante('Balance', direccion(consumidor))),
  'BurnedToken(0)': claveDeContrato(variante('BurnedToken', u32(0))),
};

async function leerTtl() {
  const nombres = Object.keys(claves);
  const r = await rpcCrudo('getLedgerEntries', { keys: nombres.map((n) => claves[n].toXdr('base64')) });
  const porClave = new Map(r.entries.map((e) => [e.key, e]));
  return {
    ledger: r.latestLedger,
    entradas: Object.fromEntries(
      nombres.map((n) => {
        const e = porClave.get(claves[n].toXdr('base64'));
        return [n, e ? e.liveUntilLedgerSeq : null];
      }),
    ),
  };
}

const ttlAntes = await leerTtl();
for (const [nombre, hasta] of Object.entries(ttlAntes.entradas)) {
  comprobar(hasta !== null, `${nombre}: existe, vive ${((hasta - ttlAntes.ledger) / DIA_EN_LEDGERS).toFixed(1)} días`);
}

async function extender(nombres, ledgers) {
  const huella = new SorobanDataBuilder().setReadOnly(nombres.map((n) => claves[n])).build();
  const cuenta = await server.getAccount(operaciones.publicKey());
  const borrador = new TransactionBuilder(cuenta, { fee: BASE_FEE, networkPassphrase: red.passphrase })
    .addOperation(Operation.extendFootprintTtl({ extendTo: ledgers }))
    .setSorobanData(huella)
    .setTimeout(120)
    .build();
  const tx = rpc.assembleTransaction(borrador, await simular(borrador)).build();
  tx.sign(operaciones);
  return enviar(tx);
}

// P-SC-6: el código se extiende por su cuenta, con su clave en la huella de
// solo lectura. `extendTo` son ledgers contados desde el actual.
const extensionCodigo = await extender(['codigo'], 150 * DIA_EN_LEDGERS);
const extensionDatos = await extender(
  ['instancia', 'Owner(2) · token vendido', 'Owner(1) · id anterior a la entrega', 'Owner(99) · último id del lote', 'OwnershipBucket(0) · ids 0–3199', 'Balance(bodega)', 'Balance(consumidor)'],
  120 * DIA_EN_LEDGERS,
);
const ttlDespues = await leerTtl();
const dias = (n) => (ttlDespues.entradas[n] - ttlDespues.ledger) / DIA_EN_LEDGERS;
comprobar(dias('codigo') > 149.9, `extendFootprintTtl sobre el código: ahora vive ${dias('codigo').toFixed(1)} días (${extensionCodigo.comision} stroops)`);
comprobar(
  dias('instancia') > 119.9 && dias('Owner(2) · token vendido') > 119.9 && dias('Balance(consumidor)') > 119.9,
  `extendFootprintTtl sobre instancia, dueños, cubo y saldos: 120 días (${extensionDatos.comision} stroops)`,
);
comprobar(
  ttlDespues.entradas['BurnedToken(0)'] === ttlAntes.entradas['BurnedToken(0)'],
  'BurnedToken(0) no se toca (S-21)',
);

// ── administración en dos pasos (al final: cambia el admin) ─────────────────

paso('Transferencia de la administración');
await ejecutarConFirmaSeparada(operaciones, op('transfer_admin_role', direccion(bodegaNueva.publicKey()), u32(caducidad)), deLaBodega);
await ejecutarConFirmaSeparada(operaciones, op('accept_admin_transfer'), { [bodegaNueva.publicKey()]: bodegaNueva });
comprobar((await leer(contrato, 'get_admin')) === bodegaNueva.publicKey(), 'el admin nuevo acepta con su autorización; paga operaciones');

// ── ejemplos de eventos ─────────────────────────────────────────────────────

paso('Eventos (getEvents)');
const respuestaEventos = await rpcCrudo('getEvents', {
  startLedger: ledgerInicial,
  filters: [{ type: 'contract', contractIds: [idContrato] }],
  pagination: { limit: 200 },
});
const porNombre = new Map();
for (const evento of respuestaEventos.events) {
  const topics = evento.topic.map((t) => scValToNative(xdr.ScVal.fromXdr(t, 'base64')));
  const nombre = topics[0];
  const ejemplo = {
    evento: nombre,
    rpc: evento,
    decodificado: { topics, value: scValToNative(xdr.ScVal.fromXdr(evento.value, 'base64')) },
  };
  if (!porNombre.has(nombre)) porNombre.set(nombre, []);
  porNombre.get(nombre).push(ejemplo);
}
const esperados = [
  'role_granted', 'consecutive_mint', 'lot_minted', 'base_uri_updated', 'paused', 'unpaused', 'transfer', 'burn',
  'role_revoked', 'approve', 'approve_for_all', 'role_admin_changed', 'admin_transfer_initiated', 'admin_transfer_completed',
];
for (const nombre of esperados) {
  const ejemplos = porNombre.get(nombre) ?? [];
  comprobar(ejemplos.length > 0, `${nombre}: ${ejemplos.length} evento(s)`);
  // Un ejemplo por archivo; el primero de cada tipo (en `role_granted`, el del
  // constructor) y, si hay más, el resto en `otros`.
  escribir(`eventos/${nombre}.json`, { ...ejemplos[0], otros: ejemplos.slice(1).map(({ rpc: r, decodificado }) => ({ rpc: r, decodificado })) });
}
const loteEmitido = porNombre.get('lot_minted')[0];
comprobar(
  loteEmitido.decodificado.topics[1] === lote && loteEmitido.decodificado.value.first_token_id === 0 && loteEmitido.decodificado.value.last_token_id === cantidad - 1,
  `lot_minted lleva la referencia del lote (${lote}) y el rango 0–${cantidad - 1}`,
);
comprobar(loteEmitido.rpc.txHash === emision.hash, 'el evento trae el hash de la transacción que lo originó (txHash)');

const { events: _eventos, ...paginacion } = respuestaEventos;
escribir('eventos/_red.json', {
  nota: 'Generado por integracion/verificar.mjs en una red local efímera; las direcciones no existen en ninguna otra red.',
  imagen: process.env.IMAGEN_RED_LOCAL ?? null,
  red: red.passphrase,
  protocolo: red.protocolVersion,
  rpc: versionRpc.version,
  sdkJs: versionSdk,
  wasmHash: hashWasm,
  contrato: idContrato,
  cuentas: { operaciones: operaciones.publicKey(), bodega: bodega.publicKey(), bodegaNueva: bodegaNueva.publicKey(), consumidor, otra: intruso.publicKey() },
  respuestaGetEventsSinEventos: paginacion,
});
escribir('claves-ttl.json', {
  nota: 'Claves de ledger de un contrato winery-nft tal como las acepta getLedgerEntries (LedgerKey en XDR base64). Durabilidad persistente. Ledgers de 5 s: 17 280 por día.',
  contrato: idContrato,
  forma: {
    instancia: 'LedgerKey::ContractData { contract, key: ScVal::LedgerKeyContractInstance, durability: Persistent }',
    codigo: 'LedgerKey::ContractCode { hash: wasmHash }',
    'Owner(id)': 'ContractData con key = ScVal::Vec([Symbol("Owner"), U32(id)])',
    'OwnershipBucket(i)': 'ContractData con key = ScVal::Vec([Symbol("OwnershipBucket"), U32(i)]); i = id / 3200',
    'Balance(dirección)': 'ContractData con key = ScVal::Vec([Symbol("Balance"), Address(dirección)])',
    'BurnedToken(id)': 'ContractData con key = ScVal::Vec([Symbol("BurnedToken"), U32(id)])',
  },
  claves: Object.fromEntries(
    Object.entries(claves).map(([n, k]) => [
      n,
      {
        ledgerKeyXdr: k.toXdr('base64'),
        diasDeVidaTrasElRecorrido: Number(((ttlAntes.entradas[n] - ttlAntes.ledger) / DIA_EN_LEDGERS).toFixed(1)),
        diasDeVidaTrasExtender: Number(dias(n).toFixed(1)),
      },
    ]),
  ),
});

// ── resumen ─────────────────────────────────────────────────────────────────

paso('Resumen');
console.log(`  ${hechos.length} comprobaciones superadas · SDK ${versionSdk} · protocolo ${red.protocolVersion}`);
for (const aviso of avisos) console.log(`  ! ${aviso}`);
if (ESCRIBIR) console.log('  Ejemplos escritos en integracion/eventos/ e integracion/claves-ttl.json');
