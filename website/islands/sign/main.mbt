///|
/// `personal_sign`, on whatever text you type.
///
/// The one prompt on this site that costs nothing and touches no chain: the
/// wallet shows the message, signs it with the account's key, and hands back 65
/// bytes. Nothing is broadcast and nothing is spent.
using @element {div, text, type DomNode}

///|
struct View {
  status : @signals.Signal[String]
  who : @signals.Signal[String]
  signature : @signals.Signal[String]
  message : @signals.Signal[String]
}

///|
fn View::new() -> View {
  {
    status: @ui.status_of("Type something and have your wallet sign it."),
    who: @ui.empty_field(),
    signature: @ui.empty_field(),
    message: @ui.input_of("I am reading the endor.mbt cookbook"),
  }
}

///|
async fn View::sign(self : View) -> Unit {
  let message = self.message.get()
  guard message.trim() != "" else {
    self.status.set("Nothing to sign.")
    return
  }
  try {
    let wallet = @browser.BrowserProvider::require()
    // `accounts` never prompts, so the only popup here is the signature itself
    guard @provider.accounts(wallet).get(0) is Some(who) else {
      self.status.set("Not connected — connect a wallet first.")
      return
    }
    self.who.set(who.to_checksum_string())
    self.status.set("Check the wallet: it should be showing you that text…")
    // personal_sign. The wallet prefixes the message with
    // "\x19Ethereum Signed Message:\n" + length before hashing, which is what
    // keeps this signature from ever being a valid transaction.
    let signature = @provider.sign_message(wallet, who, message)
    self.signature.set(signature.to_string())
    self.status.set(
      "Signed — \{signature.byte_length()} bytes of r ‖ s ‖ v. Nothing was spent.",
    )
  } catch {
    NotInstalled =>
      self.status.set("No wallet detected — install one and reload.")
    UserRejected => self.status.set("Signature declined in the wallet.")
    Unauthorized =>
      self.status.set("This page is not authorized for that account.")
    e => self.status.set("Error: \{e}")
  }
}

///|
fn View::render(self : View) -> DomNode {
  @ui.card(self.status, [
    @ui.field("Signer", self.who),
    @ui.field("Signature", self.signature),
    // the bytes that actually go over the wire: the message as UTF-8 in hex,
    // which is what lets the wallet show the text back to the reader
    @ui.computed("as sent (Hex::from_utf8)", () => {
      let message = self.message.get()
      guard message != "" else { return @ui.PLACEHOLDER }
      @endor.Hex::from_utf8(message).to_string()
    }),
    @ui.row([
      @ui.text_input(placeholder="anything you like", self.message),
      @ui.action("Sign it", () => @js.spawn(() => self.sign())),
    ]),
    @ui.note([
      text(
        "Costs nothing and broadcasts nothing. The SDK does not verify the " +
        "signature either — recovering the signer belongs to whatever is being " +
        "convinced, usually a backend or a contract.",
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
