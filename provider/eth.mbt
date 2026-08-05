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
/// Return the raw contents of one storage slot of `who` (`eth_getStorageAt`),
/// as the 32-byte word the EVM holds there. A slot that was never written reads
/// as thirty-two zero bytes rather than as an absence.
///
/// This is the only way to read state a contract does not expose: no ABI
/// declares a storage layout, so nothing above this can type the answer, and
/// what the word *means* is the caller's to know. The use that motivates it is
/// a proxy's implementation address, which EIP-1967 puts at a fixed slot —
/// there the word is an address in its low 20 bytes.
///
/// `slot` goes out as it is spelled, so it is the caller that decides whether to
/// send the full word or the short form a node also accepts.
///
/// ```
/// async fn[P : @provider.Provider] implementation_slot(
///   p : P,
///   proxy : @types.Address,
/// ) -> @types.Hex raise @provider.ProviderError {
///   // EIP-1967: keccak256("eip1967.proxy.implementation") - 1
///   let slot = @types.Hex::from_string(
///     "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc",
///   )
///   @provider.storage_at(p, proxy, slot)
/// }
/// ```
pub async fn[P : Provider] storage_at(
  provider : P,
  who : @types.Address,
  slot : @types.Hex,
  block? : @types.BlockTag = Latest,
) -> @types.Hex raise ProviderError {
  invoke_rpc(
    provider,
    method_name="eth_getStorageAt",
    params=Json::array([who.to_json(), slot.to_json(), block.to_json()]),
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
/// Return the block at `block`, or `None` when the node does not know it
/// (`eth_getBlockByNumber`).
///
/// A height past the head is not an error — a node that has not seen the block
/// answers `null`, and that is what `None` reports. `Latest` (the default) and
/// the other named tags always resolve, so those only answer `None` on a node
/// that has no chain at all.
///
/// The transactions come back as hashes, not as full objects: the SDK asks for
/// the cheap form and `transaction_receipt` is how each of them is followed up.
///
/// ```
/// async fn[P : @provider.Provider] head_timestamp(
///   p : P,
/// ) -> UInt64 raise @provider.ProviderError {
///   match @provider.block_by_number(p) {
///     Some(block) => block.timestamp
///     None => 0
///   }
/// }
/// ```
pub async fn[P : Provider] block_by_number(
  provider : P,
  block? : @types.BlockTag = Latest,
) -> @types.Block? raise ProviderError {
  invoke_rpc(
    provider,
    method_name="eth_getBlockByNumber",
    params=Json::array([block.to_json(), false.to_json()]),
    decode=j => decode_optional(j, @types.Block::from_json),
  )
}

///|
/// Return the block with `hash`, or `None` when the node does not know it
/// (`eth_getBlockByHash`) — a block from a chain the wallet is not on, or one
/// a reorg dropped.
///
/// ```
/// async fn[P : @provider.Provider] size_of(
///   p : P,
///   hash : @types.BlockHash,
/// ) -> Int raise @provider.ProviderError {
///   match @provider.block_by_hash(p, hash) {
///     Some(block) => block.transactions.length()
///     None => 0
///   }
/// }
/// ```
pub async fn[P : Provider] block_by_hash(
  provider : P,
  hash : @types.BlockHash,
) -> @types.Block? raise ProviderError {
  invoke_rpc(
    provider,
    method_name="eth_getBlockByHash",
    params=Json::array([hash.to_json(), false.to_json()]),
    decode=j => decode_optional(j, @types.Block::from_json),
  )
}

///|
/// Return how many transactions the block at `block` holds
/// (`eth_getBlockTransactionCountByNumber`), or `None` when the node does not
/// know the block.
///
/// The same count is `block_by_number(…).transactions.length()`, but this asks
/// the node for the number alone rather than for every hash in the block.
///
/// A height past the head is where nodes disagree: some answer `null`, which
/// reads as `None`, and others — Anvil among them — call it a bad parameter and
/// raise. `None` is therefore the answer to expect, not the answer to rely on.
///
/// ```
/// async fn[P : @provider.Provider] head_is_empty(
///   p : P,
/// ) -> Bool raise @provider.ProviderError {
///   @provider.block_transaction_count_by_number(p) == Some(0UL)
/// }
/// ```
pub async fn[P : Provider] block_transaction_count_by_number(
  provider : P,
  block? : @types.BlockTag = Latest,
) -> UInt64? raise ProviderError {
  block_transaction_count(
    provider,
    method_name="eth_getBlockTransactionCountByNumber",
    key=block.to_json(),
  )
}

///|
/// Return how many transactions the block with `hash` holds
/// (`eth_getBlockTransactionCountByHash`), or `None` when the node does not
/// know the block.
///
/// ```
/// async fn[P : @provider.Provider] busy(
///   p : P,
///   hash : @types.BlockHash,
/// ) -> Bool raise @provider.ProviderError {
///   @provider.block_transaction_count_by_hash(p, hash)
///   is Some(n) && n > 100UL
/// }
/// ```
pub async fn[P : Provider] block_transaction_count_by_hash(
  provider : P,
  hash : @types.BlockHash,
) -> UInt64? raise ProviderError {
  block_transaction_count(
    provider,
    method_name="eth_getBlockTransactionCountByHash",
    key=hash.to_json(),
  )
}

///|
/// The two counts differ only in how the block is named, so the decode they
/// share — a quantity, or `null` for a block the node does not have — is stated
/// once here rather than in each of them.
async fn[P : Provider] block_transaction_count(
  provider : P,
  method_name~ : String,
  key~ : Json,
) -> UInt64? raise ProviderError {
  invoke_rpc(provider, method_name~, params=Json::array([key]), decode=j => {
    decode_optional(j, @types.Quantity::from_json)
  }).map(q => q.to_uint64())
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
/// Broadcast a transaction that is *already signed* (`eth_sendRawTransaction`),
/// returning the hash the node accepted it under.
///
/// No wallet is involved and nothing prompts: `raw` is a signed, RLP-encoded
/// transaction, and whoever signed it pays for it. The SDK holds no keys, so it
/// never builds one — this is the entrance for a transaction signed elsewhere,
/// which is how a *relayer* submits work somebody else authorized (EIP-3009's
/// `transferWithAuthorization`, above all).
///
/// Like `send_transaction`, the hash says only that the transaction was
/// broadcast. `wait_for_receipt` is what turns it into an answer about what it
/// did.
///
/// ```
/// async fn[P : @provider.Provider] relay(
///   p : P,
///   signed : @types.Hex,
/// ) -> @types.TxHash raise @provider.ProviderError {
///   @provider.send_raw_transaction(p, signed)
/// }
/// ```
pub async fn[P : Provider] send_raw_transaction(
  provider : P,
  raw : @types.Hex,
) -> @types.TxHash raise ProviderError {
  invoke_rpc(
    provider,
    method_name="eth_sendRawTransaction",
    params=Json::array([raw.to_json()]),
    decode=@types.TxHash::from_json,
  )
}

///|
/// Return the receipt of `tx_hash`, or `None` when there is none yet
/// (`eth_getTransactionReceipt`).
///
/// `None` is not an error: a transaction that has been broadcast but not mined
/// has no receipt, and neither has one the mempool dropped. Telling those two
/// apart takes waiting, which is what `wait_for_receipt` does.
///
/// ```
/// async fn[P : @provider.Provider] mined(
///   p : P,
///   hash : @types.TxHash,
/// ) -> Bool raise @provider.ProviderError {
///   @provider.transaction_receipt(p, hash) is Some(_)
/// }
/// ```
pub async fn[P : Provider] transaction_receipt(
  provider : P,
  tx_hash : @types.TxHash,
) -> @types.TransactionReceipt? raise ProviderError {
  invoke_rpc(
    provider,
    method_name="eth_getTransactionReceipt",
    params=Json::array([tx_hash.to_json()]),
    decode=j => decode_optional(j, @types.TransactionReceipt::from_json),
  )
}

///|
/// Poll until `tx_hash` has a receipt with `confirmations` confirmations, and
/// return it. This is the other half of `send_transaction`: the hash it answers
/// with says the transaction was broadcast, and this says it was mined.
///
/// A receipt in the head block counts as one confirmation, so the default
/// `confirmations=1` returns as soon as the transaction is mined at all. Ask for
/// more to wait out the reorgs that can still take it back out; asking for
/// fewer than one is a caller error and is raised rather than rounded up.
///
/// Both remaining knobs are milliseconds: `timeout` is how long the wait may
/// take in total, `poll_interval` how long to wait between polls.
///
/// Running out of time raises `Timeout`, which is deliberately not the same
/// answer as `transaction_receipt`'s `None`: `None` says the node has no
/// receipt *right now*, `Timeout` says it still had none after being asked for
/// as long as the caller allowed. A transaction that reverted has a receipt and
/// so returns normally, with `status` set to `Reverted` — check it rather than
/// reading a successful return as a successful transaction.
///
/// ```
/// async fn[P : @provider.Provider] confirm(
///   p : P,
///   hash : @types.TxHash,
/// ) -> Bool raise @provider.ProviderError {
///   let receipt = @provider.wait_for_receipt(p, hash, confirmations=2)
///   receipt.status is Success
/// }
/// ```
pub async fn[P : Provider] wait_for_receipt(
  provider : P,
  tx_hash : @types.TxHash,
  confirmations? : Int = 1,
  timeout? : Int = 60_000,
  poll_interval? : Int = 1_000,
) -> @types.TransactionReceipt raise ProviderError {
  // fewer than one confirmation is not a weaker wait, it is no wait at all —
  // and a negative one, converted unsigned, would be a wait for a height the
  // chain never reaches. Neither is what any caller meant, so neither is
  // silently corrected.
  guard confirmations >= 1 else {
    raise ProviderError::internal(
      "wait_for_receipt: confirmations must be at least 1, got \{confirmations}",
    )
  }
  let wanted = confirmations.to_uint64()
  let deadline = @async.now() + timeout.to_int64()
  // a receipt does not change once it exists, so it is fetched once and the
  // rest of the wait is a question about the head alone
  let receipt = for ;; {
    if transaction_receipt(provider, tx_hash) is Some(receipt) {
      break receipt
    }
    guard poll_again(deadline, poll_interval) else {
      raise Timeout("transaction \{tx_hash} was not mined within \{timeout}ms")
    }
  }
  // the receipt's own block is the first confirmation, so the default wait is
  // over without asking the node anything more
  if wanted > 1 {
    // `head + 1 < number + wanted` rather than a subtraction: both sides are
    // unsigned and a reorg can leave the head *below* the receipt's block
    while block_number(provider) + 1 < receipt.block_number + wanted {
      guard poll_again(deadline, poll_interval) else {
        raise Timeout(
          "transaction \{tx_hash} did not reach \{wanted} confirmations within \{timeout}ms",
        )
      }
    }
  }
  receipt
}

///|
/// Wait one poll interval, or answer `false` once `deadline` has passed. Both
/// halves of the wait run off the same deadline, so `timeout` covers the whole
/// call rather than each half of it.
async fn poll_again(
  deadline : Int64,
  poll_interval : Int,
) -> Bool raise ProviderError {
  let remaining = deadline - @async.now()
  guard remaining > 0 else { return false }
  // never nap past the deadline: the last poll before it should still happen
  let nap = if remaining < poll_interval.to_int64() {
    remaining.to_int()
  } else {
    poll_interval
  }
  @async.sleep(nap) catch {
    e => raise ProviderError::internal("waiting to poll again: \{e}")
  }
  true
}

///|
/// Ask the wallet to sign an EIP-712 typed-data structure with `who`'s key
/// (`eth_signTypedData_v4`), and return the signature.
///
/// `typed_data` is an `@eip712.TypedData`: it validated the document when it was
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
///   permit : @eip712.TypedData,
/// ) -> @types.Hex raise @provider.ProviderError {
///   @provider.sign_typed_data(p, who, permit)
/// }
/// ```
pub async fn[P : Provider] sign_typed_data(
  provider : P,
  who : @types.Address,
  typed_data : @eip712.TypedData,
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
