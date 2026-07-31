///|
/// The parts every demo on the documentation site is built from: a card, the
/// read-only fields it publishes, the inputs it reads back, and the two
/// conversions between a currency's smallest unit and the digits a human types.
///
/// Nothing here knows about wallets. Each island keeps its SDK code — the part
/// a reader came to see — in one flow per button, and reaches for this package
/// for everything around it.
using @element {
  div,
  p,
  span,
  button,
  input,
  text,
  text_dyn,
  events,
  type DomNode,
}

///|
using @resource {signal}

///|
/// What a field shows before anything has been read into it.
pub const PLACEHOLDER = "—"

///|
/// A demo's frame: a status line that narrates what the wallet is doing, and
/// whatever the island puts under it.
pub fn card(
  status : @signals.Signal[String],
  children : Array[DomNode],
) -> DomNode {
  div(class="endor-demo") <| [
    p(class="endor-demo-status") <| [
      text_dyn(() => status.get()),
    ],
    ..children,
  ]
}

///|
/// One labelled value the demo publishes. Read-only: it is what the wallet
/// answered, not something the reader edits.
pub fn field(label : String, value : @signals.Signal[String]) -> DomNode {
  div(class="endor-demo-field") <| [
    span(class="endor-demo-label") <| [
      text(label),
    ],
    span(class="endor-demo-value") <| [
      text_dyn(() => value.get()),
    ],
  ]
}

///|
/// A row of controls — inputs and the button that submits them.
pub fn row(children : Array[DomNode]) -> DomNode {
  div(class="endor-demo-row") <| children
}

///|
/// A text input that writes what it holds into `into` as it is typed. The flows
/// read `into` back on submit rather than parsing while typing, so a half-typed
/// address is not an error yet.
pub fn text_input(
  placeholder~ : String,
  into : @signals.Signal[String],
) -> DomNode {
  input(
    class="endor-demo-input",
    type_="text",
    placeholder~,
    on=events().input(e => {
      into.set(@dom.HTMLInputElement::cast_from_element(e.target()).value)
    }),
  )
}

///|
/// A button that runs `action` when clicked. Wallets gate their prompts behind
/// a user gesture, so every flow on this site starts from a click rather than
/// on load.
pub fn action(label : String, run : () -> Unit) -> DomNode {
  button(class="endor-demo-button", on=events().click(_ => run())) <| [
    text(label),
  ]
}

///|
/// A new status signal, seeded with what the demo says before it is touched.
pub fn status_of(initial : String) -> @signals.Signal[String] {
  signal(initial)
}

///|
/// A new field signal, showing `PLACEHOLDER` until something is read into it.
pub fn empty_field() -> @signals.Signal[String] {
  signal(PLACEHOLDER)
}

///|
/// A new signal holding what an input currently has typed into it.
pub fn input_of(initial : String) -> @signals.Signal[String] {
  signal(initial)
}

///|
/// Parse a human amount ("0.01", "1", ".5") into the smallest unit of a
/// currency with `decimals` decimal places, or `None` when it is not a decimal
/// number that currency can carry.
///
/// The SDK deals in whole smallest units and nothing else — `Wei` for the
/// chain's own currency, a `BigInt` for a token — so scaling is a presentation
/// concern and lives out here. More decimals than the currency has are rejected
/// rather than rounded: silently dropping a digit of someone's money is worse
/// than making them retype it.
pub fn units_of_decimal(amount : String, decimals : Int) -> BigInt? {
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
  let padding = decimals - fraction.to_string().length()
  guard padding >= 0 else { return None }
  for _ in 0..<padding {
    scaled.write_char('0')
  }
  // "0" + the digits: `BigInt::from_string` needs at least one, and ".5"
  // legitimately leaves the whole part empty
  Some(BigInt::from_string("0" + scaled.to_string()))
}

///|
/// Render `units` of a currency with `decimals` decimal places back as a
/// human-readable amount — the inverse of `units_of_decimal`.
pub fn decimal_of_units(units : BigInt, decimals : Int) -> String {
  guard decimals > 0 else { return units.to_string() }
  let digits = units.to_string()
  // pad so there is at least one digit in front of the point: 1 unit of a
  // 6-decimal token is "0.000001", not ".000001"
  let padded = if digits.length() <= decimals {
    "0".repeat(decimals - digits.length() + 1) + digits
  } else {
    digits
  }
  let point = padded.length() - decimals
  padded[0:point].to_owned() + "." + padded[point:].to_owned()
}
