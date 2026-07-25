///|
/// Evaluate `request` against the node's state without broadcasting anything
/// (`eth_call`) and return the raw return data. This is how a contract's view
/// functions are read: no signature, no gas, no wallet prompt.
///
/// `block` is the state the call is evaluated against — `Latest` by default, or
/// any other `BlockTag`. There is no ABI layer yet, so the answer is the callee's
/// return data as `Hex` for the caller to decode.
///
/// A call that reverts is a wallet-side failure, not a decode failure: the node
/// answers with an error and it propagates as the `ProviderError` it mapped to.
///
/// ```
/// async fn[P : @provider.Provider] balance_of(
///   p : P,
///   token : @types.Address,
///   calldata : @types.Hex,
/// ) -> @types.Hex raise @provider.ProviderError {
///   @provider.call(p, @types.CallRequest::new(token, data=calldata))
/// }
/// ```
pub async fn[P : Provider] call(
  provider : P,
  request : @types.CallRequest,
  block? : @types.BlockTag = Latest,
) -> @types.Hex raise ProviderError {
  read(
    provider,
    method_name="eth_call",
    params=Json::array([request.to_json(), block.to_json()]),
    decode=@types.Hex::from_json,
  )
}

///|
/// Estimate how much gas `request` would need (`eth_estimateGas`). The node
/// simulates the call the way `call` does, so this too needs no signature and no
/// prompt.
///
/// The result is an upper estimate, not a guarantee: it is measured against
/// current state, and a transaction reaching a different state can still run out
/// of gas. A request the node cannot execute at all — one that reverts — comes
/// back as a `ProviderError`, which is what makes this a cheap way to check a
/// transaction before asking the user to sign it.
///
/// ```
/// async fn[P : @provider.Provider] gas_for(
///   p : P,
///   req : @types.CallRequest,
/// ) -> UInt64 raise @provider.ProviderError {
///   @provider.estimate_gas(p, req).to_uint64()
/// }
/// ```
pub async fn[P : Provider] estimate_gas(
  provider : P,
  request : @types.CallRequest,
) -> @types.Quantity raise ProviderError {
  read(
    provider,
    method_name="eth_estimateGas",
    params=Json::array([request.to_json()]),
    decode=@types.Quantity::from_json,
  )
}
