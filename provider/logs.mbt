///|
/// Return the logs matching `filter` (`eth_getLogs`) — the events already on
/// the chain, as opposed to the ones a receipt carries for a transaction the
/// caller just sent.
///
/// The `topics` come back as raw `Hex` and the `data` ABI-encoded, exactly as
/// in a receipt: `@abi.event_topic` computes the topic to filter on, and
/// `@abi.decode` reads the `data` back.
///
/// A node applies its own limits to the range and to how many logs it will
/// answer with, and raises its own error when a filter exceeds them. The SDK
/// sends the filter as it is given, so narrowing a search that a node refuses —
/// splitting the range, adding an address — is the caller's.
///
/// ```
/// async fn[P : @provider.Provider] transfers_of(
///   p : P,
///   token : @types.Address,
///   transfer : @types.Topic,
/// ) -> Array[@types.Log] raise @provider.ProviderError {
///   @provider.logs(
///     p,
///     @types.LogFilter::range(
///       from_block=Number(18000000),
///       address=[token],
///       topics=[Some(transfer)],
///     ),
///   )
/// }
/// ```
pub async fn[P : Provider] logs(
  provider : P,
  filter : @types.LogFilter,
) -> Array[@types.Log] raise ProviderError {
  invoke_rpc(
    provider,
    method_name="eth_getLogs",
    params=Json::array([filter.to_json()]),
    decode=@types.Log::array_from_json,
  )
}
