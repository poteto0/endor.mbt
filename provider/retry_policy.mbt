///|
/// How hard a provider tries again. The fields are private so that a policy
/// which later wants jitter or a per-method rule is not a breaking change.
pub struct RetryPolicy {
  priv strategy : @async.RetryMethod
  priv max_retry : Int
}

///|
/// `max_retry` is retries *after* the first attempt: `new(max_retry=5)` is six
/// attempts at most.
pub fn RetryPolicy::new(
  strategy? : @async.RetryMethod = default_strategy,
  max_retry? : Int = DEFAULT_MAX_RETRY,
) -> RetryPolicy {
  RetryPolicy::{ strategy, max_retry: max_retry.max(0) }
}

///|
/// viem's numbers: 150ms doubling to at most 2s, three retries.
pub fn RetryPolicy::default() -> RetryPolicy {
  RetryPolicy::new()
}

///|
/// No second attempt — for a caller whose own retry layer would otherwise
/// multiply with this one.
pub fn RetryPolicy::none() -> RetryPolicy {
  RetryPolicy::new(max_retry=0)
}

///|
const DEFAULT_MAX_RETRY : Int = 3

///|
let default_strategy : @async.RetryMethod = ExponentialDelay(
  initial=150,
  factor=2.0,
  maximum=2_000,
)
