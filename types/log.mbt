///|
/// One event a transaction emitted, as a receipt carries it.
///
/// `topics` is the indexed part — the first is the event signature hash for
/// anything but an anonymous event — and `data` the ABI-encoded rest. Both
/// arrive as raw `Hex`, because what they mean is the event's declaration and
/// not this type's business: `@abi.decode_log` takes the two together and
/// answers with the arguments. The fields around them are what a caller needs
/// in order to know *where* the event happened without decoding anything.
///
/// `removed` is `true` when the log belonged to a block a reorg dropped, which
/// is the one case where an already-observed event stops being true.
pub(all) struct Log {
  /// The contract that emitted the event.
  address : Address
  /// Indexed parameters, the first usually being the event signature hash.
  topics : Array[Hex]
  /// The non-indexed parameters, ABI-encoded.
  data : Hex
  /// The block the emitting transaction was mined into.
  block_number : UInt64
  block_hash : BlockHash
  /// The transaction that emitted it, and its position in the block.
  transaction_hash : TxHash
  transaction_index : UInt64
  /// The log's position within the block.
  log_index : UInt64
  /// `true` when a reorg took the log's block out of the chain.
  removed : Bool
} derive(Eq, Debug)

///|
/// Render through the derived `Debug` representation: these are decoded
/// answers, so what a caller wants to see is every field, not a summary.
pub impl Show for Log with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Decode the JSON object a node answers with inside a receipt's `logs`.
pub fn Log::from_json(j : Json) -> Log raise CodecError {
  let fields = json_object(j, what="log")
  Log::{
    address: Address::from_json(required_field(fields, "address", what="log")),
    topics: array_field(fields, "topics", what="log", Hex::from_json),
    data: Hex::from_json(required_field(fields, "data", what="log")),
    block_number: quantity_field(fields, "blockNumber", what="log"),
    block_hash: BlockHash::from_json(
      required_field(fields, "blockHash", what="log"),
    ),
    transaction_hash: TxHash::from_json(
      required_field(fields, "transactionHash", what="log"),
    ),
    transaction_index: quantity_field(fields, "transactionIndex", what="log"),
    log_index: quantity_field(fields, "logIndex", what="log"),
    // absent means "not reorged out": nodes that never reorg omit the key
    removed: optional_field(fields, "removed") is Some(True),
  }
}

///|
/// Decode the JSON array of logs `eth_getLogs` answers with. A node that
/// matched nothing answers with an empty array, not with `null`.
pub fn Log::array_from_json(j : Json) -> Array[Log] raise CodecError {
  json_array_of(j, what="logs", Log::from_json)
}
