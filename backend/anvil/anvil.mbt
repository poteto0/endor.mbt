///|
/// The Anvil backend: a local [Anvil](https://getfoundry.sh/anvil/overview)
/// node, reached through a fake wallet injected at `globalThis.ethereum`.
///
/// Anvil is itself a wallet — its dev accounts are unlocked, so the node
/// answers `eth_accounts`, `eth_sendTransaction` and the signing methods with
/// no key management on this side. Only the `wallet_*` methods, which have no
/// node-side counterpart, are emulated by the shim in `js.mbt`.
pub struct Anvil {}

///|
pub impl @backend.Backend for Anvil with fn name(_) {
  "anvil"
}

///|
pub impl @backend.Backend for Anvil with fn endpoint(_) {
  endpoint()
}

///|
pub impl @backend.Backend for Anvil with fn install(_, endpoint) {
  install_wallet(endpoint)
}

///|
/// Run `body` against a `BrowserProvider` backed by Anvil, or skip when
/// `ENDOR_E2E_RPC_URL` is unset.
///
/// ```
/// async test "chain id" {
///   @anvil.on(provider => assert_eq(
///     @provider.chain_id(provider),
///     @anvil.chain_id(),
///   ))
/// }
/// ```
pub async fn on(body : async (@browser.BrowserProvider) -> Unit) -> Unit {
  @backend.run(Anvil::{  }, () => {
    let provider = @browser.BrowserProvider::require() catch {
      e => fail("the anvil wallet shim did not install: \{e}")
    }
    body(provider)
  })
}

///|
/// Anvil's default chain id, 31337.
pub fn chain_id() -> @types.ChainId {
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
pub fn dev_account() -> @types.Address {
  account("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266")
}

///|
pub fn other_account() -> @types.Address {
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
pub fn answer_contract_runtime() -> @types.Hex {
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
pub async fn deploy_answer_contract(
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
pub async fn wait_mined(
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
