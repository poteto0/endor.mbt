///|
/// Perform one JSON-RPC call and decode its result. A malformed response is
/// the SDK's own problem, so it surfaces as `ProviderError::internal` naming
/// the method that answered; wallet-side errors propagate untouched.
///
/// Every typed helper below is this function plus a `decode`, which is what
/// keeps their error behaviour identical.
async fn[P : Provider, T] invoke_rpc(
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
/// Decode an answer a node spells `null` when it has nothing: a receipt for a
/// transaction it has not mined, a block it does not know. Absence is not a
/// failure, so it decodes to `None` rather than raising.
fn[T] decode_optional(
  j : Json,
  decode : (Json) -> T raise @types.CodecError,
) -> T? raise @types.CodecError {
  match j {
    Null => None
    _ => Some(decode(j))
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
///   let addr = @provider.require_account(p)
/// }
/// ```
pub async fn[P : Provider] request_accounts(
  provider : P,
) -> Array[@types.Address] raise ProviderError {
  invoke_rpc(
    provider,
    method_name="eth_requestAccounts",
    params=Json::array([]),
    decode=@types.Address::array_from_json,
  )
}

///|
/// Prompts for connection and returns one currently selected account (the first item of `eth_requestAccounts`).
///
/// This method is contracted to raise an error upon rejection, so returning an empty array is a breach of contract by the wallet
pub async fn[P : Provider] require_account(
  provider : P,
) -> @types.Address raise ProviderError {
  guard request_accounts(provider).get(0) is Some(addr) else {
    raise ProviderError::internal("wallet returned no accounts")
  }
  addr
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
  invoke_rpc(
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
  invoke_rpc(
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
  invoke_rpc(
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
  invoke_rpc(
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
  invoke_rpc(
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
  invoke_rpc(
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
  invoke_rpc(
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
  invoke_rpc(
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
  invoke_rpc(
    provider,
    method_name="eth_estimateGas",
    params=Json::array([request.to_json()]),
    decode=@types.Quantity::from_json,
  )
}

///|
/// Ask the wallet to sign `request` and broadcast it (`eth_sendTransaction`),
/// returning the hash of the transaction it accepted.
///
/// This is the first call in the SDK that spends the user's money, so it is
/// also the first that always prompts: the wallet — not the dapp — holds the
/// key, and a user who declines the prompt is reported as
/// `ProviderError::UserRejected` (4001). Everything the request leaves absent
/// (nonce, gas, fees) the wallet fills in.
///
/// The hash comes back as soon as the transaction is *broadcast*, which is not
/// the same as mined: it may still be dropped or replaced. `wait_for_receipt`
/// is what turns it into an answer about what the transaction did.
///
/// ```
/// async fn[P : @provider.Provider] tip(
///   p : P,
///   from : @types.Address,
///   to : @types.Address,
/// ) -> @types.TxHash raise @provider.ProviderError {
///   @provider.send_transaction(
///     p,
///     @types.TransactionRequest::new(from, to~, value=@types.Wei::from_int(1000)),
///   )
/// }
/// ```
pub async fn[P : Provider] send_transaction(
  provider : P,
  request : @types.TransactionRequest,
) -> @types.TxHash raise ProviderError {
  invoke_rpc(
    provider,
    method_name="eth_sendTransaction",
    params=Json::array([request.to_json()]),
    decode=@types.TxHash::from_json,
  )
}

///|
/// Ask the wallet to sign an EIP-712 typed-data structure with `who`'s key
/// (`eth_signTypedData_v4`), and return the signature.
///
/// `typed_data` is a `@types.TypedData`: it validated the document when it was
/// built, so what reaches the wallet is one it can be expected to accept, and
/// a field with the wrong type was already reported by name. It goes over the
/// wire *serialized* — v4 takes the document as a string, not as a nested
/// object.
///
/// The wallet, not this SDK, computes the digest: nothing here hashes anything.
/// The address comes *first*, the opposite way round from `sign_message`.
///
/// ```
/// async fn[P : @provider.Provider] sign_permit(
///   p : P,
///   who : @types.Address,
///   permit : @types.TypedData,
/// ) -> @types.Hex raise @provider.ProviderError {
///   @provider.sign_typed_data(p, who, permit)
/// }
/// ```
pub async fn[P : Provider] sign_typed_data(
  provider : P,
  who : @types.Address,
  typed_data : @types.TypedData,
) -> @types.Hex raise ProviderError {
  invoke_rpc(
    provider,
    method_name="eth_signTypedData_v4",
    params=Json::array([
      who.to_json(),
      Json::string(typed_data.to_json().stringify()),
    ]),
    decode=@types.Hex::from_json,
  )
}
