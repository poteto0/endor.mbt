///|
using @element {
  div,
  p,
  h2,
  span,
  button,
  text,
  text_dyn,
  events,
  render_to,
  type DomNode,
}

///|
using @resource {signal}

///|
/// The four values the page shows. Keeping them as signals lets the connect
/// flow below stay plain SDK code: it assigns domain values and Luna re-renders
/// the fields that changed.
struct WalletView {
  status : @signals.Signal[String]
  provider_name : @signals.Signal[String]
  address : @signals.Signal[String]
  balance : @signals.Signal[String]
  chain : @signals.Signal[String]
}

///|
const PLACEHOLDER = "—"

///|
fn WalletView::new() -> WalletView {
  {
    status: signal("Not connected yet."),
    provider_name: signal(PLACEHOLDER),
    address: signal(PLACEHOLDER),
    balance: signal(PLACEHOLDER),
    chain: signal(PLACEHOLDER),
  }
}

///|
fn WalletView::clear(self : WalletView, status~ : String) -> Unit {
  self.status.set(status)
  self.provider_name.set(PLACEHOLDER)
  self.address.set(PLACEHOLDER)
  self.balance.set(PLACEHOLDER)
  self.chain.set(PLACEHOLDER)
}

///|
/// Connect to the injected wallet and publish what it reports.
///
/// This is the end-to-end path the SDK exists for: `BrowserProvider` finds
/// `globalThis.ethereum`, then the typed RPC layer turns `eth_requestAccounts`
/// and `eth_chainId` into `Address` / `ChainId` values.
async fn WalletView::connect(self : WalletView) -> Unit {
  self.clear(status="Waiting for the wallet…")
  try {
    let wallet = @browser.BrowserProvider::require()
    self.provider_name.set(
      if wallet.is_metamask() {
        "MetaMask"
      } else {
        "EIP-1193 provider"
      },
    )
    // `request_accounts` prompts and raises rather than returning an empty
    // array, so an empty one means the wallet broke its own contract.
    guard @provider.request_accounts(wallet).get(0) is Some(addr) else {
      raise @provider.ProviderError::internal("wallet returned no accounts")
    }
    self.address.set(addr.to_string())
    self.balance.set(@provider.balance(wallet, addr).to_bigint().to_string())
    let chain_id = @provider.chain_id(wallet)
    self.chain.set("\{chain_id.to_uint64()} (\{chain_id.to_hex()})")
    self.status.set("Connected.")
  } catch {
    NotInstalled =>
      self.clear(status="MetaMask not detected — install it and reload.")
    UserRejected => self.clear(status="Request rejected in the wallet.")
    e => self.clear(status="Error: \{e}")
  }
}

///|
/// One labelled row of the card.
fn field(label : String, value : @signals.Signal[String]) -> DomNode {
  div(class="field") <| [
    span(class="label") <| [
      text(label),
    ],
    span(class="value") <| [
      text_dyn(() => value.get()),
    ],
  ]
}

///|
fn wallet_card() -> DomNode {
  let view = WalletView::new()
  div(class="card") <| [
    h2() <| [
      text("Wallet"),
    ],
    p(class="status") <| [
      text_dyn(() => view.status.get()),
    ],
    field("Provider", view.provider_name),
    field("Address", view.address),
    field("Balance", view.balance),
    field("Chain id", view.chain),
    // Wallets gate `eth_requestAccounts` behind a user gesture, so the flow is
    // started from the click rather than on load.
    button(
      class="connect",
      on=events().click(_ => @js.spawn(() => view.connect())),
    ) <| [
      text("Connect wallet"),
    ],
  ]
}

///|
fn main {
  match @dom.document().getElementById("app") {
    Some(root) => render_to(root, wallet_card())
    None => println("[endor] #app element not found")
  }
}
