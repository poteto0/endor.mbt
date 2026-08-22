///|
/// An in-memory `Provider` for tests: a table mapping JSON-RPC method names to
/// canned JSON responses or errors. Every call is recorded so tests can assert
/// that the RPC layer built the expected method name and params.
///
/// ```
/// let mock = @provider.MockProvider::new().on(
///   method_name="eth_chainId",
///   response=Json::string("0x1"),
/// )
/// ignore(mock)
/// ```
///
/// It is also an `EventSource`: `emit` fires an EIP-1193 event at whatever
/// `subscribe` (or a typed helper such as `on_accounts_changed`) registered, so
/// event handling is testable without a wallet.
pub struct MockProvider {
  priv responses : Map[String, Json]
  priv errors : Map[String, ProviderError]
  priv sequences : Map[String, Array[Answer]]
  priv calls : Array[(String, Json)]
  /// Registered event listeners, per event name. The `Int` is the id
  /// `unsubscribe` removes by, so cancelling one of several listeners on the
  /// same event removes exactly that one.
  priv listeners : Map[String, Array[(Int, (Json) -> Unit)]]
  priv mut next_listener_id : Int
}

///|
/// What a mocked method does on one call: answer, or raise.
pub(all) enum Answer {
  /// Answer with this JSON result.
  Answers(Json)
  /// Raise this error instead of answering.
  Raises(ProviderError)
}

///|
/// Create an empty mock provider.
pub fn MockProvider::new() -> MockProvider {
  MockProvider::{
    responses: Map([]),
    errors: Map([]),
    sequences: Map([]),
    calls: [],
    listeners: Map([]),
    next_listener_id: 0,
  }
}

///|
/// Register a canned successful response for `method_name`. Returns the same
/// provider for chaining.
pub fn MockProvider::on(
  self : MockProvider,
  method_name~ : String,
  response~ : Json,
) -> MockProvider {
  self.responses[method_name] = response
  self
}

///|
/// Register a canned error for `method_name`. Returns the same provider for
/// chaining.
pub fn MockProvider::on_error(
  self : MockProvider,
  method_name~ : String,
  error~ : ProviderError,
) -> MockProvider {
  self.errors[method_name] = error
  self
}

///|
/// Register a run of answers for `method_name`: the first call gets the first
/// answer, the second the second, and so on. Once they run out, calls fall back
/// to whatever `on` / `on_error` registered.
///
/// This is what a flow that retries needs — a wallet answering
/// `wallet_switchEthereumChain` with 4902 and then succeeding once the chain
/// has been added.
///
/// ```
/// let mock = @provider.MockProvider::new().on_sequence(
///   method_name="wallet_switchEthereumChain",
///   answers=[Raises(UnrecognizedChain), Answers(Json::null())],
/// )
/// ignore(mock)
/// ```
pub fn MockProvider::on_sequence(
  self : MockProvider,
  method_name~ : String,
  answers~ : Array[Answer],
) -> MockProvider {
  self.sequences[method_name] = answers
  self
}

///|
/// The list of `(method_name, params)` calls received so far, in order.
pub fn MockProvider::calls(self : MockProvider) -> Array[(String, Json)] {
  self.calls
}

///|
/// The most recent `(method_name, params)` call, if any.
pub fn MockProvider::last_call(self : MockProvider) -> (String, Json)? {
  self.calls.last()
}

///|
pub impl Provider for MockProvider with fn request(self, method_name~, params~) {
  self.calls.push((method_name, params))
  // a registered run answers first, one entry per call, until it is used up
  if self.sequences.get(method_name) is Some(answers) && !answers.is_empty() {
    return match answers.remove(0) {
      Answers(j) => j
      Raises(e) => raise e
    }
  }
  if self.errors.get(method_name) is Some(e) {
    raise e
  }
  match self.responses.get(method_name) {
    Some(j) => j
    // deliberately *not* `-32601`, which `is_method_not_found` turns into an
    // answer: a test that forgot to register a response must fail loudly
    None => raise InvalidConfig("MockProvider: no response for \{method_name}")
  }
}

///|
/// Register a listener in memory. Each one gets an id, so the returned
/// `Subscription` removes exactly the listener it belongs to and leaves the
/// others on the same event registered.
pub impl EventSource for MockProvider with fn subscribe(self, event~, handler~) {
  let id = self.next_listener_id
  self.next_listener_id = id + 1
  let registered = self.listeners.get_or_init(event, () => [])
  registered.push((id, handler))
  // the array's identity is stable, so cancelling needs nothing else
  Subscription::new(() => registered.retain(entry => entry.0 != id))
}

///|
/// Fire `event` at every listener subscribed to it, in registration order —
/// what a wallet does when the user switches account or chain.
///
/// The payload is the raw JSON EIP-1193 would carry, so a test can hand a
/// malformed one over and assert the typed helper dropped it.
///
/// ```mbt check
/// test "doc: mock emits an event" {
///   let mock = @provider.MockProvider::new()
///   let seen = []
///   let _ = @provider.on_chain_changed(mock, chain => seen.push(chain))
///   mock.emit(event="chainChanged", payload="0x1".to_json())
///   inspect(seen[0], content="ChainId(1)")
/// }
/// ```
pub fn MockProvider::emit(
  self : MockProvider,
  event~ : String,
  payload~ : Json,
) -> Unit {
  guard self.listeners.get(event) is Some(registered) else { return }
  // iterate a copy: a handler may unsubscribe itself while this walks
  for entry in registered.copy() {
    (entry.1)(payload)
  }
}
