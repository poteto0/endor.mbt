///|
using @element {
  div,
  p,
  h2,
  span,
  button,
  input,
  text,
  text_dyn,
  for_each,
  events,
  render_to,
  type DomNode,
}

///|
using @resource {signal}

///|
/// Everything the page shows or reads back. Keeping it as signals lets the
/// flows below stay plain SDK code: they assign domain values and Luna
/// re-renders the fields that changed.
struct WalletView {
  status : @signals.Signal[String]
  provider_name : @signals.Signal[String]
  address : @signals.Signal[String]
  balance : @signals.Signal[String]
  chain : @signals.Signal[String]
  /// The last transaction this page broadcast, once there is one.
  tx : @signals.Signal[String]
  /// What the two send inputs currently hold. They are read back on submit
  /// rather than parsed while typing, so a half-typed address is not an error
  /// yet.
  to_input : @signals.Signal[String]
  amount_input : @signals.Signal[String]
  /// What EIP-6963 answered the last time the page asked, for the picker to
  /// draw. Empty until the user asks, and empty again once they have picked —
  /// the SDK does not remember the choice, and neither does this list.
  wallets : @signals.Signal[Array[@browser.DiscoveredWallet]]
  /// The event subscriptions this page holds while connected. The SDK keeps no
  /// state, so the page is what turns "the wallet changed" into new signal
  /// values — and what stops listening again.
  mut watching : Array[@provider.Subscription]
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
    tx: signal(PLACEHOLDER),
    to_input: signal(""),
    amount_input: signal(""),
    wallets: signal([]),
    watching: [],
  }
}

///|
fn WalletView::clear(self : WalletView, status~ : String) -> Unit {
  self.stop_watching()
  self.status.set(status)
  self.provider_name.set(PLACEHOLDER)
  self.address.set(PLACEHOLDER)
  self.balance.set(PLACEHOLDER)
  self.chain.set(PLACEHOLDER)
  self.tx.set(PLACEHOLDER)
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
/// Re-read the account after the wallet moved under us. An event is nobody's
/// click, so a failure here is reported in the status line rather than raised.
async fn WalletView::resync(
  self : WalletView,
  wallet : @browser.BrowserProvider,
  addr : @endor.Address,
) -> Unit {
  self.show(wallet, addr) catch {
    e => self.status.set("Error: \{e}")
  }
}

///|
/// Subscribe to what the wallet does on its own: the account the user picks in
/// the extension, the chain they switch to elsewhere, the provider going away.
///
/// This is what the SDK being stateless means in practice — the current account
/// and chain live in these signals. `Subscription` is a plain handle, so
/// wrapping it in this page's lifecycle is the page's business.
fn WalletView::watch(
  self : WalletView,
  wallet : @browser.BrowserProvider,
) -> Unit {
  self.stop_watching()
  self.watching = [
    @provider.on_accounts_changed(wallet, accounts => {
      match accounts.get(0) {
        // most recently selected first: the user picked another account
        Some(addr) => {
          self.status.set("Account changed in the wallet.")
          @js.spawn(() => self.resync(wallet, addr))
        }
        // empty ⇒ the user revoked this dapp's access, which is not `disconnect`
        None => self.clear(status="The wallet revoked this dapp's access.")
      }
    }),
    @provider.on_chain_changed(wallet, chain => {
      // everything on screen was read from the old chain, so re-read it all
      self.status.set("Chain changed to \{chain.to_uint64()}.")
      @js.spawn(() => {
        // `accounts` never prompts, so re-reading costs no popup
        let accounts = @provider.accounts(wallet) catch { _ => [] }
        if accounts.get(0) is Some(addr) {
          self.resync(wallet, addr)
        }
      })
    }),
    @provider.on_disconnect(wallet, error => {
      self.clear(status="The wallet disconnected: \{error}")
    }),
  ]
}

///|
/// Stop listening — every subscription this page holds, cancelled once.
fn WalletView::stop_watching(self : WalletView) -> Unit {
  for sub in self.watching {
    sub.unsubscribe()
  }
  self.watching = []
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
    self.connect_with(wallet, name=injected_name(wallet))
  } catch {
    @provider.NotInstalled(_) =>
      self.clear(status="MetaMask not detected — install it and reload.")
    e => self.clear(status="Error: \{e}")
  }
}

///|
/// What to call a wallet that never announced itself: `globalThis.ethereum`
/// carries no name, so all the page has to go on is whether it says MetaMask.
fn injected_name(wallet : @browser.BrowserProvider) -> String {
  if wallet.is_metamask() {
    "MetaMask"
  } else {
    "EIP-1193 provider"
  }
}

///|
/// Ask EIP-6963 which wallets are installed, rather than taking whichever one
/// won the injection race.
///
/// `discover` waits out its deadline and answers with what announced; when
/// nothing did, the one entry is `globalThis.ethereum` with no `info` on it.
async fn WalletView::detect_wallets(self : WalletView) -> Unit {
  self.status.set("Asking installed wallets to announce themselves…")
  let found = @browser.BrowserProvider::discover()
  self.wallets.set(found)
  self.status.set(
    match found.length() {
      0 => "No wallet at all — install one and reload."
      1 => "One wallet. Pick it to connect."
      n => "\{n} wallets. Pick one to connect."
    },
  )
}

///|
/// Connect to the wallet the user picked out of the EIP-6963 list.
///
/// `wallet.provider` is a `BrowserProvider` like any other, so everything past
/// this line is the same code the plain connect button runs.
async fn WalletView::connect_to(
  self : WalletView,
  wallet : @browser.DiscoveredWallet,
) -> Unit {
  let name = match wallet.info {
    Some(info) => info.name
    None => injected_name(wallet.provider)
  }
  self.clear(status="Waiting for \{name}…")
  // the choice is not remembered: the list is drawn again the next time the
  // user asks, which is what the SDK being stateless costs and buys
  self.wallets.set([])
  self.connect_with(wallet.provider, name~)
}

///|
/// Everything past "which provider": ask for an account, publish it, and start
/// watching the wallet.
async fn WalletView::connect_with(
  self : WalletView,
  wallet : @browser.BrowserProvider,
  name~ : String,
) -> Unit {
  try {
    self.provider_name.set(name)
    let addr = @provider.require_account(wallet)
    self.show(wallet, addr)
    self.watch(wallet)
    self.status.set(
      if wallet.has_events() {
        "Connected. Watching the wallet for changes."
      } else {
        // subscribing to such a wallet is inert, not fatal
        "Connected. This wallet pushes no events, so the fields only update on a click."
      },
    )
  } catch {
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
    // `accounts` never prompts, so this costs no popup
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
/// Parse a human amount ("0.01", "1", ".5") into the smallest unit of a currency
/// with `decimals` decimal places, or `None` when it is not one it can carry.
///
/// `Wei::from_units` raises: an amount finer than the currency carries is
/// refused rather than rounded. What is added here is the option — a form
/// re-parses on every keystroke, and a half-typed amount is not worth a `try`.
fn units_of_decimal(amount : String, decimals : Int) -> BigInt? {
  Some(@endor.Wei::from_units(amount.trim().to_owned(), decimals~).to_bigint()) catch {
    _ => None
  }
}

///|
/// The same parse, for the chain's own currency: 1 ETH is 10^18 wei, and
/// `from_ether` is `from_units` with that filled in.
fn wei_of_ether(amount : String) -> @endor.Wei? {
  Some(@endor.Wei::from_ether(amount.trim().to_owned())) catch {
    _ => None
  }
}

///|
/// Send the amount in the form to the address in the form.
///
/// `WalletClient::send` prompts the wallet and answers with a `TxHash` —
/// broadcast, not yet mined. Both fields are parsed into domain types *before*
/// the wallet is touched, so a typo costs no prompt.
async fn WalletView::send(self : WalletView) -> Unit {
  // out of the `try` below, so that block catches only the client's errors
  let wallet = @browser.BrowserProvider::require() catch {
    _ => {
      self.clear(status="MetaMask not detected — install it and reload.")
      return
    }
  }
  // both fields parsed before the wallet is touched, so a typo costs no prompt
  let to = @endor.Address::from_string(self.to_input.get().trim().to_owned()) catch {
    _ => {
      self.status.set("Recipient is not a valid address.")
      return
    }
  }
  guard wei_of_ether(self.amount_input.get()) is Some(value) else {
    self.status.set("Amount must be a decimal number, e.g. 0.01.")
    return
  }
  // `accounts` never prompts, so this costs no popup — and it keeps the
  // Connect button the one thing that establishes the connection
  let connected = @provider.accounts(wallet) catch { _ => [] }
  guard connected.get(0) is Some(who) else {
    self.status.set("Connect the wallet first.")
    return
  }
  try {
    self.status.set("Confirm the transaction in the wallet…")
    let account = @wallet.JsonRpcAccount::new(wallet, who)
    let hash = @wallet.WalletClient::new(wallet, account).send(to~, value~)
    self.tx.set(hash.to_string())
    self.status.set("Broadcast. It still has to be mined.")
    // re-reading right away usually still shows the old balance: the sender is
    // poorer by the value plus the fee only once mined
    self.resync(wallet, who)
  } catch {
    @wallet.Provider(@provider.UserRejected) =>
      self.status.set("Transaction rejected in the wallet.")
    e => self.status.set("Error: \{e}")
  }
}

///|
/// The wallet and the account it has connected, or `None` when the page is not
/// connected yet.
///
/// Both reads belong to the provider, so their errors are re-raised as `Rpc`:
/// that is what lets each token flow below cover its whole path — connect,
/// call, prompt — with a single `try`.
async fn connected() -> (@browser.BrowserProvider, @endor.Address)? raise @contract.ContractError {
  try {
    let wallet = @browser.BrowserProvider::require()
    // `accounts` never prompts, so asking costs no popup
    match @provider.accounts(wallet).get(0) {
      Some(who) => Some((wallet, who))
      None => None
    }
  } catch {
    e => raise Rpc(e)
  }
}

///|
/// Render `units` of a currency with `decimals` decimal places back as a
/// human-readable amount — the inverse of `units_of_decimal`, and
/// `Wei::to_units` underneath.
fn decimal_of_units(units : BigInt, decimals : Int) -> String {
  @endor.Wei::from_bigint(units).to_units(decimals~)
}

///|
/// The ERC-20 half of the page: a token address, what the contract says about
/// itself, and a transfer.
///
/// The ABI layer end to end. Nothing here builds calldata or reads hex, and the
/// only conversion left is between the token's smallest unit and the digits a
/// human types — which needs `decimals`, read from the token itself.
struct TokenView {
  status : @signals.Signal[String]
  /// What the contract says it is: name, symbol and decimals in one line.
  label : @signals.Signal[String]
  balance : @signals.Signal[String]
  tx : @signals.Signal[String]
  token_input : @signals.Signal[String]
  to_input : @signals.Signal[String]
  amount_input : @signals.Signal[String]
  /// The token last loaded and the decimals its amounts are scaled by. Held
  /// because every later action needs both, and re-reading `decimals()` before
  /// each one would be a round trip to say what cannot change.
  mut loaded : (@erc20.Erc20, Int)?
}

///|
fn TokenView::new() -> TokenView {
  {
    status: signal("No token loaded."),
    label: signal(PLACEHOLDER),
    balance: signal(PLACEHOLDER),
    tx: signal(PLACEHOLDER),
    token_input: signal(""),
    to_input: signal(""),
    amount_input: signal(""),
    loaded: None,
  }
}

///|
/// Read the connected account's balance of `token` and show it scaled.
async fn TokenView::show_balance(
  self : TokenView,
  wallet : @browser.BrowserProvider,
  token : @erc20.Erc20,
  decimals : Int,
  who : @endor.Address,
) -> Unit raise @contract.ContractError {
  self.balance.set(decimal_of_units(token.balance_of(wallet, who), decimals))
}

///|
/// Ask the address in the form what token it is, and what the connected account
/// holds of it.
///
/// Four `eth_call`s, no prompt and no gas, which is why a dapp can do this the
/// moment an address is typed. An address that is not an ERC-20 answers
/// something the return types cannot be read out of, and that arrives as `Abi`.
async fn TokenView::load(self : TokenView) -> Unit {
  try {
    guard connected() is Some((wallet, who)) else {
      self.status.set("Connect the wallet first.")
      return
    }
    let at = @endor.Address::from_string(
      self.token_input.get().trim().to_owned(),
    ) catch {
      _ => {
        self.status.set("Token address is not a valid address.")
        return
      }
    }
    self.status.set("Reading the token…")
    let token = @erc20.Erc20::new(at)
    let decimals = token.decimals(wallet)
    self.label.set(
      "\{token.name(wallet)} (\{token.symbol(wallet)}), \{decimals} decimals",
    )
    self.loaded = Some((token, decimals))
    self.show_balance(wallet, token, decimals, who)
    self.status.set("Token loaded.")
  } catch {
    Rpc(NotInstalled) =>
      self.status.set("MetaMask not detected — install it and reload.")
    Abi(e) => self.status.set("That address is not an ERC-20: \{e}")
    e => self.status.set("Error: \{e}")
  }
}

///|
/// Move tokens, which is `transfer(address,uint256)` and therefore a prompt.
///
/// The amount is scaled by the token's own `decimals` before it goes anywhere:
/// "1.5" of a 6-decimal token is 1500000 units, and getting that wrong by a
/// factor of a million is the classic ERC-20 mistake.
async fn TokenView::send(self : TokenView) -> Unit {
  try {
    guard self.loaded is Some((token, decimals)) else {
      self.status.set("Load a token first.")
      return
    }
    guard connected() is Some((wallet, from)) else {
      self.status.set("Connect the wallet first.")
      return
    }
    let to = @endor.Address::from_string(self.to_input.get().trim().to_owned()) catch {
      _ => {
        self.status.set("Recipient is not a valid address.")
        return
      }
    }
    guard units_of_decimal(self.amount_input.get(), decimals) is Some(amount) else {
      self.status.set("Amount must be a decimal number the token can carry.")
      return
    }
    self.status.set("Confirm the transfer in the wallet…")
    let hash = token.transfer(wallet, from~, to~, amount~)
    self.tx.set(hash.to_string())
    self.status.set("Broadcast. The balance moves once it is mined.")
    self.show_balance(wallet, token, decimals, from)
  } catch {
    Rpc(NotInstalled) =>
      self.status.set("MetaMask not detected — install it and reload.")
    Rpc(UserRejected) => self.status.set("Transfer rejected in the wallet.")
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
    field("Last tx", view.tx),
    // wallets gate `eth_requestAccounts` behind a user gesture, so this starts
    // from the click rather than on load
    button(
      class="connect",
      on=events().click(_ => @js.spawn(() => view.connect())),
    ) <| [
      text("Connect wallet"),
    ],
    p(class="hint") <| [
      text("…or pick one, when more than one is installed:"),
    ],
    div(class="wallets") <| [
      button(
        class="chain",
        on=events().click(_ => @js.spawn(() => view.detect_wallets())),
      ) <| [
        text("Detect wallets (EIP-6963)"),
      ],
      // redrawn from the signal, so the buttons are whatever announced itself
      for_each(() => view.wallets.get(), (wallet, _) => {
        button(
          class="chain",
          on=events().click(_ => @js.spawn(() => view.connect_to(wallet))),
        ) <| [
          text(
            match wallet.info {
              Some(info) => info.name
              None => "Injected wallet"
            },
          ),
        ]
      }),
    ],
    p(class="hint") <| [
      text("Send the chain's native currency:"),
    ],
    div(class="send") <| [
      // read back on submit, so typing an address never rejects it mid-word
      text_input(class="to", placeholder="0x… recipient", view.to_input),
      text_input(class="amount", placeholder="0.01", view.amount_input),
      button(
        class="chain",
        on=events().click(_ => @js.spawn(() => view.send())),
      ) <| [
        text("Send"),
      ],
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
/// A text input that writes what it holds into `into` as it is typed.
fn text_input(
  class~ : String,
  placeholder~ : String,
  into : @signals.Signal[String],
) -> DomNode {
  input(
    class~,
    type_="text",
    placeholder~,
    on=events().input(e => {
      into.set(@dom.HTMLInputElement::cast_from_element(e.target()).value)
    }),
  )
}

///|
fn token_card() -> DomNode {
  let view = TokenView::new()
  div(class="card") <| [
    h2() <| [
      text("ERC-20 token"),
    ],
    p(class="status") <| [
      text_dyn(() => view.status.get()),
    ],
    field("Token", view.label),
    field("Balance", view.balance),
    field("Last tx", view.tx),
    p(class="hint") <| [
      text("Read a token the connected account holds:"),
    ],
    div(class="send") <| [
      text_input(
        class="to",
        placeholder="0x… token contract",
        view.token_input,
      ),
      button(
        class="chain",
        on=events().click(_ => @js.spawn(() => view.load())),
      ) <| [
        text("Load token"),
      ],
    ],
    p(class="hint") <| [
      text("Transfer it:"),
    ],
    div(class="send") <| [
      text_input(class="to", placeholder="0x… recipient", view.to_input),
      text_input(class="amount", placeholder="1.5", view.amount_input),
      button(
        class="chain",
        on=events().click(_ => @js.spawn(() => view.send())),
      ) <| [
        text("Send tokens"),
      ],
    ],
  ]
}

///|
fn main {
  match @dom.document().getElementById("app") {
    Some(root) =>
      render_to(
        root,
        div() <| [
          wallet_card(),
          token_card(),
        ],
      )
    None => println("[endor] #app element not found")
  }
}
