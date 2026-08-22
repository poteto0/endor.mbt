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
/// A `Provider` that answers several requests in one round trip.
///
/// It is a trait of its own for the reason `EventSource` is: a transport can
/// answer RPC without being able to answer many at once. EIP-1193 has no
/// batch — `request` is one call — so a browser provider cannot implement this
/// and is not asked to: `request_many` is the function every `Provider` gets,
/// and implementing this trait is the claim that the round trips really do
/// collapse. JSON-RPC over HTTP is where that is true.
///
/// A call that fails keeps its failure as a value, so the answers that did
/// arrive are still there. Only a failure of the batch itself is raised.
///
/// ```
/// async fn chain_and_block[P : @provider.BatchProvider](
///   p : P,
/// ) -> Array[Result[Json, @provider.ProviderError]] raise @provider.ProviderError {
///   p.request_many([
///     @provider.BatchCall::new(method_name="eth_chainId", params=Json::array([])),
///     @provider.BatchCall::new(method_name="eth_blockNumber", params=Json::array([])),
///   ])
/// }
/// ```
pub(open) trait BatchProvider: Provider {
  /// Answer `calls`, in the order they were given.
  async fn request_many(Self, Array[BatchCall]) -> Array[
    Result[Json, ProviderError],
  ] raise ProviderError
}

///|
/// Answer `calls` with one `request` each, run concurrently, in the order they
/// were given.
///
/// This is the path any `Provider` gets, `BatchProvider` or not: the round
/// trips stay N, but they stop waiting for each other, which is the win that
/// is available over an async message port. A caller that wants the fold takes
/// a `P : BatchProvider` instead — the code either side of the call is the
/// same.
///
/// `max_concurrent` bounds how many are in flight at once, for the endpoint
/// that answers a fan-out of two hundred reads with rate limiting rather than
/// with answers. Unbounded by default, the way a folded batch is.
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
