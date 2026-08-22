///|
/// One JSON-RPC call of a batch: the same pair `Provider::request` takes.
///
/// It is `pub(all)` because it carries no invariant — any method name and any
/// params value are as valid here as they are on `request` — and because the
/// transport that folds a batch into one body has to read both fields from its
/// own package.
///
/// ```
/// let call = @provider.BatchCall::new(
///   method_name="eth_chainId",
///   params=Json::array([]),
/// )
/// ignore(call)
/// ```
pub(all) struct BatchCall {
  method_name : String
  params : Json
} derive(Eq, @debug.Debug)

///|
/// Build one call of a batch.
pub fn BatchCall::new(method_name~ : String, params~ : Json) -> BatchCall {
  BatchCall::{ method_name, params }
}

///|
/// A `Provider` that can answer several requests at once.
///
/// It is a trait of its own for the reason `EventSource` is: a transport can
/// answer RPC without being able to answer many at once. EIP-1193 has no
/// batch — `request` is one call, `sendAsync` is superseded, and the wallets'
/// own batch extensions are non-standard — so a browser provider could never
/// implement a batch-only interface, and making one would leave every dapp
/// behind the extension out of it.
///
/// So `request_many` has a default implementation: `request` per call, run
/// concurrently. It is not a fold into one round trip, but it is the win that
/// is actually available over an async message port, and it means the caller
/// writes the same code either way. `provider/http` overrides it with a real
/// JSON-RPC batch, where the round trips do collapse into one.
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
  ] raise ProviderError = _
}

///|
/// The default: the concurrent one, so a transport declares `BatchProvider`
/// only to say it has something better.
impl BatchProvider with fn request_many(self, calls) {
  request_many(self, calls)
}

///|
/// Answer `calls` concurrently with one `request` each, in the order they were
/// given.
///
/// This is what `BatchProvider` does by default, as a function any `Provider`
/// can be handed to: a type that implements only `Provider` still gets the
/// concurrency, without claiming a batch it does not have.
///
/// An empty batch answers `[]` without touching the network, the way
/// `@multicall.aggregate3` does.
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
) -> Array[Result[Json, ProviderError]] raise ProviderError {
  guard !calls.is_empty() else { return [] }
  @async.with_task_group(group => {
    let tasks = calls.map(one => {
      group.spawn(() => {
        Ok(p.request(method_name=one.method_name, params=one.params)) catch {
          e => Err(e)
        }
      })
    })
    let answers = []
    for task in tasks {
      answers.push(task.wait())
    }
    answers
  }) catch {
    // The tasks keep their own failures, so nothing but a cancellation of the
    // group itself gets out this way.
    e => raise Transport("the batch was cancelled: \{e}")
  }
}
