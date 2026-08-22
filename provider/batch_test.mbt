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

///|
/// A transport that really does fold: it answers the whole batch itself and
/// counts how many times it was asked.
struct Folding {
  mut rounds : Int
}

///|
impl @provider.Provider for Folding with fn request(self, method_name~, params~) {
  ignore(params)
  self.rounds += 1
  method_name.to_json()
}

///|
impl @provider.BatchProvider for Folding with fn request_many(self, calls) {
  self.rounds += 1
  calls.map(one => Ok(one.method_name().to_json()))
}

///|
async test "a BatchProvider answers the whole batch in one round" {
  let folding = Folding::{ rounds: 0 }
  let answers = @provider.BatchProvider::request_many(folding, [
    call("eth_chainId"),
    call("eth_blockNumber"),
  ])
  assert_eq(answers, [
    Ok("eth_chainId".to_json()),
    Ok("eth_blockNumber".to_json()),
  ])
  assert_eq(folding.rounds, 1)
}

///|
async test "the same transport still takes one round per call through request_many" {
  let folding = Folding::{ rounds: 0 }
  let _ = @provider.request_many(folding, [
    call("eth_chainId"),
    call("eth_blockNumber"),
  ])
  assert_eq(folding.rounds, 2)
}

///|
/// A provider that writes down when each request started and finished, and
/// sleeps in between so a concurrent run has somewhere to interleave.
struct Slow {
  log : Array[String]
}

///|
impl @provider.Provider for Slow with fn request(self, method_name~, params~) {
  ignore(params)
  self.log.push("start \{method_name}")
  @async.sleep(5) catch {
    e => raise @provider.Transport("\{e}")
  }
  self.log.push("end \{method_name}")
  Json::null()
}

///|
async test "the calls run concurrently rather than one after the other" {
  let slow = Slow::{ log: [] }
  let _ = @provider.request_many(slow, [call("first"), call("second")])
  assert_eq(slow.log, ["start first", "start second", "end first", "end second"])
}
