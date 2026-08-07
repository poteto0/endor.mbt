///|
/// The shape a node answers `eth_getTransactionReceipt` with, for a plain
/// transfer that emitted one event. Tests below mutate a copy of it, so what
/// each of them is about is the field it changed.
fn a_receipt_json() -> Map[String, Json] {
  {
    "transactionHash": A_HASH.to_json(),
    "transactionIndex": "0x1".to_json(),
    "blockHash": A_BLOCK_HASH.to_json(),
    "blockNumber": "0x1b4".to_json(),
    "from": "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266".to_json(),
    "to": "0x70997970c51812dc3a010c7d01b50e0d17dc79c8".to_json(),
    "contractAddress": Json::null(),
    "cumulativeGasUsed": "0x5208".to_json(),
    "gasUsed": "0x5208".to_json(),
    "effectiveGasPrice": "0x3b9aca00".to_json(),
    "status": "0x1".to_json(),
    "logs": Json::array([Json::object(a_log_json())]),
  }
}

///|
fn a_log_json() -> Map[String, Json] {
  {
    "address": "0x70997970c51812dc3a010c7d01b50e0d17dc79c8".to_json(),
    "topics": Json::array([A_HASH.to_json()]),
    "data": "0x2a".to_json(),
    "blockNumber": "0x1b4".to_json(),
    "blockHash": A_BLOCK_HASH.to_json(),
    "transactionHash": A_HASH.to_json(),
    "transactionIndex": "0x1".to_json(),
    "logIndex": "0x0".to_json(),
  }
}

///|
/// Decode a receipt built from `a_receipt_json()` with `edits` applied, so a
/// test spells out only the field it is about.
fn receipt_with(
  edits : Map[String, Json],
) -> @types.TransactionReceipt raise @types.CodecError {
  let fields = a_receipt_json()
  for name, value in edits {
    fields[name] = value
  }
  @types.TransactionReceipt::from_json(Json::object(fields))
}

///|
test "receipt decodes every field a node reports" {
  let receipt = @types.TransactionReceipt::from_json(
    Json::object(a_receipt_json()),
  )
  inspect(receipt.transaction_hash, content=A_HASH)
  inspect(receipt.transaction_index, content="1")
  inspect(receipt.block_hash, content=A_BLOCK_HASH)
  inspect(receipt.block_number, content="436")
  inspect(receipt.from, content="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266")
  guard receipt.to is Some(to) else { fail("expected a recipient") }
  inspect(to, content="0x70997970C51812dc3A010C7d01b50e0d17dc79C8")
  assert_true(receipt.contract_address is None)
  inspect(receipt.cumulative_gas_used, content="Quantity(21000)")
  inspect(receipt.gas_used, content="Quantity(21000)")
  guard receipt.effective_gas_price is Some(price) else {
    fail("expected an effective gas price")
  }
  inspect(price.to_hex(), content="0x3b9aca00")
  inspect(receipt.status, content="Success")
  inspect(receipt.logs.length(), content="1")
}

///|
/// The two nullable address fields are each present exactly when the other is
/// not, which is how a caller tells a deployment from a call.
test "a deployment receipt has no `to` and a contract address instead" {
  let receipt = receipt_with({
    "to": Json::null(),
    "contractAddress": "0x70997970c51812dc3a010c7d01b50e0d17dc79c8".to_json(),
  })
  assert_true(receipt.to is None)
  guard receipt.contract_address is Some(deployed) else {
    fail("expected a contract address")
  }
  inspect(deployed, content="0x70997970C51812dc3A010C7d01b50e0d17dc79C8")
}

///|
/// A reverted transaction is mined and has a receipt, so decoding it must
/// succeed — the status is what says it failed.
test "receipt status decodes both outcomes and rejects anything else" {
  inspect(
    receipt_with({ "status": "0x0".to_json() }).status,
    content="Reverted",
  )
  try receipt_with({ "status": "0x2".to_json() }) catch {
    @types.CodecError::InvalidJson(msg) =>
      assert_true(msg.has_prefix("unknown receipt status"))
    e => fail("expected InvalidJson, but not \{e}")
  } noraise {
    _ => fail("expected an unknown status to be rejected")
  }
}

///|
/// A pre-EIP-1559 node reports no effective gas price; every other field is
/// required, and a missing one names itself rather than failing generically.
test "receipt tolerates a missing gas price but not a missing hash" {
  let fields = a_receipt_json()
  let _ = fields.remove("effectiveGasPrice")
  assert_true(
    @types.TransactionReceipt::from_json(Json::object(fields)).effective_gas_price
    is None,
  )
  let fields = a_receipt_json()
  let _ = fields.remove("blockNumber")
  try @types.TransactionReceipt::from_json(Json::object(fields)) catch {
    @types.CodecError::InvalidJson(msg) =>
      inspect(msg, content="receipt has no blockNumber")
    e => fail("expected InvalidJson, but not \{e}")
  } noraise {
    _ => fail("expected a receipt without a block number to be rejected")
  }
}

///|
test "receipt rejects a non-object" {
  try @types.TransactionReceipt::from_json(Json::array([])) catch {
    @types.CodecError::InvalidJson(msg) =>
      inspect(msg, content="expected receipt object")
    e => fail("expected InvalidJson, but not \{e}")
  } noraise {
    _ => fail("expected an array to be rejected")
  }
}

///|
test "log decodes its topics and defaults to not-removed" {
  let receipt = @types.TransactionReceipt::from_json(
    Json::object(a_receipt_json()),
  )
  let log = receipt.logs[0]
  inspect(log.address, content="0x70997970C51812dc3A010C7d01b50e0d17dc79C8")
  inspect(log.topics.length(), content="1")
  inspect(log.topics[0], content=A_HASH)
  inspect(log.data, content="0x2a")
  inspect(log.log_index, content="0")
  inspect(log.removed, content="false")
}

///|
test "a log from a reorged-out block reports itself as removed" {
  let log = a_log_json()
  log["removed"] = true.to_json()
  let receipt = receipt_with({ "logs": Json::array([Json::object(log)]) })
  inspect(receipt.logs[0].removed, content="true")
}

///|
test "logs must be an array of log objects" {
  try receipt_with({ "logs": "0x0".to_json() }) catch {
    @types.CodecError::InvalidJson(msg) =>
      inspect(msg, content="expected logs array")
    e => fail("expected InvalidJson, but not \{e}")
  } noraise {
    _ => fail("expected a non-array `logs` to be rejected")
  }
  // an empty object is missing every field; the one named is the first the
  // decoder asks for, which is the first the struct declares
  try receipt_with({ "logs": Json::array([Json::empty_object()]) }) catch {
    @types.CodecError::InvalidJson(msg) =>
      inspect(msg, content="log has no address")
    e => fail("expected InvalidJson, but not \{e}")
  } noraise {
    _ => fail("expected an empty log object to be rejected")
  }
}
