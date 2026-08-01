///|
/// A transaction hash in, its receipt out.
///
/// `eth_getTransactionReceipt` is a read: no prompt, no gas. Paste any hash
/// from the chain your wallet is on. The point of the demo is the `status`
/// field — a transaction that **reverted has a receipt too**, and a page that
/// only checks "did the wait succeed" reports it as a success.
using @element {div, text, type DomNode}

///|
struct View {
  status : @signals.Signal[String]
  block : @signals.Signal[String]
  result : @signals.Signal[String]
  gas : @signals.Signal[String]
  deployed : @signals.Signal[String]
  logs : @signals.Signal[String]
  hash_input : @signals.Signal[String]
}

///|
fn View::new() -> View {
  {
    status: @ui.status_of(
      "Paste a transaction hash from the chain your wallet is on.",
    ),
    block: @ui.empty_field(),
    result: @ui.empty_field(),
    gas: @ui.empty_field(),
    deployed: @ui.empty_field(),
    logs: @ui.empty_field(),
    hash_input: @ui.input_of(""),
  }
}

///|
fn View::clear(self : View) -> Unit {
  self.block.set(@ui.PLACEHOLDER)
  self.result.set(@ui.PLACEHOLDER)
  self.gas.set(@ui.PLACEHOLDER)
  self.deployed.set(@ui.PLACEHOLDER)
  self.logs.set(@ui.PLACEHOLDER)
}

///|
fn View::show(self : View, receipt : @endor.TransactionReceipt) -> Unit {
  self.block.set("\{receipt.block_number} (\{receipt.block_hash})")
  // the field to check. A revert is mined, and paid for.
  self.result.set(
    match receipt.status {
      Success => "Success"
      Reverted => "Reverted — mined, and it still paid for its gas"
    },
  )
  let price = match receipt.effective_gas_price {
    Some(wei) => "\{wei.to_bigint()} wei/gas"
    // a pre-London chain has no such thing to report
    None => "no effective price"
  }
  self.gas.set("\{receipt.gas_used} at \{price}")
  // present exactly when `to` was absent, which is what a deployment is
  self.deployed.set(
    match receipt.contract_address {
      Some(addr) => addr.to_checksum_string()
      None => "not a deployment"
    },
  )
  // `topics[0]` is what `@abi.event_topic` is matched against to pick one
  // event's logs out of the rest
  let transfer = @abi.event_topic("Transfer(address,address,uint256)")
  let transfers = receipt.logs.filter(log => {
    log.topics.get(0) is Some(t) && t == transfer
  })
  self.logs.set(
    "\{receipt.logs.length()} log(s), \{transfers.length()} of them Transfer",
  )
}

///|
async fn View::look_up(self : View) -> Unit {
  let hash = @endor.TxHash::from_string(self.hash_input.get().trim().to_owned()) catch {
    // a `TxHash` is a `Hex` narrowed to exactly 32 bytes, so a hash of the
    // wrong length is refused here rather than by the node
    e => {
      self.status.set("Not a transaction hash: \{e}")
      return
    }
  }
  self.clear()
  self.status.set("Asking the node…")
  try {
    let wallet = @browser.BrowserProvider::require()
    match @provider.transaction_receipt(wallet, hash) {
      Some(receipt) => {
        self.show(receipt)
        self.status.set("Read. No prompt and no gas — a receipt is a read.")
      }
      // `None` is not an error: it says there is no receipt *right now*, which
      // is the normal answer a second after broadcasting
      None =>
        self.status.set(
          "No receipt yet — either still pending, or not a transaction this chain knows.",
        )
    }
  } catch {
    NotInstalled =>
      self.status.set("No wallet detected — install one and reload.")
    e => self.status.set("Error: \{e}")
  }
}

///|
fn View::render(self : View) -> DomNode {
  @ui.card(self.status, [
    @ui.field("Block", self.block),
    @ui.field("status", self.result),
    @ui.field("Gas", self.gas),
    @ui.field("contract_address", self.deployed),
    @ui.field("Logs", self.logs),
    @ui.row([
      @ui.text_input(
        placeholder="0x… 32-byte transaction hash",
        self.hash_input,
      ),
      @ui.action("Read the receipt", () => @js.spawn(() => self.look_up())),
    ]),
    @ui.note([
      text(
        "Reads whatever chain your wallet is currently on, so a mainnet hash " +
        "needs a wallet on mainnet. `transaction_receipt` answers `None` for a " +
        "transaction with no receipt yet; `wait_for_receipt` is the one that waits.",
      ),
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
