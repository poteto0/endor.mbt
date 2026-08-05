///|
/// The "send the chain's own currency" demo.
///
/// One `send_transaction`, and then the wait that turns a broadcast into a
/// mined fact. Both fields are parsed into domain types before the wallet is
/// touched, so a typo costs no prompt.
using @element {div, type DomNode}

///|
struct View {
  status : @signals.Signal[String]
  from : @signals.Signal[String]
  balance : @signals.Signal[String]
  tx : @signals.Signal[String]
  receipt : @signals.Signal[String]
  to_input : @signals.Signal[String]
  amount_input : @signals.Signal[String]
}

///|
fn View::new() -> View {
  {
    status: @ui.status_of(
      "Connect, then send a little of the chain's own currency.",
    ),
    from: @ui.empty_field(),
    balance: @ui.empty_field(),
    tx: @ui.empty_field(),
    receipt: @ui.empty_field(),
    to_input: @ui.input_of(""),
    amount_input: @ui.input_of(""),
  }
}

///|
/// The wallet and the account it has authorized, without prompting: `accounts`
/// never opens a popup, so asking costs nothing.
async fn connected() -> (@browser.BrowserProvider, @endor.Address)? raise @provider.ProviderError {
  let wallet = @browser.BrowserProvider::require()
  match @provider.accounts(wallet).get(0) {
    Some(who) => Some((wallet, who))
    None => None
  }
}

///|
/// Publish the account and what it holds. Raises rather than reporting, so the
/// flows below can cover their whole path with one `try` — and so calling it
/// from inside one does not widen what that `try` catches to `Error`.
async fn View::read_account(self : View) -> Unit raise @provider.ProviderError {
  guard connected() is Some((wallet, from)) else {
    self.status.set("Not connected — connect a wallet first.")
    return
  }
  self.from.set(from.to_checksum_string())
  let wei = @provider.balance(wallet, from)
  self.balance.set("\{wei.to_ether()} (\{wei.to_bigint()} wei)")
}

///|
/// The same read, behind its own button.
async fn View::refresh(self : View) -> Unit {
  try {
    self.read_account()
    self.status.set("Ready.")
  } catch {
    NotInstalled =>
      self.status.set("No wallet detected — install one and reload.")
    e => self.status.set("Error: \{e}")
  }
}

///|
/// Send, then wait. The prompt is `send_transaction`; the wait is what says
/// whether the chain accepted it.
async fn View::send(self : View) -> Unit {
  // parsed before the wallet is touched, so a typo costs no prompt — and a
  // mistyped checksummed address is caught here rather than by the chain
  let to = @endor.Address::from_string(self.to_input.get().trim().to_owned()) catch {
    _ => {
      self.status.set("Recipient is not a valid address.")
      return
    }
  }
  // the option shape, because this re-parses on every keystroke; the scale is
  // ether's eighteen, which `Wei::from_ether` is `from_units` with filled in
  guard @ui.units_of_decimal(self.amount_input.get(), 18) is Some(units) else {
    self.status.set("Amount must be a decimal number, e.g. 0.001.")
    return
  }
  try {
    guard connected() is Some((wallet, from)) else {
      self.status.set("Not connected — connect a wallet first.")
      return
    }
    self.receipt.set(@ui.PLACEHOLDER)
    self.status.set("Confirm the transaction in the wallet…")
    // no `fee=`, which is `Fee::Auto`: the wallet prices it, and on any
    // post-London chain that means EIP-1559
    let hash = @provider.send_transaction(
      wallet,
      @endor.TransactionRequest::new(
        from,
        to~,
        value=@endor.Wei::from_bigint(units),
      ),
    )
    self.tx.set(hash.to_string())
    self.status.set("Broadcast. Waiting for it to be mined…")
    // polls eth_getTransactionReceipt. A reverted transaction has a receipt
    // too, so the wait succeeding is not the transaction succeeding.
    let receipt = @provider.wait_for_receipt(wallet, hash, timeout=120_000)
    self.receipt.set(
      match receipt.status {
        Success =>
          "success — block \{receipt.block_number}, gas \{receipt.gas_used}"
        Reverted =>
          "reverted in block \{receipt.block_number}, and still paid \{receipt.gas_used} gas"
      },
    )
    self.status.set("Mined.")
    // the sender is poorer by the value plus the fee, and now that the receipt
    // is in, the node will say so
    self.read_account()
  } catch {
    NotInstalled =>
      self.status.set("No wallet detected — install one and reload.")
    UserRejected => self.status.set("Transaction rejected in the wallet.")
    Timeout(why) => self.status.set("Gave up waiting: \{why}")
    e => self.status.set("Error: \{e}")
  }
}

///|
fn View::render(self : View) -> DomNode {
  @ui.card(self.status, [
    @ui.field("From", self.from),
    @ui.field("Balance", self.balance),
    @ui.field("Tx hash", self.tx),
    @ui.field("Receipt", self.receipt),
    @ui.row([
      @ui.action("Read the account", () => @js.spawn(() => self.refresh())),
    ]),
    @ui.row([
      @ui.text_input(placeholder="0x… recipient", self.to_input),
      @ui.text_input(placeholder="0.001", self.amount_input),
      @ui.action("Send", () => @js.spawn(() => self.send())),
    ]),
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
