///|
/// Perform one JSON-RPC read and decode its result. A malformed response is
/// the SDK's own problem, so it surfaces as `ProviderError::internal` naming
/// the method that answered; wallet-side errors propagate untouched.
///
/// Every typed helper below is this function plus a `decode`, which is what
/// keeps their error behaviour identical.
async fn[P : Provider, T] read(
  provider : P,
  method_name~ : String,
  params~ : Json,
  decode~ : (Json) -> T raise @types.CodecError,
) -> T raise ProviderError {
  let r = provider.request(method_name~, params~)
  decode(r) catch {
    e => raise ProviderError::internal("decode \{method_name}: \{e}")
  }
}

///|
/// The `[address, block]` parameter pair shared by the account reads.
fn account_params(who : @types.Address, block : @types.BlockTag) -> Json {
  Json::array([who.to_json(), block.to_json()])
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
  read(
    provider,
    method_name="eth_requestAccounts",
    params=Json::array([]),
    decode=@types.Address::array_from_json,
  )
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
  read(
    provider,
    method_name="eth_accounts",
    params=Json::array([]),
    decode=@types.Address::array_from_json,
  )
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
  read(
    provider,
    method_name="eth_chainId",
    params=Json::array([]),
    decode=@types.ChainId::from_json,
  )
}

///|
/// Return the balance of `who` in wei (`eth_getBalance`).
///
/// `block` is the block the balance is read at — `Latest` by default, or any
/// other `BlockTag` (`Pending`, `Finalized`, `Number(n)`, …).
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
  block? : @types.BlockTag = Latest,
) -> @types.Wei raise ProviderError {
  read(
    provider,
    method_name="eth_getBalance",
    params=account_params(who, block),
    decode=@types.Wei::from_json,
  )
}

///|
/// Return the number of the most recent block (`eth_blockNumber`).
///
/// ```
/// async fn[P : @provider.Provider] head(
///   p : P,
/// ) -> UInt64 raise @provider.ProviderError {
///   @provider.block_number(p)
/// }
/// ```
pub async fn[P : Provider] block_number(
  provider : P,
) -> UInt64 raise ProviderError {
  read(
    provider,
    method_name="eth_blockNumber",
    params=Json::array([]),
    decode=@types.Quantity::from_json,
  ).to_uint64()
}

///|
/// Return how many transactions `who` has sent (`eth_getTransactionCount`) —
/// the nonce to use for its next transaction.
///
/// Reading at `Pending` counts transactions the wallet has broadcast but that
/// are not mined yet, which is usually what a sender wants; `Latest` (the
/// default) counts only mined ones.
///
/// ```
/// async fn[P : @provider.Provider] next_nonce(
///   p : P,
///   who : @types.Address,
/// ) -> UInt64 raise @provider.ProviderError {
///   @provider.transaction_count(p, who, block=Pending)
/// }
/// ```
pub async fn[P : Provider] transaction_count(
  provider : P,
  who : @types.Address,
  block? : @types.BlockTag = Latest,
) -> UInt64 raise ProviderError {
  read(
    provider,
    method_name="eth_getTransactionCount",
    params=account_params(who, block),
    decode=@types.Quantity::from_json,
  ).to_uint64()
}

///|
/// Return the current gas price in wei (`eth_gasPrice`).
///
/// ```
/// async fn[P : @provider.Provider] gwei(
///   p : P,
/// ) -> BigInt raise @provider.ProviderError {
///   @provider.gas_price(p).to_bigint() / 1_000_000_000N
/// }
/// ```
pub async fn[P : Provider] gas_price(
  provider : P,
) -> @types.Wei raise ProviderError {
  read(
    provider,
    method_name="eth_gasPrice",
    params=Json::array([]),
    decode=@types.Wei::from_json,
  )
}

///|
/// Return the contract bytecode deployed at `who` (`eth_getCode`). An
/// externally owned account has no code, so it answers with an empty `Hex`.
///
/// ```
/// async fn[P : @provider.Provider] code_size(
///   p : P,
///   who : @types.Address,
/// ) -> Int raise @provider.ProviderError {
///   @provider.code(p, who).byte_length()
/// }
/// ```
pub async fn[P : Provider] code(
  provider : P,
  who : @types.Address,
  block? : @types.BlockTag = Latest,
) -> @types.Hex raise ProviderError {
  read(
    provider,
    method_name="eth_getCode",
    params=account_params(who, block),
    decode=@types.Hex::from_json,
  )
}

///|
/// Whether `who` is a contract, i.e. whether `eth_getCode` returns any bytes
/// at `block`. A contract deployed after `block` still reads as `false` there.
///
/// ```
/// async fn[P : @provider.Provider] warn_on_contract(
///   p : P,
///   who : @types.Address,
/// ) -> String raise @provider.ProviderError {
///   if @provider.is_contract(p, who) { "contract" } else { "wallet" }
/// }
/// ```
pub async fn[P : Provider] is_contract(
  provider : P,
  who : @types.Address,
  block? : @types.BlockTag = Latest,
) -> Bool raise ProviderError {
  !code(provider, who, block~).is_empty()
}
