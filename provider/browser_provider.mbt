///|
/// A browser injected EIP-1193 provider backed by `globalThis.ethereum`.
///
/// Supports MetaMask, Rabby, and other browser wallets that expose
/// an EIP-1193 compatible provider.
pub struct BrowserProvider {
  priv eth : @js.Ethereum
}

///|
/// Detect the browser injected wallet provider.
///
/// Returns `None` when `globalThis.ethereum` does not exist.
pub fn BrowserProvider::detect() -> BrowserProvider? {
  if @js.has_ethereum() {
    Some(BrowserProvider::{ eth: @js.get_ethereum() })
  } else {
    None
  }
}

///|
/// Detect provider or raise when no wallet is installed.
pub fn BrowserProvider::require() -> BrowserProvider raise ProviderError {
  match BrowserProvider::detect() {
    Some(provider) => provider
    None => raise NotInstalled
  }
}

///|
/// Returns true when this provider identifies as MetaMask.
pub fn BrowserProvider::is_metamask(self : BrowserProvider) -> Bool {
  @js.is_metamask(self.eth)
}

///|
/// Send an EIP-1193 request.
pub impl Provider for BrowserProvider with fn request(
  self,
  method_name~,
  params~,
) {
  let payload = Json::object({
    "method": Json::string(method_name),
    "params": params,
  })

  let result_json = @js.request(self.eth, payload.stringify()).wait() catch {
    e => raise ProviderError::internal("request failed: \{e}")
  }

  let result = @js.decode_envelope(result_json) catch {
    @js.JsError::RemoteError(code, msg) =>
      raise ProviderError::from_code(code, msg)
    @js.JsError::InvalidEnvelope(msg) => raise ProviderError::internal(msg)
  }

  result
}
