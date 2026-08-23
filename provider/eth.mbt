///|
/// Perform one JSON-RPC call and decode its result. An answer that will not
/// read back as the type the method promises surfaces as `Decode`, which keeps
/// the `CodecError` as it was raised and names the method that answered;
/// wallet-side errors propagate untouched. Every typed helper below is this
/// plus a `decode`, which is what keeps their error behaviour identical.
async fn[P : Provider, T] invoke_rpc(
  provider : P,
  method_name~ : String,
  params~ : Json,
  decode~ : (Json) -> T raise @types.CodecError,
) -> T raise ProviderError {
  let r = provider.request(method_name~, params~)
  decode(r) catch {
    e => raise Decode(method_name~, cause=e)
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
    raise MalformedResponse("eth_requestAccounts returned no accounts")
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
/// as the 32-byte word the EVM holds there. A slot never written reads as
/// thirty-two zero bytes rather than as an absence.
///
/// The only way to read state a contract does not expose: no ABI declares a
/// storage layout, so what the word means is the caller's to know.
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
/// (`eth_call`) and return the raw return data — no signature, no gas, no
/// wallet prompt. `block` is the state it is evaluated against.
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
/// simulates the call the way `call` does, so this needs no signature either.
///
/// An upper estimate, not a guarantee: it is measured against current state. A
/// request the node cannot execute comes back as a `ProviderError`, which makes
/// this a cheap way to check a transaction before asking the user to sign.
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
/// answers `null`. The transactions come back as hashes, not full objects;
/// `transaction_receipt` is how each is followed up.
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
/// know the block — this asks for the number alone, not for every hash.
///
/// A height past the head is where nodes disagree: some answer `null`, others —
/// Anvil among them — raise. `None` is the answer to expect, not to rely on.
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
/// share — a quantity, or `null` for a block the node does not have — is here.
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
/// returning the hash of the transaction it accepted. It always prompts, and a
/// user who declines is `ProviderError::UserRejected` (4001).
///
/// The hash comes back as soon as the transaction is *broadcast*, which is not
/// the same as mined. `wait_for_receipt` says what the transaction did.
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
/// No wallet is involved and nothing prompts: whoever signed `raw` pays for it.
/// This is the entrance for a transaction signed elsewhere, which is how a
/// relayer submits work somebody else authorized.
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
/// Return the transaction with `tx_hash` as the node holds it, or `None` when
/// it has never seen the hash (`eth_getTransactionByHash`).
///
/// It answers while `transaction_receipt` still cannot, and `inclusion` says
/// whether the transaction is in the mempool or in a block. It also says the
/// `nonce` the wallet chose — the one a speed-up or a cancel has to re-use.
///
/// ```
/// async fn[P : @provider.Provider] fee_of(
///   p : P,
///   hash : @types.TxHash,
/// ) -> @types.Fee? raise @provider.ProviderError {
///   @provider.transaction_by_hash(p, hash).map(tx => tx.fee)
/// }
/// ```
pub async fn[P : Provider] transaction_by_hash(
  provider : P,
  tx_hash : @types.TxHash,
) -> @types.Transaction? raise ProviderError {
  invoke_rpc(
    provider,
    method_name="eth_getTransactionByHash",
    params=Json::array([tx_hash.to_json()]),
    decode=j => decode_optional(j, @types.Transaction::from_json),
  )
}

///|
/// Poll until `tx_hash` has a receipt with `confirmations` confirmations, and
/// return it — the other half of `send_transaction`.
///
/// `timeout` and `poll_interval` are milliseconds, and running out raises
/// `Timeout`. A transaction that reverted has a receipt and so returns normally,
/// with `status` set to `Reverted` — check it.
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
  guard confirmations >= 1 else {
    raise InvalidConfig(
      "wait_for_receipt: confirmations must be at least 1, got \{confirmations}",
    )
  }
  let wanted = confirmations.to_uint64()
  let deadline = @async.now() + timeout.to_int64()
  // a receipt does not change once it exists: fetch it once, then watch the head
  let receipt = for ;; {
    if transaction_receipt(provider, tx_hash) is Some(receipt) {
      break receipt
    }
    guard poll_again(deadline, poll_interval) else {
      raise Timeout("transaction \{tx_hash} was not mined within \{timeout}ms")
    }
  }
  // the receipt's own block is the first confirmation
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
/// halves of the wait share the deadline, so `timeout` covers the whole call.
async fn poll_again(
  deadline : Int64,
  poll_interval : Int,
) -> Bool raise ProviderError {
  let remaining = deadline - @async.now()
  guard remaining > 0 else { return false }
  // never nap past the deadline
  let nap = if remaining < poll_interval.to_int64() {
    remaining.to_int()
  } else {
    poll_interval
  }
  @async.sleep(nap) catch {
    e => raise Transport("waiting to poll again: \{e}")
  }
  true
}

///|
/// Ask the wallet to sign an EIP-712 typed-data structure with `who`'s key
/// (`eth_signTypedData_v4`), and return the signature.
///
/// `typed_data` validated the document when it was built, and goes over the wire
/// *serialized* — v4 takes a string, not a nested object. The wallet computes
/// the digest; nothing here hashes anything.
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
