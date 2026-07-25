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
/// async fn[P : @provider.Provider] connect(
///   p : P,
/// ) -> @types.Address raise @provider.ProviderError {
///   @provider.request_accounts(p)[0]
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
/// async fn[P : @provider.Provider] current(
///   p : P,
/// ) -> Int raise @provider.ProviderError {
///   @provider.accounts(p).length()
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
/// async fn[P : @provider.Provider] on_mainnet(
///   p : P,
/// ) -> Bool raise @provider.ProviderError {
///   @provider.chain_id(p) == @types.ChainId::mainnet()
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

///|
/// Return the balance of `who` in wei (`eth_getBalance`).
///
/// `block` is the block tag the balance is read at — `"latest"` by default,
/// but any tag the wallet accepts (`"pending"`, `"finalized"`, or a
/// `0x`-prefixed block number) works.
///
/// ```
/// async fn[P : @provider.Provider] is_funded(
///   p : P,
///   who : @types.Address,
/// ) -> Bool raise @provider.ProviderError {
///   @provider.balance(p, who) != @types.Wei::zero()
/// }
/// ```
pub async fn[P : Provider] balance(
  provider : P,
  who : @types.Address,
  block? : String = "latest",
) -> @types.Wei raise ProviderError {
  let r = provider.request(
    method_name="eth_getBalance",
    params=Json::array([who.to_json(), Json::string(block)]),
  )
  @types.Wei::from_json(r) catch {
    e => raise ProviderError::internal("decode wei: \{e}")
  }
}
