///|
/// A browser injected EIP-1193 provider backed by `globalThis.ethereum`.
///
/// Supports MetaMask, Rabby, and other browser wallets that expose
/// an EIP-1193 compatible provider.
pub struct BrowserProvider {
  priv eth : @js.Ethereum
  priv retry : @provider.RetryPolicy
}

///|
/// The one place that defaults a wallet's fields, so `detect` and
/// `on_announce` cannot drift apart.
fn BrowserProvider::over(eth : @js.Ethereum) -> BrowserProvider {
  BrowserProvider::{ eth, retry: @provider.RetryPolicy::default() }
}

///|
/// The same wallet, retrying on `policy`. A wither rather than an argument to
/// `detect`, because `discover` and `on_announce` hand back providers the
/// caller never constructed.
pub fn BrowserProvider::with_retry(
  self : BrowserProvider,
  policy : @provider.RetryPolicy,
) -> BrowserProvider {
  { ..self, retry: policy }
}

///|
/// Detect the browser injected wallet provider.
///
/// Returns `None` when `globalThis.ethereum` does not exist.
pub fn BrowserProvider::detect() -> BrowserProvider? {
  if @js.has_ethereum() {
    Some(BrowserProvider::over(@js.get_ethereum()))
  } else {
    None
  }
}

///|
/// Detect provider or raise when no wallet is installed.
pub fn BrowserProvider::require() -> BrowserProvider raise @provider.ProviderError {
  match BrowserProvider::detect() {
    Some(provider) => provider
    None => raise @provider.NotInstalled
  }
}

///|
/// Returns true when this provider identifies as MetaMask.
pub fn BrowserProvider::is_metamask(self : BrowserProvider) -> Bool {
  @js.is_metamask(self.eth)
}

///|
/// Send an EIP-1193 request, retrying the failures that are about this attempt
/// rather than about the request.
///
/// A wallet is a transport too — it can be disconnected, and the node behind it
/// can be busy — so it gets the same loop. What it does *not* get is a second
/// prompt: `retry_loop` sends the methods that open a dialog exactly once.
pub impl @provider.Provider for BrowserProvider with fn request(
  self,
  method_name~,
  params~,
) {
  @provider.retry_loop(method_name~, policy=self.retry, () => {
    self.send_once(method_name~, params~)
  })
}

///|
/// One attempt: one `ethereum.request`, one envelope read.
async fn BrowserProvider::send_once(
  self : BrowserProvider,
  method_name~ : String,
  params~ : Json,
) -> Json raise @provider.ProviderError {
  let payload = Json::object({
    "method": Json::string(method_name),
    "params": params,
  })

  let result_json = @js.request(self.eth, payload.stringify()).wait() catch {
    e => raise @provider.Transport("request failed: \{e}")
  }

  let result = @js.decode_envelope(result_json) catch {
    @js.JsError::RemoteError(code, msg, data) =>
      raise @provider.ProviderError::from_code(code, msg, data~)
    @js.JsError::InvalidEnvelope(msg) => raise @provider.MalformedResponse(msg)
  }

  result
}
