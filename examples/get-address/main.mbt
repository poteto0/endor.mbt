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
/// A chain one of the buttons moves the wallet to, described well enough
/// (EIP-3085) that a wallet which has never seen it can add it.
struct Chain {
  label : String
  params : @endor.ChainParams
}

///|
/// What the buttons offer. The `ChainId` presets save spelling the ids out; the
/// rest of each entry only matters when the wallet answers the switch with
/// 4902 and the chain has to be added first.
fn chains() -> Array[Chain] {
  let ether = @endor.NativeCurrency::new(name="Ether", symbol="ETH")
  [
    {
      label: "Mainnet",
      params: @endor.ChainParams::new(
        @endor.ChainId::mainnet(),
        chain_name="Ethereum Mainnet",
        rpc_urls=["https://eth.llamarpc.com"],
        native_currency=ether,
        block_explorer_urls=["https://etherscan.io"],
      ),
    },
    {
      label: "Sepolia",
      params: @endor.ChainParams::new(
        @endor.ChainId::sepolia(),
        chain_name="Sepolia",
        rpc_urls=["https://ethereum-sepolia-rpc.publicnode.com"],
        native_currency=ether,
        block_explorer_urls=["https://sepolia.etherscan.io"],
      ),
    },
    {
      label: "Polygon",
      params: @endor.ChainParams::new(
        @endor.ChainId::polygon(),
        chain_name="Polygon Mainnet",
        rpc_urls=["https://polygon-rpc.com"],
        native_currency=@endor.NativeCurrency::new(name="POL", symbol="POL"),
        block_explorer_urls=["https://polygonscan.com"],
      ),
    },
  ]
}

///|
/// Publish the account's state on whatever chain the wallet is on now. Both
/// flows below end here, so connecting and switching show the same fields.
async fn WalletView::show(
  self : WalletView,
  wallet : @browser.BrowserProvider,
  addr : @endor.Address,
) -> Unit raise @provider.ProviderError {
  // shown to a human, so the EIP-55 spelling rather than the wire form
  self.address.set(addr.to_checksum_string())
  self.balance.set(@provider.balance(wallet, addr).to_bigint().to_string())
  let chain_id = @provider.chain_id(wallet)
  self.chain.set("\{chain_id.to_uint64()} (\{chain_id.to_hex()})")
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
    let addr = @provider.require_account(wallet)
    self.show(wallet, addr)
    self.status.set("Connected.")
  } catch {
    NotInstalled =>
      self.clear(status="MetaMask not detected — install it and reload.")
    UserRejected => self.clear(status="Request rejected in the wallet.")
    e => self.clear(status="Error: \{e}")
  }
}

///|
/// Move the wallet onto `chain`, then re-read the account there.
///
/// `switch_or_add_chain` is the whole point of this button: a wallet that does
/// not know the chain answers the switch with 4902, and the SDK adds it from
/// `ChainParams` and switches again — no 4902 handling out here.
async fn WalletView::switch_to(self : WalletView, chain : Chain) -> Unit {
  try {
    let wallet = @browser.BrowserProvider::require()
    // `accounts` never prompts, so it tells us whether connecting already
    // happened without opening a second wallet popup.
    guard @provider.accounts(wallet).get(0) is Some(addr) else {
      self.status.set("Connect the wallet first.")
      return
    }
    self.status.set("Switching to \{chain.label}…")
    @provider.switch_or_add_chain(wallet, chain.params)
    self.show(wallet, addr)
    self.status.set("Now on \{chain.label}.")
  } catch {
    NotInstalled =>
      self.clear(status="MetaMask not detected — install it and reload.")
    UserRejected => self.status.set("Chain switch rejected in the wallet.")
    e => self.status.set("Error: \{e}")
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
    p(class="hint") <| [
      text("Switch chain:"),
    ],
    div(class="chains") <| chains().map(chain => {
      button(
        class="chain",
        on=events().click(_ => @js.spawn(() => view.switch_to(chain))),
      ) <| [
        text(chain.label),
      ]
    }),
  ]
}

///|
fn main {
  match @dom.document().getElementById("app") {
    Some(root) => render_to(root, wallet_card())
    None => println("[endor] #app element not found")
  }
}
