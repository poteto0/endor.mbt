///|
/// Errors surfaced by an EIP-1193 provider, mapping the standard
/// EIP-1193 / EIP-1474 error codes onto typed variants. Wallet-side failures
/// are always reported through this suberror; the public API never panics.
///
/// ```mbt check
/// test "doc: error code test example" {
///   let e = @provider.ProviderError::from_code(4001, "user rejected")
///   inspect(e, content="UserRejected")
/// }
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
  /// `globalThis.ethereum` is not present — no wallet extension is installed.
  NotInstalled
  /// A wait the SDK gave up on: `wait_for_receipt` polled until its timeout
  /// without the transaction reaching the confirmations asked for. The wallet
  /// answered every question it was asked, so this is not a wallet-side
  /// failure — it is the absence of an answer, and it is what tells a timeout
  /// apart from the `None` a not-yet-mined transaction reads as.
  Timeout(String)
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
/// ```mbt check
/// test "doc: error from code" {
///   inspect(
///     @provider.ProviderError::from_code(4902, "unknown chain"),
///     content="UnrecognizedChain",
///   )
///   inspect(
///     @provider.ProviderError::from_code(-32603, "boom"),
///     content=(
///       #|Rpc(code=-32603, message="boom")
///     ),
///   )
/// }
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
/// Decode the `{ code, message }` object both EIP-1193 and JSON-RPC carry,
/// through the same code mapping as `from_code`. An error that cannot be read
/// is still an error, so whatever is absent or of the wrong shape falls back to
/// the internal-error code and an empty message.
///
/// This is the one place that payload is read: an event decodes it through
/// `from_json`, which additionally has to be able to say "not an error object
/// at all", and `@http.HttpProvider` decodes a node's `error` member with it.
///
/// ```mbt check
/// test "doc: error from an error object" {
///   inspect(
///     @provider.ProviderError::from_error_object({
///       "code": 4001,
///       "message": "user rejected",
///     }),
///     content="UserRejected",
///   )
/// }
/// ```
pub fn ProviderError::from_error_object(payload : Json) -> ProviderError {
  guard payload is Object(fields) else { return ProviderError::internal("") }
  let code = match fields.get("code") {
    Some(Number(c, ..)) => c.to_int()
    _ => -32603
  }
  let message = match fields.get("message") {
    Some(String(s)) => s
    _ => ""
  }
  ProviderError::from_code(code, message)
}

///|
/// Decode the `ProviderRpcError` object EIP-1193 carries — `{ code, message }` —
/// through the same code mapping as `from_code`. `None` when the payload is not
/// that shape, which is how an event with nowhere to raise to drops it: an
/// event has nowhere to raise to, so a payload it cannot read is not worth
/// inventing a code for.
fn ProviderError::from_json(payload : Json) -> ProviderError? {
  guard payload is Object(fields) else { return None }
  guard fields.get("code") is Some(Number(_)) else { return None }
  Some(ProviderError::from_error_object(payload))
}

///|
/// The SDK's own failures — a malformed response, a broken FFI boundary — are
/// reported with the JSON-RPC internal-error code so the error surface stays
/// exactly the set of variants above.
///
/// ```mbt check
/// test "doc: error internal" {
///   inspect(
///     @provider.ProviderError::internal("bad response"),
///     content=(
///       #|Rpc(code=-32603, message="bad response")
///     ),
///   )
/// }
/// ```
pub fn ProviderError::internal(message : String) -> ProviderError {
  Rpc(code=-32603, message~)
}
