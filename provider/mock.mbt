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
pub struct MockProvider {
  priv responses : Map[String, Json]
  priv errors : Map[String, ProviderError]
  priv sequences : Map[String, Array[Answer]]
  priv calls : Array[(String, Json)]
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
  // A registered run answers first, one entry per call, until it is used up.
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
    None =>
      raise Rpc(
        code=-32601,
        message="MockProvider: no response for \{method_name}",
      )
  }
}
