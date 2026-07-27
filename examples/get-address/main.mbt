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
  }
}

///|
fn WalletView::clear(self : WalletView, status~ : String) -> Unit {
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
/// How many decimal digits an ether amount has: 1 ETH is 10^18 wei.
const WEI_DIGITS = 18

///|
/// Parse a human amount of the chain's native currency ("0.01", "1", ".5")
/// into wei, or `None` when it is not a decimal number the chain can carry.
///
/// The SDK deals in `Wei` and nothing else — units are a presentation concern,
/// so the conversion lives out here in the UI rather than in `endor/types`.
/// More than 18 decimals is rejected rather than rounded: silently dropping a
/// digit of someone's money is worse than making them retype it.
fn wei_of_ether(amount : String) -> @endor.Wei? {
  let whole = StringBuilder::new()
  let fraction = StringBuilder::new()
  let mut after_point = false
  let mut digits = 0
  for c in amount.trim() {
    if c == '.' {
      guard !after_point else { return None }
      after_point = true
    } else if c.is_ascii_digit() {
      digits += 1
      (if after_point { fraction } else { whole }).write_char(c)
    } else {
      return None
    }
  }
  guard digits > 0 else { return None }
  let scaled = StringBuilder::new()
  scaled.write_string(whole.to_string())
  scaled.write_string(fraction.to_string())
  let padding = WEI_DIGITS - fraction.to_string().length()
  guard padding >= 0 else { return None }
  for _ in 0..<padding {
    scaled.write_char('0')
  }
  // "0" + the digits: `BigInt::from_string` needs at least one, and ".5"
  // legitimately leaves the whole part empty
  Some(@endor.Wei::from_bigint(BigInt::from_string("0" + scaled.to_string())))
}

///|
/// Send the amount in the form to the address in the form.
///
/// The whole point of the button: `send_transaction` prompts the wallet, and
/// what comes back is a `TxHash` — broadcast, not yet mined. Both fields are
/// parsed into domain types *before* the wallet is touched, so a typo costs no
/// prompt; a mistyped checksummed address is caught by `Address::from_string`
/// rather than by the chain.
///
/// No fee is set, which is `Fee::Auto`: the wallet prices the transaction, and
/// on any post-London chain that means EIP-1559.
async fn WalletView::send(self : WalletView) -> Unit {
  try {
    let wallet = @browser.BrowserProvider::require()
    guard @provider.accounts(wallet).get(0) is Some(from) else {
      self.status.set("Connect the wallet first.")
      return
    }
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
    self.status.set("Confirm the transaction in the wallet…")
    let hash = @provider.send_transaction(
      wallet,
      @endor.TransactionRequest::new(from, to~, value~),
    )
    self.tx.set(hash.to_string())
    self.status.set("Broadcast. It still has to be mined.")
    // the sender is poorer by the value plus the fee, once mined — re-reading
    // right away usually still shows the old balance, which is the honest
    // picture until the receipt layer lands
    self.show(wallet, from)
  } catch {
    NotInstalled =>
      self.clear(status="MetaMask not detected — install it and reload.")
    UserRejected => self.status.set("Transaction rejected in the wallet.")
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
    // Wallets gate `eth_requestAccounts` behind a user gesture, so the flow is
    // started from the click rather than on load.
    button(
      class="connect",
      on=events().click(_ => @js.spawn(() => view.connect())),
    ) <| [
      text("Connect wallet"),
    ],
    p(class="hint") <| [
      text("Send the chain's native currency:"),
    ],
    div(class="send") <| [
      // read back on submit, so typing an address never rejects it mid-word
      input(
        class="to",
        type_="text",
        placeholder="0x… recipient",
        on=events().input(e => {
          view.to_input.set(
            @dom.HTMLInputElement::cast_from_element(e.target()).value,
          )
        }),
      ),
      input(
        class="amount",
        type_="text",
        placeholder="0.01",
        on=events().input(e => {
          view.amount_input.set(
            @dom.HTMLInputElement::cast_from_element(e.target()).value,
          )
        }),
      ),
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
fn main {
  match @dom.document().getElementById("app") {
    Some(root) => render_to(root, wallet_card())
    None => println("[endor] #app element not found")
  }
}
