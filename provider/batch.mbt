///|
/// One JSON-RPC call of a batch: the same pair `Provider::request` takes.
///
/// ```
/// let call = @provider.BatchCall::new(
///   method_name="eth_chainId",
///   params=Json::array([]),
/// )
/// inspect(call.method_name(), content="eth_chainId")
/// ```
pub struct BatchCall {
  priv method_name : String
  priv params : Json
} derive(Eq, @debug.Debug)

///|
/// Build one call of a batch.
pub fn BatchCall::new(method_name~ : String, params~ : Json) -> BatchCall {
  BatchCall::{ method_name, params }
}

///|
/// The method this call names.
pub fn BatchCall::method_name(self : BatchCall) -> String {
  self.method_name
}

///|
/// The params this call carries.
pub fn BatchCall::params(self : BatchCall) -> Json {
  self.params
}

///|
/// Answer `calls` with one `request` each, run concurrently, in the order they
/// were given.
///
/// The round trips stay N — EIP-1193 has no batch. What it takes away is the
/// waiting. A call that fails keeps its failure as a value, and `max_concurrent`
/// bounds how many are in flight for an endpoint that rate-limits a fan-out.
///
/// ```
/// async fn balances[P : @provider.Provider](
///   p : P,
///   who : Array[Json],
/// ) -> Array[Result[Json, @provider.ProviderError]] raise @provider.ProviderError {
///   @provider.request_many(
///     p,
///     who.map(w => @provider.BatchCall::new(
///       method_name="eth_getBalance",
///       params=Json::array([w, Json::string("latest")]),
///     )),
///   )
/// }
/// ```
pub async fn[P : Provider] request_many(
  p : P,
  calls : Array[BatchCall],
  max_concurrent? : Int,
) -> Array[Result[Json, ProviderError]] raise ProviderError {
  let tasks : Array[async () -> Result[Json, ProviderError]] = calls.map(one => {
    () => {
      Ok(p.request(method_name=one.method_name, params=one.params)) catch {
        e => Err(e)
      }
    }
  })
  // An empty batch spawns nothing, so it answers `[]` without a round trip.
  @async.all(tasks[:], max_concurrent?) catch {
    // Each task keeps its own failure, so nothing but a cancellation of the
    // group gets out this way.
    e => raise Transport("the batch was cancelled: \{e}")
  }
}
