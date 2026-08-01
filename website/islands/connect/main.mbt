///|
/// The "connect a wallet" demo.
///
/// `BrowserProvider::require` finds `globalThis.ethereum`, `request_accounts`
/// prompts for permission, and `chain_id` says which chain the answer is about.
/// Everything else on this page is the frame around those three calls.
using @element {div, type DomNode}

///|
/// What the demo publishes. The SDK caches nothing, so these signals are the
/// page's own copy of what the wallet last said — and the events below are the
/// only thing that keeps them true.
struct View {
  status : @signals.Signal[String]
  provider_name : @signals.Signal[String]
  address : @signals.Signal[String]
  chain : @signals.Signal[String]
  mut watching : Array[@provider.Subscription]
}

///|
fn View::new() -> View {
  {
    status: @ui.status_of("Not connected yet."),
    provider_name: @ui.empty_field(),
    address: @ui.empty_field(),
    chain: @ui.empty_field(),
    watching: [],
  }
}

///|
fn View::clear(self : View, status~ : String) -> Unit {
  self.stop_watching()
  self.status.set(status)
  self.provider_name.set(@ui.PLACEHOLDER)
  self.address.set(@ui.PLACEHOLDER)
  self.chain.set(@ui.PLACEHOLDER)
}

///|
/// Publish the account and the chain it was read on.
async fn View::show(
  self : View,
  wallet : @browser.BrowserProvider,
  addr : @endor.Address,
) -> Unit raise @provider.ProviderError {
  // shown to a human, so the EIP-55 spelling rather than the wire form
  self.address.set(addr.to_checksum_string())
  let chain = @provider.chain_id(wallet)
  self.chain.set("\{chain.to_uint64()} (\{chain.to_hex()})")
}

///|
/// The whole recipe: find the wallet, ask for an account, read the chain.
async fn View::connect(self : View) -> Unit {
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
    // eth_requestAccounts, with the "no authorized account" case already an
    // error rather than an empty array to check
    let addr = @provider.require_account(wallet)
    self.show(wallet, addr)
    self.watch(wallet)
    self.status.set(
      if wallet.has_events() {
        "Connected. Watching the wallet for changes."
      } else {
        "Connected. This wallet pushes no events, so the fields only update on a click."
      },
    )
  } catch {
    NotInstalled =>
      self.clear(status="No wallet detected — install one and reload.")
    UserRejected => self.clear(status="Request rejected in the wallet.")
    e => self.clear(status="Error: \{e}")
  }
}

///|
/// Subscribe to what the wallet does on its own. Each handler is a plain
/// callback and each `Subscription` a plain handle, so the page's lifecycle is
/// what unsubscribes — here, the next connect or disconnect.
fn View::watch(self : View, wallet : @browser.BrowserProvider) -> Unit {
  self.stop_watching()
  self.watching = [
    @provider.on_accounts_changed(wallet, accounts => {
      match accounts.get(0) {
        // most recently selected first: the user picked another account
        Some(addr) => {
          self.status.set("Account changed in the wallet.")
          @js.spawn(() => {
            self.show(wallet, addr) catch {
              e => self.status.set("Error: \{e}")
            }
          })
        }
        // empty ⇒ the user revoked this dapp's access, which is not `disconnect`
        None => self.clear(status="The wallet revoked this page's access.")
      }
    }),
    @provider.on_chain_changed(wallet, chain => {
      self.chain.set("\{chain.to_uint64()} (\{chain.to_hex()})")
      self.status.set("Chain changed under us.")
    }),
    @provider.on_disconnect(wallet, error => {
      self.clear(status="The wallet disconnected: \{error}")
    }),
  ]
}

///|
fn View::stop_watching(self : View) -> Unit {
  for sub in self.watching {
    sub.unsubscribe()
  }
  self.watching = []
}

///|
fn View::render(self : View) -> DomNode {
  @ui.card(self.status, [
    @ui.field("Provider", self.provider_name),
    @ui.field("Address", self.address),
    @ui.field("Chain id", self.chain),
    @ui.row([
      @ui.action("Connect wallet", () => @js.spawn(() => self.connect())),
    ]),
  ])
}

///|
/// What astra calls once the island is on screen.
pub fn hydrate(el : @dom.Element, _state : @jsc.Any) -> Unit {
  @element.render_to(
    el,
    div() <| [
      View::new().render(),
    ],
  )
}

///|
/// Standalone entry point. Linking as an ES module needs a main package, and a
/// main package needs a `main`; making it mount on `#endor-demo` is what lets
/// the same artifact be opened in a bare HTML page while working on it, with no
/// site build in between.
fn main {
  if @dom.document().getElementById("endor-demo") is Some(el) {
    hydrate(el, @jsc.any("standalone"))
  }
}
