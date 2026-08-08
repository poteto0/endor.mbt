///|
/// Everything that can go wrong between a call and its answer, whether the
/// thing at the other end is a browser wallet or a node's HTTP endpoint.
/// Wallet-side failures are always reported through this suberror; the public
/// API never panics.
///
/// The variants are cut by **what the caller should do next**, not by where in
/// the SDK the failure was noticed. Read top to bottom they are four groups:
/// the wallet answered no (`UserRejected` … `NotInstalled`), the node answered
/// no (`Rpc`, `Reverted`), nothing answered or the answer was unreadable
/// (`Transport`, `HttpStatus`, `MalformedResponse`, `Decode`), and the caller
/// got it wrong before any I/O happened (`Config`). `is_retryable` is the
/// summary of that reading, and `message` is the line to show a person.
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
  /// Any other JSON-RPC error (EIP-1474), e.g. `-32603` internal error. This
  /// is the node or the wallet *answering*: it read the request and said no.
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
  /// The request never became an answer: no connection, DNS, TLS, a socket
  /// that closed. Nothing was decided at the other end, so the same call may
  /// well succeed later — `is_retryable` is true.
  Transport(String)
  /// The endpoint answered, with a status that is not 2xx. `429` and `5xx` are
  /// the node or its gateway asking for a moment; `401` and `403` are an API
  /// key that is wrong or absent, and no amount of retrying fixes those. The
  /// URL is carried because a dapp that reads from several nodes needs to know
  /// which one.
  HttpStatus(code~ : Int, url~ : String)
  /// A 2xx body that is not a JSON-RPC answer: it did not parse, it was not an
  /// object, it carried neither `result` nor `error`, or its `id` was not the
  /// one that was sent. Something between here and the node is not speaking
  /// JSON-RPC — a captive portal, a proxy, the wrong URL — and retrying gets
  /// the same body back.
  MalformedResponse(String)
  /// A well-formed answer whose `result` is not the type the method promises.
  /// The `CodecError` is kept as it was raised rather than flattened into a
  /// message, so which field was wrong stays readable by a program;
  /// `method_name` names the call that answered.
  Decode(method_name~ : String, cause~ : @types.CodecError)
  /// A mistake in how the SDK was set up, caught before any I/O: a URL that is
  /// not HTTP, an argument outside its range. It fails identically every time
  /// until the code changes.
  Config(String)
  /// A wait the SDK gave up on: `wait_for_receipt` polled until its timeout
  /// without the transaction reaching the confirmations asked for, or an HTTP
  /// request went unanswered past its deadline. The other side answered every
  /// question it was asked, so this is not a wallet-side failure — it is the
  /// absence of an answer, and it is what tells a timeout apart from the `None`
  /// a not-yet-mined transaction reads as.
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
/// Decode the `{ code, message }` object both EIP-1193 and JSON-RPC carry,
/// through the same code mapping as `from_code`. A member that is absent or of
/// the wrong kind falls back to the internal-error code and an empty message —
/// an error that cannot be read is still an error — while a payload that is not
/// an object at all is not an error report and comes back as
/// `MalformedResponse`.
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
  guard payload is Object(fields) else {
    return MalformedResponse(
      "JSON-RPC error is not an object: \{payload.stringify()}",
    )
  }
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
/// One line to put in front of a person: no variant name, no URL, no
/// JSON-RPC code. `Show` is the developer's view of the same error, and the
/// two are deliberately different — `Rpc(code=-32603, message="decode
/// eth_getBalance: InvalidJson(…)")` belongs in a log, not in a dialog.
///
/// The node's own `message` is passed through for `Rpc`, since that is where
/// "insufficient funds for gas * price + value" comes from and a person can
/// act on it.
///
/// ```mbt check
/// test "doc: error message" {
///   inspect(@provider.UserRejected.message(), content="You declined the request.")
/// }
/// ```
pub fn ProviderError::message(self : ProviderError) -> String {
  match self {
    UserRejected => "You declined the request."
    Unauthorized => "This site is not authorized to use that account."
    UnsupportedMethod => "Your wallet does not support that request."
    Disconnected => "Your wallet is disconnected."
    ChainDisconnected => "Your wallet is disconnected from that network."
    UnrecognizedChain => "Your wallet does not know that network."
    NotInstalled => "No wallet was found. Install one to continue."
    Rpc(message~, ..) =>
      if message.is_empty() {
        "The network refused the request."
      } else {
        message
      }
    Reverted(..) => "The contract refused the transaction."
    Transport(_) => "Could not reach the network. Check your connection."
    HttpStatus(code~, ..) =>
      if code == 429 {
        "The network is busy. Try again in a moment."
      } else if code == 401 || code == 403 {
        "This app is not authorized to use that node."
      } else if code >= 500 {
        "The node is having trouble. Try again in a moment."
      } else {
        "The node refused the request."
      }
    MalformedResponse(_) | Decode(..) =>
      "The network answered with something this app could not read."
    Config(_) => "This app is misconfigured."
    Timeout(_) => "The network did not answer in time."
  }
}

///|
/// Whether waiting and making the same call again is worth anything.
///
/// True for the failures that are about *this attempt* — nothing got through,
/// nothing answered in time, the node asked for a moment (`429`, `5xx`, the
/// `-32005` every hosted RPC rate-limits with). False for everything that has
/// already been decided: a user who said no, an account that is not authorized,
/// a body that will not parse, a URL that is not a URL. A revert is the most
/// firmly decided of all.
///
/// ```mbt check
/// test "doc: is_retryable" {
///   inspect(
///     @provider.Transport("connection refused").is_retryable(),
///     content="true",
///   )
///   inspect(@provider.UserRejected.is_retryable(), content="false")
/// }
/// ```
pub fn ProviderError::is_retryable(self : ProviderError) -> Bool {
  match self {
    Transport(_) | Timeout(_) => true
    HttpStatus(code~, ..) => code == 429 || code >= 500
    // -32005: "limit exceeded", what a hosted RPC rate-limits with over
    // JSON-RPC rather than over HTTP
    Rpc(code~, ..) => code == RATE_LIMITED
    _ => false
  }
}

///|
/// The EIP-1474 code a hosted RPC answers with when the caller is over its
/// quota. It arrives inside a 200 response, which is why `HttpStatus(429)` is
/// not the only rate limit there is.
const RATE_LIMITED : Int = -32005

///|
/// The EIP-1193 / EIP-1474 code this error was, or would have been, reported
/// under. `None` for the failures that never reached the protocol: nothing
/// connected, nothing parsed, nothing was configured right.
///
/// ```mbt check
/// test "doc: code" {
///   debug_inspect(@provider.UserRejected.code(), content="Some(4001)")
///   debug_inspect(@provider.Transport("boom").code(), content="None")
/// }
/// ```
pub fn ProviderError::code(self : ProviderError) -> Int? {
  match self {
    UserRejected => Some(4001)
    Unauthorized => Some(4100)
    UnsupportedMethod => Some(4200)
    Disconnected => Some(4900)
    ChainDisconnected => Some(4901)
    UnrecognizedChain => Some(4902)
    Rpc(code~, ..) | Reverted(code~, ..) => Some(code)
    NotInstalled
    | Transport(_)
    | HttpStatus(..)
    | MalformedResponse(_)
    | Decode(..)
    | Config(_)
    | Timeout(_) => None
  }
}
