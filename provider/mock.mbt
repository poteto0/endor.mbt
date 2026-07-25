///|
/// An in-memory `Provider` for tests: a table mapping JSON-RPC method names to
/// canned JSON responses or errors. Every call is recorded so tests can assert
/// that the RPC layer built the expected method name and params.
///
/// ```
/// let mock = @endor.MockProvider::new().on(
///   method_name="eth_chainId",
///   response=Json::string("0x1"),
/// )
/// ignore(mock)
/// ```
pub struct MockProvider {
  priv responses : Map[String, Json]
  priv errors : Map[String, ProviderError]
  priv calls : Array[(String, Json)]
}

///|
/// Create an empty mock provider.
pub fn MockProvider::new() -> MockProvider {
  MockProvider::{ responses: Map([]), errors: Map([]), calls: [] }
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
