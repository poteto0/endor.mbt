///|
/// Run `call` again while it keeps failing in a way `is_retryable` says is
/// worth another try, backing off between attempts.
///
/// This sits at the `Provider::request` layer rather than in a transport,
/// because the two most common "come back later" answers a hosted RPC gives
/// arrive **inside a 200 response**: JSON-RPC's `-32005`, and the providers
/// that put `{ code: 429 }` in the body. Neither is visible to
/// `HttpTransport::post`; both are visible once the JSON-RPC envelope is open.
/// Sitting here also means the same loop covers a browser wallet, which has no
/// HTTP layer to put a retry in at all.
///
/// The defaults are viem's — 150ms doubling to at most 2s, three retries, so
/// four attempts spanning about a second. They are the only settings there are:
/// how a caller overrides them is a later question, and until it is answered
/// both providers retry on these.
///
/// No jitter: `@async.retry` has none, so several requests that hit the same
/// `429` together will come back together. That wants a hand-written loop, and
/// it can wait until it is a problem someone has.
///
/// Not public API. It is `pub` only because `provider/http` and
/// `provider/browser` both call it; `#doc(hidden)` is what keeps it out of the
/// generated `.mbti`, which `#internal` alone does not.
#internal(internal, "the retry loop is not public API")
#doc(hidden)
pub async fn retry_loop(
  method_name~ : String,
  strategy? : @async.RetryMethod = ExponentialDelay(
    initial=150,
    factor=2.0,
    maximum=2_000,
  ),
  max_retry? : Int = 3,
  call : async () -> Json raise ProviderError,
) -> Json raise ProviderError {
  if is_not_idempotent(method_name) {
    return call()
  }
  // `@async.retry` erases what it catches to a bare `Error`, and there is no
  // way back from one to a `ProviderError`. So every failure is caught where it
  // is still typed — inside the closure — and carried out in `last`, which is
  // what both `fatal_error` and the final `raise` then read.
  let mut last : ProviderError? = None
  @async.retry(
    strategy,
    max_retry~,
    fatal_error=_ => last is Some(e) && !e.is_retryable(),
    () => {
      call() catch {
        e => {
          last = Some(e)
          raise e
        }
      }
    },
  ) catch {
    e =>
      match last {
        Some(typed) => raise typed
        // `retry` raised before any attempt did — a cancellation, which it
        // re-raises as itself. There is no typed failure to report, so the
        // bare one is carried across in a message.
        None => raise Transport("retry raised before the first attempt: \{e}")
      }
  }
}

///|
/// The methods that must be sent at most once, whatever the failure looked
/// like: sending them twice is not the same as sending them once.
///
/// A **deliberate difference from viem**, whose `shouldRetry` never looks at
/// the method name. Behind a wallet these are prompts, and a retry is a second
/// dialog in the user's face for a request they may already have answered.
///
/// `eth_sendRawTransaction` is deliberately **not** here: the transaction is
/// already signed, so a resend is byte-identical and hashes the same, and the
/// node drops the duplicate.
///
/// It reads a list of its own rather than sharing one with `needs_a_wallet` in
/// `provider/http`, because the two ask opposite questions about the same
/// names: a dev node with unlocked accounts really does serve
/// `eth_sendTransaction`, which is why HTTP lets it through — and it is exactly
/// the one that must not be sent twice.
fn is_not_idempotent(method_name : String) -> Bool {
  method_name.has_prefix("wallet_") ||
  method_name == "eth_sendTransaction" ||
  method_name == "eth_requestAccounts" ||
  method_name == "personal_sign" ||
  method_name == "eth_signTypedData_v4"
}
