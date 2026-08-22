///|
/// How a provider folds concurrent calls into one JSON-RPC batch. The fields
/// are private so that a policy which later wants a byte budget or a per-method
/// rule is not a breaking change.
///
/// A transport that cannot fold — a browser wallet — ignores it.
pub struct BatchPolicy {
  priv wait : Int
  priv max_size : Int
}

///|
/// `wait` is how long the window stays open, in milliseconds; `max_size` is how
/// many calls close it early.
pub fn BatchPolicy::new(
  wait? : Int = DEFAULT_BATCH_WAIT,
  max_size? : Int = DEFAULT_BATCH_MAX_SIZE,
) -> BatchPolicy {
  BatchPolicy::{ wait: wait.max(0), max_size: max_size.max(1) }
}

///|
/// viem's numbers: a 16ms window, at most 100 calls in it.
///
/// ```
/// let policy = @provider.BatchPolicy::default()
/// inspect(policy.wait(), content="16")
/// ```
pub fn BatchPolicy::default() -> BatchPolicy {
  BatchPolicy::new()
}

///|
/// How long the window stays open, in milliseconds.
pub fn BatchPolicy::wait(self : BatchPolicy) -> Int {
  self.wait
}

///|
/// How many calls fit in one window.
pub fn BatchPolicy::max_size(self : BatchPolicy) -> Int {
  self.max_size
}

///|
/// One frame at 60Hz — long enough for the reads a render kicks off together to
/// land in the same window, short enough that a lone read does not feel it.
const DEFAULT_BATCH_WAIT : Int = 16

///|
/// Nodes cap batch length, and the cap is not advertised. A hundred is under
/// every published one, and the overflow waits for the next window rather than
/// being split into a second POST — splitting defeats the cap it is under.
const DEFAULT_BATCH_MAX_SIZE : Int = 100
