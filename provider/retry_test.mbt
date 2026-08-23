///|
/// Drive `method_name` through `retry_loop` against `mock`, inside the task
/// group every async call needs, and answer with the error it ended on.
///
/// `Immediate` unless a test says otherwise: these tests are about which attempt
/// happens, and the real 150ms backoff would only make them slow.
async fn drive(
  mock : @provider.MockProvider,
  method_name~ : String,
  strategy? : @async.RetryMethod = Immediate,
  max_retry? : Int = 3,
) -> @provider.ProviderError? {
  @async.with_task_group(_ => {
    try
      @provider.retry_loop(
        method_name~,
        policy=@provider.RetryPolicy::new(strategy~, max_retry~),
        () => mock.request(method_name~, params=Json::array([])),
      )
    catch {
      e => Some(e)
    } noraise {
      _ => None
    }
  })
}

///|
async test "a retryable failure is tried again, and the answer that follows is the one returned" {
  let mock = @provider.MockProvider::new().on_sequence(
    method_name="eth_blockNumber",
    answers=[Raises(Transport("connection refused")), Answers("0x2a".to_json())],
  )
  assert_eq(drive(mock, method_name="eth_blockNumber"), None)
  // exactly two attempts: the loop stopped as soon as it had an answer
  assert_eq(mock.calls().length(), 2)
}

///|
async test "a decided failure is not tried again" {
  let mock = @provider.MockProvider::new().on_error(
    method_name="eth_sendRawTransaction",
    error=UserRejected,
  )
  assert_eq(
    drive(mock, method_name="eth_sendRawTransaction"),
    Some(UserRejected),
  )
  assert_eq(mock.calls().length(), 1)
}

///|
async test "running out of retries raises the last failure" {
  let busy = busy()
  let mock = @provider.MockProvider::new().on_error(
    method_name="eth_blockNumber",
    error=busy,
  )
  assert_eq(drive(mock, method_name="eth_blockNumber", max_retry=2), Some(busy))
  // `max_retry` counts the retries, not the attempts
  assert_eq(mock.calls().length(), 3)
}

///|
async test "a non-idempotent method is sent once, however retryable the failure looks" {
  let refused = @provider.Transport("connection refused")
  let mock = @provider.MockProvider::new().on_error(
    method_name="eth_sendTransaction",
    error=refused,
  )
  assert_eq(drive(mock, method_name="eth_sendTransaction"), Some(refused))
  assert_eq(mock.calls().length(), 1)
}

///|
/// `Retry-After` is a node stating what the backoff can only guess at, so the
/// loop waits what it asked for instead — here, nothing at all, against a
/// backoff a second long that the elapsed time would show.
async test "a Retry-After on the failure is waited instead of the backoff" {
  let mock = @provider.MockProvider::new().on_sequence(
    method_name="eth_blockNumber",
    answers=[Raises(busy(retry_after=0)), Answers("0x2a".to_json())],
  )
  let started = @async.now()
  assert_eq(
    drive(mock, method_name="eth_blockNumber", strategy=FixedDelay(1_000)),
    None,
  )
  assert_eq(mock.calls().length(), 2)
  assert_true(@async.now() - started < 500)
}

///|
/// A node asking to be left alone for longer than the loop is willing to wait
/// ends it: coming back sooner than it asked is another `429`, and sitting on
/// the caller's request that long is worse than answering.
async test "a Retry-After past what the loop will wait ends it" {
  let asked = busy(retry_after=61)
  let mock = @provider.MockProvider::new().on_error(
    method_name="eth_blockNumber",
    error=asked,
  )
  assert_eq(drive(mock, method_name="eth_blockNumber"), Some(asked))
  // no second attempt: the wait, not the retry count, is what stopped it
  assert_eq(mock.calls().length(), 1)
}

///|
/// A `429` from a node, with or without a `Retry-After`.
fn busy(retry_after? : Int) -> @provider.ProviderError {
  HttpStatus(
    code=429,
    url="https://node.example",
    info=@provider.HttpStatusInfo::new(retry_after?),
  )
}
