///|
/// Whether the transaction's execution succeeded, as the post-Byzantium
/// `status` field reports it.
///
/// A reverted transaction is still mined and still charged for its gas, so a
/// receipt existing says nothing about the transaction having done what it was
/// sent to do — this field does.
pub(all) enum ReceiptStatus {
  /// `0x1` — the transaction executed to completion.
  Success
  /// `0x0` — the transaction reverted; its state changes were rolled back.
  Reverted
} derive(Eq, Debug)

///|
pub impl Show for ReceiptStatus with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// What a node knows about a transaction once it is mined
/// (`eth_getTransactionReceipt`): where it landed, what it cost, whether it
/// succeeded, and what it emitted.
///
/// A receipt exists only for a mined transaction, which is why
/// `@provider.transaction_receipt` answers with `TransactionReceipt?` and
/// `@provider.wait_for_receipt` polls for one.
///
/// `to` is absent exactly when the transaction was a deployment, and
/// `contract_address` is present exactly then — the address the code now lives
/// at.
pub(all) struct TransactionReceipt {
  transaction_hash : TxHash
  /// The transaction's position in its block.
  transaction_index : UInt64
  block_hash : BlockHash
  block_number : UInt64
  /// The account that signed and paid for the transaction.
  from : Address
  /// The recipient — absent for a contract deployment.
  to : Address?
  /// The address of the contract a deployment created.
  contract_address : Address?
  /// Gas used by every transaction up to and including this one, in its block.
  cumulative_gas_used : Quantity
  /// Gas this transaction alone used — what `estimate_gas` was estimating.
  gas_used : Quantity
  /// The price actually paid per gas, once the block's base fee was known.
  /// Absent from pre-EIP-1559 nodes.
  effective_gas_price : Wei?
  /// Whether the execution succeeded or reverted.
  status : ReceiptStatus
  /// The events the transaction emitted, in emission order.
  logs : Array[Log]
} derive(Eq, Debug)

///|
/// Render through the derived `Debug` representation, so the field list stays
/// the single source of truth for how a receipt prints.
pub impl Show for TransactionReceipt with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Decode the JSON object `eth_getTransactionReceipt` answers with. A `null`
/// answer means "not mined yet" and is handled by the caller, not here.
pub fn TransactionReceipt::from_json(
  j : Json,
) -> TransactionReceipt raise CodecError {
  let fields = json_object(j, what="receipt")
  let logs = []
  for
    log in json_array(
      required_field(fields, "logs", what="receipt"),
      what="logs",
    ) {
    logs.push(Log::from_json(log))
  }
  TransactionReceipt::{
    transaction_hash: TxHash::from_json(
      required_field(fields, "transactionHash", what="receipt"),
    ),
    transaction_index: quantity_field(
      fields,
      "transactionIndex",
      what="receipt",
    ),
    block_hash: BlockHash::from_json(
      required_field(fields, "blockHash", what="receipt"),
    ),
    block_number: quantity_field(fields, "blockNumber", what="receipt"),
    from: Address::from_json(required_field(fields, "from", what="receipt")),
    to: optional_map(fields, "to", Address::from_json),
    contract_address: optional_map(
      fields,
      "contractAddress",
      Address::from_json,
    ),
    cumulative_gas_used: Quantity::from_json(
      required_field(fields, "cumulativeGasUsed", what="receipt"),
    ),
    gas_used: Quantity::from_json(
      required_field(fields, "gasUsed", what="receipt"),
    ),
    effective_gas_price: optional_map(
      fields,
      "effectiveGasPrice",
      Wei::from_json,
    ),
    status: ReceiptStatus::from_json(
      required_field(fields, "status", what="receipt"),
    ),
    logs,
  }
}

///|
/// Decode the `status` quantity: `0x1` succeeded, `0x0` reverted. Pre-Byzantium
/// receipts carry a state root there instead, which is not a status and is
/// rejected rather than guessed at.
fn ReceiptStatus::from_json(j : Json) -> ReceiptStatus raise CodecError {
  match Quantity::from_json(j).to_uint64() {
    1 => Success
    0 => Reverted
    other => raise InvalidJson("unknown receipt status: \{other}")
  }
}
