///|
/// Errors surfaced by an EIP-1193 provider, mapping the standard
/// EIP-1193 / EIP-1474 error codes onto typed variants. Wallet-side failures
/// are always reported through this suberror; the public API never panics.
///
/// ```
/// let e = @endor.ProviderError::from_code(4001, "user rejected")
/// inspect(e, content="UserRejected")
/// ```
pub(all) suberror ProviderError {
  /// 4001 — the user rejected the request.
  UserRejected
  /// 4100 — the requested account/method is not authorized by the user.
  Unauthorized
  /// 4200 — the provider does not support the requested method.
  UnsupportedMethod
  /// 4900 — the provider is disconnected from all chains.
  Disconnected
  /// 4901 — the provider is disconnected from the requested chain.
  ChainDisconnected
  /// 4902 — the chain is not recognized (e.g. `wallet_switchEthereumChain`).
  UnrecognizedChain
  /// Any other JSON-RPC error (EIP-1474), e.g. `-32603` internal error.
  Rpc(code~ : Int, message~ : String)
  /// `window.ethereum` is not present — MetaMask is not installed.
  NotInstalled
} derive(Eq, Debug)

///|
/// Render through the derived `Debug` representation, so the variant list stays
/// the single source of truth for how errors print.
pub impl Show for ProviderError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Map an EIP-1193 / EIP-1474 numeric error code (with its message) onto a
/// `ProviderError` variant. Unknown codes fall through to `Rpc`.
///
/// ```
/// inspect(@endor.ProviderError::from_code(4902, "unknown chain"), content="UnrecognizedChain")
/// inspect(
///   @endor.ProviderError::from_code(-32603, "boom"),
///   content=(
///     #|Rpc(code=-32603, message="boom")
///   ),
/// )
/// ```
pub fn ProviderError::from_code(code : Int, message : String) -> ProviderError {
  match code {
    4001 => UserRejected
    4100 => Unauthorized
    4200 => UnsupportedMethod
    4900 => Disconnected
    4901 => ChainDisconnected
    4902 => UnrecognizedChain
    _ => Rpc(code~, message~)
  }
}

///|
/// The SDK's own failures — a malformed response, a broken FFI boundary — are
/// reported with the JSON-RPC internal-error code so the error surface stays
/// exactly the set of variants above.
///
/// ```
/// inspect(
///   @endor.ProviderError::internal("bad response"),
///   content=(
///     #|Rpc(code=-32603, message="bad response")
///   ),
/// )
/// ```
pub fn ProviderError::internal(message : String) -> ProviderError {
  Rpc(code=-32603, message~)
}
