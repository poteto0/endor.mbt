///|
/// Decode a JSON array of address strings into `Array[Address]`, mapping any
/// codec failure to an `Rpc(-32603)` provider error.
fn decode_accounts(j : Json) -> Array[@types.Address] raise ProviderError {
  guard j is Array(items) else {
    raise ProviderError::internal("expected accounts array")
  }
  let out = []
  for it in items {
    out.push(
      @types.Address::from_json(it) catch {
        e => raise ProviderError::internal("decode address: \{e}")
      },
    )
  }
  out
}

///|
/// Request the user's accounts, prompting the wallet to connect if needed
/// (`eth_requestAccounts`). The first element is the currently selected
/// account.
///
/// ```
/// async fn connect(p : &@endor.Provider) -> @endor.Address raise @endor.ProviderError {
///   @endor.request_accounts(p)[0]
/// }
/// ```
pub async fn[P : Provider] request_accounts(
  provider : P,
) -> Array[@types.Address] raise ProviderError {
  let r = provider.request(
    method_name="eth_requestAccounts",
    params=Json::array([]),
  )
  decode_accounts(r)
}

///|
/// Return the accounts the wallet has already authorized without prompting
/// (`eth_accounts`). Returns an empty array when the dapp is not connected.
///
/// ```
/// async fn current(p : &@endor.Provider) -> Int raise @endor.ProviderError {
///   @endor.accounts(p).length()
/// }
/// ```
pub async fn[P : Provider] accounts(
  provider : P,
) -> Array[@types.Address] raise ProviderError {
  let r = provider.request(method_name="eth_accounts", params=Json::array([]))
  decode_accounts(r)
}

///|
/// Return the chain id the wallet is currently connected to (`eth_chainId`).
///
/// ```
/// async fn on_mainnet(p : &@endor.Provider) -> Bool raise @endor.ProviderError {
///   @endor.chain_id(p) == @endor.ChainId::mainnet()
/// }
/// ```
pub async fn[P : Provider] chain_id(
  provider : P,
) -> @types.ChainId raise ProviderError {
  let r = provider.request(method_name="eth_chainId", params=Json::array([]))
  @types.ChainId::from_json(r) catch {
    e => raise ProviderError::internal("decode chainId: \{e}")
  }
}
