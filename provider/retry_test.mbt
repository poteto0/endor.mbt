///|
/// Drive `method_name` through `retry_loop` against `mock`, inside the task
/// group every async call needs, and answer with the error it ended on (or
/// `None` when it answered).
///
/// `Immediate` throughout: what these tests are about is which attempt happens
/// and which does not, and the real 150ms backoff would only make them slow.
async fn drive(
  mock : @provider.MockProvider,
  method_name~ : String,
  max_retry? : Int = 3,
) -> @provider.ProviderError? {
  @async.with_task_group(_ => {
    try
      @provider.retry_loop(method_name~, strategy=Immediate, max_retry~, () => {
        mock.request(method_name~, params=Json::array([]))
      })
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
  let busy = @provider.HttpStatus(code=429, url="https://node.example")
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
