///|
/// The "read an ERC-20" demo.
///
/// Four `eth_call`s, no prompt and no gas: reads cost the reader nothing, which
/// is why this demo is safe to leave on a page. Nothing here builds calldata or
/// reads hex — `Erc20` turns `balanceOf` into a `BigInt` and `decimals` into an
/// `Int`, and the only conversion left is the one between a token's smallest
/// unit and the digits a human reads.
using @element {div, type DomNode}

///|
struct View {
  status : @signals.Signal[String]
  token : @signals.Signal[String]
  supply : @signals.Signal[String]
  holder : @signals.Signal[String]
  balance : @signals.Signal[String]
  token_input : @signals.Signal[String]
}

///|
fn View::new() -> View {
  {
    status: @ui.status_of("Paste a token contract and read it."),
    token: @ui.empty_field(),
    supply: @ui.empty_field(),
    holder: @ui.empty_field(),
    balance: @ui.empty_field(),
    // USDC on Ethereum mainnet, so the demo has something to read out of the box
    token_input: @ui.input_of("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"),
  }
}

///|
/// Everything the token says about itself, plus what the connected account
/// holds of it. Raises, so the flow below covers connect, call and decode with
/// one `try`.
async fn View::read(
  self : View,
  token : @endor.Address,
) -> Unit raise @contract.ContractError {
  let wallet = @browser.BrowserProvider::require() catch { e => raise Rpc(e) }
  let erc20 = @erc20.Erc20::new(token)
  // `decimals` is what every amount below is scaled by, so it is read first
  let decimals = erc20.decimals(wallet)
  self.token.set(
    "\{erc20.name(wallet)} (\{erc20.symbol(wallet)}), \{decimals} decimals",
  )
  self.supply.set(@ui.decimal_of_units(erc20.total_supply(wallet), decimals))
  // `accounts` never prompts, so a reader who has not connected still gets the
  // token's own answers — only the balance needs to know who is asking
  let who = @provider.accounts(wallet) catch { e => raise Rpc(e) }
  match who.get(0) {
    Some(addr) => {
      self.holder.set(addr.to_checksum_string())
      self.balance.set(
        @ui.decimal_of_units(erc20.balance_of(wallet, addr), decimals),
      )
    }
    None => {
      self.holder.set("not connected")
      self.balance.set(@ui.PLACEHOLDER)
    }
  }
}

///|
async fn View::load(self : View) -> Unit {
  let token = @endor.Address::from_string(
    self.token_input.get().trim().to_owned(),
  ) catch {
    _ => {
      self.status.set("That is not a valid contract address.")
      return
    }
  }
  self.status.set("Reading the token…")
  try {
    self.read(token)
    self.status.set(
      "Read. No prompt, no gas — every call above was an eth_call.",
    )
  } catch {
    // the wallet could not answer, or answered an error
    Rpc(e) => self.status.set("The wallet said: \{e}")
    // it answered, but not with what an ERC-20 returns — most often because
    // that address holds no contract, or holds one that is not a token
    Abi(e) =>
      self.status.set("That address does not answer like an ERC-20: \{e}")
    e => self.status.set("Error: \{e}")
  }
}

///|
fn View::render(self : View) -> DomNode {
  @ui.card(self.status, [
    @ui.field("Token", self.token),
    @ui.field("Total supply", self.supply),
    @ui.field("Holder", self.holder),
    @ui.field("Balance", self.balance),
    @ui.row([
      @ui.text_input(placeholder="0x… token contract", self.token_input),
      @ui.action("Read the token", () => @js.spawn(() => self.load())),
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
