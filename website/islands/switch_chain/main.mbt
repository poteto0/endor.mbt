///|
/// The "switch chains" demo.
///
/// One call per button. `switch_or_add_chain` sends
/// `wallet_switchEthereumChain`, and when the wallet answers 4902 — it does not
/// know that chain — adds it from the same `ChainParams` and switches again.
/// That fallback is the part every dapp otherwise writes by hand, and there is
/// no 4902 handling anywhere in this file.
using @element {div, type DomNode}

///|
/// A chain a button moves the wallet to, described well enough (EIP-3085) that
/// a wallet which has never seen it can add it.
struct Chain {
  label : String
  params : @endor.ChainParams
}

///|
/// The `ChainId` presets save spelling the ids out; the rest of each entry only
/// matters on the 4902 path.
fn chains() -> Array[Chain] {
  let ether = @endor.NativeCurrency::new(name="Ether", symbol="ETH")
  let pol = @endor.NativeCurrency::new(name="POL", symbol="POL")
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
        native_currency=pol,
        block_explorer_urls=["https://polygonscan.com"],
      ),
    },
  ]
}

///|
struct View {
  status : @signals.Signal[String]
  chain : @signals.Signal[String]
  balance : @signals.Signal[String]
  mut watching : Array[@provider.Subscription]
}

///|
fn View::new() -> View {
  {
    status: @ui.status_of("Pick a chain. Your wallet will ask before moving."),
    chain: @ui.empty_field(),
    balance: @ui.empty_field(),
    watching: [],
  }
}

///|
/// Where the wallet is now, and what the account holds there. Every chain has
/// its own balances, so the second field is what makes a switch visible.
async fn View::read_chain(self : View) -> Unit raise @provider.ProviderError {
  let wallet = @browser.BrowserProvider::require()
  let chain = @provider.chain_id(wallet)
  self.chain.set("\{chain.to_uint64()} (\{chain.to_hex()})")
  match @provider.accounts(wallet).get(0) {
    Some(who) => {
      let wei = @provider.balance(wallet, who)
      self.balance.set("\{wei.to_bigint()} wei")
    }
    None => self.balance.set("not connected")
  }
  self.listen(wallet)
}

///|
/// A chain can also change from inside the wallet, with no button involved.
/// `chainChanged` is how the page learns that everything it read is about
/// another chain now.
fn View::listen(self : View, wallet : @browser.BrowserProvider) -> Unit {
  guard self.watching.is_empty() else { return }
  self.watching = [
    @provider.on_chain_changed(wallet, chain => {
      self.chain.set("\{chain.to_uint64()} (\{chain.to_hex()})")
      self.status.set("The wallet moved to chain \{chain.to_uint64()}.")
      @js.spawn(() => {
        self.read_chain() catch {
          e => self.status.set("Error: \{e}")
        }
      })
    }),
  ]
}

///|
async fn View::refresh(self : View) -> Unit {
  try {
    self.read_chain()
    self.status.set("Read.")
  } catch {
    NotInstalled =>
      self.status.set("No wallet detected — install one and reload.")
    e => self.status.set("Error: \{e}")
  }
}

///|
async fn View::switch_to(self : View, chain : Chain) -> Unit {
  try {
    let wallet = @browser.BrowserProvider::require()
    self.status.set("Switching to \{chain.label}…")
    @provider.switch_or_add_chain(wallet, chain.params)
    self.read_chain()
    self.status.set("Now on \{chain.label}.")
  } catch {
    NotInstalled =>
      self.status.set("No wallet detected — install one and reload.")
    UserRejected => self.status.set("Rejected in the wallet.")
    e => self.status.set("Error: \{e}")
  }
}

///|
fn View::render(self : View) -> DomNode {
  @ui.card(self.status, [
    @ui.field("Chain id", self.chain),
    @ui.field("Balance here", self.balance),
    @ui.row([
      @ui.action("Read the chain", () => @js.spawn(() => self.refresh())),
    ]),
    @ui.row(
      chains().map(chain => {
        @ui.action(chain.label, () => @js.spawn(() => self.switch_to(chain)))
      }),
    ),
  ])
}

///|
pub fn hydrate(el : @dom.Element, _state : @jsc.Any) -> Unit {
  @element.render_to(
    el,
    div() <| [
      View::new().render(),
    ],
  )
}

///|
/// Standalone entry point — see `connect/main.mbt`.
fn main {
  if @dom.document().getElementById("endor-demo") is Some(el) {
    hydrate(el, @jsc.any("standalone"))
  }
}
