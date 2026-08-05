///|
/// A block header as `eth_getBlockByNumber` / `eth_getBlockByHash` report it,
/// with the hashes of the transactions it contains.
///
/// `number` and `hash` are absent for the *pending* block: it has not been
/// sealed, so it has neither yet. Every other field is what the node currently
/// proposes for it.
///
/// The SDK asks for hashes rather than full transaction objects, so
/// `transactions` is a list of `TxHash` — the handle each transaction's receipt
/// is fetched with.
pub(all) struct Block {
  /// The block's height — absent while it is still pending.
  number : UInt64?
  /// The block's own hash — absent while it is still pending.
  hash : BlockHash?
  parent_hash : BlockHash
  /// Seconds since the Unix epoch, as the block's proposer stamped it.
  timestamp : UInt64
  /// The account credited with proposing the block.
  miner : Address
  /// The gas the block allows, and the gas its transactions actually used.
  gas_limit : Quantity
  gas_used : Quantity
  /// The EIP-1559 base fee burned per gas. Absent on chains (or blocks) from
  /// before the London fork.
  base_fee_per_gas : Wei?
  /// The hashes of the transactions in the block, in execution order.
  transactions : Array[TxHash]
} derive(Eq, Debug)

///|
pub impl Show for Block with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Decode the JSON object a block RPC answers with. A `null` answer means the
/// node does not know the block and is handled by the caller, not here.
pub fn Block::from_json(j : Json) -> Block raise CodecError {
  let fields = json_object(j, what="block")
  let transactions = array_field(
    fields,
    "transactions",
    what="block",
    TxHash::from_json,
  )
  Block::{
    number: optional_map(fields, "number", j => {
      Quantity::from_json(j).to_uint64()
    }),
    hash: optional_map(fields, "hash", BlockHash::from_json),
    parent_hash: BlockHash::from_json(
      required_field(fields, "parentHash", what="block"),
    ),
    timestamp: quantity_field(fields, "timestamp", what="block"),
    miner: Address::from_json(required_field(fields, "miner", what="block")),
    gas_limit: Quantity::from_json(
      required_field(fields, "gasLimit", what="block"),
    ),
    gas_used: Quantity::from_json(
      required_field(fields, "gasUsed", what="block"),
    ),
    base_fee_per_gas: optional_map(fields, "baseFeePerGas", Wei::from_json),
    transactions,
  }
}
