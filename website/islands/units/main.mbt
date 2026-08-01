///|
/// Where the decimal point goes, and why the SDK will not move it for you.
///
/// The SDK deals in whole smallest units — `Wei` for the chain's own currency,
/// a `BigInt` for a token — because only `decimals` says where the point
/// belongs, and it is read from the token. Scaling is therefore a job for the
/// layer with the text input in it, which is exactly what this widget is.
///
/// Type more decimals than the currency has and it refuses rather than rounds.
using @element {div, type DomNode}

///|
struct View {
  amount : @signals.Signal[String]
  decimals : @signals.Signal[String]
}

///|
fn View::new() -> View {
  { amount: @ui.input_of("0.015"), decimals: @ui.input_of("18") }
}

///|
/// How many decimal places the currency carries. 18 for ether, 6 for USDC, and
/// whatever `Erc20::decimals` answered for anything else.
fn View::places(self : View) -> Int? {
  let typed = self.decimals.get().trim()
  guard typed != "" else { return None }
  for c in typed {
    guard c.is_ascii_digit() else { return None }
  }
  let n = @string.parse_int(typed.to_owned()) catch { _ => return None }
  guard n >= 0 && n <= 77 else { return None }
  Some(n)
}

///|
/// The amount in whole smallest units, or `None` when it is not a decimal
/// number this currency can carry.
fn View::units(self : View) -> BigInt? {
  guard self.places() is Some(places) else { return None }
  @ui.units_of_decimal(self.amount.get(), places)
}

///|
fn View::render(self : View) -> DomNode {
  @ui.panel("Scaling an amount — the SDK does none of this for you", [
    @ui.row([
      @ui.text_input(placeholder="0.015", self.amount),
      @ui.text_input(placeholder="18", self.decimals),
    ]),
    @ui.computed_checked(
      "smallest units",
      () => {
        match self.units() {
          Some(units) => units.to_string()
          None =>
            if self.places() is None {
              "decimals must be a whole number 0…77"
            } else {
              // a digit finer than the currency can carry, or something that is
              // not a decimal number at all
              "refused — not a decimal this currency can carry"
            }
        }
      },
      () => self.units() is None,
    ),
    @ui.computed("as Wei", () => {
      match self.units() {
        // `Wei::from_bigint` takes whole wei, and this is the only conversion
        // between the two the SDK ever needs
        Some(units) => "\{@endor.Wei::from_bigint(units).to_bigint()} wei"
        None => @ui.PLACEHOLDER
      }
    }),
    @ui.computed("and back", () => {
      match (self.units(), self.places()) {
        // the inverse: what a balance read off the chain is shown as
        (Some(units), Some(places)) => @ui.decimal_of_units(units, places)
        _ => @ui.PLACEHOLDER
      }
    }),
    @ui.note([
      @element.text(
        "The amount, then the currency's decimals. 18 is ether; 6 is USDC.",
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
