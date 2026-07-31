///|
/// keccak256, live: a signature in, the four bytes a call starts with and the
/// 32-byte topic an event is logged under back out.
///
/// Both are `@abi` on its own — no provider, no network, no `js` needed. Edit
/// one character of the signature and every digit changes, which is the whole
/// point of a hash and the reason `transfer(address,uint256)` and
/// `transfer(address,uint)` are different functions.
using @element {div, text, type DomNode}

///|
struct View {
  signature : @signals.Signal[String]
}

///|
fn View::new() -> View {
  { signature: @ui.input_of("transfer(address,uint256)") }
}

///|
fn View::typed(self : View) -> String {
  self.signature.get().trim().to_owned()
}

///|
fn View::render(self : View) -> DomNode {
  @ui.panel([
    @ui.row([
      @ui.text_input(placeholder="transfer(address,uint256)", self.signature),
    ]),
    @ui.computed("@abi.selector", () => {
      let sig = self.typed()
      guard sig != "" else { return @ui.PLACEHOLDER }
      // the first four bytes of keccak256(signature) — what calldata opens with
      @abi.selector(sig).to_string()
    }),
    @ui.computed("@abi.event_topic", () => {
      let sig = self.typed()
      guard sig != "" else { return @ui.PLACEHOLDER }
      // the whole 32 bytes — what a log's `topics[0]` is matched against
      @abi.event_topic(sig).to_string()
    }),
    @ui.note([
      text(
        "A signature is the name and the parameter types with no spaces and no names. " +
        "`@abi.signature(name~, inputs~)` builds one from `AbiType`s, which is how " +
        "`Contract::call` gets the selector it sends.",
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
