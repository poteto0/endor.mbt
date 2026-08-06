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
  /// The contract refused the call: the node answered with an error carrying
  /// the ABI-encoded revert (EIP-1474 code 3, `execution reverted`).
  ///
  /// `data` is that revert, exactly as it came off the wire and not yet read:
  /// what it *says* — `Error(string)`, `Panic(uint256)`, or a custom error —
  /// needs the ABI, which is a layer up (`@contract.ContractError`). `code` and
  /// `message` are the node's own, so nothing the wallet said is lost by
  /// telling this apart from `Rpc`.
  Reverted(code~ : Int, message~ : String, data~ : @types.Hex)
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
///
/// `Reverted` is the one exception: its `data` is a `Hex`, whose derived debug
/// form is the struct it is made of rather than the `0x…` everything else
/// spells it as, and a revert is read by a person often enough that it is worth
/// the arm.
pub impl Show for ProviderError with fn output(self, logger) {
  match self {
    Reverted(code~, message~, data~) =>
      logger.write_string(
        "Reverted(code=\{code}, message=\"\{message}\", data=\{data})",
      )
    _ => logger.write_string(@debug.to_string(self))
  }
}

///|
/// Map an EIP-1193 / EIP-1474 numeric error code (with its message) onto a
/// `ProviderError` variant. Unknown codes fall through to `Rpc`, or to
/// `Reverted` when `data` carries the revert the contract raised.
///
/// A code EIP-1193 gives a meaning to keeps that meaning whatever `data` holds:
/// a user who rejected the prompt is `UserRejected` and nothing else.
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
pub fn ProviderError::from_code(
  code : Int,
  message : String,
  data? : Json,
) -> ProviderError {
  match code {
    4001 => UserRejected
    4100 => Unauthorized
    4200 => UnsupportedMethod
    4900 => Disconnected
    4901 => ChainDisconnected
    4902 => UnrecognizedChain
    _ =>
      match data.bind(revert_data) {
        Some(data) => Reverted(code~, message~, data~)
        None => Rpc(code~, message~)
      }
  }
}

///|
/// The ABI-encoded revert hiding in a JSON-RPC error's `data`, if there is one.
///
/// Which key it is under is not something the standards settle, so the shapes
/// nodes actually write are all read: geth and Anvil put the hex directly in
/// `error.data`, while a wallet that wraps a node's answer nests it once
/// (`error.data.data`) or twice, keeping the node's own error alongside
/// (`error.data.originalError.data`). Anything else — a plain string that is not
/// hex, an object with none of those keys — is no revert, and the error stays
/// `Rpc`.
fn revert_data(data : Json) -> @types.Hex? {
  match data {
    String(_) => Some(@types.Hex::from_json(data) catch { _ => return None })
    Object(fields) =>
      match fields.get("data") {
        Some(nested) => revert_data(nested)
        None => fields.get("originalError").bind(revert_data)
      }
    _ => None
  }
}

///|
/// Decode the `ProviderRpcError` object EIP-1193 carries — `{ code, message }` —
/// through the same code mapping as `from_code`. `None` when the payload is not
/// that shape, which is how an event with nowhere to raise to drops it.
fn ProviderError::from_json(payload : Json) -> ProviderError? {
  guard payload is Object(fields) else { return None }
  guard fields.get("code") is Some(Number(code, ..)) else { return None }
  let message = match fields.get("message") {
    Some(String(s)) => s
    _ => ""
  }
  Some(
    ProviderError::from_code(code.to_int(), message, data?=fields.get("data")),
  )
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
