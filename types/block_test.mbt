///|
/// A block header as a node reports it, asked for with `false` so the
/// transactions come back as hashes.
fn a_block_json() -> Map[String, Json] {
  {
    "number": "0x1b4".to_json(),
    "hash": A_BLOCK_HASH.to_json(),
    "parentHash": A_PARENT_HASH.to_json(),
    "timestamp": "0x687fbc00".to_json(),
    "miner": "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266".to_json(),
    "gasLimit": "0x1c9c380".to_json(),
    "gasUsed": "0x5208".to_json(),
    "baseFeePerGas": "0x3b9aca00".to_json(),
    "transactions": Json::array([A_HASH.to_json()]),
  }
}

///|
const A_PARENT_HASH : String = "0x1a2b3c4d1a2b3c4d1a2b3c4d1a2b3c4d1a2b3c4d1a2b3c4d1a2b3c4d1a2b3c4d"

///|
test "block decodes every field a node reports" {
  let block = @types.Block::from_json(Json::object(a_block_json()))
  guard block.number is Some(number) else { fail("expected a block number") }
  inspect(number, content="436")
  guard block.hash is Some(hash) else { fail("expected a block hash") }
  inspect(hash, content=A_BLOCK_HASH)
  inspect(block.parent_hash, content=A_PARENT_HASH)
  inspect(block.timestamp, content="1753201664")
  inspect(block.miner, content="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266")
  inspect(block.gas_limit, content="Quantity(30000000)")
  inspect(block.gas_used, content="Quantity(21000)")
  guard block.base_fee_per_gas is Some(base_fee) else {
    fail("expected a base fee")
  }
  inspect(base_fee.to_hex(), content="0x3b9aca00")
  inspect(block.transactions.length(), content="1")
  inspect(block.transactions[0], content=A_HASH)
}

///|
/// The pending block has been proposed but not sealed, so it has neither a
/// number nor a hash yet — the one case where those are absent rather than
/// malformed.
test "the pending block has no number and no hash" {
  let fields = a_block_json()
  fields["number"] = Json::null()
  fields["hash"] = Json::null()
  let block = @types.Block::from_json(Json::object(fields))
  assert_true(block.number is None)
  assert_true(block.hash is None)
  inspect(block.parent_hash, content=A_PARENT_HASH)
}

///|
/// A pre-London chain burns no base fee, and a block with no transactions is
/// an empty list rather than a missing key.
test "block tolerates a missing base fee and an empty transaction list" {
  let fields = a_block_json()
  let _ = fields.remove("baseFeePerGas")
  fields["transactions"] = Json::array([])
  let block = @types.Block::from_json(Json::object(fields))
  assert_true(block.base_fee_per_gas is None)
  inspect(block.transactions.length(), content="0")
}

///|
test "block rejects a missing parent hash and a non-object" {
  let fields = a_block_json()
  let _ = fields.remove("parentHash")
  try @types.Block::from_json(Json::object(fields)) catch {
    @types.CodecError::InvalidJson(msg) =>
      inspect(msg, content="block has no parentHash")
    e => fail("expected InvalidJson, but not \{e}")
  } noraise {
    _ => fail("expected a block without a parent hash to be rejected")
  }
  try @types.Block::from_json(Json::null()) catch {
    @types.CodecError::InvalidJson(msg) =>
      inspect(msg, content="expected block object")
    e => fail("expected InvalidJson, but not \{e}")
  } noraise {
    _ => fail("expected null to be rejected")
  }
}

///|
/// The SDK asks for hashes, so full transaction objects are not what it can
/// decode — a mismatch worth reporting rather than silently dropping.
test "block rejects transaction objects where it asked for hashes" {
  let fields = a_block_json()
  fields["transactions"] = Json::array([Json::object(a_receipt_json())])
  try @types.Block::from_json(Json::object(fields)) catch {
    @types.CodecError::InvalidJson(msg) =>
      inspect(msg, content="expected transaction hash string")
    e => fail("expected InvalidJson, but not \{e}")
  } noraise {
    _ => fail("expected full transaction objects to be rejected")
  }
}
