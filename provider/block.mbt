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
