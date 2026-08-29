///|
/// Where a transaction is: still in the mempool, or in a block.
///
/// A node reports `blockHash`, `blockNumber` and `transactionIndex` as `null`
/// until it is mined — the three are absent together and present together. An
/// enum makes that the type's own rule rather than a convention three
/// `Option`s hope the caller knows.
pub(all) enum Inclusion {
  /// Broadcast and in the mempool, not in a block yet.
  Pending
  /// In the block it names, at the index it names.
  Mined(
    block_hash~ : BlockHash,
    block_number~ : UInt64,
    /// The transaction's position in its block.
    transaction_index~ : UInt64
  )
} derive(Eq, Debug)

///|
pub impl Show for Inclusion with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// A transaction the chain already knows about, as `eth_getTransactionByHash`
/// reports it — the state between a `TransactionRequest` and a
/// `TransactionReceipt`. The only way to see the `nonce` the wallet chose.
///
/// Fields this SDK does not model (the signature, an access list, blob fields)
/// are dropped rather than rejected, so a newer type still decodes.
///
/// The authorization list is read, though: it is what a `0x04` transaction did,
/// and nothing else in the answer says which accounts it delegated.
pub(all) struct Transaction {
  hash : TxHash
  /// Whether it is still in the mempool, and where it landed if not.
  inclusion : Inclusion
  /// The account that signed it and pays for it.
  from : Address
  /// The recipient — absent for a contract deployment.
  to : Address?
  /// The sender's sequence number. Re-sending at this same nonce is what a
  /// speed-up or a cancel is.
  nonce : Quantity
  value : Wei
  /// The calldata, or the creation code when `to` is absent.
  input : Hex
  /// The gas limit the transaction carries — what it may spend, not what it
  /// spent. The receipt's `gas_used` is the latter.
  gas : Quantity
  /// What it offers to pay per gas, in the same two markets a
  /// `TransactionRequest` chooses between.
  fee : Fee
  /// The chain it is valid on. Absent from a pre-EIP-155 legacy transaction,
  /// which is replayable on every chain because it names none.
  chain_id : ChainId?
  /// The EIP-2718 type byte: `0x0` legacy, `0x1` access-list, `0x2` dynamic
  /// fee, `0x3` blob, `0x4` delegating. Absent from nodes older than Berlin,
  /// which typed nothing.
  transaction_type : UInt64?
  /// The EIP-7702 delegations it carried, empty for every other type. Whose
  /// they are comes out of `SignedAuthorization::authority`, not from here.
  authorization_list : Array[SignedAuthorization]
} derive(Eq, Debug)

///|
/// Render through the derived `Debug` representation, so the field list stays
/// the single source of truth for how a transaction prints.
pub impl Show for Transaction with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Decode the JSON object `eth_getTransactionByHash` answers with. A `null`
/// answer means the node has never seen the hash and is handled by the caller,
/// not here.
pub fn Transaction::from_json(j : Json) -> Transaction raise CodecError {
  let fields = json_object(j, what="transaction")
  Transaction::{
    hash: TxHash::from_json(required_field(fields, "hash", what="transaction")),
    inclusion: inclusion_from(fields),
    from: Address::from_json(required_field(fields, "from", what="transaction")),
    to: optional_map(fields, "to", Address::from_json),
    nonce: Quantity::from_json(
      required_field(fields, "nonce", what="transaction"),
    ),
    value: Wei::from_json(required_field(fields, "value", what="transaction")),
    input: Hex::from_json(required_field(fields, "input", what="transaction")),
    gas: Quantity::from_json(required_field(fields, "gas", what="transaction")),
    fee: Fee::from_fields(fields),
    chain_id: optional_map(fields, "chainId", ChainId::from_json),
    transaction_type: optional_quantity_field(fields, "type"),
    authorization_list: match optional_field(fields, "authorizationList") {
      Some(list) =>
        json_array_of(
          list,
          what="authorizationList",
          SignedAuthorization::from_json,
        )
      None => []
    },
  }
}

///|
/// Read the three fields that place a transaction in a block. `blockNumber`
/// decides: a node that reports one and then no `blockHash` is malformed, not
/// pending, so the other two are required once it is there.
fn inclusion_from(fields : Map[String, Json]) -> Inclusion raise CodecError {
  match optional_quantity_field(fields, "blockNumber") {
    None => Pending
    Some(block_number) =>
      Mined(
        block_hash=BlockHash::from_json(
          required_field(fields, "blockHash", what="mined transaction"),
        ),
        block_number~,
        transaction_index=quantity_field(
          fields,
          "transactionIndex",
          what="mined transaction",
        ),
      )
  }
}
