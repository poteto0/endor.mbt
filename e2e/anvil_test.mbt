///|
/// The endpoint the suite runs against, from `ENDOR_E2E_RPC_URL`
/// (`just e2e` sets it). Empty when unset, and then every test skips.
extern "js" fn rpc_url() -> String =
  #| () => (globalThis.process && globalThis.process.env
  #|         && globalThis.process.env.ENDOR_E2E_RPC_URL) || ""

///|
/// Install a fake injected wallet at `globalThis.ethereum` forwarding EIP-1193
/// requests to Anvil over HTTP JSON-RPC. Anvil's dev accounts are unlocked, so
/// the node answers everything except the two `wallet_*` methods, which have no
/// node-side counterpart and are emulated here.
///
/// Why a shim rather than a headless extension, and what that does and does not
/// prove: `docs/e2e.md`.
extern "js" fn install_wallet(rpc_url : String) -> Unit =
  #| (rpcUrl) => {
  #|   // tests share one JS context and run concurrently, so the wallet is
  #|   // installed once and never removed
  #|   if (globalThis.ethereum) return
  #|   let nextId = 0
  #|   const call = async (method, params) => {
  #|     const res = await fetch(rpcUrl, {
  #|       method: 'POST',
  #|       headers: { 'content-type': 'application/json' },
  #|       body: JSON.stringify({ jsonrpc: '2.0', id: ++nextId, method, params }),
  #|     })
  #|     if (!res.ok) throw { code: -32603, message: `HTTP ${res.status} from ${rpcUrl}` }
  #|     const body = await res.json()
  #|     if (body.error) {
  #|       throw {
  #|         code: typeof body.error.code === 'number' ? body.error.code : -32603,
  #|         message: String(body.error.message ?? 'rpc error'),
  #|       }
  #|     }
  #|     return body.result === undefined ? null : body.result
  #|   }
  #|   // the node's own chain, asked for once: it cannot change for its lifetime
  #|   let chainId = null
  #|   const currentChain = async () =>
  #|     chainId ??= BigInt(await call('eth_chainId', [])).toString()
  #|   const added = new Set()
  #|   // concurrent tests are otherwise handed the same nonce; a real wallet
  #|   // prompts for one transaction at a time, so serializing is also faithful
  #|   let queue = Promise.resolve()
  #|   const send = (method, args) => {
  #|     const done = queue.then(() => call(method, args))
  #|     queue = done.catch(() => {})
  #|     return done
  #|   }
  #|   globalThis.ethereum = {
  #|     isMetaMask: true,
  #|     request: async ({ method, params }) => {
  #|       const args = params ?? []
  #|       switch (method) {
  #|         case 'eth_requestAccounts':
  #|           return call('eth_accounts', [])
  #|         case 'eth_sendTransaction':
  #|           return send(method, args)
  #|         case 'wallet_addEthereumChain':
  #|           added.add(BigInt(args[0].chainId).toString())
  #|           return null
  #|         case 'wallet_switchEthereumChain': {
  #|           const want = BigInt(args[0].chainId).toString()
  #|           if (added.has(want) || want === await currentChain()) return null
  #|           throw { code: 4902, message: `Unrecognized chain ID ${want}` }
  #|         }
  #|         default:
  #|           return call(method, args)
  #|       }
  #|     },
  #|   }
  #| }

///|
/// Said once when the suite skips, so a green run without a node cannot be
/// mistaken for a green run against one.
let skip_reported : Ref[Bool] = { val: false }

///|
/// Run `body` against a `BrowserProvider` backed by Anvil, or skip when no
/// endpoint is configured. An error from `body` fails the test, so the tests
/// themselves only catch where the error *is* the assertion.
async fn on_anvil(body : async (@browser.BrowserProvider) -> Unit) -> Unit {
  let url = rpc_url()
  if url == "" {
    if !skip_reported.val {
      skip_reported.val = true
      println("e2e: skipped — ENDOR_E2E_RPC_URL is unset (see `just e2e`)")
    }
    return
  }
  install_wallet(url)
  @async.with_task_group(_ => {
    let provider = @browser.BrowserProvider::require() catch {
      e => fail("the anvil wallet shim did not install: \{e}")
    }
    body(provider) catch {
      e => fail("\{e}")
    }
  })
}

///|
/// Anvil's default chain id, 31337.
fn anvil_chain_id() -> @types.ChainId {
  @types.ChainId::new(31337)
}

///|
/// One of the ten funded, unlocked accounts Anvil starts with.
fn account(hex : String) -> @types.Address {
  @types.Address::from_string(hex) catch {
    e => abort("bad dev account: \{e}")
  }
}

///|
fn dev_account() -> @types.Address {
  account("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266")
}

///|
fn other_account() -> @types.Address {
  account("0x70997970C51812dc3A010C7d01b50e0d17dc79C8")
}

///|
/// Creation code of a contract whose runtime always returns the 32-byte word
/// `42`, so `call` / `estimate_gas` / `is_contract` run against real EVM code
/// rather than a mock's answer.
///
/// `600a600c600039600a6000f3` copies the 10 runtime bytes at offset 12 and
/// returns them; the runtime `602a60005260206000f3` stores `0x2a` and returns
/// one word of it.
const ANSWER_CONTRACT_CODE : String = "0x600a600c600039600a6000f3602a60005260206000f3"

///|
/// The runtime `ANSWER_CONTRACT_CODE` leaves on chain.
fn answer_contract_runtime() -> @types.Hex {
  @types.Hex::from_string("0x602a60005260206000f3") catch {
    e => abort("bad runtime code: \{e}")
  }
}

///|
/// Deploy `ANSWER_CONTRACT_CODE` from the unlocked dev account and return its
/// address, once mined.
///
/// Deployment goes through `Provider::request` rather than a typed helper:
/// `eth_sendTransaction` and receipts are not wrapped yet (#10), and this is
/// exactly the escape hatch that exists for methods the SDK has not typed.
async fn deploy_answer_contract(
  provider : @browser.BrowserProvider,
) -> @types.Address raise @provider.ProviderError {
  let tx = Json::object({
    "from": dev_account().to_json(),
    "data": Json::string(ANSWER_CONTRACT_CODE),
  })
  let hash = provider.request(
    method_name="eth_sendTransaction",
    params=Json::array([tx]),
  )
  let receipt = wait_mined(provider, hash)
  guard receipt is Object(fields) && fields.get("contractAddress") is Some(addr) else {
    raise @provider.ProviderError::internal("receipt has no contractAddress")
  }
  @types.Address::from_json(addr) catch {
    e => raise @provider.ProviderError::internal("bad contractAddress: \{e}")
  }
}

///|
/// Poll `eth_getTransactionReceipt` until the transaction is mined. Anvil
/// automines, so the first poll normally answers.
async fn wait_mined(
  provider : @browser.BrowserProvider,
  tx_hash : Json,
) -> Json raise @provider.ProviderError {
  for _ in 0..<50 {
    let receipt = provider.request(
      method_name="eth_getTransactionReceipt",
      params=Json::array([tx_hash]),
    )
    if receipt is Object(_) {
      return receipt
    }
    @async.sleep(100) catch {
      e => raise @provider.ProviderError::internal("waiting to be mined: \{e}")
    }
  }
  raise @provider.ProviderError::internal(
    "transaction \{tx_hash.stringify()} was not mined",
  )
}
