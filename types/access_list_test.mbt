///|
const SLOT_7 = "0x0000000000000000000000000000000000000000000000000000000000000007"

///|
test "an access list item encodes as the node's object" {
  let item = @types.AccessListItem::new(
    @types.Address::from_string(RECIPIENT),
    storage_keys=[@types.Hex::from_string(SLOT_7)],
  )
  inspect(
    item.to_json().stringify(),
    content=(
      #|{"address":"0x70997970c51812dc3a010c7d01b50e0d17dc79c8","storageKeys":["0x0000000000000000000000000000000000000000000000000000000000000007"]}
    ),
  )
}

///|
/// An entry that declares no slots still declares its address.
test "an access list item may hold no storage keys" {
  let item = @types.AccessListItem::new(@types.Address::from_string(RECIPIENT))
  inspect(
    item.to_json().stringify(),
    content=(
      #|{"address":"0x70997970c51812dc3a010c7d01b50e0d17dc79c8","storageKeys":[]}
    ),
  )
}

///|
/// What `eth_createAccessList` answers reads back as what a transaction can
/// then carry.
test "an access list item decodes from the node's answer" {
  let item = @types.AccessListItem::from_json(
    Json::object({
      "address": Json::string(RECIPIENT),
      "storageKeys": Json::array([Json::string(SLOT_7)]),
    }),
  )
  assert_eq(item.address(), @types.Address::from_string(RECIPIENT))
  assert_eq(item.storage_keys(), [@types.Hex::from_string(SLOT_7)])
}

///|
/// A slot number is a word: a key written short is not the same slot, so it is
/// refused rather than padded.
test "a storage key must be 32 bytes" {
  try
    @types.AccessListItem::new(@types.Address::from_string(RECIPIENT), storage_keys=[
      @types.Hex::from_string("0x07"),
    ])
    |> ignore
  catch {
    InvalidLength(_) => ()
    e => fail("expected an invalid length, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// The keys are copied both ways in, so neither the caller's array nor the one
/// it reads back is the item's own.
test "an access list item cannot be changed afterwards" {
  let keys = [@types.Hex::from_string(SLOT_7)]
  let item = @types.AccessListItem::new(
    @types.Address::from_string(RECIPIENT),
    storage_keys=keys,
  )
  keys.clear()
  item.storage_keys().clear()
  assert_eq(item.storage_keys().length(), 1)
}

///|
test "an access list estimate decodes gas and list" {
  let estimate = @types.AccessListEstimate::from_json(
    Json::object({
      "accessList": Json::array([
        Json::object({
          "address": Json::string(RECIPIENT),
          "storageKeys": Json::array([Json::string(SLOT_7)]),
        }),
      ]),
      "gasUsed": Json::string("0x6a40"),
    }),
  )
  assert_eq(estimate.gas_used.to_uint64(), 27200)
  assert_eq(estimate.access_list.length(), 1)
  assert_true(estimate.error is None)
}

///|
/// A transaction the node could not execute comes back with the reason beside
/// the list it had built.
test "an access list estimate carries the node's error" {
  let estimate = @types.AccessListEstimate::from_json(
    Json::object({
      "accessList": Json::array([]),
      "gasUsed": Json::string("0x0"),
      "error": Json::string("execution reverted"),
    }),
  )
  assert_eq(estimate.error, Some("execution reverted"))
}
