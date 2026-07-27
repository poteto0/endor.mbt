///|
/// A local [Anvil](https://getfoundry.sh/anvil/overview) node, reached through
/// the fake wallet `js.mbt` injects. An implementation detail of `on`.
priv struct Anvil {}

///|
impl @backend.Backend for Anvil with fn name(_) {
  "anvil"
}

///|
impl @backend.Backend for Anvil with fn endpoint(_) {
  endpoint()
}

///|
impl @backend.Backend for Anvil with fn install(_, endpoint) {
  install_wallet(endpoint, reject_account().to_string())
}

///|
/// Run `body` against a `BrowserProvider` backed by Anvil, or skip when
/// `ENDOR_E2E_RPC_URL` is unset.
///
/// ```mbt check
/// async test "doc: chain id" {
///   @anvil.on(provider => {
///     inspect(@provider.chain_id(provider), content="ChainId(31337)")
///   })
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
/// The account the wallet shim refuses to sign for: a send from it comes back
/// as 4001. A node has no way to decline on the user's behalf, so this is the
/// one wallet-side behaviour the shim fabricates rather than forwards.
pub fn reject_account() -> @types.Address {
  account("0x00000000000000000000000000000000e2ec1053")
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
/// The send is the typed `send_transaction`; waiting for the receipt still
/// goes through `Provider::request`, because receipts are not wrapped yet
/// (#11) and this is exactly the escape hatch that exists for methods the SDK
/// has not typed. Generic over `Provider`, not tied to `BrowserProvider`:
/// deploying a contract is a property of the chain, so a second backend (#19)
/// reuses it as is.
///
/// TODO(#11): delete `wait_mined` in favour of the typed receipt layer.
pub async fn[P : @provider.Provider] deploy_answer_contract(
  provider : P,
) -> @types.Address raise @provider.ProviderError {
  let data = @types.Hex::from_string(ANSWER_CONTRACT_CODE) catch {
    e => abort("bad creation code: \{e}")
  }
  // no `to`: a transaction without a recipient deploys `data`
  let hash = @provider.send_transaction(
    provider,
    @types.TransactionRequest::new(dev_account(), data~),
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
///
/// TODO(#11): delete in favour of the typed receipt layer.
async fn[P : @provider.Provider] wait_mined(
  provider : P,
  tx_hash : @types.TxHash,
) -> Json raise @provider.ProviderError {
  for _ in 0..<50 {
    let receipt = provider.request(
      method_name="eth_getTransactionReceipt",
      params=Json::array([tx_hash.to_json()]),
    )
    if receipt is Object(_) {
      return receipt
    }
    @async.sleep(100) catch {
      e => raise @provider.ProviderError::internal("waiting to be mined: \{e}")
    }
  }
  raise @provider.ProviderError::internal(
    "transaction \{tx_hash} was not mined",
  )
}
