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
/// A `Retry-After` on the failure wins over the backoff, the way viem's `delay`
/// prefers it: a node that says how long it wants to be left alone is stating
/// what the backoff is only guessing at. One longer than
/// `MAX_RETRY_AFTER_S` ends the loop instead — see there.
///
/// No jitter: several requests that hit the same `429` together come back
/// together. That can wait until it is a problem someone has.
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
  // Written out rather than handed to `@async.retry`, which picks its delay
  // from the strategy alone and so has nowhere to read a `Retry-After` from.
  // The price is that `first_delay` / `next_delay` mirror what `@async.retry`
  // reads `RetryMethod` to mean, and have to keep matching it.
  for attempt = 0, delay = first_delay(strategy) {
    try call() catch {
      e => {
        guard attempt < max_retry &&
          e.is_retryable() &&
          !@async.is_being_cancelled() else {
          raise e
        }
        // the node's own answer to "how long", when it gave one
        let wait = match retry_after_seconds(e) {
          Some(asked) => {
            guard asked <= MAX_RETRY_AFTER_S else { raise e }
            asked * 1_000
          }
          None => delay
        }
        // `sleep` raises `Error` on cancellation, which cannot cross a
        // `ProviderError` boundary as itself
        @async.sleep(wait) catch {
          cancelled =>
            raise Transport(
              "the retry of \{method_name} was cancelled: \{cancelled}",
            )
        }
        continue attempt + 1, next_delay(strategy, delay)
      }
    } noraise {
      answer => return answer
    }
  }
}

///|
/// The longest wait this loop sits through, in seconds. A node that asks for
/// longer is not asking for a moment — it is saying the quota is spent — and
/// the loop hands the failure back rather than either ignoring what it asked
/// (coming back sooner is another `429`) or holding the caller's request for an
/// hour. The `Retry-After` is on the error, so a caller who does want to wait
/// that long can read it and decide for itself.
///
/// A minute: past every backoff this loop runs, and short of the quota windows
/// a hosted RPC hands out when the day's requests are spent.
const MAX_RETRY_AFTER_S : Int = 60

///|
/// How long the node asked to be left alone for. Only an HTTP response carries
/// such a request, and only `provider/http/endpoint` reads one off the wire.
fn retry_after_seconds(error : ProviderError) -> Int? {
  guard error is HttpStatus(info~) else { return None }
  info.retry_after()
}

///|
/// The wait before the second attempt.
fn first_delay(strategy : @async.RetryMethod) -> Int {
  match strategy {
    Immediate => 0
    FixedDelay(delay) => delay
    ExponentialDelay(initial~, ..) => initial
  }
}

///|
/// The wait after one that was `delay` — the growth `ExponentialDelay`
/// describes, and no growth at all for the other two.
fn next_delay(strategy : @async.RetryMethod, delay : Int) -> Int {
  match strategy {
    Immediate | FixedDelay(_) => delay
    ExponentialDelay(factor~, maximum~, ..) => {
      let grown = (delay.to_double() * factor).to_int()
      if grown > maximum {
        maximum
      } else {
        grown
      }
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
