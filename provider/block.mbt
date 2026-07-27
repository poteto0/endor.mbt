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
