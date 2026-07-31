///|
/// `Address::from_string`, run on every keystroke.
///
/// No wallet and no network: this is the constructor deciding, in front of the
/// reader, whether what they typed is an address — and, when it is not, saying
/// which rule it broke. Change one character of the checksummed form and watch
/// it turn into `InvalidChecksum`.
using @element {div, type DomNode}

///|
struct View {
  typed : @signals.Signal[String]
}

///|
fn View::new() -> View {
  // vitalik.eth, in the EIP-55 spelling, so the demo starts on a valid one
  { typed: @ui.input_of("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045") }
}

///|
/// What the constructor answered, as one of three shapes: the address, the rule
/// it broke, or nothing at all for an empty box.
enum Verdict {
  Empty
  Address(@endor.Address)
  Refused(String)
}

///|
fn View::verdict(self : View) -> Verdict {
  let typed = self.typed.get().trim().to_owned()
  guard typed != "" else { return Empty }
  Address(@endor.Address::from_string(typed)) catch {
    // the ways a string is not an address, named as `CodecError` names them —
    // the message each carries says which character or which length was wrong
    InvalidHex(what) => Refused("InvalidHex — \{what}")
    InvalidLength(what) => Refused("InvalidLength — \{what}")
    InvalidChecksum(what) => Refused("InvalidChecksum — \{what}")
    e => Refused("\{e}")
  }
}

///|
fn View::render(self : View) -> DomNode {
  @ui.panel([
    @ui.row([@ui.text_input(placeholder="0x… an address", self.typed)]),
    @ui.computed_checked(
      "Address::from_string",
      () => {
        match self.verdict() {
          Empty => "waiting for something to parse"
          Address(_) => "accepted"
          Refused(why) => "raises CodecError::\{why}"
        }
      },
      () => self.verdict() is Refused(_),
    ),
    @ui.computed("to_string()", () => {
      match self.verdict() {
        // lowercase: the form that goes on the wire
        Address(addr) => addr.to_string()
        _ => @ui.PLACEHOLDER
      }
    }),
    @ui.computed("to_checksum_string()", () => {
      match self.verdict() {
        // EIP-55: the form to show a human, and the one that catches a typo
        Address(addr) => addr.to_checksum_string()
        _ => @ui.PLACEHOLDER
      }
    }),
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
