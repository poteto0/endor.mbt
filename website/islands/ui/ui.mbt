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
/// One labelled value computed from whatever the inputs currently hold, rather
/// than from something a button went and fetched.
///
/// This is what a demo without a wallet in it is made of: `value()` is called
/// again on every keystroke, so the reader sees the function's actual answer —
/// including the error it raises — as they type the argument.
pub fn computed(label : String, value : () -> String) -> DomNode {
  div(class="endor-demo-field") <| [
    span(class="endor-demo-label") <| [
      text(label),
    ],
    span(class="endor-demo-value") <| [
      text_dyn(value),
    ],
  ]
}

///|
/// The same, marked as the value the SDK is refusing. `bad()` decides, so a
/// field can be red for one input and plain for the next.
pub fn computed_checked(
  label : String,
  value : () -> String,
  bad : () -> Bool,
) -> DomNode {
  div(class="endor-demo-field") <| [
    span(class="endor-demo-label") <| [
      text(label),
    ],
    span(
      dyn_class=() => {
        if bad() {
          "endor-demo-value is-bad"
        } else {
          "endor-demo-value"
        }
      },
    ) <| [
      text_dyn(value),
    ],
  ]
}

///|
/// A demo with no status line: nothing here talks to a wallet, so there is
/// nothing to narrate. What it does is visible in the fields.
///
/// `title` names the call the widget is making, because a box of inputs and
/// values on a documentation page does not otherwise say what it is.
pub fn panel(title : String, children : Array[DomNode]) -> DomNode {
  div(class="endor-demo") <| [
    p(class="endor-demo-title") <| [
      span(class="endor-demo-live") <| [
        text("live"),
      ],
      text(title),
    ],
    ..children,
  ]
}

///|
/// The line under a demo naming the call it makes, so the widget and the code
/// beside it are visibly the same thing.
pub fn note(children : Array[DomNode]) -> DomNode {
  p(class="endor-demo-note") <| children
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
    // the signal's starting value, written once. Not `dyn_value`: that would
    // rewrite the box on every keystroke and fight whoever is typing in it.
    value=into.get(),
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
/// `Wei::from_units` is the SDK's, and it raises rather than answering an
/// option — an amount finer than the currency carries is refused rather than
/// rounded, because silently dropping a digit of somebody's money is worse than
/// making them retype it. What is left out here is the option: a widget that
/// re-parses on every keystroke asks the question far more often than it is
/// answered yes, and a half-typed amount is not an error worth a `try`.
pub fn units_of_decimal(amount : String, decimals : Int) -> BigInt? {
  Some(@endor.Wei::from_units(amount.trim().to_owned(), decimals~).to_bigint()) catch {
    _ => None
  }
}

///|
/// Render `units` of a currency with `decimals` decimal places back as a
/// human-readable amount — the inverse of `units_of_decimal`.
pub fn decimal_of_units(units : BigInt, decimals : Int) -> String {
  @endor.Wei::from_bigint(units).to_units(decimals~)
}
