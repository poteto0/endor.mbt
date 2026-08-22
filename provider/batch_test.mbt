///|
fn call(method_name : String) -> @provider.BatchCall {
  @provider.BatchCall::new(method_name~, params=Json::array([]))
}

///|
async test "every call is answered, in the order it was given" {
  let mock = @provider.MockProvider::new()
    .on(method_name="eth_chainId", response="0x1".to_json())
    .on(method_name="eth_blockNumber", response="0x2a".to_json())
  let answers = @provider.request_many(mock, [
    call("eth_blockNumber"),
    call("eth_chainId"),
  ])
  assert_eq(answers, [Ok("0x2a".to_json()), Ok("0x1".to_json())])
}

///|
async test "a call that fails keeps its failure while the others still answer" {
  let mock = @provider.MockProvider::new()
    .on(method_name="eth_chainId", response="0x1".to_json())
    .on_error(
      method_name="eth_blockNumber",
      error=Transport("connection refused"),
    )
  let answers = @provider.request_many(mock, [
    call("eth_chainId"),
    call("eth_blockNumber"),
  ])
  assert_eq(answers[0], Ok("0x1".to_json()))
  assert_true(answers[1] is Err(Transport(_)))
}

///|
async test "an empty batch touches nothing" {
  let mock = @provider.MockProvider::new()
  assert_eq(@provider.request_many(mock, []), [])
  assert_eq(mock.calls().length(), 0)
}
