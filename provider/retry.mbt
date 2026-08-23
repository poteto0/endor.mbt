///|
/// Run `call` again while it keeps failing in a way `is_retryable` says is
/// worth another try, backing off between attempts. The `Retry-After` preference
/// below and the send-once list are not the policy's to override.
///
/// No jitter: several requests that hit the same `429` together come back
/// together.
#internal(internal, "the retry loop is not public API")
#doc(hidden)
pub async fn retry_loop(
  method_name~ : String,
  policy~ : RetryPolicy,
  call : async () -> Json raise ProviderError,
) -> Json raise ProviderError {
  if is_not_idempotent(method_name) {
    return call()
  }
  retry_loop_of(label=method_name, policy~, call)
}

///|
/// The loop itself, for a caller that has already settled idempotency some other
/// way — a JSON-RPC batch does it by admission.
///
/// `label` names the thing being retried in a cancellation message and decides
/// nothing. Splitting it off the method name keeps such a caller from inventing
/// a name that misses the send-once list.
#internal(internal, "the retry loop is not public API")
#doc(hidden)
pub async fn retry_loop_of(
  label~ : String,
  policy~ : RetryPolicy,
  call : async () -> Json raise ProviderError,
) -> Json raise ProviderError {
  // Written out rather than handed to `@async.retry`, which picks its delay
  // from the strategy alone and so has nowhere to read a `Retry-After` from.
  // The price is that `first_delay` / `next_delay` mirror what `@async.retry`
  // reads `RetryMethod` to mean, and have to keep matching it.
  for attempt = 0, delay = first_delay(policy.strategy) {
    try call() catch {
      e => {
        guard attempt < policy.max_retry &&
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
            raise Transport("the retry of \{label} was cancelled: \{cancelled}")
        }
        continue attempt + 1, next_delay(policy.strategy, delay)
      }
    } noraise {
      answer => return answer
    }
  }
}

///|
/// The longest wait this loop sits through, in seconds. A node that asks for
/// longer is saying the quota is spent, so the loop hands the failure back; the
/// `Retry-After` is on the error for a caller who does want to wait.
///
/// A minute: past every backoff this loop runs, and short of the quota windows a
/// hosted RPC hands out.
const MAX_RETRY_AFTER_S : Int = 60

///|
/// How long the node asked to be left alone for. Only an HTTP response carries
/// such a request, and only `provider/http/endpoint` reads one off the wire.
fn retry_after_seconds(error : ProviderError) -> Int? {
  guard error is HttpStatus(info~, ..) else { return None }
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
/// The methods that must be sent at most once. A **deliberate difference from
/// viem**: behind a wallet these are prompts, and a retry is a second dialog for
/// a request the user may already have answered.
///
/// `eth_sendRawTransaction` is deliberately **not** here — a resend is
/// byte-identical and the node drops the duplicate.
#internal(internal, "the send-once list is not public API")
#doc(hidden)
pub fn is_not_idempotent(method_name : String) -> Bool {
  method_name.has_prefix("wallet_") ||
  method_name == "eth_sendTransaction" ||
  method_name == "eth_requestAccounts" ||
  method_name == "personal_sign" ||
  method_name == "eth_signTypedData_v4"
}
