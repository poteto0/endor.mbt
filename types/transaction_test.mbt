///|
/// A mined EIP-1559 transfer as a node reports it. Tests below edit a copy, so
/// what each of them is about is the field it changed.
///
/// It carries `gasPrice` next to the dynamic-fee pair, and keys this SDK models
/// nothing for, because that is what a node actually answers with.
fn a_transaction_json() -> Map[String, Json] {
  {
    "hash": A_HASH.to_json(),
    "blockHash": A_BLOCK_HASH.to_json(),
    "blockNumber": "0x1b4".to_json(),
    "transactionIndex": "0x1".to_json(),
    "from": "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266".to_json(),
    "to": "0x70997970c51812dc3a010c7d01b50e0d17dc79c8".to_json(),
    "nonce": "0x7".to_json(),
    "value": "0xde0b6b3a7640000".to_json(),
    "input": "0x".to_json(),
    "gas": "0x5208".to_json(),
    "gasPrice": "0x3b9aca00".to_json(),
    "maxFeePerGas": "0x77359400".to_json(),
    "maxPriorityFeePerGas": "0x3b9aca00".to_json(),
    "chainId": "0x1".to_json(),
    "type": "0x2".to_json(),
    "v": "0x1".to_json(),
    "r": A_HASH.to_json(),
    "s": A_HASH.to_json(),
    "accessList": Json::array([]),
  }
}

///|
/// Decode a transaction built from `a_transaction_json()` with `edits`
/// applied, so a test spells out only the field it is about.
fn transaction_with(
  edits : Map[String, Json],
) -> @types.Transaction raise @types.CodecError {
  let fields = a_transaction_json()
  for name, value in edits {
    fields[name] = value
  }
  @types.Transaction::from_json(Json::object(fields))
}

///|
test "transaction decodes every field a node reports" {
  let tx = @types.Transaction::from_json(Json::object(a_transaction_json()))
  inspect(tx.hash, content=A_HASH)
  inspect(tx.from, content="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266")
  guard tx.to is Some(to) else { fail("expected a recipient") }
  inspect(to, content="0x70997970C51812dc3A010C7d01b50e0d17dc79C8")
  inspect(tx.nonce, content="Quantity(7)")
  inspect(tx.value.to_hex(), content="0xde0b6b3a7640000")
  inspect(tx.input, content="0x")
  inspect(tx.gas, content="Quantity(21000)")
  guard tx.chain_id is Some(chain_id) else { fail("expected a chain id") }
  inspect(chain_id.to_uint64(), content="1")
  debug_inspect(tx.transaction_type, content="Some(2)")
  guard tx.inclusion is Mined(block_hash~, block_number~, transaction_index~) else {
    fail("expected a mined transaction")
  }
  inspect(block_hash, content=A_BLOCK_HASH)
  inspect(block_number, content="436")
  inspect(transaction_index, content="1")
}

///|
/// The reason the type exists: a transaction is readable while it is still in
/// the mempool, and the three fields that place it in a block are `null` until
/// it is mined. `Pending` is that state, and it is a case rather than three
/// `None`s.
test "a transaction still in the mempool is pending" {
  let tx = transaction_with({
    "blockHash": Json::null(),
    "blockNumber": Json::null(),
    "transactionIndex": Json::null(),
  })
  inspect(tx.inclusion, content="Pending")
}

///|
/// A node that places a transaction in a block and then names no block is
/// malformed, not pending — `blockNumber` decides, and the rest follows it.
test "a block number with no block hash is rejected" {
  try transaction_with({ "blockHash": Json::null() }) catch {
    @types.InvalidJson(msg) =>
      inspect(msg, content="mined transaction has no blockHash")
    e => fail("expected an InvalidJson, but not \{e}")
  } noraise {
    _ => fail("expected a half-mined transaction to be rejected")
  }
}

///|
/// The dynamic-fee pair decides, even though the node reports `gasPrice`
/// alongside it.
test "an EIP-1559 transaction reads as a dynamic fee" {
  let tx = @types.Transaction::from_json(Json::object(a_transaction_json()))
  guard tx.fee is Eip1559(max_fee_per_gas~, max_priority_fee_per_gas~) else {
    fail("expected a dynamic fee")
  }
  inspect(max_fee_per_gas.to_hex(), content="0x77359400")
  inspect(max_priority_fee_per_gas.to_hex(), content="0x3b9aca00")
}

///|
/// A legacy transaction has `gasPrice` and nothing else, on a chain that may
/// predate EIP-155 and so name no chain id at all.
test "a legacy transaction reads as a flat gas price" {
  // `null` and absent are the same to the decoder, so the fixture can say
  // "without these" in the one form every other test here uses
  let tx = transaction_with({
    "maxFeePerGas": Json::null(),
    "maxPriorityFeePerGas": Json::null(),
    "chainId": Json::null(),
    "type": Json::null(),
  })
  guard tx.fee is Legacy(gas_price~) else { fail("expected a flat gas price") }
  inspect(gas_price.to_hex(), content="0x3b9aca00")
  assert_true(tx.chain_id is None)
  assert_true(tx.transaction_type is None)
}

///|
/// The forward-compatibility rule: a transaction of a type this release has
/// never heard of, pricing its gas in fields it has never heard of either,
/// decodes to everything that is still there rather than failing. `Auto` is
/// what "no fee field I know" reads as.
test "an unknown transaction type decodes without its fees" {
  let tx = transaction_with({
    "maxFeePerGas": Json::null(),
    "maxPriorityFeePerGas": Json::null(),
    "gasPrice": Json::null(),
    "type": "0x7e".to_json(),
    "maxFeePerNewThing": "0x1".to_json(),
  })
  assert_true(tx.fee is Auto)
  debug_inspect(tx.transaction_type, content="Some(126)")
  inspect(tx.hash, content=A_HASH)
}

///|
/// A deployment names no recipient, and its `input` is the creation code.
test "a deployment has no recipient" {
  let tx = transaction_with({
    "to": Json::null(),
    "input": "0x60806040".to_json(),
  })
  assert_true(tx.to is None)
  inspect(tx.input, content="0x60806040")
}

///|
/// A field the transaction cannot be read without is an error naming it, not a
/// silent default.
test "a transaction with no nonce is rejected" {
  let fields = a_transaction_json()
  fields.remove("nonce") |> ignore
  try @types.Transaction::from_json(Json::object(fields)) catch {
    @types.InvalidJson(msg) => inspect(msg, content="transaction has no nonce")
    e => fail("expected an InvalidJson, but not \{e}")
  } noraise {
    _ => fail("expected a transaction with no nonce to be rejected")
  }
}

///|
test "a transaction is not decoded from a non-object" {
  try @types.Transaction::from_json(Json::array([])) catch {
    @types.InvalidJson(msg) =>
      inspect(msg, content="expected transaction object")
    e => fail("expected an InvalidJson, but not \{e}")
  } noraise {
    _ => fail("expected a non-object to be rejected")
  }
}

///|
/// A type-`0x04` transaction reports what it delegated, and that is the one
/// list this type reads back: nothing else in the answer names the accounts.
test "a delegating transaction carries its authorizations" {
  let tx = transaction_with({
    "type": "0x4".to_json(),
    "authorizationList": Json::array([
      {
        "chainId": "0x1".to_json(),
        "address": "0x70997970c51812dc3a010c7d01b50e0d17dc79c8".to_json(),
        "nonce": "0x8".to_json(),
        "yParity": "0x1".to_json(),
        "r": "0x1".to_json(),
        "s": "0x2".to_json(),
      },
    ]),
  })
  assert_eq(tx.authorization_list.length(), 1)
  assert_eq(
    tx.authorization_list[0].authorization().nonce(),
    @types.Quantity::new(8),
  )
}

///|
/// Every other type reports no list at all, and reads back as the empty one
/// rather than as an absence a caller has to unwrap.
test "a transaction with no authorizations has an empty list" {
  let tx = @types.Transaction::from_json(Json::object(a_transaction_json()))
  assert_eq(tx.authorization_list, [])
}
