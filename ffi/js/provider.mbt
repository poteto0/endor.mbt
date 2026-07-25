///|
/// A live MetaMask (EIP-1193) provider backed by `globalThis.ethereum`.
/// Obtain one with `detect()`. Implements `@endor.Provider`, so it plugs
/// directly into the typed RPC helpers (`@endor.request_accounts`, ...).
///
/// ```
/// async fn run() -> Unit raise @endor.ProviderError {
///   let mm = match @ffi.detect() {
///     Some(p) => p
///     None => raise NotInstalled
///   }
///   let accounts = @endor.request_accounts(mm)
///   ignore(accounts)
/// }
/// ```
pub struct MetaMaskProvider {
  priv eth : Ethereum
}

///|
/// Detect the injected MetaMask provider. Returns `None` when no EIP-1193
/// provider is present on `globalThis.ethereum` (MetaMask not installed).
///
/// ```
/// if @ffi.detect() is Some(_) {
///   // wallet available
/// }
/// ```
pub fn detect() -> MetaMaskProvider? {
  if js_has_ethereum() {
    Some(MetaMaskProvider::{ eth: js_get_ethereum() })
  } else {
    None
  }
}

///|
/// Like `detect`, but raises `NotInstalled` when no provider is present, so
/// obtaining the wallet composes with the rest of the typed API under a single
/// `try`.
///
/// ```
/// async fn run() -> Unit raise @endor.ProviderError {
///   let accounts = @endor.request_accounts(@ffi.require())
///   ignore(accounts)
/// }
/// ```
pub fn require() -> MetaMaskProvider raise @provider.ProviderError {
  match detect() {
    Some(p) => p
    None => raise @provider.NotInstalled
  }
}

///|
/// Run an async task from a synchronous entry point (`fn main`), bridging to
/// the JS event loop. Dapps need this because every wallet call is async while
/// `main` is not.
///
/// ```
/// fn main {
///   @ffi.spawn(fn() { ... })
/// }
/// ```
pub fn spawn(task : async () -> Unit) -> Unit {
  @js_async.Promise::from_async(task) |> ignore
}

///|
/// Whether the detected provider advertises the MetaMask `isMetaMask` flag.
/// Detection itself is intentionally lenient (any EIP-1193 provider), so use
/// this to distinguish genuine MetaMask when several wallets are present.
pub fn MetaMaskProvider::is_metamask(self : MetaMaskProvider) -> Bool {
  js_is_metamask(self.eth)
}

///|
/// Parse the JSON-string envelope returned by `js_request` into the typed
/// result, mapping any error envelope onto a `ProviderError`.
fn decode_envelope(result_json : String) -> Json raise @provider.ProviderError {
  let parsed = @json.parse(result_json) catch {
    e => raise @provider.ProviderError::internal("malformed FFI envelope: \{e}")
  }
  guard parsed is Object(obj) else {
    raise @provider.ProviderError::internal("FFI envelope not an object")
  }
  if obj.get("err") is Some(Object(err_obj)) {
    // Both fields are defaulted: the envelope crosses a JS boundary where a
    // thrown value need not be a well-formed EIP-1193 error object.
    let code = match err_obj.get("code") {
      Some(Number(c, ..)) => c.to_int()
      _ => -32603
    }
    let message = match err_obj.get("message") {
      Some(String(s)) => s
      _ => ""
    }
    raise @provider.ProviderError::from_code(code, message)
  }
  guard obj.get("ok") is Some(v) else {
    raise @provider.ProviderError::internal("FFI envelope missing ok/err")
  }
  v
}

///|
pub impl @provider.Provider for MetaMaskProvider with fn request(
  self,
  method_name~,
  params~,
) {
  let payload = Json::object({
    "method": Json::string(method_name),
    "params": params,
  })
  let payload_json = payload.stringify()
  let result_json = js_request(self.eth, payload_json).wait() catch {
    e => raise @provider.ProviderError::internal("request failed: \{e}")
  }
  decode_envelope(result_json)
}
