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
/// Deploy creation code from the unlocked dev account and answer with the
/// address it was mined at.
///
/// Both halves are the typed API — `send_transaction` then `wait_for_receipt`
/// — with no `to`, since a transaction without a recipient deploys `data`.
/// Generic over `Provider`, not tied to `BrowserProvider`: deploying a contract
/// is a property of the chain, so a second backend (#19) reuses it as is.
///
/// Anvil automines, so the receipt is normally there on the first poll; the
/// interval is short and the timeout small so a node that is not mining fails
/// the test rather than holding the suite for a minute.
///
/// Shared by `deploy_answer_contract` and `deploy_selector_gate`: both are
/// this same deploy-and-locate mechanism applied to different bytecode, so it
/// is written once here rather than once per contract.
async fn[P : @provider.Provider] deploy_creation_code(
  provider : P,
  data : @types.Hex,
) -> @types.Address raise @provider.ProviderError {
  let hash = @provider.send_transaction(
    provider,
    @types.TransactionRequest::new(dev_account(), data~),
  )
  let receipt = @provider.wait_for_receipt(
    provider,
    hash,
    timeout=5_000,
    poll_interval=100,
  )
  guard receipt.contract_address is Some(deployed) else {
    raise @provider.ProviderError::internal("receipt has no contractAddress")
  }
  deployed
}

///|
/// Deploy `ANSWER_CONTRACT_CODE` from the unlocked dev account and return its
/// address, once mined.
pub async fn[P : @provider.Provider] deploy_answer_contract(
  provider : P,
) -> @types.Address raise @provider.ProviderError {
  let data = @types.Hex::from_string(ANSWER_CONTRACT_CODE) catch {
    e => abort("bad creation code: \{e}")
  }
  deploy_creation_code(provider, data)
}

///|
/// A contract that answers `42` for exactly one function selector and reverts
/// for every other — the negative half `deploy_answer_contract` cannot give.
///
/// The answer contract ignores its calldata, so a call reaching it proves the
/// SDK produced *some* well-formed transaction; it cannot prove the SDK
/// produced the *right* one. This one dispatches: the four bytes it was
/// deployed for are the only four bytes it accepts, so a caller whose selector
/// is wrong by one bit gets a revert from a real EVM rather than a passing
/// test. That is what makes it worth deploying a contract to check a hash.
///
/// ```mbt check
/// async test "doc: selector gate" {
///   @anvil.on(provider => {
///     // the selector of `totalSupply()`
///     let sel = @types.Hex::from_string("0x18160ddd")
///     let at = @anvil.deploy_selector_gate(provider, sel)
///     inspect(@provider.is_contract(provider, at), content="true")
///   })
/// }
/// ```
pub async fn[P : @provider.Provider] deploy_selector_gate(
  provider : P,
  selector : @types.Hex,
) -> @types.Address raise @provider.ProviderError {
  guard selector.byte_length() == 4 else {
    raise @provider.ProviderError::internal(
      "a selector is four bytes, got \{selector}",
    )
  }
  let data = @types.Hex::from_digits(
    SELECTOR_GATE_INIT + selector.digits() + SELECTOR_GATE_BODY,
  ) catch {
    e => abort("bad gate code: \{e}")
  }
  deploy_creation_code(provider, data)
}

///|
/// The two halves of the selector gate's creation code, with the four selector
/// bytes spliced between them.
///
/// The initcode is the same shape as the answer contract's — `CODECOPY` the
/// runtime out of itself and return it — for a runtime of `0x1e` bytes at
/// offset `0x0c`. The runtime is:
///
/// ```text
/// 6000 35        CALLDATALOAD(0)      the first word of the calldata
/// 60e0 1c        SHR(0xe0)            keep its top four bytes: the selector
/// 63 ssssssss    PUSH4 <selector>     the one this gate was deployed for
/// 14             EQ
/// 6013 57        JUMPI(0x13)          equal → the JUMPDEST below
/// 6000 80 fd     REVERT(0, 0)         otherwise: no such function here
/// 5b             JUMPDEST
/// 602a 6000 52   MSTORE(0, 42)
/// 6020 6000 f3   RETURN(0, 32)        one word holding 42
/// ```
/// Digits, not a `Hex`: neither half is a byte string on its own, and the
/// selector goes between them. `Hex::from_digits` puts the `0x` back once the
/// three are one.
const SELECTOR_GATE_INIT : String = "601e600c600039601e6000f360003560e01c63"

///|
const SELECTOR_GATE_BODY : String = "14601357600080fd5b602a600052602060" +
  "00f3"
