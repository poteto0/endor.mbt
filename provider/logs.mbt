///|
/// Return the logs matching `filter` (`eth_getLogs`) — the events already on the
/// chain, as opposed to the ones a receipt carries.
///
/// The `topics` come back as raw `Hex` and the `data` ABI-encoded, exactly as in
/// a receipt. A node applies its own limits to the range, and the SDK sends the
/// filter as given, so narrowing one a node refuses is the caller's.
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
