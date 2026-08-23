///|
/// Ask the wallet to switch the chain it is connected to
/// (`wallet_switchEthereumChain`).
///
/// The wallet prompts the user, so this raises `UserRejected` when they
/// decline, and `UnrecognizedChain` (4902) when the chain is not one it knows —
/// use `switch_or_add_chain` to add it and retry in that case.
///
/// ```
/// async fn[P : @provider.Provider] to_mainnet(
///   p : P,
/// ) -> Unit raise @provider.ProviderError {
///   @provider.switch_chain(p, @types.ChainId::mainnet())
/// }
/// ```
pub async fn[P : Provider] switch_chain(
  provider : P,
  chain_id : @types.ChainId,
) -> Unit raise ProviderError {
  ignore(
    provider.request(
      method_name="wallet_switchEthereumChain",
      params=Json::array([{ "chainId": chain_id.to_json() }]),
    ),
  )
}

///|
/// Ask the wallet to add a chain it does not know yet
/// (`wallet_addEthereumChain`). Wallets treat this as a switch too, so on
/// success the user is generally left on `params.chain_id()`.
///
/// ```
/// async fn[P : @provider.Provider] add_polygon(
///   p : P,
/// ) -> Unit raise @provider.ProviderError {
///   @provider.add_chain(
///     p,
///     @types.ChainParams::new(
///       @types.ChainId::polygon(),
///       chain_name="Polygon Mainnet",
///       rpc_urls=["https://polygon-rpc.com"],
///       native_currency=@types.NativeCurrency::new(name="POL", symbol="POL"),
///     ),
///   )
/// }
/// ```
pub async fn[P : Provider] add_chain(
  provider : P,
  params : @types.ChainParams,
) -> Unit raise ProviderError {
  ignore(
    provider.request(
      method_name="wallet_addEthereumChain",
      params=Json::array([params.to_json()]),
    ),
  )
}

///|
/// Put the wallet on `params.chain_id()`, adding the chain first if the wallet
/// does not know it: switch, and on `UnrecognizedChain` (4902) add and switch
/// again. Every other error propagates from the step that raised it.
///
/// The second switch is what makes it reliable, since a wallet that adds a chain
/// without switching leaves the user where they were.
///
/// ```
/// async fn[P : @provider.Provider] to_polygon(
///   p : P,
/// ) -> Unit raise @provider.ProviderError {
///   @provider.switch_or_add_chain(
///     p,
///     @types.ChainParams::new(
///       @types.ChainId::polygon(),
///       chain_name="Polygon Mainnet",
///       rpc_urls=["https://polygon-rpc.com"],
///       native_currency=@types.NativeCurrency::new(name="POL", symbol="POL"),
///     ),
///   )
/// }
/// ```
pub async fn[P : Provider] switch_or_add_chain(
  provider : P,
  params : @types.ChainParams,
) -> Unit raise ProviderError {
  switch_chain(provider, params.chain_id()) catch {
    UnrecognizedChain => {
      add_chain(provider, params)
      switch_chain(provider, params.chain_id())
    }
    e => raise e
  }
}
